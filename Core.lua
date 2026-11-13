local addonName, ns = ...
local L = ns.L

-- ============================================================================
-- 1. Konstanten & Datenbank-Initialisierung
-- ============================================================================

ns.ADDON_NAME = "BoisCraft"
ns.ADDON_PREFIX = "BoisCraft"
ns.INACTIVE_THRESHOLD = 60 * 24 * 3600 -- 60 Tage in Sekunden

function ns.EnsureSavedVariables()
    FriendProfessionDB = FriendProfessionDB or {}
    IncomingOrders     = IncomingOrders or {}
    PendingOrders      = PendingOrders or {}
    ShoppingList       = ShoppingList or {}
    RecipeReagentsDB   = RecipeReagentsDB or {}

    -- Bidirektionales Mapping zwischen RecipeSpellID und hergestellter ItemID
    RecipeItemMapDB = RecipeItemMapDB or {}
    RecipeItemMapDB.recipeToItem = RecipeItemMapDB.recipeToItem or {}
    RecipeItemMapDB.itemToRecipes = RecipeItemMapDB.itemToRecipes or {}

    -- Metadaten für Freunde (Klassenfarbe, Skill-Level, LastSeen, verarbeitete Order-IDs & Tombstones)
    FriendMetaDB = FriendMetaDB or {}
    FriendMetaDB.players = FriendMetaDB.players or {}
    FriendMetaDB.processedOrders = FriendMetaDB.processedOrders or {}
    FriendMetaDB.orderTombstones = FriendMetaDB.orderTombstones or {}

    -- Einstellungen, Sprache & Account-Twinks
    BoisCraftSettings = BoisCraftSettings or {}
    BoisCraftSettings.channelName = BoisCraftSettings.channelName or "boisrezepte"
    BoisCraftSettings.language = BoisCraftSettings.language or "AUTO"
    BoisCraftSettings.myAlts = BoisCraftSettings.myAlts or {}
    BoisCraftSettings.minimap = BoisCraftSettings.minimap or {
        minimapPos = BoisCraftSettings.minimapPos or 190,
        hide = false,
    }

    -- Dungeon-Planer & Wunschlisten (charakterspezifisch unter .chars[charName])
    BoisCraftWishlist = BoisCraftWishlist or {}
    BoisCraftWishlist.chars = BoisCraftWishlist.chars or {}
    BoisCraftWishlist.myItems = BoisCraftWishlist.myItems or {}
    BoisCraftWishlist.friends = BoisCraftWishlist.friends or {}

    -- Drop-Quellen-Cache & Beute-Logbuch
    BoisCraftDropCache = BoisCraftDropCache or {}
    BoisCraftLootHistory = BoisCraftLootHistory or {}
end

function ns.GetMyCharWishlist(charName)
    ns.EnsureSavedVariables()
    local name = charName and ns.NormalizeName(charName) or ns.GetFullPlayerName("player")
    if not name or name == "" then
        name = UnitName("player") or "Unknown"
    end
    BoisCraftWishlist.chars[name] = BoisCraftWishlist.chars[name] or {}
    return BoisCraftWishlist.chars[name], name
end

ns.EnsureSavedVariables()

-- Die Spielersuche erfolgt ausschliesslich ueber die ausgewaehlte WoW-Community.
-- Bestehende channelName-Einstellungen werden aus Kompatibilitaetsgruenden
-- nicht aus SavedVariables geloescht, aber nicht mehr verwendet.

-- ============================================================================
-- 3. Combat-Lockdown-Puffer & Asynchroner Item-Loader
-- ============================================================================

local combatQueue = {}
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    for key, func in pairs(combatQueue) do
        pcall(func)
        combatQueue[key] = nil
    end
end)

function ns.RunOutOfCombat(func, queueKey)
    if type(func) ~= "function" then return end
    if InCombatLockdown and InCombatLockdown() then
        local key = queueKey or tostring(func)
        combatQueue[key] = func
    else
        func()
    end
end

function ns.AsyncLoadItem(itemID, callback)
    itemID = tonumber(itemID)
    if not itemID or type(callback) ~= "function" then return end

    if Item and Item.CreateFromItemID then
        local itemObj = Item:CreateFromItemID(itemID)
        itemObj:ContinueOnItemLoad(function()
            local name = itemObj:GetItemName()
            local link = itemObj:GetItemLink()
            local quality = itemObj:GetItemQuality()
            local icon = itemObj:GetItemIcon()
            callback(name, link, quality, icon)
        end)
        return
    end

    local name, link, quality, _, _, _, _, _, _, icon = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    end

    if name then
        callback(name, link, quality, icon)
    else
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        callback("Item #" .. itemID, nil, 1, 134400)
    end
end

-- ============================================================================
-- 4. Sprachneutrale Berufe-Logik (Automatischer Abgleich über Locales.lua)
-- ============================================================================

ns.DISPLAY_PROFESSIONS = {
    "ALCHEMY",
    "BLACKSMITHING",
    "ENCHANTING",
    "ENGINEERING",
    "LEATHERWORKING",
    "TAILORING",
    "COOKING",
    "FIRSTAID",
}

local PROF_ALIASES = {
    ALCHEMY        = { "alchemy", "alchimie", "alchemie" },
    BLACKSMITHING  = { "blacksmithing", "schmiedekunst" },
    ENCHANTING     = { "enchanting", "verzauberkunst" },
    ENGINEERING    = { "engineering", "ingenieurskunst", "ingenieurkunst" },
    LEATHERWORKING = { "leatherworking", "lederverarbeitung" },
    TAILORING      = { "tailoring", "schneiderei", "schneidern" },
    COOKING        = { "cooking", "kochkunst", "kochen" },
    FIRSTAID       = { "first aid", "firstaid", "erste hilfe" },
}

-- Erkennt den kanonischen Schlüssel automatisch anhand von Aliasen und Locales.lua
function ns.NormalizeProfName(rawName)
    if not rawName or rawName == "" then return "" end
    rawName = strtrim(rawName)
    local upper = rawName:upper()
    local lower = rawName:lower()

    -- 1. Prüfen, ob es bereits der kanonische Schlüssel ist (z. B. "LEATHERWORKING")
    for _, key in ipairs(ns.DISPLAY_PROFESSIONS) do
        if upper == key then
            return key
        end
    end

    -- 2. Bekannte Schreibweisen (z. B. "Alchimie" in WoW Classic vs. "Alchemie", "Schneiderei" vs. "Schneidern") prüfen
    for _, key in ipairs(ns.DISPLAY_PROFESSIONS) do
        local aliases = PROF_ALIASES[key]
        if aliases then
            for _, alias in ipairs(aliases) do
                if lower == alias or lower:find(alias, 1, true) then
                    return key
                end
            end
        end
    end

    -- 3. Direkt gegen alle Sprach-Tabellen in Locales.lua prüfen (inkl. Präfixe wie "Classic Cooking")
    if ns.Locales then
        for _, key in ipairs(ns.DISPLAY_PROFESSIONS) do
            local localeKey = "PROF_" .. key
            for _, dict in pairs(ns.Locales) do
                local translated = dict[localeKey]
                if translated then
                    local transLower = translated:lower()
                    if lower == transLower or lower:find(transLower, 1, true) then
                        return key
                    end
                end
            end
        end
    end

    return rawName
end

-- Gibt den Berufsnamen in der aktuell in BoisCraft gewählten Sprache zurück
function ns.GetLocalizedProfName(profNameOrKey)
    local key = ns.NormalizeProfName(profNameOrKey)
    local localeKey = "PROF_" .. key
    if ns.L and ns.L[localeKey] ~= localeKey then
        return ns.L[localeKey]
    end
    return profNameOrKey or ""
end

-- ============================================================================
-- 5. Spielernamen, Klassenfarben & Skill-Level
-- ============================================================================

function ns.NormalizeName(name)
    if not name or name == "" then return "" end
    name = Ambiguate(name, "none")
    name = name:gsub("%-.*$", "")
    return strtrim(name)
end

function ns.GetFullPlayerName(unit)
    unit = unit or "player"
    local fullName = nil
    if GetUnitName then
        local name = GetUnitName(unit, false)
        if name and name ~= "" then fullName = name end
    end

    if not fullName then fullName = UnitName(unit) end
    if not fullName then return "" end

    fullName = Ambiguate(fullName, "none")
    fullName = fullName:gsub("%-.*$", "")

    if unit == "player" and not fullName:find(" ") and PlayerFrame and PlayerFrame.name and PlayerFrame.name.GetText then
        local frameText = PlayerFrame.name:GetText()
        if frameText and frameText ~= "" and frameText:find(fullName, 1, true) then
            fullName = frameText
        end
    end

    return strtrim(fullName)
end

function ns.UpdatePlayerMeta(playerName, classToken, profName, skillRank, skillMax)
    playerName = ns.NormalizeName(playerName)
    if playerName == "" then return end

    ns.EnsureSavedVariables()
    FriendMetaDB.players[playerName] = FriendMetaDB.players[playerName] or { skills = {} }
    local meta = FriendMetaDB.players[playerName]

    meta.lastSeen = time()
    if classToken and classToken ~= "" then
        meta.class = classToken:upper()
    end

    if profName and profName ~= "" and skillRank and skillMax then
        local normProf = ns.NormalizeProfName(profName)
        meta.skills = meta.skills or {}
        meta.skills[normProf] = {
            rank = tonumber(skillRank) or 0,
            maxRank = tonumber(skillMax) or 0,
        }
    end
end

function ns.GetColoredPlayerName(playerName, defaultColorHex)
    playerName = ns.NormalizeName(playerName)
    local fallback = defaultColorHex or "FFD100"
    if playerName == "" then return "" end

    local meta = FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[playerName]
    local classToken = meta and meta.class

    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local colorStr = RAID_CLASS_COLORS[classToken].colorStr
        if colorStr then
            return "|c" .. colorStr .. playerName .. "|r"
        end
    end

    return "|cFF" .. fallback .. playerName .. "|r"
end

function ns.GetPlayerProfessionSkillText(playerName, profName)
    playerName = ns.NormalizeName(playerName)
    local normProf = ns.NormalizeProfName(profName)
    local meta = FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[playerName]
    if meta and meta.skills and meta.skills[normProf] then
        local s = meta.skills[normProf]
        if s.rank and s.maxRank and s.maxRank > 0 then
            return string.format("%d/%d", s.rank, s.maxRank)
        end
    end
    return nil
end

-- ============================================================================
-- 6. Migration (Namen + Sprachneutrale Berufsschlüssel) & Inaktivitäts-Cleanup
-- ============================================================================

function ns.MigrateOldSingleNames()
    ns.EnsureSavedVariables()
    local myFullName = ns.GetFullPlayerName("player")
    local myFirstName = UnitName("player") or ""

    if myFullName ~= "" then
        BoisCraftSettings.myAlts[myFullName] = true
        local _, myClass = UnitClass("player")
        ns.UpdatePlayerMeta(myFullName, myClass)

        BoisCraftWishlist.chars = BoisCraftWishlist.chars or {}
        BoisCraftWishlist.chars[myFullName] = BoisCraftWishlist.chars[myFullName] or {}
        if not BoisCraftWishlist.__charMigrated and type(BoisCraftWishlist.myItems) == "table" and next(BoisCraftWishlist.myItems) then
            for itemID, data in pairs(BoisCraftWishlist.myItems) do
                local numID = tonumber(itemID)
                if numID and type(data) == "table" then
                    BoisCraftWishlist.chars[myFullName][numID] = data
                end
            end
            BoisCraftWishlist.myItems = {}
            BoisCraftWishlist.__charMigrated = true
        else
            BoisCraftWishlist.myItems = {}
            BoisCraftWishlist.__charMigrated = true
        end
        if BoisCraftWishlist.friends then
            BoisCraftWishlist.friends[myFullName] = nil
        end
    end

    if myFullName ~= "" and myFullName ~= myFirstName then
        if FriendProfessionDB and FriendProfessionDB[myFirstName] then
            FriendProfessionDB[myFullName] = FriendProfessionDB[myFullName] or {}
            for pName, recipes in pairs(FriendProfessionDB[myFirstName]) do
                FriendProfessionDB[myFullName][pName] = recipes
            end
            FriendProfessionDB[myFirstName] = nil
        end
        if ShoppingList and ShoppingList[myFirstName] then
            ShoppingList[myFullName] = ShoppingList[myFullName] or {}
            for itemID, qty in pairs(ShoppingList[myFirstName]) do
                ShoppingList[myFullName][itemID] = (ShoppingList[myFullName][itemID] or 0) + qty
            end
            ShoppingList[myFirstName] = nil
        end
    end

    if FriendProfessionDB then
        for friendName, profs in pairs(FriendProfessionDB) do
            if type(profs) == "table" then
                local migratedProfs = {}
                for rawProfName, recipeList in pairs(profs) do
                    local normKey = ns.NormalizeProfName(rawProfName)
                    migratedProfs[normKey] = migratedProfs[normKey] or {}
                    local seen = {}
                    for _, existingID in ipairs(migratedProfs[normKey]) do
                        seen[tonumber(existingID)] = true
                    end
                    if type(recipeList) == "table" then
                        for _, rID in ipairs(recipeList) do
                            local numID = tonumber(rID)
                            if numID and not seen[numID] then
                                seen[numID] = true
                                table.insert(migratedProfs[normKey], numID)
                            end
                        end
                    end
                end
                FriendProfessionDB[friendName] = migratedProfs
            end
        end
    end

    if FriendMetaDB and FriendMetaDB.players then
        for _, meta in pairs(FriendMetaDB.players) do
            if meta and type(meta.skills) == "table" then
                local newSkills = {}
                for rawProf, skillData in pairs(meta.skills) do
                    local normKey = ns.NormalizeProfName(rawProf)
                    newSkills[normKey] = skillData
                end
                meta.skills = newSkills
            end
        end
    end
end

function ns.CleanupInactiveCrafters()
    if not FriendProfessionDB then return end
    ns.EnsureSavedVariables()

    local myFullName = ns.GetFullPlayerName("player")
    local myShortName = UnitName("player") or ""
    local now = time()
    local removedCount = 0

    for friendName, _ in pairs(FriendProfessionDB) do
        local isProtected = (friendName == myFullName)
            or (friendName == myShortName)
            or (BoisCraftSettings.myAlts and BoisCraftSettings.myAlts[friendName])

        if not isProtected then
            FriendMetaDB.players[friendName] = FriendMetaDB.players[friendName] or { lastSeen = now, skills = {} }
            local lastSeen = FriendMetaDB.players[friendName].lastSeen or now

            if (now - lastSeen) > ns.INACTIVE_THRESHOLD then
                FriendProfessionDB[friendName] = nil
                removedCount = removedCount + 1
            end
        end
    end

    if removedCount > 0 then
        print(string.format(L["MSG_INACTIVE_CLEANED"], removedCount))
        if ns.RenderProfessions then
            ns.RunOutOfCombat(ns.RenderProfessions, "RenderProfessions")
        end
    end

    -- Abgeschlossene/stornierte Order-Tombstones nach 7 Tagen bereinigen
    local tombstoneTTL = 7 * 24 * 3600
    if FriendMetaDB.orderTombstones then
        for oID, info in pairs(FriendMetaDB.orderTombstones) do
            local ts = type(info) == "table" and tonumber(info.updatedAt) or 0
            if (now - ts) > tombstoneTTL then
                FriendMetaDB.orderTombstones[oID] = nil
            end
        end
    end
    if FriendMetaDB.processedOrders then
        local processedTTL = 14 * 24 * 3600
        for oID, ts in pairs(FriendMetaDB.processedOrders) do
            if (now - (tonumber(ts) or 0)) > processedTTL then
                FriendMetaDB.processedOrders[oID] = nil
            end
        end
    end
end

-- ============================================================================
-- 7. Rezept <-> Item Mapping & Sprachunabhängige Namensauflösung
-- ============================================================================

function ns.RegisterRecipeItemMapping(recipeID, outputItemID)
    recipeID = tonumber(recipeID)
    outputItemID = tonumber(outputItemID)
    if not recipeID or not outputItemID or outputItemID <= 0 then return end

    ns.EnsureSavedVariables()
    RecipeItemMapDB.recipeToItem[recipeID] = outputItemID
    RecipeItemMapDB.itemToRecipes[outputItemID] = RecipeItemMapDB.itemToRecipes[outputItemID] or {}
    RecipeItemMapDB.itemToRecipes[outputItemID][recipeID] = true
end

function ns.GetItemIDForRecipe(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end

    if RecipeItemMapDB and RecipeItemMapDB.recipeToItem and RecipeItemMapDB.recipeToItem[recipeID] then
        return RecipeItemMapDB.recipeToItem[recipeID]
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, rInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(rInfo) == "table" and rInfo.itemID then
            ns.RegisterRecipeItemMapping(recipeID, rInfo.itemID)
            return rInfo.itemID
        end
    end

    return nil
end

function ns.GetLocalizedRecipeName(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return "Unknown" end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, rInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(rInfo) == "table" and rInfo.name and rInfo.name ~= "" then
            return rInfo.name, rInfo.icon
        end
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, sInfo = pcall(C_Spell.GetSpellInfo, recipeID)
        if ok and type(sInfo) == "table" and sInfo.name and sInfo.name ~= "" then
            return sInfo.name, sInfo.iconID
        end
    end

    if GetSpellInfo then
        local ok, sName, _, sIcon = pcall(GetSpellInfo, recipeID)
        if ok and sName and sName ~= "" then
            return sName, sIcon
        end
    end

    local outItemID = ns.GetItemIDForRecipe(recipeID)
    if outItemID then
        local iName, _, _, _, _, _, _, _, _, iIcon = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
        if C_Item and C_Item.GetItemInfo then
            iName, _, _, _, _, _, _, _, _, iIcon = C_Item.GetItemInfo(outItemID)
        elseif GetItemInfo then
            iName, _, _, _, _, _, _, _, _, iIcon = GetItemInfo(outItemID)
        end
        if iName and iName ~= "" then
            return iName, iIcon
        end
    end

    return "Recipe #" .. recipeID, 136240
end

function ns.GetCraftersForRecipe(recipeID)
    recipeID = tonumber(recipeID)
    local crafters = {}
    if not recipeID or not FriendProfessionDB then return crafters end

    for friend, profs in pairs(FriendProfessionDB) do
        if type(profs) == "table" then
            for pName, recipes in pairs(profs) do
                if type(recipes) == "table" then
                    for _, rID in ipairs(recipes) do
                        if tonumber(rID) == recipeID then
                            table.insert(crafters, {
                                name = friend,
                                profession = ns.NormalizeProfName(pName),
                                recipeID = recipeID
                            })
                            break
                        end
                    end
                end
            end
        end
    end
    return crafters
end

function ns.GetCraftersForItemID(itemID)
    itemID = tonumber(itemID)
    if not itemID or not RecipeItemMapDB or not RecipeItemMapDB.itemToRecipes then return {} end

    local recipeSet = RecipeItemMapDB.itemToRecipes[itemID]
    if not recipeSet then return {} end

    local results = {}
    local seenCrafters = {}
    for recipeID, _ in pairs(recipeSet) do
        local list = ns.GetCraftersForRecipe(recipeID)
        for _, entry in ipairs(list) do
            if not seenCrafters[entry.name] then
                seenCrafters[entry.name] = true
                table.insert(results, entry)
            end
        end
    end
    return results
end

-- ============================================================================
-- 8. Reagenzien, Teil-Crafting & Auftrags-Stacking
-- ============================================================================

function ns.GetRecipeRequiredReagents(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return {} end

    if RecipeReagentsDB and RecipeReagentsDB[recipeID] and #RecipeReagentsDB[recipeID] > 0 then
        return RecipeReagentsDB[recipeID]
    end

    local reagents = {}
    local seenItems = {}

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if ok and schematic and schematic.reagentSlotSchematics then
            if schematic.outputItemID then
                ns.RegisterRecipeItemMapping(recipeID, schematic.outputItemID)
            end
            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                local reqCount = slot.quantityRequired or 1
                if slot.reagents and slot.reagents[1] and slot.reagents[1].itemID then
                    local rItemID = slot.reagents[1].itemID
                    if not seenItems[rItemID] then
                        seenItems[rItemID] = true
                        table.insert(reagents, {
                            itemID = rItemID,
                            count = reqCount
                        })
                    end
                end
            end
            if #reagents > 0 then
                RecipeReagentsDB[recipeID] = reagents
                return reagents
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeNumReagents then
        local ok, reagentCount = pcall(C_TradeSkillUI.GetRecipeNumReagents, recipeID)
        if ok and reagentCount and reagentCount > 0 then
            for i = 1, reagentCount do
                local _, _, reqCount = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
                local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
                local rItemID = link and tonumber(link:match("item:(%d+)"))
                if rItemID and not seenItems[rItemID] then
                    seenItems[rItemID] = true
                    table.insert(reagents, {
                        itemID = rItemID,
                        count = reqCount or 1
                    })
                end
            end
            if #reagents > 0 then
                RecipeReagentsDB[recipeID] = reagents
                return reagents
            end
        end
    end

    return reagents
end

function ns.GetBagAndBankItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return 0, 0, 0 end
    local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, false))
        or (GetItemCount and GetItemCount(itemID, false)) or 0
    local totalWithBank = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true))
        or (GetItemCount and GetItemCount(itemID, true)) or inBags
    local inBank = math.max(0, (tonumber(totalWithBank) or 0) - (tonumber(inBags) or 0))
    return inBags, inBank, totalWithBank
end

function ns.GetMaxCraftableAmount(recipeID, includeBank)
    local reagents = ns.GetRecipeRequiredReagents(recipeID)
    if #reagents == 0 then return 1 end

    local maxPossible = 9999
    for _, reg in ipairs(reagents) do
        local inBags, _, totalWithBank = ns.GetBagAndBankItemCount(reg.itemID)
        local available = includeBank and totalWithBank or inBags
        local req = math.max(1, reg.count or 1)
        local canMake = math.floor(available / req)
        if canMake < maxPossible then
            maxPossible = canMake
        end
    end

    if maxPossible == 9999 then return 0 end
    return maxPossible
end

function ns.HasReagentsForRecipe(recipeID)
    local reagents = ns.GetRecipeRequiredReagents(recipeID)
    if #reagents == 0 then return true end
    return ns.GetMaxCraftableAmount(recipeID, true) >= 1
end

function ns.IsProfessionKnownByAnyFriend(profNameOrKey)
    if not FriendProfessionDB then return false end
    local targetKey = ns.NormalizeProfName(profNameOrKey)
    for _, profs in pairs(FriendProfessionDB) do
        if type(profs) == "table" then
            for pName, recipes in pairs(profs) do
                if ns.NormalizeProfName(pName) == targetKey and type(recipes) == "table" and #recipes > 0 then
                    return true
                end
            end
        end
    end
    return false
end

function ns.GenerateOrderID()
    return string.format("%06d-%03d", time() % 1000000, math.random(100, 999))
end

function ns.RecordOrderTombstone(orderID, status, targetName, recipeID)
    if not orderID or orderID == "" then return end
    ns.EnsureSavedVariables()
    FriendMetaDB.orderTombstones[orderID] = {
        status    = status,
        target    = ns.NormalizeName(targetName or ""),
        recipeID  = tonumber(recipeID) or 0,
        updatedAt = time(),
    }
end

function ns.AddOrStackIncomingOrder(newOrder)
    if not newOrder or not newOrder.recipeID then return false end
    ns.EnsureSavedVariables()

    local orderID = newOrder.orderID
    if orderID and (FriendMetaDB.processedOrders[orderID] or FriendMetaDB.orderTombstones[orderID]) then
        return false
    end
    if orderID then
        FriendMetaDB.processedOrders[orderID] = time()
    end

    local sender = ns.NormalizeName(newOrder.sender or "Unknown")
    local crafter = ns.NormalizeName(newOrder.crafter or ns.GetFullPlayerName("player"))
    local recipeID = tonumber(newOrder.recipeID)
    local addCount = tonumber(newOrder.count) or 1

    for _, existing in ipairs(IncomingOrders) do
        if ns.NormalizeName(existing.sender) == sender
           and ns.NormalizeName(existing.crafter or crafter) == crafter
           and tonumber(existing.recipeID) == recipeID then
            existing.count = (tonumber(existing.count) or 1) + addCount
            existing.countOrdered = (tonumber(existing.countOrdered) or existing.count) + addCount
            existing.lastOrderID = orderID or existing.orderID
            return true, existing
        end
    end

    local entry = {
        orderID      = orderID or ns.GenerateOrderID(),
        sender       = sender,
        crafter      = crafter,
        recipeID     = recipeID,
        count        = addCount,
        countOrdered = addCount,
        countCrafted = 0,
        origin       = newOrder.origin or "COMM",
        isAltOrder   = newOrder.isAltOrder or false,
        timestamp    = time(),
    }
    table.insert(IncomingOrders, entry)
    return true, entry
end