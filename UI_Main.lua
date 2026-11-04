local addonName, ns = ...
local L = ns.L

-- ============================================================================
-- 1. Hauptfenster (Dunkles Blizzard-Dialog-Design, 820x480)
-- ============================================================================

local MainFrame = CreateFrame("Frame", "BoisCraftMainFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(820, 480)
MainFrame:SetPoint("CENTER")
MainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
MainFrame:SetFrameStrata("HIGH")
MainFrame:Hide()

tinsert(UISpecialFrames, "BoisCraftMainFrame")
ns.MainFrame = MainFrame

-- Titelzeile & Trennlinie oben
local TitleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
TitleText:SetPoint("TOP", MainFrame, "TOP", 0, -10)
MainFrame.TitleText = TitleText

local TopBarLine = MainFrame:CreateTexture(nil, "BORDER")
TopBarLine:SetHeight(1)
TopBarLine:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 8, -28)
TopBarLine:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -8, -28)
TopBarLine:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- Schließen-Button oben rechts
local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)

-- ============================================================================
-- 2. Ansichts-Container (Views für die 4 Reiter)
-- ============================================================================

local CatalogView = CreateFrame("Frame", nil, MainFrame)
CatalogView:SetAllPoints(MainFrame)
ns.CatalogView = CatalogView

local OrdersView = CreateFrame("Frame", nil, MainFrame)
OrdersView:SetAllPoints(MainFrame)
OrdersView:Hide()
ns.OrdersView = OrdersView

local ShoppingView = CreateFrame("Frame", nil, MainFrame)
ShoppingView:SetAllPoints(MainFrame)
ShoppingView:Hide()
ns.ShoppingView = ShoppingView

local DungeonsView = CreateFrame("Frame", nil, MainFrame)
DungeonsView:SetAllPoints(MainFrame)
DungeonsView:Hide()
ns.DungeonsView = DungeonsView

-- ============================================================================
-- 3. Untere Reiter-Buttons (Tabs 1 bis 4)
-- ============================================================================

local function CreateBottomTab(id, name, parent)
    local tab = CreateFrame("Button", name, parent, "BackdropTemplate")
    tab:SetID(id)
    tab:SetSize(135, 30)
    tab:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER", 0, 0)

    tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.highlight:SetAllPoints()
    tab.highlight:SetColorTexture(1, 0.82, 0, 0.15)

    function tab:SetTabText(str)
        self.text:SetText(str)
        local textWidth = self.text:GetStringWidth() or 80
        self:SetWidth(math.max(115, textWidth + 32))
    end

    return tab
end

local Tab1 = CreateBottomTab(1, "BoisCraftTab1", MainFrame)
Tab1:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 12, 2)
ns.Tab1 = Tab1

local Tab2 = CreateBottomTab(2, "BoisCraftTab2", MainFrame)
Tab2:SetPoint("LEFT", Tab1, "RIGHT", 4, 0)
ns.Tab2 = Tab2

local Tab3 = CreateBottomTab(3, "BoisCraftTab3", MainFrame)
Tab3:SetPoint("LEFT", Tab2, "RIGHT", 4, 0)
ns.Tab3 = Tab3

local Tab4 = CreateBottomTab(4, "BoisCraftTab4", MainFrame)
Tab4:SetPoint("LEFT", Tab3, "RIGHT", 4, 0)
ns.Tab4 = Tab4

local allTabs = { Tab1, Tab2, Tab3, Tab4 }

function ns.SelectTab(tabID)
    ns.activeTabID = tabID

    CatalogView:SetShown(tabID == 1)
    OrdersView:SetShown(tabID == 2)
    ShoppingView:SetShown(tabID == 3)
    DungeonsView:SetShown(tabID == 4)

    -- Beute-Log-Button oben rechts nur im Dungeon-Reiter einblenden (falls vorhanden)
    if ns.LogToggleBtn then
        ns.LogToggleBtn:SetShown(tabID == 4)
    end
    if tabID ~= 4 and ns.LootLogFrame then
        ns.LootLogFrame:Hide()
    end

    for idx, tab in ipairs(allTabs) do
        if idx == tabID then
            tab:SetBackdropBorderColor(1, 0.82, 0, 1)
            tab.text:SetFontObject(GameFontHighlight)
        else
            tab:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            tab.text:SetFontObject(GameFontNormal)
        end
    end

    if tabID == 1 then
        if ns.RenderProfessions then ns.RenderProfessions() end
        if ns.selectedProfession and ns.DisplayRecipesForProfession then
            ns.DisplayRecipesForProfession(ns.selectedProfession)
        end
    elseif tabID == 2 then
        if ns.UpdateOrdersList then ns.UpdateOrdersList() end
    elseif tabID == 3 then
        if ns.UpdateShoppingListView then ns.UpdateShoppingListView() end
    elseif tabID == 4 then
        if ns.UpdateDungeonsView then ns.UpdateDungeonsView() end
    end
end

for idx, tab in ipairs(allTabs) do
    tab:SetScript("OnClick", function()
        ns.SelectTab(idx)
    end)
end

-- ============================================================================
-- 4. Sprach-Aktualisierung & Öffnen/Schließen
-- ============================================================================

function ns.RefreshMainFrameLocale()
    TitleText:SetText(L["MAIN_TITLE"])
    Tab1:SetTabText(L["TAB_RECIPES"])

    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    local seenOrderIDs = {}
    local orderCount = 0

    -- 1. Eingegangene Aufträge für diesen Charakter zählen
    if IncomingOrders then
        for _, o in ipairs(IncomingOrders) do
            local cNorm = (ns.NormalizeName and ns.NormalizeName(o.crafter)) or o.crafter
            if not cNorm or cNorm == "" or cNorm == myName then
                orderCount = orderCount + 1
                if o.orderID then
                    seenOrderIDs[o.orderID] = true
                end
            end
        end
    end

    -- 2. Eigene erteilte Bestellungen (PendingOrders) mitzählen (ohne Eigenbestellungen doppelt zu zählen)
    if PendingOrders then
        for _, p in ipairs(PendingOrders) do
            local sNorm = (ns.NormalizeName and ns.NormalizeName(p.sender)) or p.sender
            if not sNorm or sNorm == "" or sNorm == myName then
                if not p.orderID or not seenOrderIDs[p.orderID] then
                    orderCount = orderCount + 1
                end
            end
        end
    end

    if Tab2.SetTabText then
        Tab2:SetTabText(string.format(L["TAB_ORDERS"], orderCount))
    else
        Tab2:SetText(string.format(L["TAB_ORDERS"], orderCount))
    end
    Tab3:SetTabText(L["TAB_SHOPPING"])
    if Tab4 and L["TAB_DUNGEONS"] then
        Tab4:SetTabText(L["TAB_DUNGEONS"])
    end
end

MainFrame:SetScript("OnShow", function()
    ns.RefreshMainFrameLocale()
    ns.SelectTab(ns.activeTabID or 1)
end)

function ns.ToggleMainFrame()
    if MainFrame:IsShown() then
        MainFrame:Hide()
    else
        MainFrame:Show()
    end
end

-- Slash-Befehle (/bc und /boiscraft)
SLASH_BOISCRAFT1 = "/bc"
SLASH_BOISCRAFT2 = "/boiscraft"
SlashCmdList["BOISCRAFT"] = function(msg)
    local cmd = strtrim((msg or ""):lower())
    if cmd == "options" or cmd == "config" then
        if ns.ToggleOptions then ns.ToggleOptions() end
    elseif cmd == "sync" then
        if ns.ManualSync then ns.ManualSync() end
    elseif cmd:match("^sync%s+") then
        if ns.ManualSync then ns.ManualSync(strtrim(cmd:sub(6))) end
    else
        ns.ToggleMainFrame()
    end
end

ns.RefreshMainFrameLocale()
ns.SelectTab(1)