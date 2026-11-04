local addonName, ns = ...
local L = ns.L

ns.EnsureSavedVariables()

local ShoppingView = ns.ShoppingView
if not ShoppingView then
    local parent = ns.MainFrame or UIParent
    ShoppingView = CreateFrame("Frame", nil, parent)
    ShoppingView:SetAllPoints(parent)
    ns.ShoppingView = ShoppingView
end

-- ============================================================================
-- 1. Container- & Briefkasten-Hilfsfunktionen
-- ============================================================================

local function IsMailboxOpen()
    if SendMailFrame and SendMailFrame:IsShown() then return true end
    if MailFrame and MailFrame:IsShown() then return true end
    return false
end

local function EnsureSendMailTabActive()
    if MailFrame and MailFrame:IsShown() and SendMailFrame and not SendMailFrame:IsShown() then
        if MailFrameTab_OnClick then
            pcall(MailFrameTab_OnClick, nil, 2)
        elseif MailFrameTab2 then
            pcall(MailFrameTab2.Click, MailFrameTab2)
        end
    end
end

local function GetBagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function GetBagSlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.itemID, info.stackCount or 1, info.isLocked
        end
        return nil, 0, false
    elseif GetContainerItemInfo then
        local _, count, locked, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        if not itemID and link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
        return itemID, count or 1, locked
    end
    return nil, 0, false
end

local function PickupBagSlot(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then
        PickupContainerItem(bag, slot)
    end
end

local function SplitBagSlot(bag, slot, amount)
    if C_Container and C_Container.SplitContainerItem then
        C_Container.SplitContainerItem(bag, slot, amount)
    elseif SplitContainerItem then
        SplitContainerItem(bag, slot, amount)
    end
end

-- Ermittelt die ItemID und Stapelgröße in einem Briefkasten-Anhang-Slot (1..12)
local function GetMailSlotItemInfo(slotIndex)
    local itemID = nil
    local count = 0

    if GetSendMailItemLink then
        local link = GetSendMailItemLink(slotIndex)
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if GetSendMailItem then
        local name, a2, a3, a4 = GetSendMailItem(slotIndex)
        if name and name ~= "" then
            if type(a4) == "number" then
                count = a4
                if not itemID and type(a2) == "number" and a2 > 0 then
                    itemID = a2
                end
            elseif type(a3) == "number" then
                count = a3
            else
                count = 1
            end
        end
    end

    return itemID, count
end

-- Zählt live, wie viele Items aktuell im geöffneten Postfenster liegen
local function GetAttachedMailItemsForCrafter(crafterName)
    local attached = {}
    if not IsMailboxOpen() then return attached end

    local currentRecipient = ""
    if SendMailNameEditBox then
        currentRecipient = ns.NormalizeName(SendMailNameEditBox:GetText() or "")
    end

    local normCrafter = ns.NormalizeName(crafterName)
    if currentRecipient ~= "" and currentRecipient ~= normCrafter then
        return attached
    end

    local maxAttachments = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxAttachments do
        local itemID, count = GetMailSlotItemInfo(i)
        if itemID and count and count > 0 then
            attached[itemID] = (attached[itemID] or 0) + count
        end
    end
    return attached
end

-- ============================================================================
-- 2. Asynchroner Mail-Auftragsgenerator (Schreibt BC_ORD:... in den Brieftext)
-- ============================================================================

function ns.PrepareOrderMailHeaderAndBody(crafterName)
    crafterName = ns.NormalizeName(crafterName)
    if crafterName == "" then return end

    EnsureSendMailTabActive()

    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(crafterName)
    end

    local orderLines = {}
    local firstOrder = nil
    if PendingOrders then
        for _, pOrder in ipairs(PendingOrders) do
            if ns.NormalizeName(pOrder.crafter) == crafterName then
                local oID = pOrder.orderID or ns.GenerateOrderID()
                pOrder.orderID = oID
                local rID = tonumber(pOrder.recipeID)
                local cnt = tonumber(pOrder.count) or 1
                if rID then
                    if not firstOrder then firstOrder = pOrder end
                    table.insert(orderLines, string.format("BC_ORD:%s:%d:%d", oID, rID, cnt))
                end
            end
        end
    end

    if SendMailSubjectEditBox then
        if #orderLines == 1 and firstOrder then
            local subj = string.format("[BC:ORD:%s:%d:%d]", firstOrder.orderID, firstOrder.recipeID, firstOrder.count or 1)
            SendMailSubjectEditBox:SetText(subj)
        else
            SendMailSubjectEditBox:SetText(L["MAIL_SUBJECT_ORDER"])
        end
    end

    if SendMailBodyEditBox and #orderLines > 0 then
        local existingBody = SendMailBodyEditBox:GetText() or ""
        local newBody = table.concat(orderLines, "\n")
        if not existingBody:find("BC_ORD:", 1, true) then
            if existingBody ~= "" then
                SendMailBodyEditBox:SetText(existingBody .. "\n" .. newBody)
            else
                SendMailBodyEditBox:SetText(newBody)
            end
        else
            SendMailBodyEditBox:SetText(newBody)
        end
    end
end

-- Legt das Material in den Briefkasten, LÖSCHT ES ABER NOCH NICHT aus ShoppingList!
-- Das echte Löschen passiert erst bei MAIL_SEND_SUCCESS!
local function AttachMaterialForCrafter(crafterName, itemID, reqQty, silent, sharedUsedSlots)
    if not IsMailboxOpen() then
        if not silent then print(L["MSG_OPEN_MAILBOX_FIRST"]) end
        return 0
    end

    crafterName = ns.NormalizeName(crafterName)
    ns.PrepareOrderMailHeaderAndBody(crafterName)

    local alreadyInMail = GetAttachedMailItemsForCrafter(crafterName)[itemID] or 0
    local stillNeeded = math.max(0, (tonumber(reqQty) or 1) - alreadyInMail)
    if stillNeeded <= 0 then return 0 end

    local attachedNow = 0
    local usedMailSlots = sharedUsedSlots or {}

    local function GetNextAvailableMailSlot()
        local maxAttachments = ATTACHMENTS_MAX_SEND or 12
        for i = 1, maxAttachments do
            if not usedMailSlots[i] then
                local hasItem = false
                if GetSendMailItem then
                    local itemName = GetSendMailItem(i)
                    if itemName and itemName ~= "" then
                        hasItem = true
                    end
                end
                if not hasItem then
                    usedMailSlots[i] = true
                    return i
                end
            end
        end
        return nil
    end

    -- 1. Durchgang: Stapel suchen, die kleiner oder genau passend sind
    for bag = 0, 4 do
        local numSlots = GetBagSlots(bag)
        for slot = 1, numSlots do
            if stillNeeded <= 0 then break end
            local slotItemID, stackCount, isLocked = GetBagSlotInfo(bag, slot)
            if slotItemID == itemID and not isLocked and stackCount <= stillNeeded then
                local mailSlot = GetNextAvailableMailSlot()
                if not mailSlot then break end

                ClearCursor()
                PickupBagSlot(bag, slot)
                ClickSendMailItemButton(mailSlot)
                ClearCursor()

                stillNeeded = stillNeeded - stackCount
                attachedNow = attachedNow + stackCount
            end
        end
    end

    -- 2. Durchgang: Größeren Stapel exakt teilen
    if stillNeeded > 0 then
        for bag = 0, 4 do
            local numSlots = GetBagSlots(bag)
            for slot = 1, numSlots do
                local slotItemID, stackCount, isLocked = GetBagSlotInfo(bag, slot)
                if slotItemID == itemID and not isLocked and stackCount > stillNeeded then
                    local mailSlot = GetNextAvailableMailSlot()
                    if mailSlot then
                        ClearCursor()
                        SplitBagSlot(bag, slot, stillNeeded)
                        ClickSendMailItemButton(mailSlot)
                        ClearCursor()

                        attachedNow = attachedNow + stillNeeded
                        stillNeeded = 0
                    end
                    break
                end
            end
        end
    end

    if attachedNow > 0 then
        if not silent then
            local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("Item #" .. itemID)
            print(string.format(L["MSG_SHOPPING_ATTACHED"], attachedNow, itemName, ns.GetColoredPlayerName(crafterName)))
        end
        ns.UpdateShoppingListView()
    elseif not silent then
        local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("Item #" .. itemID)
        print(string.format(L["MSG_SHOPPING_NO_ITEMS"], itemName))
    end

    return attachedNow
end

-- ============================================================================
-- 3. UI-Elemente: Liste-leeren-Button & Scrollbereich
-- ============================================================================

local ClearBtn = CreateFrame("Button", "BoisCraftClearShoppingBtn", ShoppingView, "UIPanelButtonTemplate")
ClearBtn:SetSize(115, 22)
ClearBtn:SetPoint("TOPRIGHT", ShoppingView, "TOPRIGHT", -32, -32)
ClearBtn:SetText(L["BTN_CLEAR_SHOPPING"])

ClearBtn:SetScript("OnClick", function()
    ShoppingList = {}
    ns.UpdateShoppingListView()
    print(L["MSG_SHOPPING_CLEARED"])
end)

local ShoppingScroll = CreateFrame("ScrollFrame", "BoisCraftShoppingScroll", ShoppingView, "UIPanelScrollFrameTemplate")
ShoppingScroll:SetPoint("TOPLEFT", ShoppingView, "TOPLEFT", 18, -58)
ShoppingScroll:SetPoint("BOTTOMRIGHT", ShoppingView, "BOTTOMRIGHT", -35, 42)

local ShoppingContent = CreateFrame("Frame", nil, ShoppingScroll)
ShoppingContent:SetSize(755, 360)
ShoppingScroll:SetScrollChild(ShoppingContent)

local shoppingRows = {}

-- ============================================================================
-- 4. Einkaufsliste rendern (mit Live-Vorschau der im Brief liegenden Items)
-- ============================================================================

function ns.UpdateShoppingListView()
    ClearBtn:SetText(L["BTN_CLEAR_SHOPPING"])
    for _, row in ipairs(shoppingRows) do row:Hide() end

    local rowIndex = 0
    local yOffset = 0
    local hasAny = false

    local sortedCrafters = {}
    if ShoppingList then
        for crafter, items in pairs(ShoppingList) do
            if type(items) == "table" then
                for _, reqQty in pairs(items) do
                    if reqQty and reqQty > 0 then
                        table.insert(sortedCrafters, crafter)
                        break
                    end
                end
            end
        end
    end
    table.sort(sortedCrafters, function(a, b) return a:lower() < b:lower() end)

    for _, crafter in ipairs(sortedCrafters) do
        local items = ShoppingList[crafter]
        local attachedInMail = GetAttachedMailItemsForCrafter(crafter)

        local itemKeys = {}
        for itemID, reqQty in pairs(items) do
            local numID = tonumber(itemID)
            local inMail = (numID and attachedInMail[numID]) or 0
            local effectiveNeed = (tonumber(reqQty) or 0) - inMail
            if numID and effectiveNeed > 0 then
                table.insert(itemKeys, numID)
            end
        end
        table.sort(itemKeys)

        if #itemKeys > 0 then
            hasAny = true

            rowIndex = rowIndex + 1
            local headerRow = shoppingRows[rowIndex]
            if not headerRow then
                headerRow = CreateFrame("Frame", nil, ShoppingContent)
                headerRow:SetSize(750, 28)
                shoppingRows[rowIndex] = headerRow
            end

            headerRow:SetPoint("TOPLEFT", ShoppingContent, "TOPLEFT", 0, -yOffset)

            if not headerRow.headerText then
                headerRow.headerText = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
                headerRow.headerText:SetPoint("LEFT", headerRow, "LEFT", 4, 0)
            end
            if not headerRow.mailAllBtn then
                headerRow.mailAllBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
                headerRow.mailAllBtn:SetSize(165, 22)
                headerRow.mailAllBtn:SetPoint("RIGHT", headerRow, "RIGHT", -4, 0)
            end

            if headerRow.iconBtn then headerRow.iconBtn:Hide() end
            if headerRow.sendBtn then headerRow.sendBtn:Hide() end
            if headerRow.doneBtn then headerRow.doneBtn:Hide() end
            if headerRow.itemText then headerRow.itemText:Hide() end
            if headerRow.bg then headerRow.bg:Hide() end

            local coloredCrafter = ns.GetColoredPlayerName(crafter)
            headerRow.headerText:SetText(string.format(L["SHOPPING_HEADER"], coloredCrafter))
            headerRow.headerText:Show()

            headerRow.mailAllBtn:SetText(L["BTN_MAIL_ORDER"])
            headerRow.mailAllBtn:Show()
            headerRow.mailAllBtn:SetScript("OnClick", function()
                if not IsMailboxOpen() then
                    print(L["MSG_OPEN_MAILBOX_FIRST"])
                    return
                end
                ns.PrepareOrderMailHeaderAndBody(crafter)
                local sharedUsedSlots = {}
                for _, itemID in ipairs(itemKeys) do
                    local totalReq = items[itemID] or items[tostring(itemID)] or 0
                    if totalReq > 0 then
                        AttachMaterialForCrafter(crafter, itemID, totalReq, false, sharedUsedSlots)
                    end
                end
            end)
            headerRow.mailAllBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(L["BTN_MAIL_ORDER"], 1, 0.82, 0)
                GameTooltip:AddLine(L["TT_MAIL_ORDER_BTN"], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            headerRow.mailAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            headerRow:Show()
            yOffset = yOffset + 30

            for _, itemID in ipairs(itemKeys) do
                local totalReq = items[itemID] or items[tostring(itemID)] or 0
                local inMail = attachedInMail[itemID] or 0
                local reqQty = math.max(0, totalReq - inMail)

                rowIndex = rowIndex + 1

                local row = shoppingRows[rowIndex]
                if not row then
                    row = CreateFrame("Frame", nil, ShoppingContent)
                    row:SetSize(750, 28)
                    shoppingRows[rowIndex] = row
                end

                row:SetPoint("TOPLEFT", ShoppingContent, "TOPLEFT", 0, -yOffset)

                if row.headerText then row.headerText:Hide() end
                if row.mailAllBtn then row.mailAllBtn:Hide() end

                if not row.bg then
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.bg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
                end
                row.bg:Show()

                if not row.iconBtn then
                    row.iconBtn = CreateFrame("Button", nil, row)
                    row.iconBtn:SetSize(22, 22)
                    row.iconBtn:SetPoint("LEFT", row, "LEFT", 10, 0)

                    row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
                    row.icon:SetAllPoints()
                    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                    row.border = row.iconBtn:CreateTexture(nil, "OVERLAY")
                    row.border:SetSize(28, 28)
                    row.border:SetPoint("CENTER", row.iconBtn, "CENTER", 0, 0)
                    row.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                    row.border:SetBlendMode("ADD")
                end
                row.iconBtn:Show()

                if not row.doneBtn then
                    row.doneBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.doneBtn:SetSize(80, 22)
                    row.doneBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end
                row.doneBtn:SetText(L["BTN_DONE"])
                row.doneBtn:Show()

                if not row.sendBtn then
                    row.sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.sendBtn:SetSize(90, 22)
                    row.sendBtn:SetPoint("RIGHT", row.doneBtn, "LEFT", -6, 0)
                end
                row.sendBtn:SetText(L["BTN_MAIL_SEND"])
                row.sendBtn:Show()

                if not row.itemText then
                    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.itemText:SetPoint("LEFT", row.iconBtn, "RIGHT", 8, 0)
                    row.itemText:SetPoint("RIGHT", row.sendBtn, "LEFT", -8, 0)
                    row.itemText:SetJustifyH("LEFT")
                end
                row.itemText:Show()

                local totalInBags, inBank, totalWithBank = 0, 0, 0
                if ns.GetBagAndBankItemCount then
                    totalInBags, inBank, totalWithBank = ns.GetBagAndBankItemCount(itemID)
                else
                    totalInBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, false))
                        or (GetItemCount and GetItemCount(itemID)) or 0
                    totalWithBank = totalInBags
                end
                local availableInBags = math.max(0, totalInBags - inMail)
                local bagColor = (availableInBags >= reqQty) and "00FF00" or ((math.max(0, totalWithBank - inMail) >= reqQty) and "FFCC00" or "FF7777")
                local bankSuffix = (inBank > 0) and string.format(L["BANK_COUNT_SUFFIX"] or " |cFF88CCFF[Bank: %d]|r", inBank) or ""

                if availableInBags > 0 then
                    row.sendBtn:Enable()
                else
                    row.sendBtn:Disable()
                end

                ns.AsyncLoadItem(itemID, function(itemName, itemLink, itemQuality, itemIcon)
                    row.icon:SetTexture(itemIcon or 134400)
                    if ns.SetIconQualityBorder then
                        ns.SetIconQualityBorder(row.border, itemQuality)
                    end
                    local displayLabel = itemLink or itemName or ("Item #" .. itemID)
                    row.itemText:SetText(string.format(L["SHOPPING_ITEM_LINE"], displayLabel, reqQty, bagColor, availableInBags) .. bankSuffix)
                end)

                row.iconBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(itemID)
                    GameTooltip:Show()
                end)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row.sendBtn:SetScript("OnClick", function()
                    AttachMaterialForCrafter(crafter, itemID, totalReq, false)
                end)

                row.doneBtn:SetScript("OnClick", function()
                    if ShoppingList[crafter] then
                        ShoppingList[crafter][itemID] = nil
                        ShoppingList[crafter][tostring(itemID)] = nil
                        local anyLeft = false
                        for _, cnt in pairs(ShoppingList[crafter]) do
                            if cnt and cnt > 0 then anyLeft = true break end
                        end
                        if not anyLeft then
                            ShoppingList[crafter] = nil
                        end
                    end
                    ns.UpdateShoppingListView()
                end)

                row:Show()
                yOffset = yOffset + 30
            end

            yOffset = yOffset + 10
        end
    end

    if not hasAny then
        rowIndex = 1
        local emptyRow = shoppingRows[rowIndex] or CreateFrame("Frame", nil, ShoppingContent)
        shoppingRows[rowIndex] = emptyRow
        emptyRow:SetSize(750, 28)
        emptyRow:SetPoint("TOPLEFT", ShoppingContent, "TOPLEFT", 0, 0)
        if not emptyRow.headerText then
            emptyRow.headerText = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyRow.headerText:SetPoint("LEFT", emptyRow, "LEFT", 4, 0)
        end
        emptyRow.headerText:SetText(L["NO_SHOPPING_ITEMS"])
        emptyRow.headerText:Show()
        if emptyRow.mailAllBtn then emptyRow.mailAllBtn:Hide() end
        if emptyRow.iconBtn then emptyRow.iconBtn:Hide() end
        if emptyRow.sendBtn then emptyRow.sendBtn:Hide() end
        if emptyRow.doneBtn then emptyRow.doneBtn:Hide() end
        if emptyRow.itemText then emptyRow.itemText:Hide() end
        if emptyRow.bg then emptyRow.bg:Hide() end
        emptyRow:Show()
        yOffset = 32
    end

    ShoppingContent:SetHeight(math.max(350, yOffset + 10))
end

-- ============================================================================
-- 5. Automatisches Post-Tracking (SendMail Hook & MAIL_SEND_SUCCESS)
-- ============================================================================

local pendingMailRecipient = nil
local pendingMailItems = {}
local pendingMailHadOrderCode = false

hooksecurefunc("SendMail", function(recipient, subject, body)
    pendingMailRecipient = ns.NormalizeName(recipient or "")
    pendingMailItems = {}
    pendingMailHadOrderCode = false

    if (subject and subject:find("%[BC:ORD:", 1, true)) or (body and body:find("BC_ORD:", 1, true)) then
        pendingMailHadOrderCode = true
    end

    local maxAttachments = ATTACHMENTS_MAX_SEND or 12
    for i = 1, maxAttachments do
        local itemID, qty = GetMailSlotItemInfo(i)
        if itemID and qty and qty > 0 then
            pendingMailItems[itemID] = (pendingMailItems[itemID] or 0) + qty
        end
    end
end)

-- Direkt am MailFrame lauschen, falls man vom Briefkasten weggeht oder ihn schließt
if MailFrame and MailFrame.HookScript then
    MailFrame:HookScript("OnHide", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                ns.RunOutOfCombat(ns.UpdateShoppingListView, "RefreshShoppingOnMailHide")
            end)
        else
            ns.RunOutOfCombat(ns.UpdateShoppingListView, "RefreshShoppingOnMailHide")
        end
    end)
end

local mailEventFrame = CreateFrame("Frame")
for _, evt in ipairs({
    "MAIL_SEND_SUCCESS",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "MAIL_SEND_INFO_UPDATE",
    "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED",
    "PLAYERBANKSLOTS_CHANGED",
}) do
    pcall(mailEventFrame.RegisterEvent, mailEventFrame, evt)
end

mailEventFrame:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SEND_SUCCESS" then
        if pendingMailRecipient and pendingMailRecipient ~= "" then
            -- ERST JETZT (nach echtem Versand!) werden die Materialien aus ShoppingList gelöscht!
            if ShoppingList and ShoppingList[pendingMailRecipient] then
                local listChanged = false

                for itemID, sentQty in pairs(pendingMailItems) do
                    local currentReq = ShoppingList[pendingMailRecipient][itemID] or ShoppingList[pendingMailRecipient][tostring(itemID)]
                    if currentReq and currentReq > 0 then
                        local remaining = currentReq - sentQty
                        ShoppingList[pendingMailRecipient][tostring(itemID)] = nil
                        if remaining <= 0 then
                            ShoppingList[pendingMailRecipient][itemID] = nil
                        else
                            ShoppingList[pendingMailRecipient][itemID] = remaining
                        end
                        listChanged = true
                    end
                end

                local anyRemaining = false
                for _, cnt in pairs(ShoppingList[pendingMailRecipient]) do
                    if cnt and cnt > 0 then anyRemaining = true break end
                end
                if not anyRemaining then
                    ShoppingList[pendingMailRecipient] = nil
                end

                if listChanged then
                    print(string.format(L["MSG_SHOPPING_MAIL_SENT"], ns.GetColoredPlayerName(pendingMailRecipient)))
                end
            end

            -- Falls Auftrags-Code im Brief war, PendingOrders als "Per Post gesendet" markieren
            if pendingMailHadOrderCode and PendingOrders then
                for _, pOrder in ipairs(PendingOrders) do
                    if ns.NormalizeName(pOrder.crafter) == pendingMailRecipient then
                        pOrder.mailed = true
                    end
                end
            end

            -- Prüfen, ob ein Crafter gerade fertige Auftrags-Items an den Kunden zurückgeschickt hat
            if ns.RecordOrderDelivery then
                for itemID, sentQty in pairs(pendingMailItems) do
                    ns.RecordOrderDelivery(pendingMailRecipient, itemID, sentQty)
                end
            end
        end

        pendingMailRecipient = nil
        pendingMailItems = {}
        pendingMailHadOrderCode = false

        ns.RunOutOfCombat(function()
            ns.UpdateShoppingListView()
            if ns.UpdateOrdersList then ns.UpdateOrdersList() end
        end, "UpdateShoppingAfterMail")

    elseif event == "MAIL_CLOSED" or event == "MAIL_SHOW" or event == "MAIL_SEND_INFO_UPDATE"
        or event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
        ns.RunOutOfCombat(ns.UpdateShoppingListView, "RefreshShoppingView")
    end
end)