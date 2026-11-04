local addonName, ns = ...
local L = ns.L or {}

-- Sicherstellen, dass wir exakt das Frame nutzen, das UI_Main.lua für Tab 4 bereitstellt
local parent = ns.MainFrame or _G["BoisCraftMainFrame"] or UIParent
local DungeonsView = ns.DungeonsView

if not DungeonsView then
    DungeonsView = CreateFrame("Frame", "BoisCraftDungeonsView", parent)
    DungeonsView:SetAllPoints(parent)
    DungeonsView:Hide()
    ns.DungeonsView = DungeonsView
end

local selectedDungeonKey = nil
local filterOnlineGroup = false
local lastRenderedDungeonName = nil
local lastRenderedBossOrder = {}
local lastRenderedWishes = {}

local function GetSafeLocale(key, defaultText)
    local val = L and L[key]
    if not val or val == key then
        return defaultText
    end
    return val
end

-- Sichere Abfrage von Item-Daten über alle WoW-Client-Versionen hinweg
local function SafeGetItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    elseif _G.GetItemInfo then
        return _G.GetItemInfo(itemID)
    end
    return nil
end

-- ============================================================================
-- 1. Trennlinie & Spalten-Überschriften
-- ============================================================================

local DungeonDivider = DungeonsView:CreateTexture(nil, "ARTWORK")
DungeonDivider:SetWidth(2)
DungeonDivider:SetPoint("TOPLEFT", DungeonsView, "TOPLEFT", 220, -32)
DungeonDivider:SetPoint("BOTTOMLEFT", DungeonsView, "BOTTOMLEFT", 220, 44)
DungeonDivider:SetColorTexture(0.45, 0.45, 0.45, 0.9)

local LeftHeader = DungeonsView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LeftHeader:SetPoint("TOPLEFT", DungeonsView, "TOPLEFT", 16, -34)
LeftHeader:SetText(GetSafeLocale("DUNGEON_PRIORITY_HEADER", "Dungeon Priority"))

-- ============================================================================
-- 2. Linke Spalte: Dungeon-Prioritäten (Scoreboard)
-- ============================================================================

local DungeonScroll = CreateFrame("ScrollFrame", "BoisCraftDungeonScroll", DungeonsView, "UIPanelScrollFrameTemplate")
DungeonScroll:SetPoint("TOPLEFT", DungeonsView, "TOPLEFT", 12, -54)
DungeonScroll:SetPoint("BOTTOMLEFT", DungeonsView, "BOTTOMLEFT", 12, 50)
DungeonScroll:SetWidth(182)

local DungeonContent = CreateFrame("Frame", nil, DungeonScroll)
DungeonContent:SetSize(180, 360)
DungeonScroll:SetScrollChild(DungeonContent)

local dungeonRows = {}

local function GetEffectiveSources(itemID)
    local sources = ns.GetItemDropSources and ns.GetItemDropSources(itemID) or {}
    if #sources > 0 then
        return sources
    end
    return {
        {
            dungeonKey = "FALLBACK",
            dungeon    = GetSafeLocale("WL_FALLBACK_DUNGEON", "Wishlist (General)"),
            boss       = GetSafeLocale("WL_FALLBACK_BOSS", "Unassigned / World Drops"),
        }
    }
end

local function GetDungeonGroupKey(src)
    if not src then return "FALLBACK" end
    if src.dungeonKey == "FALLBACK" then
        return "FALLBACK"
    end
    return src.dungeon or src.dungeonKey or "UNKNOWN"
end

function ns.SelectWishlistDungeonForItem(itemID)
    local sources = GetEffectiveSources(itemID)
    if sources and sources[1] then
        selectedDungeonKey = GetDungeonGroupKey(sources[1])
    end
end

local function CalculateDungeonScores()
    local scores = {} -- [dungeonKey] = { score = X, name = "Sauberer Name" }

    local function AddWishlistToScores(list)
        if type(list) ~= "table" then return end
        for itemID, data in pairs(list) do
            if type(data) == "table" and data.status == "WANTED" then
                local sources = GetEffectiveSources(itemID)
                local counted = {}
                for _, src in ipairs(sources) do
                    local dKey = GetDungeonGroupKey(src)
                    if not counted[dKey] then
                        counted[dKey] = true
                        if not scores[dKey] then
                            scores[dKey] = { score = 0, name = src.dungeon }
                        end
                        scores[dKey].score = scores[dKey].score + (tonumber(data.needed) or 1)
                    end
                end
            end
        end
    end

    if BoisCraftWishlist and BoisCraftWishlist.chars then
        for charName, cList in pairs(BoisCraftWishlist.chars) do
            if not filterOnlineGroup or not ns.IsPlayerActiveInGroupOrOnline or ns.IsPlayerActiveInGroupOrOnline(charName) then
                AddWishlistToScores(cList)
            end
        end
    end
    if BoisCraftWishlist and BoisCraftWishlist.friends then
        for fName, fList in pairs(BoisCraftWishlist.friends) do
            if not (BoisCraftWishlist.chars and BoisCraftWishlist.chars[fName]) then
                if not filterOnlineGroup or not ns.IsPlayerActiveInGroupOrOnline or ns.IsPlayerActiveInGroupOrOnline(fName) then
                    AddWishlistToScores(fList)
                end
            end
        end
    end

    return scores
end

-- ============================================================================
-- 3. Rechte Spalte: Filter, Party-Share & Boss-Beute
-- ============================================================================

local FilterOnlineCheck = CreateFrame("CheckButton", "BoisCraftDungeonFilterOnlineCheck", DungeonsView, "UICheckButtonTemplate")
FilterOnlineCheck:SetSize(24, 24)
FilterOnlineCheck:SetPoint("TOPLEFT", DungeonsView, "TOPLEFT", 228, -30)
FilterOnlineCheck:SetChecked(false)

local FilterOnlineLabel = FilterOnlineCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
FilterOnlineLabel:SetPoint("LEFT", FilterOnlineCheck, "RIGHT", 2, 0)
FilterOnlineLabel:SetText(GetSafeLocale("FILTER_ONLINE_GROUP", "Current Group / Online Only"))

FilterOnlineCheck:SetScript("OnClick", function(self)
    filterOnlineGroup = self:GetChecked() and true or false
    ns.UpdateDungeonsView()
end)

local SharePartyBtn = CreateFrame("Button", "BoisCraftDungeonSharePartyBtn", DungeonsView, "UIPanelButtonTemplate")
SharePartyBtn:SetSize(160, 22)
SharePartyBtn:SetPoint("TOPRIGHT", DungeonsView, "TOPRIGHT", -32, -31)
SharePartyBtn:SetText(GetSafeLocale("BTN_SHARE_PARTY", "Share in Party Chat"))

local function SendDungeonWishlistLine(msg, chatType)
    if chatType and SendChatMessage then
        SendChatMessage(msg, chatType)
    else
        print("|cFF00CCFF" .. msg .. "|r")
    end
end

SharePartyBtn:SetScript("OnClick", function()
    if not lastRenderedDungeonName or #lastRenderedBossOrder == 0 then
        print(GetSafeLocale("MSG_PARTY_SHARE_NONE", "|cFFFF7777[BoisCraft]|r No active wishes for the selected dungeon."))
        return
    end

    local chatType = nil
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        chatType = "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup and IsInGroup() then
        chatType = "PARTY"
    end

    local headerFmt = GetSafeLocale("MSG_PARTY_SHARE_HEADER", "[BoisCraft] Wishlist for %s:")
    SendDungeonWishlistLine(string.format(headerFmt, lastRenderedDungeonName), chatType)

    for _, bossName in ipairs(lastRenderedBossOrder) do
        local wishes = lastRenderedWishes[bossName]
        if wishes and #wishes > 0 then
            local byItem = {}
            local itemOrder = {}
            for _, w in ipairs(wishes) do
                if not byItem[w.id] then
                    byItem[w.id] = {}
                    table.insert(itemOrder, w.id)
                end
                table.insert(byItem[w.id], w.owner)
            end

            local parts = {}
            for _, itemID in ipairs(itemOrder) do
                local name, link = SafeGetItemInfo(itemID)
                local itemDisp = link or name or ("Item #" .. itemID)
                table.insert(parts, string.format("%s (%s)", itemDisp, table.concat(byItem[itemID], ", ")))
            end

            local line = string.format("- %s: %s", bossName, table.concat(parts, "; "))
            if #line > 245 then
                line = line:sub(1, 242) .. "..."
            end
            SendDungeonWishlistLine(line, chatType)
        end
    end
end)

local LootScroll = CreateFrame("ScrollFrame", "BoisCraftDungeonLootScroll", DungeonsView, "UIPanelScrollFrameTemplate")
LootScroll:SetPoint("TOPLEFT", DungeonsView, "TOPLEFT", 232, -56)
LootScroll:SetPoint("BOTTOMRIGHT", DungeonsView, "BOTTOMRIGHT", -32, 50)

local LootContent = CreateFrame("Frame", nil, LootScroll)
LootContent:SetSize(540, 380)
LootScroll:SetScrollChild(LootContent)

local bossRows = {}
local itemRows = {}

local EmptyHint = DungeonsView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
EmptyHint:SetPoint("CENTER", LootScroll, "CENTER", 0, 0)
EmptyHint:SetText(GetSafeLocale("DUNGEON_EMPTY_HINT", "|cFF888888No items on your Wishlist yet.\nUse |cFFFFD100Alt + Left-Click|cFF888888 on any item to add it!|r"))
EmptyHint:Hide()

-- ============================================================================
-- 4. Ansicht aktualisieren
-- ============================================================================

function ns.UpdateDungeonsView()
    if not DungeonsView then return end

    LeftHeader:SetText(GetSafeLocale("DUNGEON_PRIORITY_HEADER", "Dungeon Priority"))
    FilterOnlineLabel:SetText(GetSafeLocale("FILTER_ONLINE_GROUP", "Current Group / Online Only"))
    SharePartyBtn:SetText(GetSafeLocale("BTN_SHARE_PARTY", "Share in Party Chat"))
    EmptyHint:SetText(GetSafeLocale("DUNGEON_EMPTY_HINT", "|cFF888888No items on your Wishlist yet.\nUse |cFFFFD100Alt + Left-Click|cFF888888 on any item to add it!|r"))

    lastRenderedDungeonName = nil
    lastRenderedBossOrder = {}
    lastRenderedWishes = {}

    for _, r in ipairs(dungeonRows) do r:Hide() end
    for _, r in ipairs(bossRows) do r:Hide() end
    for _, r in ipairs(itemRows) do r:Hide() end

    local scores = CalculateDungeonScores()
    local sortedDungeons = {}
    for dKey, dInfo in pairs(scores) do
        table.insert(sortedDungeons, { key = dKey, name = dInfo.name, score = dInfo.score })
    end

    table.sort(sortedDungeons, function(a, b)
        if a.key == "FALLBACK" and b.key ~= "FALLBACK" then return false end
        if b.key == "FALLBACK" and a.key ~= "FALLBACK" then return true end
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)

    if #sortedDungeons == 0 then
        EmptyHint:Show()
        return
    else
        EmptyHint:Hide()
    end

    if not selectedDungeonKey or not scores[selectedDungeonKey] then
        selectedDungeonKey = sortedDungeons[1].key
    end

    local selectedDungeonName = scores[selectedDungeonKey] and scores[selectedDungeonKey].name or selectedDungeonKey

    -- A. Linke Liste rendern
    local yDungeon = 0
    for idx, dEntry in ipairs(sortedDungeons) do
        local row = dungeonRows[idx]
        if not row then
            row = CreateFrame("Button", nil, DungeonContent)
            row:SetSize(178, 26)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            dungeonRows[idx] = row
        end

        row:SetPoint("TOPLEFT", DungeonContent, "TOPLEFT", 0, -yDungeon)

        local isSelected = (selectedDungeonKey == dEntry.key)
        if isSelected then
            row.bg:SetColorTexture(0.25, 0.45, 0.75, 0.55)
            row.text:SetText(string.format("|cFFFFFFFF%s (%d)|r", dEntry.name, dEntry.score))
        else
            row.bg:SetColorTexture(0.15, 0.15, 0.15, 0.65)
            row.text:SetText(string.format("|cFFFFD100%s|r |cFF00FF00(%d)|r", dEntry.name, dEntry.score))
        end

        local clickedKey = dEntry.key
        row:SetScript("OnClick", function()
            selectedDungeonKey = clickedKey
            ns.UpdateDungeonsView()
        end)

        row:Show()
        yDungeon = yDungeon + 28
    end
    DungeonContent:SetHeight(math.max(350, yDungeon + 10))

    -- B. Rechte Spalte rendern
    if not selectedDungeonKey then return end

    local yLoot = 0
    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player")

    local activeWishes = {}
    local bossOrder = {}

    local function CollectWish(ownerName, itemID, data)
        if type(data) ~= "table" or data.status ~= "WANTED" then return end
        if filterOnlineGroup and ns.IsPlayerActiveInGroupOrOnline and not ns.IsPlayerActiveInGroupOrOnline(ownerName) then
            return
        end
        local sources = GetEffectiveSources(itemID)
        for _, src in ipairs(sources) do
            local dKey = GetDungeonGroupKey(src)
            if dKey == selectedDungeonKey then
                local bName = src.boss or "Boss"
                if not activeWishes[bName] then
                    activeWishes[bName] = {}
                    table.insert(bossOrder, bName)
                end
                table.insert(activeWishes[bName], {
                    owner  = ownerName,
                    id     = tonumber(itemID),
                    needed = tonumber(data.needed) or 1,
                })
            end
        end
    end

    if BoisCraftWishlist and BoisCraftWishlist.chars then
        for charName, cList in pairs(BoisCraftWishlist.chars) do
            if type(cList) == "table" then
                for id, dat in pairs(cList) do
                    CollectWish(charName, id, dat)
                end
            end
        end
    end
    if BoisCraftWishlist and BoisCraftWishlist.friends then
        for fName, fList in pairs(BoisCraftWishlist.friends) do
            if not (BoisCraftWishlist.chars and BoisCraftWishlist.chars[fName]) and type(fList) == "table" then
                for id, dat in pairs(fList) do
                    CollectWish(fName, id, dat)
                end
            end
        end
    end

    table.sort(bossOrder)
    lastRenderedDungeonName = selectedDungeonName
    lastRenderedBossOrder = bossOrder
    lastRenderedWishes = activeWishes

    local bossRowIndex = 0
    local itemRowIndex = 0

    for _, bossName in ipairs(bossOrder) do
        local wishes = activeWishes[bossName]
        table.sort(wishes, function(a, b)
            if a.id == b.id then return tostring(a.owner) < tostring(b.owner) end
            return (a.id or 0) < (b.id or 0)
        end)

        bossRowIndex = bossRowIndex + 1
        local bossRow = bossRows[bossRowIndex]
        if not bossRow then
            bossRow = CreateFrame("Frame", nil, LootContent)
            bossRow:SetSize(520, 24)
            bossRow.text = bossRow:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
            bossRow.text:SetPoint("LEFT", bossRow, "LEFT", 4, 0)
            bossRows[bossRowIndex] = bossRow
        end
        bossRow:SetPoint("TOPLEFT", LootContent, "TOPLEFT", 0, -yLoot)
        bossRow.text:SetText("|cFFFFD100" .. bossName .. "|r")
        bossRow:Show()
        yLoot = yLoot + 26

        for _, w in ipairs(wishes) do
            itemRowIndex = itemRowIndex + 1
            local row = itemRows[itemRowIndex]
            if not row then
                row = CreateFrame("Button", nil, LootContent)
                row:SetSize(520, 30)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0.15, 0.15, 0.15, 0.65)

                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 0.82, 0, 0.10)

                row.iconBtn = CreateFrame("Button", nil, row)
                row.iconBtn:SetSize(24, 24)
                row.iconBtn:SetPoint("LEFT", row, "LEFT", 8, 0)

                row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
                row.icon:SetAllPoints()
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                row.border = row.iconBtn:CreateTexture(nil, "OVERLAY")
                row.border:SetSize(42, 42)
                row.border:SetPoint("CENTER", row.iconBtn, "CENTER", 0, 0)
                row.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                row.border:SetBlendMode("ADD")

                row.lootBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.lootBtn:SetSize(75, 22)
                row.lootBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

                row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.removeBtn:SetSize(75, 22)
                row.removeBtn:SetPoint("RIGHT", row.lootBtn, "LEFT", -4, 0)

                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
                row.text:SetPoint("RIGHT", row.removeBtn, "LEFT", -8, 0)
                row.text:SetJustifyH("LEFT")

                itemRows[itemRowIndex] = row
            end

            row:SetPoint("TOPLEFT", LootContent, "TOPLEFT", 10, -yLoot)
            row.bg:Show()
            row.iconBtn:Show()
            row.lootBtn:Show()
            row.lootBtn:SetText(GetSafeLocale("BTN_LOOTED", "Looted"))
            row.removeBtn:SetText(GetSafeLocale("BTN_REMOVE", "Remove"))
            row.removeBtn:Show()

            local coloredOwner = (ns.GetColoredPlayerName and ns.GetColoredPlayerName(w.owner)) or w.owner

            -- Sicheres Initial-Rendering ohne Absturz, falls GetItemInfo nil ist
            local name, link, quality, _, _, _, _, _, _, tex = SafeGetItemInfo(w.id)
            local fallbackIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(w.id)) or tex or 134400
            row.icon:SetTexture(fallbackIcon)
            if ns.SetIconQualityBorder then ns.SetIconQualityBorder(row.border, quality or 2) end
            row.text:SetText(string.format("%s (x%d)  —  %s", link or name or ("Item #" .. w.id), w.needed, coloredOwner))

            local expectedItemID = w.id
            local expectedNeeded = w.needed
            local expectedOwner = coloredOwner
            row.currentItemID = expectedItemID

            if ns.AsyncLoadItem then
                ns.AsyncLoadItem(expectedItemID, function(_, itemLink, itemQuality, itemIcon)
                    if row.currentItemID ~= expectedItemID then return end
                    row.icon:SetTexture(itemIcon or fallbackIcon)
                    if ns.SetIconQualityBorder then ns.SetIconQualityBorder(row.border, itemQuality) end
                    local displayLink = itemLink or ("Item #" .. expectedItemID)
                    row.text:SetText(string.format("%s (x%d)  —  %s", displayLink, expectedNeeded, expectedOwner))
                end)
            end

            local function ShowRowTooltip(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(w.id)
                else
                    GameTooltip:SetHyperlink("item:" .. tostring(w.id))
                end
                GameTooltip:Show()
                if IsModifiedClick and IsModifiedClick("DRESSUP") and ShowInspectCursor then
                    ShowInspectCursor()
                else
                    ResetCursor()
                end
            end

            local function HideRowTooltip()
                GameTooltip:Hide()
                ResetCursor()
            end

            local function OnRowItemClick(_, button)
                if button ~= "LeftButton" then return end
                local _, itemLink = SafeGetItemInfo(w.id)
                local linkOrItem = itemLink or ("item:" .. tostring(w.id))
                if IsControlKeyDown() then
                    if DressUpItemLink then
                        DressUpItemLink(linkOrItem)
                    elseif HandleModifiedItemClick and itemLink then
                        HandleModifiedItemClick(itemLink)
                    end
                    if DressUpFrame and DressUpFrame:IsShown() then
                        local topParent = ns.MainFrame or _G["BoisCraftMainFrame"]
                        if topParent then
                            DressUpFrame:SetFrameStrata(topParent:GetFrameStrata())
                            DressUpFrame:SetFrameLevel(topParent:GetFrameLevel() + 20)
                        end
                        DressUpFrame:Raise()
                    end
                elseif IsShiftKeyDown() and itemLink and HandleModifiedItemClick then
                    HandleModifiedItemClick(itemLink)
                end
            end

            row:SetScript("OnEnter", ShowRowTooltip)
            row:SetScript("OnLeave", HideRowTooltip)
            row:SetScript("OnClick", OnRowItemClick)

            row.iconBtn:SetScript("OnEnter", ShowRowTooltip)
            row.iconBtn:SetScript("OnLeave", HideRowTooltip)
            row.iconBtn:SetScript("OnClick", OnRowItemClick)

            row.lootBtn:SetScript("OnClick", function()
                BoisCraftLootHistory = BoisCraftLootHistory or {}
                table.insert(BoisCraftLootHistory, {
                    player    = w.owner,
                    itemID    = w.id,
                    dungeon   = selectedDungeonName,
                    boss      = bossName,
                    timestamp = time(),
                })

                if BoisCraftWishlist.chars and BoisCraftWishlist.chars[w.owner] and BoisCraftWishlist.chars[w.owner][w.id] then
                    BoisCraftWishlist.chars[w.owner][w.id].status = "LOOTED"
                    if w.owner == myName and ns.BroadcastMyWishlist then
                        ns.BroadcastMyWishlist()
                    end
                end
                if BoisCraftWishlist.friends and BoisCraftWishlist.friends[w.owner] and BoisCraftWishlist.friends[w.owner][w.id] then
                    BoisCraftWishlist.friends[w.owner][w.id].status = "LOOTED"
                end

                local cleanDungeon = tostring(selectedDungeonName or "Dungeon"):gsub(":", " -")
                local cleanBoss = tostring(bossName or "Boss"):gsub(":", " -")
                local payload = string.format("LOOTED:%s:%d:%s:%s:%d", w.owner, w.id, cleanDungeon, cleanBoss, time())
                if ns.SendSyncMessage then ns.SendSyncMessage(payload) end

                ns.UpdateDungeonsView()
                if ns.UpdateLootLogView then ns.UpdateLootLogView() end
            end)

            row.removeBtn:SetScript("OnClick", function()
                if BoisCraftWishlist.chars and BoisCraftWishlist.chars[w.owner] then
                    BoisCraftWishlist.chars[w.owner][w.id] = nil
                end
                if BoisCraftWishlist.friends and BoisCraftWishlist.friends[w.owner] then
                    BoisCraftWishlist.friends[w.owner][w.id] = nil
                end
                if w.owner == myName and ns.BroadcastMyWishlist then
                    ns.BroadcastMyWishlist()
                end
                ns.UpdateDungeonsView()
            end)

            row:Show()
            yLoot = yLoot + 32
        end
    end

    LootContent:SetHeight(math.max(360, yLoot + 10))
end

DungeonsView:RegisterEvent("GROUP_ROSTER_UPDATE")
DungeonsView:SetScript("OnEvent", function(self)
    if self:IsShown() then
        ns.UpdateDungeonsView()
    end
end)

DungeonsView:SetScript("OnShow", function()
    ns.UpdateDungeonsView()
end)