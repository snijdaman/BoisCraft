local addonName, ns = ...
local L = ns.L

local CatalogView = ns.CatalogView
if not CatalogView then
    local parent = ns.MainFrame or UIParent
    CatalogView = CreateFrame("Frame", nil, parent)
    CatalogView:SetAllPoints(parent)
    ns.CatalogView = CatalogView
end

ns.selectedProfession = nil
ns.selectedFilterCrafter = nil
ns.selectedRecipeID = nil
ns.selectedCrafter = nil
ns.orderQuantity = 1

local expandedProfessions = {}
local searchFilterText = ""
local filterOnlyCraftable = false

-- ============================================================================
-- 1. Hilfsfunktionen: Qualitätsrahmen & Einkaufslisten-Verbuchung
-- ============================================================================

function ns.SetIconQualityBorder(borderTexture, quality)
    if not borderTexture then return end
    quality = tonumber(quality)
    if quality and quality >= 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        borderTexture:SetVertexColor(c.r, c.g, c.b, 0.95)
        borderTexture:Show()
    else
        borderTexture:SetVertexColor(0.35, 0.35, 0.35, 0.7)
        borderTexture:Show()
    end
end

function ns.AddRecipeToShoppingList(crafterName, recipeID, orderQty)
    crafterName = ns.NormalizeName(crafterName)
    recipeID = tonumber(recipeID)
    orderQty = tonumber(orderQty) or 1
    if crafterName == "" or not recipeID then return end

    local reagents = ns.GetRecipeRequiredReagents(recipeID)
    if not reagents or #reagents == 0 then return end

    ShoppingList = ShoppingList or {}
    ShoppingList[crafterName] = ShoppingList[crafterName] or {}

    local seenInThisCall = {}
    for _, reg in ipairs(reagents) do
        local rItemID = tonumber(reg.itemID)
        local reqPerCraft = tonumber(reg.count) or 1
        if rItemID and not seenInThisCall[rItemID] then
            seenInThisCall[rItemID] = true
            local totalAdd = reqPerCraft * orderQty
            ShoppingList[crafterName][rItemID] = (ShoppingList[crafterName][rItemID] or 0) + totalAdd
        end
    end

    if ns.UpdateShoppingListView then
        ns.UpdateShoppingListView()
    end
end

function ns.RemoveRecipeFromShoppingList(crafterName, recipeID, orderQty)
    crafterName = ns.NormalizeName(crafterName)
    recipeID = tonumber(recipeID)
    orderQty = tonumber(orderQty) or 1
    if crafterName == "" or not recipeID or not ShoppingList or not ShoppingList[crafterName] then return end

    local reagents = ns.GetRecipeRequiredReagents(recipeID)
    if not reagents or #reagents == 0 then return end

    local seenInThisCall = {}
    for _, reg in ipairs(reagents) do
        local rItemID = tonumber(reg.itemID)
        local reqPerCraft = tonumber(reg.count) or 1
        if rItemID and not seenInThisCall[rItemID] and ShoppingList[crafterName][rItemID] then
            seenInThisCall[rItemID] = true
            local totalRemove = reqPerCraft * orderQty
            local newVal = ShoppingList[crafterName][rItemID] - totalRemove
            if newVal <= 0 then
                ShoppingList[crafterName][rItemID] = nil
            else
                ShoppingList[crafterName][rItemID] = newVal
            end
        end
    end

    local hasRemaining = false
    for _, cnt in pairs(ShoppingList[crafterName]) do
        if cnt and cnt > 0 then hasRemaining = true break end
    end
    if not hasRemaining then
        ShoppingList[crafterName] = nil
    end

    if ns.UpdateShoppingListView then
        ns.UpdateShoppingListView()
    end
end

-- ============================================================================
-- 2. Dreispaltiges Layout & Trennlinien
-- ============================================================================

-- Vertikale Linie 1 (zwischen Berufe-Baum und Rezeptliste)
local LeftDivider = CatalogView:CreateTexture(nil, "BORDER")
LeftDivider:SetWidth(1)
LeftDivider:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 215, -30)
LeftDivider:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 215, 44)
LeftDivider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

-- Vertikale Linie 2 (zwischen Rezeptliste und Vorschau)
local RightDivider = CatalogView:CreateTexture(nil, "BORDER")
RightDivider:SetWidth(1)
RightDivider:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 505, -30)
RightDivider:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 505, 44)
RightDivider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

-- Horizontale Footer-Linie unten
local FooterDivider = CatalogView:CreateTexture(nil, "BORDER")
FooterDivider:SetHeight(1)
FooterDivider:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 10, 44)
FooterDivider:SetPoint("BOTTOMRIGHT", CatalogView, "BOTTOMRIGHT", -10, 44)
FooterDivider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

-- ============================================================================
-- 3. Linke Spalte: Ausklappbare Berufe + Charaktere mit Skill-Level
-- ============================================================================

local ProfScroll = CreateFrame("ScrollFrame", "BoisCraftProfScroll", CatalogView, "UIPanelScrollFrameTemplate")
ProfScroll:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 12, -36)
ProfScroll:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 12, 50)
ProfScroll:SetWidth(178)

local ProfContent = CreateFrame("Frame", nil, ProfScroll)
ProfContent:SetSize(175, 380)
ProfScroll:SetScrollChild(ProfContent)

local profHeaderButtons = {}
local profCrafterButtons = {}

-- Hilfsfunktion: Alle Freunde finden, die diesen Beruf kennen
local function GetFriendsWithProfession(profKey)
    local list = {}
    if not FriendProfessionDB then return list end
    for friendName, profs in pairs(FriendProfessionDB) do
        if type(profs) == "table" then
            for pName, recipes in pairs(profs) do
                if ns.NormalizeProfName(pName) == profKey and type(recipes) == "table" and #recipes > 0 then
                    table.insert(list, friendName)
                    break
                end
            end
        end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

local function CountMatchingRecipesInProfession(profKey)
    if not FriendProfessionDB then return 0 end
    local uniqueRecipes = {}
    for friendName, profs in pairs(FriendProfessionDB) do
        if not ns.selectedFilterCrafter or ns.selectedFilterCrafter == friendName then
            if type(profs) == "table" then
                for pName, recipes in pairs(profs) do
                    if ns.NormalizeProfName(pName) == profKey and type(recipes) == "table" then
                        for _, rID in ipairs(recipes) do
                            uniqueRecipes[tonumber(rID)] = true
                        end
                    end
                end
            end
        end
    end
    local count = 0
    for rID, _ in pairs(uniqueRecipes) do
        local rName = ns.GetLocalizedRecipeName(rID) or ""
        local matchesSearch = (searchFilterText == "") or (rName:lower():find(searchFilterText, 1, true) ~= nil)
        local matchesCraftable = (not filterOnlyCraftable) or ns.HasReagentsForRecipe(rID)
        if matchesSearch and matchesCraftable then
            count = count + 1
        end
    end
    return count
end

function ns.RenderProfessions()
    for _, btn in ipairs(profHeaderButtons) do btn:Hide() end
    for _, btn in ipairs(profCrafterButtons) do btn:Hide() end

    local headerIndex = 0
    local crafterIndex = 0
    local yOffset = 0

    for _, profKey in ipairs(ns.DISPLAY_PROFESSIONS) do
        headerIndex = headerIndex + 1
        local btn = profHeaderButtons[headerIndex]
        if not btn then
            btn = CreateFrame("Button", nil, ProfContent)
            btn:SetSize(172, 24)

            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()

            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            btn.text:SetJustifyH("LEFT")
            if btn.text.SetWordWrap then btn.text:SetWordWrap(false) end

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            profHeaderButtons[headerIndex] = btn
        end

        btn:SetPoint("TOPLEFT", ProfContent, "TOPLEFT", 0, -yOffset)

        local isKnown = ns.IsProfessionKnownByAnyFriend(profKey)
        local isSelectedProf = (ns.selectedProfession == profKey)
        local isExpanded = expandedProfessions[profKey]
        local localizedName = ns.GetLocalizedProfName(profKey)

        if isSelectedProf and not ns.selectedFilterCrafter then
            btn.bg:SetColorTexture(0.25, 0.45, 0.75, 0.45)
        elseif isSelectedProf then
            btn.bg:SetColorTexture(0.2, 0.3, 0.45, 0.25)
        else
            btn.bg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        end

        if isKnown then
            local arrow = isExpanded and "[-] " or "[+] "
            local color = isSelectedProf and "|cFFFFFFFF" or "|cFFFFD100"
            local matchSuffix = ""
            if searchFilterText ~= "" or filterOnlyCraftable then
                local mCount = CountMatchingRecipesInProfession(profKey)
                if mCount > 0 then
                    matchSuffix = string.format(" |cFF00FF00(%d)|r", mCount)
                else
                    matchSuffix = " |cFF666666(0)|r"
                end
            end
            btn.text:SetText(arrow .. color .. localizedName .. "|r" .. matchSuffix)
            btn:Enable()
        else
            btn.text:SetText("    |cFF666666" .. localizedName .. "|r")
            btn:Disable()
        end

        btn:SetScript("OnClick", function()
            if ns.selectedProfession == profKey and not ns.selectedFilterCrafter then
                expandedProfessions[profKey] = not expandedProfessions[profKey]
            else
                ns.selectedProfession = profKey
                ns.selectedFilterCrafter = nil
                expandedProfessions[profKey] = true
            end
            ns.RenderProfessions()
            ns.DisplayRecipesForProfession(profKey)
        end)

        btn:Show()
        yOffset = yOffset + 26

        -- Wenn Beruf aufgeklappt ist: Darunter die einzelnen Charaktere mit Skill-Level auflisten
        if isKnown and isExpanded then
            local crafters = GetFriendsWithProfession(profKey)
            for _, friendName in ipairs(crafters) do
                crafterIndex = crafterIndex + 1
                local subBtn = profCrafterButtons[crafterIndex]
                if not subBtn then
                    subBtn = CreateFrame("Button", nil, ProfContent)
                    subBtn:SetSize(172, 20)

                    subBtn.bg = subBtn:CreateTexture(nil, "BACKGROUND")
                    subBtn.bg:SetAllPoints()

                    subBtn.text = subBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    subBtn.text:SetPoint("LEFT", subBtn, "LEFT", 8, 0)
                    subBtn.text:SetPoint("RIGHT", subBtn, "RIGHT", -2, 0)
                    subBtn.text:SetJustifyH("LEFT")
                    if subBtn.text.SetWordWrap then subBtn.text:SetWordWrap(false) end

                    local hl = subBtn:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0.12)

                    profCrafterButtons[crafterIndex] = subBtn
                end

                subBtn:SetPoint("TOPLEFT", ProfContent, "TOPLEFT", 0, -yOffset)

                local isFilteredChar = (isSelectedProf and ns.selectedFilterCrafter == friendName)
                if isFilteredChar then
                    subBtn.bg:SetColorTexture(0.25, 0.55, 0.35, 0.45)
                else
                    subBtn.bg:SetColorTexture(0, 0, 0, 0)
                end

                local coloredName = ns.GetColoredPlayerName(friendName)
                local skillStr = ns.GetPlayerProfessionSkillText(friendName, profKey)
                if skillStr then
                    subBtn.text:SetText(string.format("|cFFAAAAAA•|r %s |cFFAAAAAA(%s)|r", coloredName, skillStr))
                else
                    subBtn.text:SetText(string.format("|cFFAAAAAA•|r %s", coloredName))
                end

                subBtn:Enable()
                subBtn:SetScript("OnClick", function()
                    ns.selectedProfession = profKey
                    if ns.selectedFilterCrafter == friendName then
                        ns.selectedFilterCrafter = nil
                    else
                        ns.selectedFilterCrafter = friendName
                    end
                    ns.RenderProfessions()
                    ns.DisplayRecipesForProfession(profKey)
                end)

                subBtn:Show()
                yOffset = yOffset + 21
            end
        end
    end

    ProfContent:SetHeight(math.max(360, yOffset + 10))
end

-- ============================================================================
-- 4. Mittlere Spalte: Echtzeit-Suchleiste, Material-Filter & Rezeptliste
-- ============================================================================

local SearchBox = CreateFrame("EditBox", "BoisCraftRecipeSearchBox", CatalogView, "InputBoxTemplate")
SearchBox:SetSize(155, 22)
SearchBox:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 230, -36)
SearchBox:SetAutoFocus(false)

local SearchPlaceholder = SearchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
SearchPlaceholder:SetPoint("LEFT", SearchBox, "LEFT", 6, 0)
SearchPlaceholder:SetText(L["SEARCH_PLACEHOLDER"])

local ClearSearchBtn = CreateFrame("Button", nil, SearchBox)
ClearSearchBtn:SetSize(14, 14)
ClearSearchBtn:SetPoint("RIGHT", SearchBox, "RIGHT", -4, 0)
ClearSearchBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
ClearSearchBtn:SetAlpha(0.7)
ClearSearchBtn:Hide()

ClearSearchBtn:SetScript("OnClick", function()
    SearchBox:SetText("")
    SearchBox:ClearFocus()
end)

SearchBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    searchFilterText = strtrim(text):lower()
    if searchFilterText ~= "" then
        SearchPlaceholder:Hide()
        ClearSearchBtn:Show()
    else
        SearchPlaceholder:Show()
        ClearSearchBtn:Hide()
    end
    ns.RenderProfessions()
    ns.DisplayRecipesForProfession(ns.selectedProfession)
end)

SearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
SearchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- Checkbox: Nur Rezepte mit vorhandenen Materialien
local CraftableCheck = CreateFrame("CheckButton", "BoisCraftFilterCraftableCheck", CatalogView, "UICheckButtonTemplate")
CraftableCheck:SetSize(22, 22)
CraftableCheck:SetPoint("LEFT", SearchBox, "RIGHT", 6, 0)

local CraftableCheckLabel = CatalogView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
CraftableCheckLabel:SetPoint("LEFT", CraftableCheck, "RIGHT", 1, 0)
CraftableCheckLabel:SetText(L["FILTER_CRAFTABLE"])

CraftableCheck:SetScript("OnClick", function(self)
    filterOnlyCraftable = self:GetChecked() and true or false
    ns.RenderProfessions()
    ns.DisplayRecipesForProfession(ns.selectedProfession)
end)

-- ScrollFrame für Rezepte
local RecipeScroll = CreateFrame("ScrollFrame", "BoisCraftRecipeScroll", CatalogView, "UIPanelScrollFrameTemplate")
RecipeScroll:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 225, -64)
RecipeScroll:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 225, 50)
RecipeScroll:SetWidth(252)

local RecipeContent = CreateFrame("Frame", nil, RecipeScroll)
RecipeContent:SetSize(248, 350)
RecipeScroll:SetScrollChild(RecipeContent)

local recipeButtons = {}

-- ============================================================================
-- 5. Rechte Spalte: Rezept-Vorschau, Stats & Materialien mit Qualitätsrahmen
-- ============================================================================

local PreviewPane = CreateFrame("Frame", nil, CatalogView)
PreviewPane:SetPoint("TOPLEFT", CatalogView, "TOPLEFT", 515, -36)
PreviewPane:SetPoint("BOTTOMRIGHT", CatalogView, "BOTTOMRIGHT", -15, 50)

-- Haupt-Icon des gewählten Rezepts
local PreviewIconFrame = CreateFrame("Button", nil, PreviewPane)
PreviewIconFrame:SetSize(40, 40)
PreviewIconFrame:SetPoint("TOPLEFT", PreviewPane, "TOPLEFT", 4, -4)

local PreviewIcon = PreviewIconFrame:CreateTexture(nil, "ARTWORK")
PreviewIcon:SetPoint("TOPLEFT", 2, -2)
PreviewIcon:SetPoint("BOTTOMRIGHT", -2, 2)
PreviewIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local PreviewIconBorder = PreviewIconFrame:CreateTexture(nil, "OVERLAY")
PreviewIconBorder:SetSize(70, 70) -- Bei 40x40 Icon ca. 68x68 bis 70x70 wählen
PreviewIconBorder:SetPoint("CENTER", PreviewIconFrame, "CENTER", 0, 0)
PreviewIconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
PreviewIconBorder:SetBlendMode("ADD")
PreviewIconBorder:Hide()

local PreviewTitle = PreviewPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
PreviewTitle:SetPoint("LEFT", PreviewIconFrame, "RIGHT", 10, 4)
PreviewTitle:SetPoint("RIGHT", PreviewPane, "RIGHT", -5, 4)
PreviewTitle:SetJustifyH("LEFT")
PreviewTitle:SetText(L["NO_RECIPE_SELECTED"])

local PreviewSubTitle = PreviewPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
PreviewSubTitle:SetPoint("TOPLEFT", PreviewTitle, "BOTTOMLEFT", 0, -2)
PreviewSubTitle:SetJustifyH("LEFT")

-- Item-Stats / Beschreibungstext
local PreviewStatsText = PreviewPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
PreviewStatsText:SetPoint("TOPLEFT", PreviewIconFrame, "BOTTOMLEFT", 0, -10)
PreviewStatsText:SetPoint("RIGHT", PreviewPane, "RIGHT", -5, 0)
PreviewStatsText:SetJustifyH("LEFT")
PreviewStatsText:SetSpacing(2)

-- Überschrift "Benötigte Materialien:"
local ReagentsHeader = PreviewPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ReagentsHeader:SetPoint("TOPLEFT", PreviewStatsText, "BOTTOMLEFT", 0, -14)
ReagentsHeader:SetText(L["REQUIRED_MATERIALS"])
ReagentsHeader:Hide()

local reagentRows = {}

-- Unsichtbarer Scanner-Tooltip zum Auslesen von Gegenstands-Werten
local ScanTooltip = CreateFrame("GameTooltip", "BoisCraftScanTooltip", nil, "GameTooltipTemplate")
ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ExtractTooltipLinesForRecipe(recipeID)
    ScanTooltip:ClearLines()
    local outItemID = ns.GetItemIDForRecipe(recipeID)
    if outItemID then
        ScanTooltip:SetItemByID(outItemID)
    elseif ScanTooltip.SetRecipeResultItem then
        pcall(ScanTooltip.SetRecipeResultItem, ScanTooltip, recipeID)
    elseif ScanTooltip.SetSpellByID then
        pcall(ScanTooltip.SetSpellByID, ScanTooltip, recipeID)
    end

    local lines = {}
    for i = 2, ScanTooltip:NumLines() do
        local leftFont = _G["BoisCraftScanTooltipTextLeft" .. i]
        if leftFont then
            local text = leftFont:GetText()
            if text and text ~= "" and not text:find("^%[BoisCraft%]") then
                local r, g, b = leftFont:GetTextColor()
                local hex = string.format("%02x%02x%02x", math.floor((r or 1) * 255), math.floor((g or 1) * 255), math.floor((b or 1) * 255))
                table.insert(lines, "|cFF" .. hex .. text .. "|r")
                if #lines >= 7 then break end
            end
        end
    end
    return table.concat(lines, "\n")
end

-- ============================================================================
-- 6. Footer: Crafter-Dropdown, Mengen-Auswahl (- [1] +) & Bestell-Button
-- ============================================================================

local Footer = CreateFrame("Frame", nil, CatalogView)
Footer:SetPoint("BOTTOMLEFT", CatalogView, "BOTTOMLEFT", 10, 6)
Footer:SetPoint("BOTTOMRIGHT", CatalogView, "BOTTOMRIGHT", -10, 6)
Footer:SetHeight(36)

local CrafterDropdown = CreateFrame("Frame", "BoisCraftCrafterDropdown", Footer, "UIDropDownMenuTemplate")
CrafterDropdown:SetPoint("LEFT", Footer, "LEFT", -8, -2)
if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(CrafterDropdown, 185)
end

local SyncButton = CreateFrame("Button", "BoisCraftCatalogSyncButton", Footer, "UIPanelButtonTemplate")
SyncButton:SetSize(74, 24)
SyncButton:SetPoint("LEFT", CrafterDropdown, "RIGHT", -8, 2)
SyncButton:SetText(L["BTN_SYNC"] or "Sync")
SyncButton:SetScript("OnClick", function()
    if ns.ManualSync then ns.ManualSync() end
end)
SyncButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["BTN_SYNC"] or "Sync", 1, 0.82, 0)
    GameTooltip:AddLine(L["TT_SYNC_BTN"] or "Synchronize with online community members.", 1, 1, 1, true)
    GameTooltip:Show()
end)
SyncButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local OrderButton = CreateFrame("Button", nil, Footer, "UIPanelButtonTemplate")
OrderButton:SetSize(115, 24)
OrderButton:SetPoint("RIGHT", Footer, "RIGHT", -6, 0)
OrderButton:SetText(L["BTN_ORDER"])
OrderButton:Disable()

-- Mengen-Steuerung (Menge: [-] [ 1 ] [+])
local PlusQtyBtn = CreateFrame("Button", nil, Footer, "UIPanelButtonTemplate")
PlusQtyBtn:SetSize(22, 22)
PlusQtyBtn:SetPoint("RIGHT", OrderButton, "LEFT", -10, 0)
PlusQtyBtn:SetText("+")

local QtyBox = CreateFrame("EditBox", nil, Footer, "InputBoxTemplate")
QtyBox:SetSize(36, 22)
QtyBox:SetPoint("RIGHT", PlusQtyBtn, "LEFT", -3, 0)
QtyBox:SetAutoFocus(false)
QtyBox:SetNumeric(true)
QtyBox:SetMaxLetters(3)
QtyBox:SetJustifyH("CENTER")
QtyBox:SetText("1")

local MinusQtyBtn = CreateFrame("Button", nil, Footer, "UIPanelButtonTemplate")
MinusQtyBtn:SetSize(22, 22)
MinusQtyBtn:SetPoint("RIGHT", QtyBox, "LEFT", -5, 0)
MinusQtyBtn:SetText("-")

local QtyLabel = Footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
QtyLabel:SetPoint("RIGHT", MinusQtyBtn, "LEFT", -6, 0)
QtyLabel:SetText(L["QTY_LABEL"])

local function SetOrderQuantity(val)
    val = math.max(1, math.min(999, tonumber(val) or 1))
    ns.orderQuantity = val
    if QtyBox:GetNumber() ~= val then
        QtyBox:SetText(tostring(val))
    end
    if ns.selectedRecipeID then
        ns.UpdateRecipePreview(ns.selectedRecipeID)
    end
end

MinusQtyBtn:SetScript("OnClick", function() SetOrderQuantity((ns.orderQuantity or 1) - 1) end)
PlusQtyBtn:SetScript("OnClick", function() SetOrderQuantity((ns.orderQuantity or 1) + 1) end)
QtyBox:SetScript("OnTextChanged", function(self)
    local num = tonumber(self:GetText())
    if num and num >= 1 then
        ns.orderQuantity = math.min(999, num)
        if ns.selectedRecipeID then ns.UpdateRecipePreview(ns.selectedRecipeID) end
    end
end)
QtyBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
QtyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- ============================================================================
-- 7. Vorschau & Dropdown-Aktualisierung
-- ============================================================================

local function FormatCrafterDropdownLabel(crafterName, profKey)
    local colored = ns.GetColoredPlayerName(crafterName)
    local skillStr = ns.GetPlayerProfessionSkillText(crafterName, profKey)
    if skillStr then
        return string.format("%s |cFFAAAAAA(%s)|r", colored, skillStr)
    end
    return colored
end

function ns.UpdateDropdownOptions()
    if not ns.selectedRecipeID then
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(CrafterDropdown, L["NO_RECIPE_SELECTED"])
        end
        OrderButton:Disable()
        return
    end

    local crafterEntries = ns.GetCraftersForRecipe(ns.selectedRecipeID)
    local availableFriends = {}
    for _, entry in ipairs(crafterEntries) do
        table.insert(availableFriends, entry.name)
    end
    table.sort(availableFriends, function(a, b) return a:lower() < b:lower() end)

    local function Dropdown_Initialize(self, level)
        if not UIDropDownMenu_CreateInfo then return end
        for _, friend in ipairs(availableFriends) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = FormatCrafterDropdownLabel(friend, ns.selectedProfession)
            info.value = friend
            info.checked = (ns.selectedCrafter == friend)
            info.func = function()
                ns.selectedCrafter = friend
                if UIDropDownMenu_SetText then
                    UIDropDownMenu_SetText(CrafterDropdown, FormatCrafterDropdownLabel(friend, ns.selectedProfession))
                end
                OrderButton:Enable()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(CrafterDropdown, Dropdown_Initialize)
    end

    if #availableFriends > 0 then
        -- Falls links im Baum ein bestimmter Charakter angeklickt wurde und er das Rezept kann, diesen bevorzugen
        local preferred = availableFriends[1]
        if ns.selectedFilterCrafter then
            for _, f in ipairs(availableFriends) do
                if f == ns.selectedFilterCrafter then
                    preferred = f
                    break
                end
            end
        end
        ns.selectedCrafter = preferred
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(CrafterDropdown, FormatCrafterDropdownLabel(preferred, ns.selectedProfession))
        end
        OrderButton:Enable()
    else
        ns.selectedCrafter = nil
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(CrafterDropdown, L["NO_CRAFTER_AVAILABLE"])
        end
        OrderButton:Disable()
    end
end

function ns.UpdateRecipePreview(recipeID)
    for _, r in ipairs(reagentRows) do r:Hide() end

    if not recipeID then
        PreviewIcon:SetTexture(nil)
        PreviewIconBorder:Hide()
        PreviewTitle:SetText(L["NO_RECIPE_SELECTED"])
        PreviewSubTitle:SetText("")
        PreviewStatsText:SetText("")
        ReagentsHeader:Hide()
        return
    end

    local rName, rIcon = ns.GetLocalizedRecipeName(recipeID)
    local outItemID = ns.GetItemIDForRecipe(recipeID)
    local qty = ns.orderQuantity or 1

    PreviewIcon:SetTexture(rIcon or 136240)
    PreviewTitle:SetText(rName)
    PreviewSubTitle:SetText(ns.GetLocalizedProfName(ns.selectedProfession or ""))

    if outItemID then
        ns.AsyncLoadItem(outItemID, function(itemName, itemLink, itemQuality, itemIcon)
            if ns.selectedRecipeID ~= recipeID then return end
            if itemIcon then PreviewIcon:SetTexture(itemIcon) end
            if itemLink then PreviewTitle:SetText(itemLink) end
            ns.SetIconQualityBorder(PreviewIconBorder, itemQuality)
            PreviewStatsText:SetText(ExtractTooltipLinesForRecipe(recipeID))
        end)
    else
        ns.SetIconQualityBorder(PreviewIconBorder, 1)
        PreviewStatsText:SetText(ExtractTooltipLinesForRecipe(recipeID))
    end

    PreviewIconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if outItemID then
            GameTooltip:SetItemByID(outItemID)
        elseif GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(recipeID)
        end
        GameTooltip:Show()
    end)
    PreviewIconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PreviewIconFrame:SetScript("OnClick", function()
        if outItemID then
            local _, link = C_Item.GetItemInfo(outItemID)
            if link then HandleModifiedItemClick(link) end
        end
    end)

    ReagentsHeader:Show()
    local reagents = ns.GetRecipeRequiredReagents(recipeID)

    if #reagents == 0 then
        local row = reagentRows[1] or CreateFrame("Frame", nil, PreviewPane)
        reagentRows[1] = row
        row:SetSize(270, 24)
        row:SetPoint("TOPLEFT", ReagentsHeader, "BOTTOMLEFT", 0, -6)
        if not row.text then
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
        if row.icon then row.icon:Hide() end
        if row.border then row.border:Hide() end
        row.text:SetText(L["NO_REAGENTS_DATA"])
        row:Show()
        return
    end

    for idx, reg in ipairs(reagents) do
        local row = reagentRows[idx]
        if not row then
            row = CreateFrame("Button", nil, PreviewPane)
            row:SetSize(275, 26)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.border = row:CreateTexture(nil, "OVERLAY")
            row.border:SetSize(28, 28)
            row.border:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
            row.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            row.border:SetBlendMode("ADD")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.text:SetJustifyH("LEFT")

            reagentRows[idx] = row
        end

        row:SetPoint("TOPLEFT", ReagentsHeader, "BOTTOMLEFT", 0, -6 - (idx - 1) * 28)
        row.icon:Show()

        local reqTotal = (reg.count or 1) * qty
        local inBags, inBank, totalWithBank = 0, 0, 0
        if ns.GetBagAndBankItemCount then
            inBags, inBank, totalWithBank = ns.GetBagAndBankItemCount(reg.itemID)
        else
            inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(reg.itemID, false))
                or (GetItemCount and GetItemCount(reg.itemID)) or 0
            totalWithBank = inBags
        end
        local countColor = (inBags >= reqTotal) and "00FF00" or ((totalWithBank >= reqTotal) and "FFCC00" or "FF7777")
        local bankSuffix = (inBank > 0) and string.format(L["BANK_COUNT_SUFFIX"] or " |cFF88CCFF[Bank: %d]|r", inBank) or ""

        ns.AsyncLoadItem(reg.itemID, function(itemName, itemLink, itemQuality, itemIcon)
            row.icon:SetTexture(itemIcon or 134400)
            ns.SetIconQualityBorder(row.border, itemQuality)
            row.text:SetText(string.format("%s  |cFF%s(%d/%d)|r%s", itemName or ("Item #" .. reg.itemID), countColor, inBags, reqTotal, bankSuffix))
        end)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(reg.itemID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Show()
    end
end

-- ============================================================================
-- 8. Rezeptliste für gewählten Beruf (und optionalen Charakter-Filter) rendern
-- ============================================================================

function ns.DisplayRecipesForProfession(profNameOrKey)
    local normProf = profNameOrKey and ns.NormalizeProfName(profNameOrKey) or ""
    if normProf ~= "" then
        ns.selectedProfession = normProf
    end

    for _, btn in ipairs(recipeButtons) do btn:Hide() end

    -- Wenn ein Suchbegriff aktiv ist (oder noch kein Beruf gewählt wurde, aber ein Filter aktiv ist),
    -- wird berufsübergreifend über alle gespeicherten Rezepte gesucht!
    local searchAllProfessions = (searchFilterText ~= "") or (normProf == "" and filterOnlyCraftable)
    if normProf == "" and not searchAllProfessions then
        RecipeContent:SetHeight(340)
        return
    end

    local uniqueRecipes = {}
    if FriendProfessionDB then
        for friendName, profs in pairs(FriendProfessionDB) do
            -- Falls links ein Charakter unter dem Beruf ausgewählt wurde, nur dessen Rezepte zeigen
            if not ns.selectedFilterCrafter or ns.selectedFilterCrafter == friendName then
                if type(profs) == "table" then
                    for pName, recipes in pairs(profs) do
                        local pKey = ns.NormalizeProfName(pName)
                        if (searchAllProfessions or pKey == normProf) and type(recipes) == "table" then
                            for _, rID in ipairs(recipes) do
                                local numID = tonumber(rID)
                                if numID and (not uniqueRecipes[numID] or pKey == normProf) then
                                    uniqueRecipes[numID] = pKey
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local sortedList = {}
    for rID, pKey in pairs(uniqueRecipes) do
        local rName, rIcon = ns.GetLocalizedRecipeName(rID)
        local hasMats = ns.HasReagentsForRecipe(rID)

        local matchesSearch = (searchFilterText == "") or (rName:lower():find(searchFilterText, 1, true) ~= nil)
        local matchesCraftable = (not filterOnlyCraftable) or hasMats

        if matchesSearch and matchesCraftable then
            table.insert(sortedList, {
                id = rID,
                profKey = pKey,
                name = rName,
                icon = rIcon,
                hasMats = hasMats,
            })
        end
    end

    table.sort(sortedList, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    local yOffset = 0
    for idx, entry in ipairs(sortedList) do
        local btn = recipeButtons[idx]
        if not btn then
            btn = CreateFrame("Button", nil, RecipeContent)
            btn:SetSize(244, 22)

            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()

            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(18, 18)
            btn.icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
            btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            btn.text:SetJustifyH("LEFT")

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            recipeButtons[idx] = btn
        end

        btn:SetPoint("TOPLEFT", RecipeContent, "TOPLEFT", 2, -yOffset)
        btn.icon:SetTexture(entry.icon or 136240)

        if ns.selectedRecipeID == entry.id then
            btn.bg:SetColorTexture(0.25, 0.45, 0.75, 0.45)
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
        end

        local textColor = entry.hasMats and "|cFF00FF00" or "|cFFFF7777"
        btn.text:SetText(textColor .. entry.name .. "|r")

        btn:SetScript("OnClick", function()
            ns.selectedRecipeID = entry.id
            if entry.profKey and entry.profKey ~= "" and ns.selectedProfession ~= entry.profKey then
                ns.selectedProfession = entry.profKey
                expandedProfessions[entry.profKey] = true
                ns.RenderProfessions()
            end
            ns.DisplayRecipesForProfession(ns.selectedProfession)
            ns.UpdateRecipePreview(entry.id)
            ns.UpdateDropdownOptions()
        end)

        btn:Show()
        yOffset = yOffset + 23
    end

    RecipeContent:SetHeight(math.max(340, yOffset + 10))
end

-- ============================================================================
-- 9. Bestell-Button Logik (Mit Mengen, Stacking & Twink-Direktübergabe)
-- ============================================================================

OrderButton:SetScript("OnClick", function()
    if not ns.selectedCrafter or not ns.selectedRecipeID then return end

    local currentMyName = ns.GetFullPlayerName("player")
    local targetCrafter = ns.NormalizeName(ns.selectedCrafter)
    local qty = math.max(1, tonumber(ns.orderQuantity) or 1)
    local orderUID = ns.GenerateOrderID()
    local rName = ns.GetLocalizedRecipeName(ns.selectedRecipeID)

    -- 1. Benötigte Materialien (multipliziert mit Menge) auf die Einkaufsliste setzen
    ns.AddRecipeToShoppingList(targetCrafter, ns.selectedRecipeID, qty)

    -- 2. In PendingOrders eintragen (oder mit bestehender offener Bestellung an denselben Crafter stapeln)
    PendingOrders = PendingOrders or {}
    local stackedPending = false
    for _, pOrder in ipairs(PendingOrders) do
        if ns.NormalizeName(pOrder.crafter) == targetCrafter
           and tonumber(pOrder.recipeID) == tonumber(ns.selectedRecipeID)
           and not pOrder.acked then
            pOrder.count = (tonumber(pOrder.count) or 1) + qty
            orderUID = pOrder.orderID or orderUID
            pOrder.orderID = orderUID
            stackedPending = true
            break
        end
    end

    if not stackedPending then
        table.insert(PendingOrders, {
            orderID  = orderUID,
            sender   = currentMyName,
            crafter  = targetCrafter,
            recipeID = ns.selectedRecipeID,
            count    = qty,
            acked    = false,
        })
    end

    -- 3. Prüfen, ob der Crafter ein eigener Charakter/Twink auf diesem Account ist
    local isMyAlt = (targetCrafter == currentMyName)
        or (BoisCraftSettings.myAlts and BoisCraftSettings.myAlts[targetCrafter])

    if isMyAlt then
        ns.AddOrStackIncomingOrder({
            orderID    = orderUID,
            sender     = currentMyName,
            crafter    = targetCrafter,
            recipeID   = ns.selectedRecipeID,
            count      = qty,
            origin     = "ALT",
            isAltOrder = true,
        })

        if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
            PlaySound(SOUNDKIT.READY_CHECK)
        end
        if ns.UpdateOrdersList then ns.UpdateOrdersList() end
        print(string.format(L["MSG_ORDER_SENT"], qty, rName, ns.GetColoredPlayerName(targetCrafter)))
        SetOrderQuantity(1)
        return
    end

    -- 4. Externer Freund: direktes, Classic-kompatibles Addon-Whisper.
    -- Unbestätigte Aufträge verbleiben in PendingOrders und werden bei HELLO erneut versendet.
    local payload = string.format("ORDER:%s:%d:%d:%s", targetCrafter, ns.selectedRecipeID, qty, orderUID)
    if ns.SendSyncMessage and ns.SendSyncMessage(payload, targetCrafter) then
        print(string.format(L["MSG_ORDER_QUEUED"], qty, rName, ns.GetColoredPlayerName(targetCrafter)))
    else
        print("|cffff5555BoisCraft: Auftrag konnte nicht zum Senden vorgemerkt werden.|r")
    end

    if ns.UpdateOrdersList then ns.UpdateOrdersList() end
    SetOrderQuantity(1)
end)

-- ============================================================================
-- 10. Globaler Item-Tooltip Hook ("Herstellbar von...")
-- ============================================================================

local function OnTooltipSetItemHook(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end

    local crafters = ns.GetCraftersForItemID(itemID)
    if #crafters > 0 then
        local parts = {}
        for _, c in ipairs(crafters) do
            local coloredName = ns.GetColoredPlayerName(c.name)
            local locProf = ns.GetLocalizedProfName(c.profession)
            table.insert(parts, string.format("%s (%s)", coloredName, locProf))
        end
        tooltip:AddLine(string.format(L["TT_CRAFTABLE_BY"], table.concat(parts, ", ")), 1, 1, 1, true)
        tooltip:Show()
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItemHook)
else
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItemHook)
    end
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItemHook)
    end
end

-- ============================================================================
-- 11. Lokalisierung des Katalog-Tabs bei Sprachwechsel
-- ============================================================================

function ns.RefreshCatalogLocale()
    SearchPlaceholder:SetText(L["SEARCH_PLACEHOLDER"])
    CraftableCheckLabel:SetText(L["FILTER_CRAFTABLE"])
    ReagentsHeader:SetText(L["REQUIRED_MATERIALS"])
    QtyLabel:SetText(L["QTY_LABEL"])
    OrderButton:SetText(L["BTN_ORDER"])
    SyncButton:SetText(L["BTN_SYNC"] or "Sync")

    if ns.selectedRecipeID then
        ns.UpdateRecipePreview(ns.selectedRecipeID)
    else
        PreviewTitle:SetText(L["NO_RECIPE_SELECTED"])
    end
    ns.UpdateDropdownOptions()
end

for _, evt in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(CatalogView.RegisterEvent, CatalogView, evt)
end
CatalogView:SetScript("OnEvent", function(self)
    if not self:IsShown() then return end
    if ns.selectedRecipeID then
        ns.UpdateRecipePreview(ns.selectedRecipeID)
    end
    if ns.selectedProfession or searchFilterText ~= "" or filterOnlyCraftable then
        ns.DisplayRecipesForProfession(ns.selectedProfession)
    end
end)