local addonName, ns = ...
local L = ns.L

BoisCraftLootHistory = BoisCraftLootHistory or {}

-- ============================================================================
-- 1. Seitenfenster (Dockt an ns.MainFrame an)
-- ============================================================================

local LootLogFrame = CreateFrame("Frame", "BoisCraftLootLogFrame", ns.MainFrame, "BackdropTemplate")
LootLogFrame:SetSize(320, 480)
LootLogFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 2, 0)
LootLogFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
LootLogFrame:Hide()
ns.LootLogFrame = LootLogFrame

local logTitle = LootLogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logTitle:SetPoint("TOP", LootLogFrame, "TOP", 0, -12)
logTitle:SetText(L["LOOTLOG_TITLE"])

local closeBtn = CreateFrame("Button", nil, LootLogFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function() LootLogFrame:Hide() end)

-- ============================================================================
-- 2. Statistik-Header (Wer hat wie viel Loot?)
-- ============================================================================

local statsHeader = LootLogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statsHeader:SetPoint("TOPLEFT", LootLogFrame, "TOPLEFT", 15, -35)
statsHeader:SetPoint("TOPRIGHT", LootLogFrame, "TOPRIGHT", -15, -35)
statsHeader:SetJustifyH("LEFT")

local function UpdateLootStatistics()
    local counts = {}
    for _, entry in ipairs(BoisCraftLootHistory) do
        counts[entry.player] = (counts[entry.player] or 0) + 1
    end

    local statLines = {}
    for player, count in pairs(counts) do
        table.insert(statLines, string.format("%s: %d", ns.GetColoredPlayerName(player), count))
    end

    if #statLines > 0 then
        statsHeader:SetText(L["LOOTLOG_STATS_PREFIX"] .. table.concat(statLines, " | "))
    else
        statsHeader:SetText(L["LOOTLOG_EMPTY"])
    end
end

local statDivider = LootLogFrame:CreateTexture(nil, "BORDER")
statDivider:SetHeight(1)
statDivider:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", -5, -6)
statDivider:SetPoint("TOPRIGHT", statsHeader, "BOTTOMRIGHT", 5, -6)
statDivider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

-- ============================================================================
-- 3. ScrollFrame & Beute-Einträge
-- ============================================================================

local LogScroll = CreateFrame("ScrollFrame", "BoisCraftLogScroll", LootLogFrame, "UIPanelScrollFrameTemplate")
LogScroll:SetPoint("TOPLEFT", statDivider, "BOTTOMLEFT", 0, -8)
LogScroll:SetPoint("BOTTOMRIGHT", LootLogFrame, "BOTTOMRIGHT", -26, 35)

local LogContent = CreateFrame("Frame", nil, LogScroll)
LogContent:SetSize(280, 360)
LogScroll:SetScrollChild(LogContent)

local logRows = {}

function ns.UpdateLootLogView()
    UpdateLootStatistics()
    for _, row in ipairs(logRows) do row:Hide() end

    local yOffset = 0
    for index = #BoisCraftLootHistory, 1, -1 do
        local entry = BoisCraftLootHistory[index]
        local displayIdx = #BoisCraftLootHistory - index + 1

        local row = logRows[displayIdx]
        if not row then
            row = CreateFrame("Frame", nil, LogContent)
            row:SetSize(275, 32)
            
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 4)
            row.text:SetPoint("RIGHT", row, "RIGHT", -5, 4)
            row.text:SetJustifyH("LEFT")

            row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.subText:SetPoint("LEFT", row.icon, "RIGHT", 6, -8)
            row.subText:SetJustifyH("LEFT")

            logRows[displayIdx] = row
        end

        row:SetPoint("TOPLEFT", LogContent, "TOPLEFT", 0, -yOffset)

        ns.AsyncLoadItem(entry.itemID, function(_, itemLink, _, itemIcon)
            row.icon:SetTexture(itemIcon or 134400)
            local dateStr = entry.timestamp and date("%d.%m.", entry.timestamp) or ""
            row.text:SetText(string.format("%s: %s", ns.GetColoredPlayerName(entry.player), itemLink or ("Item #" .. entry.itemID)))
            row.subText:SetText(string.format("%s - %s (%s)", dateStr, entry.dungeon or "Dungeon", entry.boss or "Boss"))
        end)

        row:Show()
        yOffset = yOffset + 34
    end

    LogContent:SetHeight(math.max(360, yOffset + 10))
end

-- ============================================================================
-- 4. Toggle-Knopf in ns.MainFrame (Oben Rechts im Hauptfenster)
-- ============================================================================

local logToggleBtn = CreateFrame("Button", "BoisCraftLogToggleBtn", ns.MainFrame, "UIPanelButtonTemplate")
logToggleBtn:SetSize(110, 20)
logToggleBtn:SetPoint("TOPRIGHT", ns.MainFrame, "TOPRIGHT", -32, -6)
logToggleBtn:SetText(L["BTN_OPEN_LOOTLOG"])
ns.LogToggleBtn = logToggleBtn
logToggleBtn:Hide() -- Wird nur im 4. Reiter eingeblendet

logToggleBtn:SetScript("OnClick", function()
    if LootLogFrame:IsShown() then
        LootLogFrame:Hide()
        logToggleBtn:SetText(L["BTN_OPEN_LOOTLOG"])
    else
        LootLogFrame:Show()
        logToggleBtn:SetText(L["BTN_CLOSE_LOOTLOG"])
        ns.UpdateLootLogView()
    end
end)

ns.MainFrame:HookScript("OnHide", function()
    LootLogFrame:Hide()
    logToggleBtn:SetText(L["BTN_OPEN_LOOTLOG"])
end)