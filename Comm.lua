local addonName, ns = ...
local L = ns.L

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("ADDON_LOADED")
commFrame:RegisterEvent("PLAYER_LOGIN")
commFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
commFrame:RegisterEvent("CLUB_ADDED")
commFrame:RegisterEvent("CLUB_REMOVED")
commFrame:RegisterEvent("CLUB_MEMBERS_UPDATED")
commFrame:RegisterEvent("CLUB_MEMBER_ADDED")
commFrame:RegisterEvent("CLUB_MEMBER_REMOVED")
commFrame:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
commFrame:RegisterEvent("CLUB_MEMBER_UPDATED")
commFrame:RegisterEvent("TRADE_SKILL_SHOW")
commFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
commFrame:RegisterEvent("MAIL_INBOX_UPDATE")
commFrame:RegisterEvent("MAIL_SHOW")
commFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
commFrame:RegisterEvent("CHAT_MSG_LOOT")
commFrame:RegisterEvent("SKILL_LINES_CHANGED")

-- ==========================================================================
-- Nur die explizit ausgewaehlte WoW-Community dient als Mitgliederverzeichnis.
-- Die Community ist KEIN Transportkanal. Addon-Nachrichten gehen ausschliesslich
-- als WHISPER an ihre online erkannten Mitglieder. Keine Gilden-/Gruppen-Sync.
-- ==========================================================================
local channelPeers = {}       -- Community-Mitglieder mit bestaetigtem HELLO/HI
local communityMembers = {}   -- alle Spieler der gewaehlten Community
local onlineMembers = {}      -- laut Community online/away/busy
local aliases = {}            -- kurzer Name => vollstaendiger Chatname (nur eindeutige)
local helloRequested = {}
local lastFullSync = {}
local sendQueue = {}
local sendQueueHead = 1
local SEND_MAX_BYTES = 230
local communityStatus = "NO_SELECTION"
local communityTotal, communityOnline = 0, 0

local function NormalTransportName(name)
    if type(name) ~= "string" then return nil end
    name = strtrim(name)
    -- WoW Forever erlaubt VOR- UND NACHNAMEN mit Leerzeichen!
    -- Nur Steuerzeichen, BattleTags und Protokolltrenner ausschliessen.
    if name == "" or name:find("[%c#:]" ) then return nil end
    local mine = ns.GetFullPlayerName("player")
    if ns.NormalizeName(name) == ns.NormalizeName(mine) then return nil end
    return name
end

-- Vermeidet insbesondere gleichnamige Charaktere auf unterschiedlichen Realms.
local function ResolvePeer(name)
    name = NormalTransportName(name)
    if not name then return nil end
    if communityMembers[name] then return name end
    if name:find("-", 1, true) then return nil end
    return aliases[ns.NormalizeName(name)]
end

local function ClearPeers()
    channelPeers, communityMembers, onlineMembers, aliases = {}, {}, {}, {}
    helloRequested, lastFullSync = {}, {}
    communityTotal, communityOnline = 0, 0
    sendQueue, sendQueueHead = {}, 1
end
ns.ClearChannelPeers = ClearPeers -- Rueckwaertskompatibilitaet fuer UI-Aufrufer

function ns.GetAvailableSyncCommunities()
    local result = {}
    if not C_Club or not C_Club.GetSubscribedClubs then return result end
    if InCombatLockdown and InCombatLockdown() then return result end
    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or type(clubs) ~= "table" then return result end
    local characterType = Enum and Enum.ClubType and Enum.ClubType.Character or 1
    for _, club in ipairs(clubs) do
        if club and club.clubId and club.clubType == characterType then
            result[#result+1] = { id = club.clubId, name = club.name or tostring(club.clubId) }
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function ns.SetSyncCommunity(clubID)
    local id = tonumber(clubID)
    if id then
        local valid = false
        for _, community in ipairs(ns.GetAvailableSyncCommunities()) do
            if tonumber(community.id) == id then valid = true break end
        end
        if not valid then
            print("|cffff5555BoisCraft: Diese WoW-Community steht nicht zur Auswahl.|r")
            return false
        end
    end
    BoisCraftSettings = BoisCraftSettings or {}
    if tonumber(BoisCraftSettings.syncCommunityId) ~= id then
        ClearPeers()
    end
    BoisCraftSettings.syncCommunityId = id
    if id then
        ns.DiscoverCommunityPeers(true)
    else
        communityStatus = "NO_SELECTION"
    end
    return true
end

function ns.GetCommunitySyncStatus()
    local connected = 0
    for _ in pairs(channelPeers) do connected = connected + 1 end
    -- Mitgliederzahlen inklusive des eigenen Charakters (wie Blizzard-UI).
    return communityStatus, communityTotal, communityOnline, connected
end

function ns.IsPlayerActiveInGroupOrOnline(playerName)
    local target = ns.NormalizeName(playerName)
    if target == "" then return false end

    local myFullName = ns.GetFullPlayerName("player")
    local myShortName = UnitName("player") or ""
    if target == myFullName or (target == myShortName and not myFullName:find(" ")) then
        return true
    end

    if IsInGroup and IsInGroup() then
        if IsInRaid and IsInRaid() then
            local num = GetNumGroupMembers and GetNumGroupMembers() or 40
            for i = 1, num do
                local unit = "raid" .. i
                if UnitExists and UnitExists(unit) then
                    local uFull = ns.NormalizeName(ns.GetFullPlayerName(unit))
                    local uShort = ns.NormalizeName(UnitName(unit))
                    if uFull == target or (uShort == target and not uFull:find(" ")) then
                        return true
                    end
                end
            end
        else
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists and UnitExists(unit) then
                    local uFull = ns.NormalizeName(ns.GetFullPlayerName(unit))
                    local uShort = ns.NormalizeName(UnitName(unit))
                    if uFull == target or (uShort == target and not uFull:find(" ")) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local peer = ResolvePeer(target)
    if peer and (onlineMembers[peer] or channelPeers[peer]) then
        return true
    end
    return false
end

-- Senden darf nur ein Mitglied der ausgewaehlten Community sein.
function ns.SendSyncMessage(payload, target)
    if type(payload) ~= "string" or #payload > SEND_MAX_BYTES or #payload == 0 then
        if type(payload) == "string" and #payload > SEND_MAX_BYTES then
            print("|cffff5555BoisCraft: Nachricht zu lang (" .. #payload .. " Bytes).|r")
        end
        return false
    end
    local function enqueue(name)
        local peer = ResolvePeer(name)
        if not peer then return false end
        sendQueue[#sendQueue + 1] = { peer = peer, payload = payload, attempts = 0 }
        return true
    end
    if target then return enqueue(target) end
    local queued = false
    for peer in pairs(channelPeers) do
        if onlineMembers[peer] and enqueue(peer) then queued = true end
    end
    return queued
end

local function FlushOneSyncMessage()
    local entry = sendQueue[sendQueueHead]
    if not entry then
        if sendQueueHead > 1 then sendQueue, sendQueueHead = {}, 1 end
        return
    end
    -- Bei Community-Wechsel oder offline gegangenem Ziel nichts versenden.
    if not communityMembers[entry.peer] then
        sendQueueHead = sendQueueHead + 1
        return
    end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    local ok, code1, code2 = pcall(C_ChatInfo.SendAddonMessage,
        ns.ADDON_PREFIX, entry.payload, "WHISPER", entry.peer)
    local result = code2 ~= nil and code2 or code1
    if ok and (result == 0 or result == true) then
        sendQueueHead = sendQueueHead + 1
        return
    end
    if ok and (result == 3 or result == 8) and entry.attempts < 12 then
        entry.attempts = entry.attempts + 1
        return
    end
    sendQueueHead = sendQueueHead + 1
    if entry.attempts == 0 then
        print("|cffff5555BoisCraft: Addon-Whisper an " .. entry.peer ..
            " fehlgeschlagen (" .. tostring(result) .. ").|r")
    end
end

local function RequestHello(name, force)
    local peer = ResolvePeer(name)
    if not peer then return false end
    local now = GetTime and GetTime() or time()
    if not force and channelPeers[peer] then return false end
    if not force and helloRequested[peer] and now - helloRequested[peer] < 90 then return false end
    helloRequested[peer] = now
    return ns.SendSyncMessage("HELLO:" .. ns.GetFullPlayerName("player"), peer)
end

function ns.DiscoverCommunityPeers(force)
    local id = BoisCraftSettings and tonumber(BoisCraftSettings.syncCommunityId)
    if not id then
        communityStatus = "NO_SELECTION"
        if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
        return 0
    end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    if not C_Club or not C_Club.GetClubMembers or not C_Club.GetMemberInfo then
        communityStatus = "NO_API"
        if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
        return 0
    end
    local exists = false
    for _, club in ipairs(ns.GetAvailableSyncCommunities()) do
        if tonumber(club.id) == id then exists = true break end
    end
    if not exists then
        communityStatus = "COMMUNITY_NOT_FOUND"
        ClearPeers()
        if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
        return 0
    end
    local ok, ids = pcall(C_Club.GetClubMembers, id)
    if not ok or type(ids) ~= "table" or #ids == 0 then
        communityStatus = "MEMBERS_NOT_LOADED"
        if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
        return 0
    end

    local known, online, newAliases, duplicates = {}, {}, {}, {}
    local found, total, onlineCount, unresolved = 0, 0, 0, 0
    local myName = ns.GetFullPlayerName("player")
    local function AddAlias(alias, peer)
        if not alias or alias == "" then return end
        alias = ns.NormalizeName(alias)
        if duplicates[alias] then return end
        if newAliases[alias] and newAliases[alias] ~= peer then
            newAliases[alias] = nil
            duplicates[alias] = true
        else
            newAliases[alias] = peer
        end
    end
    for _, memberID in ipairs(ids) do
        local good, info = pcall(C_Club.GetMemberInfo, id, memberID)
        if good and type(info) == "table" then
            local rawName = type(info.name) == "string" and strtrim(info.name) or nil
            if rawName and rawName ~= "" then
                total = total + 1
                local isOnline = (info.presence == 1 or info.presence == 4 or info.presence == 5)
                if isOnline then onlineCount = onlineCount + 1 end
                -- isSelf kann auf einigen Clients fehlen. Vollnamen abgleichen.
                if not info.isSelf and ns.NormalizeName(rawName) ~= ns.NormalizeName(myName) then
                    local peer = NormalTransportName(rawName)
                    if peer then
                        known[peer] = true
                        AddAlias(peer, peer)
                        -- Fallback, falls CHAT_MSG_ADDON nur den Vornamen liefert.
                        -- Kollisionen werden nicht aufgeloest (kein falscher Empfaenger).
                        AddAlias(peer:match("^(%S+)%s+"), peer)
                        if isOnline then
                            online[peer] = true
                            found = found + 1
                        end
                    else
                        unresolved = unresolved + 1
                    end
                end
            else
                unresolved = unresolved + 1
            end
        else
            unresolved = unresolved + 1
        end
    end
    communityMembers, onlineMembers, aliases = known, online, newAliases
    communityTotal, communityOnline = total, onlineCount
    if total == 0 then
        communityStatus = "NAMES_NOT_LOADED"
    elseif unresolved > 0 then
        communityStatus = "MEMBERS_PARTIAL"
    elseif total > 1 and next(known) == nil then
        communityStatus = "NO_VALID_PEERS"
    else
        communityStatus = "OK"
    end
    for peer in pairs(channelPeers) do
        if not onlineMembers[peer] then
            channelPeers[peer], helloRequested[peer], lastFullSync[peer] = nil, nil, nil
        end
    end
    for peer in pairs(onlineMembers) do RequestHello(peer, force) end
    if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
    return found
end

function ns.ManualSync(target)
    local id = BoisCraftSettings and BoisCraftSettings.syncCommunityId
    if not id then
        print("|cffffaa00BoisCraft: Bitte zuerst unter /bc options eine Community waehlen.|r")
        return
    end
    local found = ns.DiscoverCommunityPeers(false)
    if target and target ~= "" then
        local peer = ResolvePeer(target)
        if peer and onlineMembers[peer] then
            RequestHello(peer, true)
            print("|cff66ccffBoisCraft: Synchronisation mit " .. peer .. " angefordert.|r")
        else
            print("|cffffaa00BoisCraft: " .. tostring(target) .. " ist kein online erkanntes Mitglied der gewaehlten Community.|r")
        end
    else
        for peer in pairs(onlineMembers) do RequestHello(peer, true) end
        local status, total, online, connected = ns.GetCommunitySyncStatus()
        if status == "MEMBERS_NOT_LOADED" or status == "NAMES_NOT_LOADED" or (total or 0) == 0 then
            print("|cff66ccff[BoisCraft]|r " .. (L["COMMUNITY_NOT_LOADED_HINT"] or "|cFFFFAA00Mitgliederliste noch nicht geladen – bitte öffne einmal kurz das Community-Fenster.|r"))
        else
            print(string.format("|cff66ccffBoisCraft: Community %d Mitglieder, %d online (inkl. dir); %d Online-Ziele, %d verbunden.|r", total, online, found, connected))
        end
    end
end

local function SendFullStateToPeer(peer)
    local now = GetTime and GetTime() or time()
    if lastFullSync[peer] and now - lastFullSync[peer] < 12 then return end
    lastFullSync[peer] = now
    ns.BroadcastPendingOrdersToCrafter(peer)
    ns.BroadcastMyMetaAndProfessions(peer)
    ns.BroadcastMyWishlist(peer)
end

local networkTickerStarted = false
local function StartNetworkTicker()
    if networkTickerStarted or not C_Timer or not C_Timer.NewTicker then return end
    networkTickerStarted = true
    C_Timer.NewTicker(0.40, FlushOneSyncMessage)
    C_Timer.NewTicker(40, function() ns.DiscoverCommunityPeers(false) end)
end

-- ============================================================================
-- 1. Eigene Berufe, Skill-Level, Reagenzien & Item-IDs scannen + senden
-- ============================================================================

local VALID_PROF_MAP = {}
for _, k in ipairs(ns.DISPLAY_PROFESSIONS or {}) do
    VALID_PROF_MAP[k] = true
end

local function CleanupUnlearnedMyProfessions(myName)
    if not myName or myName == "" then return end
    if not FriendProfessionDB or type(FriendProfessionDB[myName]) ~= "table" then return end

    local currentProfs = {}
    local canVerifyAll = false

    -- 1. Moderne GetProfessions-API (falls vorhanden)
    if GetProfessions and GetProfessionInfo then
        local p1, p2, _, _, cook, firstAid = GetProfessions()
        for _, idx in ipairs({ p1, p2, cook, firstAid }) do
            if idx then
                local name = GetProfessionInfo(idx)
                if name and name ~= "" then
                    local norm = ns.NormalizeProfName(name)
                    if VALID_PROF_MAP[norm] then
                        currentProfs[norm] = true
                    end
                end
            end
        end
        canVerifyAll = true
    -- 2. Klassische GetNumSkillLines-API (nur wenn keine Header eingeklappt sind)
    elseif GetNumSkillLines and GetSkillLineInfo then
        local numLines = GetNumSkillLines() or 0
        if numLines > 0 then
            local hasCollapsedHeader = false
            for i = 1, numLines do
                local skillName, isHeader, isExpanded = GetSkillLineInfo(i)
                if isHeader then
                    if not isExpanded then
                        hasCollapsedHeader = true
                        break
                    end
                elseif skillName and skillName ~= "" then
                    local norm = ns.NormalizeProfName(skillName)
                    if VALID_PROF_MAP[norm] then
                        currentProfs[norm] = true
                    end
                end
            end
            if not hasCollapsedHeader then
                canVerifyAll = true
            end
        end
    end

    if not canVerifyAll then return end

    local removedAny = false
    for savedProf, _ in pairs(FriendProfessionDB[myName]) do
        local normSaved = ns.NormalizeProfName(savedProf)
        if VALID_PROF_MAP[normSaved] and not currentProfs[normSaved] then
            FriendProfessionDB[myName][savedProf] = nil
            if FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[myName] and FriendMetaDB.players[myName].skills then
                FriendMetaDB.players[myName].skills[normSaved] = nil
            end
            ns.SendSyncMessage(string.format("UNLEARN:%s:%s", myName, normSaved))
            removedAny = true
        end
    end

    if removedAny then
        ns.RunOutOfCombat(function()
            if ns.RenderProfessions then ns.RenderProfessions() end
            if ns.DisplayRecipesForProfession and ns.selectedProfession then
                ns.DisplayRecipesForProfession(ns.selectedProfession)
            end
        end, "UpdateCatalogAfterUnlearn")
    end
end

local function HaveRecipesChanged(oldList, newList)
    if type(oldList) ~= "table" then return true end
    if #oldList ~= #newList then return true end
    local oldSet = {}
    for _, rID in ipairs(oldList) do
        oldSet[tonumber(rID)] = true
    end
    for _, rID in ipairs(newList) do
        if not oldSet[tonumber(rID)] then
            return true
        end
    end
    return false
end

local scanPending = false

local function ScanAndSaveCurrentTradeSkill()
    scanPending = false
    local profName = nil
    local skillRank, skillMax = 0, 0

    -- Zuerst Basis-Berufsinfo prüfen
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo and baseInfo.professionName and baseInfo.professionName ~= "" then
            profName = baseInfo.professionName
            skillRank = baseInfo.skillLevel or 0
            skillMax = baseInfo.maxSkillLevel or 0
        end
    end

    -- Ergänzend ChildProfessionInfo prüfen (enthält auf manchen Clients die aktuellen Skill-Punkte)
    if C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfo then
        local ok, childInfo = pcall(C_TradeSkillUI.GetChildProfessionInfo)
        if ok and childInfo then
            if (not profName or profName == "") and childInfo.professionName and childInfo.professionName ~= "" then
                profName = childInfo.professionName
            end
            if (skillMax == 0) and (childInfo.maxSkillLevel or 0) > 0 then
                skillRank = childInfo.skillLevel or 0
                skillMax = childInfo.maxSkillLevel or 0
            end
        end
    end

    -- Klassischer Fallback
    if (not profName or profName == "") and GetTradeSkillLine then
        local name, rank, maxRank = GetTradeSkillLine()
        if name and name ~= "UNKNOWN" then
            profName = name
            skillRank = rank or 0
            skillMax = maxRank or 0
        end
    end

    if not profName or profName == "" or profName == "UNKNOWN" then return end

    local normProf = ns.NormalizeProfName(profName)
    local myName = ns.GetFullPlayerName("player")
    if myName == "" then return end

    local _, myClass = UnitClass("player")
    local prevMeta = FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[myName]
    local prevSkill = prevMeta and prevMeta.skills and prevMeta.skills[normProf]
    local skillChanged = (not prevSkill)
        or (tonumber(prevSkill.rank) ~= tonumber(skillRank))
        or (tonumber(prevSkill.maxRank) ~= tonumber(skillMax))

    ns.UpdatePlayerMeta(myName, myClass, normProf, skillRank, skillMax)
    BoisCraftSettings.myAlts[myName] = true
    CleanupUnlearnedMyProfessions(myName)

    local learnedIDs = {}
    local seenIDs = {}

    -- A. Moderne TradeSkill-API
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if ok and type(recipeIDs) == "table" then
            for _, rID in ipairs(recipeIDs) do
                local okInfo, rInfo = pcall(C_TradeSkillUI.GetRecipeInfo, rID)
                if okInfo and rInfo and rInfo.learned then
                    if not seenIDs[rID] then
                        seenIDs[rID] = true
                        table.insert(learnedIDs, rID)
                    end
                    if rInfo.itemID then
                        ns.RegisterRecipeItemMapping(rID, rInfo.itemID)
                    end
                    ns.GetRecipeRequiredReagents(rID)
                end
            end
        end
    end

    -- B. Klassischer TradeSkill-Fallback
    if #learnedIDs == 0 and GetNumTradeSkills then
        for i = 1, GetNumTradeSkills() do
            local _, skillType = GetTradeSkillInfo(i)
            if skillType ~= "header" then
                local rLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
                local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                local rID = rLink and tonumber(rLink:match("enchant:(%d+)"))
                local outItemID = itemLink and tonumber(itemLink:match("item:(%d+)"))

                if not rID and outItemID then rID = outItemID end
                if rID then
                    if not seenIDs[rID] then
                        seenIDs[rID] = true
                        table.insert(learnedIDs, rID)
                    end
                    if outItemID then
                        ns.RegisterRecipeItemMapping(rID, outItemID)
                    end
                    if GetTradeSkillNumReagents then
                        local numReagents = GetTradeSkillNumReagents(i) or 0
                        if numReagents > 0 then
                            RecipeReagentsDB[rID] = {}
                            for r = 1, numReagents do
                                local _, _, rCount = GetTradeSkillReagentInfo(i, r)
                                local regLink = GetTradeSkillReagentItemLink(i, r)
                                local regItemID = regLink and tonumber(regLink:match("item:(%d+)"))
                                if regItemID then
                                    table.insert(RecipeReagentsDB[rID], {
                                        itemID = regItemID,
                                        count = rCount or 1
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #learnedIDs == 0 then return end

    -- Prüfen, ob sich die gelernten Rezepte gegenüber dem gespeicherten Stand geändert haben
    FriendProfessionDB[myName] = FriendProfessionDB[myName] or {}
    local existingList = FriendProfessionDB[myName][normProf]
    local recipesChanged = HaveRecipesChanged(existingList, learnedIDs)

    -- Lokal unter sprachneutralem Key speichern
    FriendProfessionDB[myName][normProf] = learnedIDs

    -- UI aktualisieren (kampfsicher)
    ns.RunOutOfCombat(function()
        if ns.RenderProfessions then ns.RenderProfessions() end
        if ns.DisplayRecipesForProfession and ns.selectedProfession and ns.NormalizeProfName(ns.selectedProfession) == normProf then
            ns.DisplayRecipesForProfession(normProf)
        end
    end, "UpdateCatalogAfterScan")

    -- Nur wenn wirklich neue Rezepte dazugekommen sind (oder der Beruf erstmals gescannt wurde),
    -- Chat-Meldung ausgeben und komplette Rezeptliste an die Community senden
    if recipesChanged then
        local localProfDisplay = ns.GetLocalizedProfName(normProf)
        print(string.format(L["MSG_RECIPES_SAVED"], #learnedIDs, localProfDisplay, myName))
        ns.BroadcastSingleProfession(myName, normProf, learnedIDs, skillRank, skillMax)
    elseif skillChanged and skillRank and skillMax then
        local metaPayload = string.format("META:%s:%s:%s:%d:%d", myName, myClass or "", normProf, skillRank, skillMax)
        ns.SendSyncMessage(metaPayload)
    end
end

function ns.BroadcastSingleProfession(playerName, normProf, recipeList, skillRank, skillMax, target)
    if not recipeList or #recipeList == 0 then return end
    local _, myClass = UnitClass("player")
    if skillRank and skillMax then
        local metaPayload = string.format("META:%s:%s:%s:%d:%d", playerName, myClass or "", normProf, skillRank, skillMax)
        ns.SendSyncMessage(metaPayload, target)
    end

    local buffer = {}
    local payloadStart = string.format("SYNC:%s:%s:", playerName, normProf)
    for _, rID in ipairs(recipeList) do
        local outItem = ns.GetItemIDForRecipe(rID)
        local token = outItem and string.format("%d=%d", rID, outItem) or tostring(rID)
        local nextList = table.concat(buffer, ",")
        if #buffer > 0 and #payloadStart + #nextList + 1 + #token > SEND_MAX_BYTES then
            ns.SendSyncMessage(payloadStart .. nextList, target)
            buffer = {}
        end
        table.insert(buffer, token)
    end
    if #buffer > 0 then
        ns.SendSyncMessage(payloadStart .. table.concat(buffer, ","), target)
    end
end

-- ============================================================================
-- 2. Offene Aufträge, Wunschlisten & Metadaten bei HELLO synchronisieren
-- ============================================================================

function ns.BroadcastPendingOrdersToCrafter(crafterName)
    if not PendingOrders or #PendingOrders == 0 then return end
    local normCrafter = ns.NormalizeName(crafterName)
    for _, order in ipairs(PendingOrders) do
        if ns.NormalizeName(order.crafter) == normCrafter and not order.acked then
            local oID = order.orderID or ns.GenerateOrderID()
            order.orderID = oID
            local payload = string.format("ORDER:%s:%d:%d:%s", normCrafter, order.recipeID, order.count or 1, oID)
            ns.SendSyncMessage(payload, normCrafter)
        end
    end
end

function ns.BroadcastMyMetaAndProfessions(target)
    local myName = ns.GetFullPlayerName("player")
    if myName == "" then return end
    local _, myClass = UnitClass("player")

    local meta = FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[myName]
    if meta and meta.skills and next(meta.skills) then
        for profKey, skill in pairs(meta.skills) do
            local metaPayload = string.format("META:%s:%s:%s:%d:%d", myName, myClass or "", profKey, skill.rank or 0, skill.maxRank or 0)
            ns.SendSyncMessage(metaPayload, target)
        end
    else
        ns.SendSyncMessage(string.format("META:%s:%s::0:0", myName, myClass or ""), target)
    end

    if FriendProfessionDB and FriendProfessionDB[myName] then
        for profKey, recipeList in pairs(FriendProfessionDB[myName]) do
            ns.BroadcastSingleProfession(myName, ns.NormalizeProfName(profKey), recipeList, nil, nil, target)
        end
    end
end

function ns.BroadcastMyWishlist(target)
    local myList, myName = nil, ns.GetFullPlayerName("player")
    if not myName or myName == "" then return end
    if ns.GetMyCharWishlist then
        myList = ns.GetMyCharWishlist(myName)
    elseif BoisCraftWishlist and BoisCraftWishlist.chars then
        myList = BoisCraftWishlist.chars[myName]
    end
    myList = myList or {}

    local prefix = "WL:" .. myName .. ":"
    -- Damit große Wunschlisten in mehreren Paketen übertragen werden können.
    -- Vor jeder vollständigen Liste wird die alte Version dieses Charakters zurückgesetzt.
    ns.SendSyncMessage("WL_BEGIN:" .. myName, target)
    local tokens = {}
    for itemID, data in pairs(myList) do
        if type(data) == "table" and data.status == "WANTED" then
            local needed = tonumber(data.needed) or 1
            local collected = tonumber(data.collected) or 0
            local token = string.format("%d=%d/%d", tonumber(itemID), collected, needed)
            local current = table.concat(tokens, ",")
            if #tokens > 0 and #prefix + #current + 1 + #token > SEND_MAX_BYTES then
                ns.SendSyncMessage(prefix .. current, target)
                tokens = {}
            end
            table.insert(tokens, token)
        end
    end
    ns.SendSyncMessage(prefix .. table.concat(tokens, ","), target)
end

local function InitCommunityAndHello()
    ns.DiscoverCommunityPeers(false)
end

-- ============================================================================
-- 3. Automatischer Posteingangs-Scanner für Mail-Aufträge
-- ============================================================================

local function ScanMailInboxForOrders()
    if not GetInboxNumItems or not GetInboxHeaderInfo then return end
    local numItems = GetInboxNumItems() or 0
    if numItems == 0 then return end

    local myName = ns.GetFullPlayerName("player")
    local newOrdersCount = 0

    for i = 1, numItems do
        local _, _, sender, subject = GetInboxHeaderInfo(i)
        local bodyText = GetInboxText and GetInboxText(i) or ""
        local normSender = ns.NormalizeName(sender or "Mail")

        -- 1. Prüfung auf Kurz-Betreff: [BC:ORD:orderID:recipeID:count]
        if subject then
            local oID, rID, cnt = subject:match("%[BC:ORD:([^:]+):(%d+):(%d+)%]")
            if oID and rID then
                local added = ns.AddOrStackIncomingOrder({
                    orderID  = oID,
                    sender   = normSender,
                    crafter  = myName,
                    recipeID = tonumber(rID),
                    count    = tonumber(cnt) or 1,
                    origin   = "MAIL",
                })
                if added then newOrdersCount = newOrdersCount + 1 end
            end
        end

        -- 2. Prüfung auf Mehrfach-Aufträge im Brieftext: BC_ORD:orderID:recipeID:count
        if bodyText and bodyText ~= "" then
            for oID, rID, cnt in bodyText:gmatch("BC_ORD:([^:%s]+):(%d+):(%d+)") do
                local added = ns.AddOrStackIncomingOrder({
                    orderID  = oID,
                    sender   = normSender,
                    crafter  = myName,
                    recipeID = tonumber(rID),
                    count    = tonumber(cnt) or 1,
                    origin   = "MAIL",
                })
                if added then newOrdersCount = newOrdersCount + 1 end
            end
        end
    end

    if newOrdersCount > 0 then
        if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
            PlaySound(SOUNDKIT.READY_CHECK)
        end
        print(string.format(L["MSG_MAIL_ORDERS_IMPORTED"], newOrdersCount))
        ns.RunOutOfCombat(function()
            if ns.UpdateOrdersList then ns.UpdateOrdersList() end
        end, "UpdateOrdersFromMail")
    end
end

-- ============================================================================
-- 4. Automatischer Abzug beim Herstellen (UNIT_SPELLCAST_SUCCEEDED)
-- ============================================================================

local function OnPlayerSpellcastSucceeded(spellID)
    spellID = tonumber(spellID)
    if not spellID or not IncomingOrders or #IncomingOrders == 0 then return end

    local myName = ns.GetFullPlayerName("player")
    for i = #IncomingOrders, 1, -1 do
        local order = IncomingOrders[i]
        local isMyOrder = (not order.crafter) or (ns.NormalizeName(order.crafter) == myName)
        if isMyOrder and tonumber(order.recipeID) == spellID and (tonumber(order.count) or 0) > 0 then
            order.countCrafted = (tonumber(order.countCrafted) or 0) + 1
            order.count = math.max(0, (tonumber(order.count) or 1) - 1)

            if order.count == 0 then
                print(string.format(L["MSG_CRAFT_COMPLETE"], ns.GetColoredPlayerName(order.sender)))
            else
                print(string.format(L["MSG_CRAFT_PARTIAL"], ns.GetColoredPlayerName(order.sender), order.count))
            end

            ns.RunOutOfCombat(function()
                if ns.UpdateOrdersList then ns.UpdateOrdersList() end
            end, "UpdateOrdersAfterCraft")
            break
        end
    end
end

-- ============================================================================
-- 4b. Automatische Beute-Erkennung fuer Dungeon-Wunschliste (CHAT_MSG_LOOT)
-- ============================================================================

local function IsSelfLootChatMessage(text, playerName, playerName2, guid)
    local myFullName = ns.GetFullPlayerName("player")
    local myShortName = UnitName("player") or ""

    if guid and UnitGUID and guid == UnitGUID("player") then
        return true
    end

    local looter = ns.NormalizeName(playerName2 ~= "" and playerName2 or playerName or "")
    if looter ~= "" then
        return looter == myFullName or (looter == myShortName and not myFullName:find(" "))
    end

    if type(text) ~= "string" then return false end
    for _, globalFmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
        if type(globalFmt) == "string" then
            local prefix = globalFmt:match("^([^%%]+)")
            if prefix and prefix ~= "" and text:sub(1, #prefix) == prefix then
                return true
            end
        end
    end
    if text:find("^You receive loot:") or text:find("^Ihr erhaltet Beute:")
       or text:find("^You receive item:") or text:find("^Ihr erhaltet Gegenstand:") then
        return true
    end
    return false
end

local function OnChatMsgLoot(text, playerName, _, _, playerName2, _, _, _, _, _, _, guid)
    if type(text) ~= "string" then return end
    local itemID = tonumber(text:match("item:(%d+)"))
    if not itemID then return end

    if not IsSelfLootChatMessage(text, playerName, playerName2, guid) then
        return
    end

    ns.EnsureSavedVariables()
    local myName = ns.GetFullPlayerName("player")
    local myWL = ns.GetMyCharWishlist and ns.GetMyCharWishlist(myName)
    local entry = myWL and myWL[itemID]
    if not entry or entry.status ~= "WANTED" then return end

    local count = tonumber(text:match("|h|rx(%d+)")) or tonumber(text:match("x(%d+)%.?$")) or 1
    local needed = tonumber(entry.needed) or 1
    entry.collected = (tonumber(entry.collected) or 0) + count

    local currentZone = GetRealZoneText and GetRealZoneText() or nil
    local dungeonName = (currentZone and currentZone ~= "") and currentZone or "Dungeon"
    local bossName = "Boss"
    local sources = ns.GetItemDropSources and ns.GetItemDropSources(itemID) or {}
    if #sources > 0 then
        local matchedSource = sources[1]
        if currentZone and currentZone ~= "" then
            for _, src in ipairs(sources) do
                if src.dungeon == currentZone then
                    matchedSource = src
                    break
                end
            end
        end
        dungeonName = (matchedSource.dungeon or dungeonName):gsub(":", " ")
        bossName = (matchedSource.boss or bossName):gsub(":", " ")
    else
        dungeonName = dungeonName:gsub(":", " ")
    end

    if entry.collected >= needed then
        entry.collected = needed
        entry.status = "LOOTED"
    end

    local now = time()
    local logKey = string.format("%s-%d-%d", myName, itemID, math.floor(now / 60))
    local exists = false
    for _, logEntry in ipairs(BoisCraftLootHistory) do
        if logEntry.logKey == logKey then exists = true break end
    end
    if not exists then
        table.insert(BoisCraftLootHistory, {
            logKey    = logKey,
            player    = myName,
            itemID    = itemID,
            dungeon   = dungeonName,
            boss      = bossName,
            timestamp = now,
        })
    end

    local _, link = GetItemInfo(itemID)
    print(string.format(L["MSG_LOOT_CONGRATS"], ns.GetColoredPlayerName(myName), link or ("Item " .. itemID)))

    ns.SendSyncMessage(string.format("LOOTED:%s:%d:%s:%s:%d",
        myName, itemID, dungeonName, bossName, now))
    if ns.BroadcastMyWishlist then ns.BroadcastMyWishlist() end
    ns.RunOutOfCombat(function()
        if ns.UpdateDungeonsView then ns.UpdateDungeonsView() end
        if ns.UpdateLootLogView then ns.UpdateLootLogView() end
    end, "AutoLootWishlistUpdate")
end

-- ============================================================================
-- 5. Zentrale Event-Verarbeitung
-- ============================================================================

commFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName or loadedAddon == "BoisCraft" then
            ns.EnsureSavedVariables()
            if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
                C_ChatInfo.RegisterAddonMessagePrefix(ns.ADDON_PREFIX)
            end
        end

    elseif event == "PLAYER_LOGIN" then
        ns.EnsureSavedVariables()
        ns.MigrateOldSingleNames()
        ns.CleanupInactiveCrafters()
        if ns.RefreshAllLocaleTexts then
            ns.RefreshAllLocaleTexts()
        end
        StartNetworkTicker()
        C_Timer.After(2.0, InitCommunityAndHello)
        C_Timer.After(8.0, InitCommunityAndHello)

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2.5, InitCommunityAndHello)

    elseif event == "INITIAL_CLUBS_LOADED" or event == "CLUB_ADDED"
        or event == "CLUB_REMOVED" or event == "CLUB_MEMBERS_UPDATED"
        or event == "CLUB_MEMBER_ADDED" or event == "CLUB_MEMBER_REMOVED"
        or event == "CLUB_MEMBER_PRESENCE_UPDATED" or event == "CLUB_MEMBER_UPDATED" then
        local clubID = ...
        local chosenID = BoisCraftSettings and tonumber(BoisCraftSettings.syncCommunityId)
        if event == "INITIAL_CLUBS_LOADED" or event == "CLUB_ADDED"
            or event == "CLUB_REMOVED" or (chosenID and tonumber(clubID) == chosenID) then
            C_Timer.After(1.0, InitCommunityAndHello)
        end

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        if not scanPending then
            scanPending = true
            C_Timer.After(0.35, ScanAndSaveCurrentTradeSkill)
        end

    elseif event == "SKILL_LINES_CHANGED" then
        local myName = ns.GetFullPlayerName("player")
        if myName ~= "" then
            CleanupUnlearnedMyProfessions(myName)
        end

    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        ScanMailInboxForOrders()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget, _, spellID = ...
        if unitTarget == "player" and spellID then
            OnPlayerSpellcastSucceeded(spellID)
        end

    elseif event == "CHAT_MSG_LOOT" then
        OnChatMsgLoot(...)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix ~= ns.ADDON_PREFIX or not message then return end

        -- Nichtmitgliedern darf weder geantwortet noch deren Zustand uebernommen werden.
        local transportSender = ResolvePeer(sender)
        if not transportSender then return end
        -- Der Sender kommt direkt aus WoWs CHAT_MSG_ADDON und wird der
        -- ausgewaehlten Community zugeordnet. Niemals den Payload als
        -- Identitaetsnachweis akzeptieren; Forever-Vollnamen beibehalten.
        local shortSender = ns.NormalizeName(transportSender)
        local myFullName = ns.GetFullPlayerName("player")
        local myShortName = UnitName("player") or ""

        local msgType, arg1, arg2, arg3, arg4, arg5 = strsplit(":", message)

        if shortSender ~= "" then
            ns.UpdatePlayerMeta(shortSender)
        end

        if msgType == "HELLO" then
            -- Die Identität kommt vom echten Absender des Addon-Whispers.
            if transportSender then
                channelPeers[transportSender] = true
                ns.UpdatePlayerMeta(shortSender)
                ns.SendSyncMessage("HI:" .. myFullName, transportSender)
                SendFullStateToPeer(transportSender)
                if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
            end

        elseif msgType == "HI" then
            if transportSender then
                channelPeers[transportSender] = true
                SendFullStateToPeer(transportSender)
                if ns.UpdateOptionsCommunityStatus then ns.UpdateOptionsCommunityStatus() end
            end

        elseif msgType == "META" then
            local fullSender = shortSender  -- Kein fremder Name aus dem Payload übernehmen.
            local classToken = arg2
            local profKey = arg3 and arg3 ~= "" and ns.NormalizeProfName(arg3) or nil
            local rank = tonumber(arg4) or 0
            local maxRank = tonumber(arg5) or 0
            ns.UpdatePlayerMeta(fullSender, classToken, profKey, rank, maxRank)
            ns.RunOutOfCombat(function()
                if ns.RenderProfessions then ns.RenderProfessions() end
            end, "UpdateMetaUI")

        elseif msgType == "SYNC" then
            local crafterName, rawProf, recipeString
            if arg3 and arg3 ~= "" then
                crafterName = ns.NormalizeName(arg1)
                rawProf = arg2
                recipeString = arg3
            else
                crafterName = shortSender
                rawProf = arg1
                recipeString = arg2 or ""
            end

            if crafterName ~= shortSender then return end
            if crafterName == myFullName or (crafterName == myShortName and not myFullName:find(" ")) then
                return
            end

            local normProf = ns.NormalizeProfName(rawProf)
            if normProf == "" then return end

            FriendProfessionDB[crafterName] = FriendProfessionDB[crafterName] or {}
            local list = FriendProfessionDB[crafterName][normProf] or {}
            local existingMap = {}
            for _, id in ipairs(list) do existingMap[tonumber(id)] = true end

            for token in string.gmatch(recipeString, "([^,]+)") do
                local rStr, iStr = strsplit("=", token)
                local rID = tonumber(rStr)
                local outItemID = tonumber(iStr)
                if rID then
                    if not existingMap[rID] then
                        existingMap[rID] = true
                        table.insert(list, rID)
                    end
                    if outItemID then
                        ns.RegisterRecipeItemMapping(rID, outItemID)
                    end
                end
            end

            FriendProfessionDB[crafterName][normProf] = list
            ns.RunOutOfCombat(function()
                if ns.RenderProfessions then ns.RenderProfessions() end
                if ns.DisplayRecipesForProfession and ns.selectedProfession and ns.NormalizeProfName(ns.selectedProfession) == normProf then
                    ns.DisplayRecipesForProfession(normProf)
                end
            end, "UpdateCatalogSync")

        elseif msgType == "UNLEARN" then
            local crafterName = ns.NormalizeName(arg1)
            local normProf = ns.NormalizeProfName(arg2 or "")
            if crafterName ~= shortSender or normProf == "" then return end
            if FriendProfessionDB and FriendProfessionDB[crafterName] then
                FriendProfessionDB[crafterName][normProf] = nil
            end
            if FriendMetaDB and FriendMetaDB.players and FriendMetaDB.players[crafterName] and FriendMetaDB.players[crafterName].skills then
                FriendMetaDB.players[crafterName].skills[normProf] = nil
            end
            ns.RunOutOfCombat(function()
                if ns.RenderProfessions then ns.RenderProfessions() end
                if ns.DisplayRecipesForProfession and ns.selectedProfession then
                    ns.DisplayRecipesForProfession(ns.selectedProfession)
                end
            end, "UpdateCatalogUnlearn")

        elseif msgType == "ORDER" then
            local targetCrafter = ns.NormalizeName(arg1)
            local recipeID = tonumber(arg2)
            local count = tonumber(arg3) or 1
            local orderID = arg4 or ns.GenerateOrderID()

            if targetCrafter == myFullName or (targetCrafter == myShortName and not myFullName:find(" ")) then
                local added = ns.AddOrStackIncomingOrder({
                    orderID  = orderID,
                    sender   = shortSender,
                    crafter  = myFullName,
                    recipeID = recipeID,
                    count    = count,
                    origin   = "COMM",
                })

                ns.SendSyncMessage(string.format("ACK:%s:%s:%s", shortSender, orderID, myFullName), shortSender)

                if added then
                    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
                        PlaySound(SOUNDKIT.READY_CHECK)
                    end
                    print(string.format(L["MSG_ORDER_RECEIVED"], ns.GetColoredPlayerName(shortSender)))
                    ns.RunOutOfCombat(function()
                        if ns.UpdateOrdersList then ns.UpdateOrdersList() end
                    end, "UpdateOrdersIncoming")
                end
            end

        elseif msgType == "ACK" then
            local ackOrderID = arg2 or arg1
            local crafterName = ns.NormalizeName(arg3 or shortSender)
            if PendingOrders and ackOrderID then
                for idx = #PendingOrders, 1, -1 do
                    local pOrder = PendingOrders[idx]
                    if pOrder.orderID == ackOrderID and not pOrder.acked then
                        pOrder.acked = true
                        print(string.format(L["MSG_ORDER_ACKED"], ns.GetColoredPlayerName(crafterName)))
                        if ns.UpdateOrdersList then ns.UpdateOrdersList() end
                        break
                    end
                end
            end

        elseif msgType == "WL_BEGIN" then
            local wlOwner = shortSender
            if wlOwner ~= myFullName then
                BoisCraftWishlist.friends[wlOwner] = {}
            end

        elseif msgType == "WL" then
            local wlOwner = shortSender
            if wlOwner == myFullName then return end
            local listStr = arg2 or ""

            local newList = BoisCraftWishlist.friends[wlOwner] or {}
            for token in string.gmatch(listStr, "([^,]+)") do
                local itemStr, ratioStr = strsplit("=", token)
                local itemID = tonumber(itemStr)
                if itemID then
                    local colStr, needStr = strsplit("/", ratioStr or "0/1")
                    newList[itemID] = {
                        status = "WANTED",
                        collected = tonumber(colStr) or 0,
                        needed = tonumber(needStr) or 1,
                    }
                end
            end

            BoisCraftWishlist.friends[wlOwner] = newList
            ns.RunOutOfCombat(function()
                if ns.UpdateDungeonsView then ns.UpdateDungeonsView() end
            end, "UpdateDungeonsWL")

        elseif msgType == "LOOTED" then
            local looter = ns.NormalizeName(arg1)
            local itemID = tonumber(arg2)
            local dungeon = arg3 or "Dungeon"
            local boss = arg4 or "Boss"
            local ts = tonumber(arg5) or time()

            if looter ~= "" and itemID then
                if BoisCraftWishlist and BoisCraftWishlist.chars and BoisCraftWishlist.chars[looter] and BoisCraftWishlist.chars[looter][itemID] then
                    BoisCraftWishlist.chars[looter][itemID].status = "LOOTED"
                end
                if BoisCraftWishlist and BoisCraftWishlist.friends and BoisCraftWishlist.friends[looter] and BoisCraftWishlist.friends[looter][itemID] then
                    BoisCraftWishlist.friends[looter][itemID].status = "LOOTED"
                end

                local logKey = string.format("%s-%d-%d", looter, itemID, math.floor(ts / 60))
                local exists = false
                for _, entry in ipairs(BoisCraftLootHistory) do
                    if entry.logKey == logKey then exists = true break end
                end
                if not exists then
                    table.insert(BoisCraftLootHistory, {
                        logKey    = logKey,
                        player    = looter,
                        itemID    = itemID,
                        dungeon   = dungeon,
                        boss      = boss,
                        timestamp = ts,
                    })
                end
                ns.RunOutOfCombat(function()
                    if ns.UpdateDungeonsView then ns.UpdateDungeonsView() end
                    if ns.UpdateLootLogView then ns.UpdateLootLogView() end
                end, "UpdateLootHistoryUI")
            end
        end
    end
end)