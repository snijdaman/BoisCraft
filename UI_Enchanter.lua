local addonName, ns = ...
local L = ns.L or {}

local parent = ns.MainFrame or _G["BoisCraftMainFrame"] or UIParent
local EnchanterView = ns.EnchanterView

if not EnchanterView then
    EnchanterView = CreateFrame("Frame", "BoisCraftEnchanterView", parent)
    EnchanterView:SetAllPoints(parent)
    EnchanterView:Hide()
    ns.EnchanterView = EnchanterView
end

local selectedRecipeID = nil
local selectedTargetKey = nil
local selectedTargetInfo = nil
local searchText = ""
local filterCraftable = false
local targetCount = 10
local remainingEnchants = 0
local totalBatchCount = 0
local autoConfirmUntil = 0

local function GetSafeLocale(key, defaultText)
    local val = L and L[key]
    if not val or val == key then
        return defaultText
    end
    return val
end

local function SafeGetItemInfo(itemIDOrLink)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemIDOrLink)
    elseif _G.GetItemInfo then
        return _G.GetItemInfo(itemIDOrLink)
    end
    return nil
end

local function SafeGetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif _G.GetContainerNumSlots then
        return _G.GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function SafeGetContainerItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.iconFileID, info.itemID, info.hyperlink, info.quality
        end
        return nil
    elseif _G.GetContainerItemInfo then
        local icon, _, _, quality, _, _, link, _, _, itemID = _G.GetContainerItemInfo(bag, slot)
        return icon, itemID, link, quality
    end
    return nil
end

local function SafeUseContainerItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    elseif _G.UseContainerItem then
        _G.UseContainerItem(bag, slot)
    end
end

-- ============================================================================
-- 1. Trennlinien & Spalten-Layout
-- ============================================================================

local VerticalDivider = EnchanterView:CreateTexture(nil, "ARTWORK")
VerticalDivider:SetWidth(2)
VerticalDivider:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 315, -32)
VerticalDivider:SetPoint("BOTTOMLEFT", EnchanterView, "BOTTOMLEFT", 315, 112)
VerticalDivider:SetColorTexture(0.45, 0.45, 0.45, 0.9)

local BottomDivider = EnchanterView:CreateTexture(nil, "ARTWORK")
BottomDivider:SetHeight(2)
BottomDivider:SetPoint("BOTTOMLEFT", EnchanterView, "BOTTOMLEFT", 12, 110)
BottomDivider:SetPoint("BOTTOMRIGHT", EnchanterView, "BOTTOMRIGHT", -12, 110)
BottomDivider:SetColorTexture(0.45, 0.45, 0.45, 0.9)

-- ============================================================================
-- 2. Linke Spalte: Verzauberkunst-Rezepte
-- ============================================================================

local RecipesHeader = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
RecipesHeader:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 16, -34)
RecipesHeader:SetText(GetSafeLocale("ENCH_RECIPES_HEADER", "Enchanting Recipes"))

local SearchBox = CreateFrame("EditBox", "BoisCraftEnchanterSearchBox", EnchanterView, "InputBoxTemplate")
SearchBox:SetSize(165, 22)
SearchBox:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 18, -54)
SearchBox:SetAutoFocus(false)

local SearchPlaceholder = SearchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
SearchPlaceholder:SetPoint("LEFT", SearchBox, "LEFT", 6, 0)
SearchPlaceholder:SetText(GetSafeLocale("SEARCH_PLACEHOLDER", "Search recipes..."))

local CraftableCheck = CreateFrame("CheckButton", "BoisCraftEnchanterCraftableCheck", EnchanterView, "UICheckButtonTemplate")
CraftableCheck:SetSize(22, 22)
CraftableCheck:SetPoint("LEFT", SearchBox, "RIGHT", 6, 0)

local CraftableLabel = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
CraftableLabel:SetPoint("LEFT", CraftableCheck, "RIGHT", 1, 0)
CraftableLabel:SetText(GetSafeLocale("FILTER_CRAFTABLE", "Have Materials"))

local RecipeScroll = CreateFrame("ScrollFrame", "BoisCraftEnchanterRecipeScroll", EnchanterView, "UIPanelScrollFrameTemplate")
RecipeScroll:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 14, -82)
RecipeScroll:SetPoint("BOTTOMLEFT", EnchanterView, "BOTTOMLEFT", 14, 118)
RecipeScroll:SetWidth(274)

local RecipeContent = CreateFrame("Frame", nil, RecipeScroll)
RecipeContent:SetSize(270, 270)
RecipeScroll:SetScrollChild(RecipeContent)

local recipeRows = {}

local NoRecipesHint = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
NoRecipesHint:SetPoint("CENTER", RecipeScroll, "CENTER", 0, 0)
NoRecipesHint:SetWidth(250)
NoRecipesHint:SetText(GetSafeLocale("ENCH_NO_RECIPES", "No Enchanting recipes found."))
NoRecipesHint:Hide()

-- ============================================================================
-- 3. Rechte Spalte: Ziel-Items (Ausgerüstet & Taschen)
-- ============================================================================

local TargetsHeader = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
TargetsHeader:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 330, -34)
TargetsHeader:SetText(GetSafeLocale("ENCH_TARGETS_HEADER", "Target Item (Equipped / Bags)"))

local RefreshTargetsBtn = CreateFrame("Button", nil, EnchanterView, "UIPanelButtonTemplate")
RefreshTargetsBtn:SetSize(90, 20)
RefreshTargetsBtn:SetPoint("TOPRIGHT", EnchanterView, "TOPRIGHT", -32, -32)
RefreshTargetsBtn:SetText("Refresh")

local TargetScroll = CreateFrame("ScrollFrame", "BoisCraftEnchanterTargetScroll", EnchanterView, "UIPanelScrollFrameTemplate")
TargetScroll:SetPoint("TOPLEFT", EnchanterView, "TOPLEFT", 328, -58)
TargetScroll:SetPoint("BOTTOMRIGHT", EnchanterView, "BOTTOMRIGHT", -32, 118)

local TargetContent = CreateFrame("Frame", nil, TargetScroll)
TargetContent:SetSize(445, 290)
TargetScroll:SetScrollChild(TargetContent)

local targetRows = {}

local NoTargetsHint = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontDisable")
NoTargetsHint:SetPoint("CENTER", TargetScroll, "CENTER", 0, 0)
NoTargetsHint:SetWidth(350)
NoTargetsHint:SetText(GetSafeLocale("ENCH_NO_TARGETS", "No enchantable items found."))
NoTargetsHint:Hide()

-- ============================================================================
-- 4. Unterer Steuerbereich: Mats-Zusammenfassung, Anzahl & Start-Button
-- ============================================================================

local SelectedSummaryText = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SelectedSummaryText:SetPoint("BOTTOMLEFT", EnchanterView, "BOTTOMLEFT", 16, 86)
SelectedSummaryText:SetPoint("BOTTOMRIGHT", EnchanterView, "BOTTOMRIGHT", -16, 86)
SelectedSummaryText:SetJustifyH("LEFT")

local HintText = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
HintText:SetPoint("BOTTOMLEFT", EnchanterView, "BOTTOMLEFT", 16, 48)
HintText:SetWidth(420)
HintText:SetJustifyH("LEFT")
HintText:SetText(GetSafeLocale("ENCH_STATUS_HINT", ""))

local EnchantBtn = CreateFrame("Button", "BoisCraftEnchanterStartBtn", EnchanterView, "UIPanelButtonTemplate")
EnchantBtn:SetSize(165, 28)
EnchantBtn:SetPoint("BOTTOMRIGHT", EnchanterView, "BOTTOMRIGHT", -16, 46)

local ResetBtn = CreateFrame("Button", nil, EnchanterView, "UIPanelButtonTemplate")
ResetBtn:SetSize(64, 28)
ResetBtn:SetPoint("RIGHT", EnchantBtn, "LEFT", -6, 0)
ResetBtn:SetText(GetSafeLocale("ENCH_BTN_RESET", "Reset"))

local MaxBtn = CreateFrame("Button", nil, EnchanterView, "UIPanelButtonTemplate")
MaxBtn:SetSize(44, 22)
MaxBtn:SetPoint("RIGHT", ResetBtn, "LEFT", -8, 0)
MaxBtn:SetText("Max")

local PlusBtn = CreateFrame("Button", nil, EnchanterView, "UIPanelButtonTemplate")
PlusBtn:SetSize(22, 22)
PlusBtn:SetPoint("RIGHT", MaxBtn, "LEFT", -4, 0)
PlusBtn:SetText("+")

local CountBox = CreateFrame("EditBox", "BoisCraftEnchanterCountBox", EnchanterView, "InputBoxTemplate")
CountBox:SetSize(38, 22)
CountBox:SetPoint("RIGHT", PlusBtn, "LEFT", -4, 0)
CountBox:SetAutoFocus(false)
CountBox:SetNumeric(true)
CountBox:SetMaxLetters(3)
CountBox:SetJustifyH("CENTER")
CountBox:SetText(tostring(targetCount))

local MinusBtn = CreateFrame("Button", nil, EnchanterView, "UIPanelButtonTemplate")
MinusBtn:SetSize(22, 22)
MinusBtn:SetPoint("RIGHT", CountBox, "LEFT", -4, 0)
MinusBtn:SetText("-")

local CountLabel = EnchanterView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
CountLabel:SetPoint("RIGHT", MinusBtn, "LEFT", -6, 0)
CountLabel:SetText(GetSafeLocale("ENCH_REPEAT_LABEL", "Count:"))

-- ============================================================================
-- 5. Datensammlung: Eigene Verzauberungen & verzauberbare Ziel-Items
-- ============================================================================

local function CollectMyEnchantingRecipes()
    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    local seen = {}
    local list = {}

    local function AddRecipe(rID)
        rID = tonumber(rID)
        if not rID or seen[rID] then return end
        seen[rID] = true
        local rName, rIcon = ns.GetLocalizedRecipeName(rID)
        local maxMake = ns.GetMaxCraftableAmount and ns.GetMaxCraftableAmount(rID, false) or 0
        table.insert(list, {
            id = rID,
            name = rName or ("Recipe #" .. rID),
            icon = rIcon or 136244,
            maxMake = maxMake,
        })
    end

    if FriendProfessionDB and FriendProfessionDB[myName] then
        for pName, recipes in pairs(FriendProfessionDB[myName]) do
            if ns.NormalizeProfName and ns.NormalizeProfName(pName) == "ENCHANTING" and type(recipes) == "table" then
                for _, rID in ipairs(recipes) do
                    AddRecipe(rID)
                end
            end
        end
    end

    -- Falls Verzauberkunst-Fenster gerade offen ist, Live-Rezepte mit einbeziehen
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetAllRecipeIDs then
        local okBase, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if okBase and baseInfo and baseInfo.professionName and ns.NormalizeProfName(baseInfo.professionName) == "ENCHANTING" then
            local okAll, rIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
            if okAll and type(rIDs) == "table" then
                for _, rID in ipairs(rIDs) do
                    local okInfo, rInfo = pcall(C_TradeSkillUI.GetRecipeInfo, rID)
                    if okInfo and rInfo and rInfo.learned then
                        AddRecipe(rID)
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return list
end

local EQUIP_SLOTS = {
    1,  -- Head
    3,  -- Shoulder
    5,  -- Chest
    6,  -- Waist
    7,  -- Legs
    8,  -- Feet
    9,  -- Wrist
    10, -- Hands
    15, -- Back
    16, -- MainHand
    17, -- SecondaryHand
}

local function IsEnchantableItemClass(classID)
    -- 2 = Weapon, 4 = Armor
    return classID == 2 or classID == 4
end

local function CollectEnchantableTargets()
    local targets = {}

    -- 1. Ausgerüstete Gegenstände
    for _, invSlot in ipairs(EQUIP_SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
        if link then
            local name, _, quality, _, _, _, _, _, _, tex, _, classID = SafeGetItemInfo(link)
            local itemID = tonumber(link:match("item:(%d+)"))
            if not classID and itemID and C_Item and C_Item.GetItemInfoInstant then
                local _, _, _, _, iconInstant, cID = C_Item.GetItemInfoInstant(itemID)
                classID = cID
                tex = tex or iconInstant
            end
            if not classID or IsEnchantableItemClass(classID) then
                table.insert(targets, {
                    key = "EQUIP:" .. invSlot,
                    isEquipped = true,
                    invSlot = invSlot,
                    itemID = itemID,
                    link = link,
                    name = name or link,
                    quality = quality or 1,
                    icon = tex or (GetInventoryItemTexture and GetInventoryItemTexture("player", invSlot)) or 134400,
                })
            end
        end
    end

    -- 2. Gegenstände in den Taschen (Rucksäcke 0 bis 4)
    local numBags = NUM_BAG_SLOTS or 4
    for bag = 0, numBags do
        local slots = SafeGetContainerNumSlots(bag)
        for slot = 1, slots do
            local icon, itemID, link, quality = SafeGetContainerItemInfo(bag, slot)
            if itemID or link then
                local name, itemLink, q2, _, _, _, _, _, _, tex, _, classID = SafeGetItemInfo(link or itemID)
                if not classID and itemID and C_Item and C_Item.GetItemInfoInstant then
                    local _, _, _, _, iconInstant, cID = C_Item.GetItemInfoInstant(itemID)
                    classID = cID
                    tex = tex or iconInstant
                end
                if IsEnchantableItemClass(classID) then
                    table.insert(targets, {
                        key = string.format("BAG:%d:%d", bag, slot),
                        isEquipped = false,
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        link = itemLink or link,
                        name = name or itemLink or link or ("Item #" .. tostring(itemID)),
                        quality = q2 or quality or 1,
                        icon = tex or icon or 134400,
                    })
                end
            end
        end
    end

    return targets
end

-- ============================================================================
-- 6. UI-Rendering & Steuerungs-Logik
-- ============================================================================

local function UpdateActionFooter()
    CountLabel:SetText(GetSafeLocale("ENCH_REPEAT_LABEL", "Count:"))
    HintText:SetText(GetSafeLocale("ENCH_STATUS_HINT", ""))
    ResetBtn:SetText(GetSafeLocale("ENCH_BTN_RESET", "Reset"))

    if remainingEnchants > 0 then
        EnchantBtn:SetText(string.format(GetSafeLocale("ENCH_BTN_START", "Enchant (%d left)"), remainingEnchants))
    else
        EnchantBtn:SetText(string.format(GetSafeLocale("ENCH_BTN_START_IDLE", "Enchant (%dx)"), targetCount))
    end

    if selectedRecipeID and selectedTargetInfo then
        local rName = ns.GetLocalizedRecipeName(selectedRecipeID)
        local maxMake = ns.GetMaxCraftableAmount and ns.GetMaxCraftableAmount(selectedRecipeID, false) or 0
        local reagents = ns.GetRecipeRequiredReagents and ns.GetRecipeRequiredReagents(selectedRecipeID) or {}
        local matParts = {}
        for _, reg in ipairs(reagents) do
            local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(reg.itemID, false))
                or (GetItemCount and GetItemCount(reg.itemID)) or 0
            local req = (reg.count or 1) * (remainingEnchants > 0 and remainingEnchants or targetCount)
            local itemName = SafeGetItemInfo(reg.itemID) or ("#" .. reg.itemID)
            local color = (inBags >= req) and "00FF00" or "FF7777"
            table.insert(matParts, string.format("%s |cFF%s(%d/%d)|r", itemName, color, inBags, req))
        end
        local matStr = (#matParts > 0) and table.concat(matParts, ", ") or "-"
        SelectedSummaryText:SetText(string.format("|cFFFFD100%s|r -> %s  |cFFAAAAAA(Max: %d)|r  |  %s",
            rName, selectedTargetInfo.link or selectedTargetInfo.name, maxMake, matStr))
        if maxMake > 0 then
            EnchantBtn:Enable()
        else
            EnchantBtn:Disable()
        end
    else
        SelectedSummaryText:SetText(GetSafeLocale("ENCH_SELECT_HINT", "Select an enchantment and a target item first."))
        EnchantBtn:Disable()
    end
end

local function SetRepeatCount(val)
    val = math.max(1, math.min(999, tonumber(val) or 1))
    targetCount = val
    if CountBox:GetNumber() ~= val then
        CountBox:SetText(tostring(val))
    end
    UpdateActionFooter()
end

MinusBtn:SetScript("OnClick", function() SetRepeatCount(targetCount - 1) end)
PlusBtn:SetScript("OnClick", function() SetRepeatCount(targetCount + 1) end)
MaxBtn:SetScript("OnClick", function()
    if selectedRecipeID and ns.GetMaxCraftableAmount then
        local m = ns.GetMaxCraftableAmount(selectedRecipeID, false)
        SetRepeatCount(math.max(1, m))
    end
end)
ResetBtn:SetScript("OnClick", function()
    remainingEnchants = 0
    totalBatchCount = 0
    autoConfirmUntil = 0
    UpdateActionFooter()
end)

CountBox:SetScript("OnTextChanged", function(self)
    local num = tonumber(self:GetText())
    if num and num >= 1 then
        targetCount = math.min(999, num)
        UpdateActionFooter()
    end
end)
CountBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
CountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

function ns.UpdateEnchanterView()
    if not EnchanterView then return end

    RecipesHeader:SetText(GetSafeLocale("ENCH_RECIPES_HEADER", "Enchanting Recipes"))
    TargetsHeader:SetText(GetSafeLocale("ENCH_TARGETS_HEADER", "Target Item (Equipped / Bags)"))
    SearchPlaceholder:SetText(GetSafeLocale("SEARCH_PLACEHOLDER", "Search recipes..."))
    CraftableLabel:SetText(GetSafeLocale("FILTER_CRAFTABLE", "Have Materials"))
    NoRecipesHint:SetText(GetSafeLocale("ENCH_NO_RECIPES", "No Enchanting recipes found."))
    NoTargetsHint:SetText(GetSafeLocale("ENCH_NO_TARGETS", "No enchantable items found."))

    -- 1. Rezepte rendern
    for _, r in ipairs(recipeRows) do r:Hide() end
    local recipes = CollectMyEnchantingRecipes()
    local filteredRecipes = {}
    for _, entry in ipairs(recipes) do
        local matchSearch = (searchText == "") or (entry.name:lower():find(searchText, 1, true) ~= nil)
        local matchMats = (not filterCraftable) or (entry.maxMake > 0)
        if matchSearch and matchMats then
            table.insert(filteredRecipes, entry)
        end
    end

    NoRecipesHint:SetShown(#filteredRecipes == 0)

    local yRec = 0
    for idx, entry in ipairs(filteredRecipes) do
        local row = recipeRows[idx]
        if not row then
            row = CreateFrame("Button", nil, RecipeContent)
            row:SetSize(268, 22)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            recipeRows[idx] = row
        end

        row:SetPoint("TOPLEFT", RecipeContent, "TOPLEFT", 0, -yRec)
        row.icon:SetTexture(entry.icon)
        if selectedRecipeID == entry.id then
            row.bg:SetColorTexture(0.25, 0.45, 0.75, 0.5)
        else
            row.bg:SetColorTexture(0.12, 0.12, 0.12, 0.45)
        end

        local color = (entry.maxMake > 0) and "00FF00" or "FF7777"
        row.text:SetText(string.format("|cFF%s%s|r |cFFAAAAAA(%d)|r", color, entry.name, entry.maxMake))

        row:SetScript("OnClick", function()
            if selectedRecipeID ~= entry.id then
                remainingEnchants = 0
            end
            selectedRecipeID = entry.id
            ns.UpdateEnchanterView()
        end)

        row:Show()
        yRec = yRec + 23
    end
    RecipeContent:SetHeight(math.max(260, yRec + 8))

    -- 2. Ziel-Items rendern
    for _, r in ipairs(targetRows) do r:Hide() end
    local targets = CollectEnchantableTargets()
    NoTargetsHint:SetShown(#targets == 0)

    selectedTargetInfo = nil
    local yTgt = 0
    for idx, t in ipairs(targets) do
        if selectedTargetKey == t.key then
            selectedTargetInfo = t
        end

        local row = targetRows[idx]
        if not row then
            row = CreateFrame("Button", nil, TargetContent)
            row:SetSize(442, 26)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.text:SetJustifyH("LEFT")

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            targetRows[idx] = row
        end

        row:SetPoint("TOPLEFT", TargetContent, "TOPLEFT", 0, -yTgt)
        row.icon:SetTexture(t.icon)

        if selectedTargetKey == t.key then
            row.bg:SetColorTexture(0.25, 0.45, 0.75, 0.5)
        else
            row.bg:SetColorTexture(0.12, 0.12, 0.12, 0.45)
        end

        local tag = t.isEquipped and GetSafeLocale("ENCH_EQUIPPED_TAG", "[Equipped]") or GetSafeLocale("ENCH_BAG_TAG", "[Bag]")
        row.text:SetText(string.format("%s  %s", tag, t.link or t.name))

        row:SetScript("OnEnter", function(self)
            if t.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(t.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:SetScript("OnClick", function()
            selectedTargetKey = t.key
            selectedTargetInfo = t
            ns.UpdateEnchanterView()
        end)

        row:Show()
        yTgt = yTgt + 28
    end
    TargetContent:SetHeight(math.max(280, yTgt + 8))

    UpdateActionFooter()
end

SearchBox:SetScript("OnTextChanged", function(self)
    searchText = strtrim(self:GetText() or ""):lower()
    SearchPlaceholder:SetShown(searchText == "")
    ns.UpdateEnchanterView()
end)
SearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
SearchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

CraftableCheck:SetScript("OnClick", function(self)
    filterCraftable = self:GetChecked() and true or false
    ns.UpdateEnchanterView()
end)

RefreshTargetsBtn:SetScript("OnClick", function()
    ns.UpdateEnchanterView()
end)

-- ============================================================================
-- 7. Verzauberung ausführen + Ziel-Item automatisch wählen + Replace bestätigen
-- ============================================================================

local function TryStartClassicDoTradeSkill(recipeID)
    if not GetNumTradeSkills or not GetTradeSkillInfo or not DoTradeSkill then return false end
    local targetName = ns.GetLocalizedRecipeName and ns.GetLocalizedRecipeName(recipeID)
    if not targetName then return false end
    local num = GetNumTradeSkills() or 0
    for i = 1, num do
        local name, skillType = GetTradeSkillInfo(i)
        if skillType ~= "header" and name == targetName then
            local ok = pcall(DoTradeSkill, i, 1)
            return ok
        end
    end
    return false
end

local function ApplyTargetItemToCursor(target)
    if not target then return end
    if SpellIsTargeting and not SpellIsTargeting() then return end

    if target.isEquipped and target.invSlot and UseInventoryItem then
        pcall(UseInventoryItem, target.invSlot)
    elseif (not target.isEquipped) and target.bag ~= nil and target.slot ~= nil then
        pcall(SafeUseContainerItem, target.bag, target.slot)
    end
end

EnchantBtn:SetScript("OnClick", function()
    if not selectedRecipeID or not selectedTargetInfo then
        print(GetSafeLocale("ENCH_SELECT_HINT", "Select an enchantment and a target item first."))
        return
    end

    if remainingEnchants <= 0 then
        totalBatchCount = math.max(1, tonumber(targetCount) or 1)
        remainingEnchants = totalBatchCount
        UpdateActionFooter()
    end

    autoConfirmUntil = (GetTime and GetTime() or 0) + 3.0

    -- Verzauberkunst-Berufsfenster öffnen, falls nötig
    if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
        pcall(C_TradeSkillUI.OpenTradeSkill, 333)
    end
    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        pcall(C_TradeSkillUI.OpenRecipe, selectedRecipeID)
    end

    local started = false
    if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
        local ok = pcall(C_TradeSkillUI.CraftRecipe, selectedRecipeID, 1)
        if ok then started = true end
    end
    if not started then
        started = TryStartClassicDoTradeSkill(selectedRecipeID)
    end

    if not started then
        print(GetSafeLocale("ENCH_OPEN_PROF_HINT", "|cFFFFAA00[BoisCraft]|r Please open your Enchanting window once."))
        return
    end

    ApplyTargetItemToCursor(selectedTargetInfo)

    if ReplaceEnchant and StaticPopup_Visible and StaticPopup_Visible("REPLACE_ENCHANT") then
        pcall(ReplaceEnchant)
        if StaticPopup_Hide then pcall(StaticPopup_Hide, "REPLACE_ENCHANT") end
    end
end)

local enchEventFrame = CreateFrame("Frame")
enchEventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
enchEventFrame:RegisterEvent("REPLACE_ENCHANT")
enchEventFrame:RegisterEvent("TRADE_REPLACE_ENCHANT")
enchEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
enchEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

enchEventFrame:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if (event == "REPLACE_ENCHANT" or event == "TRADE_REPLACE_ENCHANT") then
        local now = GetTime and GetTime() or 0
        if now <= autoConfirmUntil and ReplaceEnchant then
            pcall(ReplaceEnchant)
            if StaticPopup_Hide then
                pcall(StaticPopup_Hide, "REPLACE_ENCHANT")
                pcall(StaticPopup_Hide, "TRADE_REPLACE_ENCHANT")
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" and selectedRecipeID and tonumber(arg3) == tonumber(selectedRecipeID) and remainingEnchants > 0 then
            remainingEnchants = math.max(0, remainingEnchants - 1)
            if remainingEnchants == 0 then
                if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
                    PlaySound(SOUNDKIT.READY_CHECK)
                end
                print(string.format(GetSafeLocale("ENCH_BATCH_DONE", "|cFF00FF00[BoisCraft]|r All %d enchants completed!"), totalBatchCount))
                totalBatchCount = 0
                autoConfirmUntil = 0
            end
            if EnchanterView:IsShown() then
                ns.UpdateEnchanterView()
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        if EnchanterView:IsShown() then
            ns.UpdateEnchanterView()
        end
    end
end)

EnchanterView:SetScript("OnShow", function()
    ns.UpdateEnchanterView()
end)
