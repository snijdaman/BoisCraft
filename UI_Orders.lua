local addonName, ns = ...
local L = ns.L

-- Gespeicherte Tabellen sicherstellen
IncomingOrders = IncomingOrders or {}
PendingOrders = PendingOrders or {}
BoisCraftSettings = BoisCraftSettings or {}
BoisCraftSettings.myAlts = BoisCraftSettings.myAlts or {}

-- View-Frame sicherstellen
local OrdersView = ns.OrdersView
if not OrdersView then
    local parent = ns.MainFrame or UIParent
    OrdersView = CreateFrame("Frame", nil, parent)
    OrdersView:SetAllPoints(parent)
    ns.OrdersView = OrdersView
end

-- ============================================================================
-- 1. Automatischer Twink-Sync
-- ============================================================================

function ns.SyncAltOrders()
    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    if myName == "" then return end

    BoisCraftSettings = BoisCraftSettings or {}
    BoisCraftSettings.myAlts = BoisCraftSettings.myAlts or {}
    BoisCraftSettings.myAlts[myName] = true

    if not PendingOrders then return end
    IncomingOrders = IncomingOrders or {}

    for _, pOrder in ipairs(PendingOrders) do
        local targetCrafter = (ns.NormalizeName and ns.NormalizeName(pOrder.crafter)) or pOrder.crafter
        if targetCrafter == myName then
            local exists = false
            for _, inOrder in ipairs(IncomingOrders) do
                if inOrder.orderID == pOrder.orderID then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(IncomingOrders, {
                    orderID      = pOrder.orderID,
                    sender       = pOrder.sender,
                    crafter      = myName,
                    recipeID     = pOrder.recipeID,
                    count        = pOrder.count or 1,
                    countOrdered = pOrder.count or 1,
                    countCrafted = 0,
                    origin       = "ALT",
                    isAltOrder   = true,
                })
            end
        end
    end
end

-- ============================================================================
-- 2. Herstellungs- & Rückversand-Logik (Crafter -> Besteller)
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

local function AttachCraftedItemToMail(order)
    if not order or not order.recipeID then return end
    if not IsMailboxOpen() then
        print(L["MSG_OPEN_MAILBOX_FIRST"])
        return
    end

    local outItemID = ns.GetItemIDForRecipe and ns.GetItemIDForRecipe(order.recipeID)
    local rName = (ns.GetLocalizedRecipeName and ns.GetLocalizedRecipeName(order.recipeID)) or ("Recipe #" .. tostring(order.recipeID))
    if not outItemID then
        print(string.format(L["MSG_SHOPPING_NO_ITEMS"], rName))
        return
    end

    local recipient = (ns.NormalizeName and ns.NormalizeName(order.sender)) or order.sender or ""
    if recipient == "" then return end

    EnsureSendMailTabActive()
    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(recipient)
    end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(L["MAIL_SUBJECT_RETURN"] or "[BoisCraft] Crafted Item")
    end

    local totalNeeded = math.max(1, tonumber(order.countOrdered) or ((tonumber(order.count) or 0) + (tonumber(order.countCrafted) or 0)))
    local attachedNow = 0
    local maxAttachments = ATTACHMENTS_MAX_SEND or 12

    local function GetNextFreeMailSlot()
        for i = 1, maxAttachments do
            local hasItem = false
            if GetSendMailItem then
                local itemName = GetSendMailItem(i)
                if itemName and itemName ~= "" then hasItem = true end
            end
            if not hasItem then return i end
        end
        return nil
    end

    for bag = 0, 4 do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
            or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            if attachedNow >= totalNeeded then break end
            local slotItemID, stackCount, isLocked = nil, 1, false
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    slotItemID = info.itemID
                    stackCount = info.stackCount or 1
                    isLocked = info.isLocked
                end
            elseif GetContainerItemInfo then
                local _, cnt, locked, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
                slotItemID = id or (link and tonumber(link:match("item:(%d+)")))
                stackCount = cnt or 1
                isLocked = locked
            end

            if slotItemID == outItemID and not isLocked then
                local mailSlot = GetNextFreeMailSlot()
                if not mailSlot then break end
                ClearCursor()
                if C_Container and C_Container.PickupContainerItem then
                    C_Container.PickupContainerItem(bag, slot)
                elseif PickupContainerItem then
                    PickupContainerItem(bag, slot)
                end
                ClickSendMailItemButton(mailSlot)
                ClearCursor()
                attachedNow = attachedNow + stackCount
            end
        end
    end

    if attachedNow > 0 then
        print(string.format(L["MSG_ITEM_ATTACHED_RET"], attachedNow, rName, ns.GetColoredPlayerName(recipient)))
    else
        print(string.format(L["MSG_SHOPPING_NO_ITEMS"], rName))
    end
end

function ns.CompleteIncomingOrderByIndex(orderIndex)
    if not IncomingOrders or not IncomingOrders[orderIndex] then return end
    local order = IncomingOrders[orderIndex]
    local sender = (ns.NormalizeName and ns.NormalizeName(order.sender)) or order.sender or ""
    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    local oID = order.lastOrderID or order.orderID or ""
    local firstOID = order.orderID or ""
    local rID = tonumber(order.recipeID) or 0

    table.remove(IncomingOrders, orderIndex)

    if ns.RecordOrderTombstone then
        if oID ~= "" then ns.RecordOrderTombstone(oID, "DONE", sender, rID) end
        if firstOID ~= "" and firstOID ~= oID then ns.RecordOrderTombstone(firstOID, "DONE", sender, rID) end
    end

    if PendingOrders and (oID ~= "" or firstOID ~= "") then
        for pIdx = #PendingOrders, 1, -1 do
            local pID = PendingOrders[pIdx].orderID
            if pID == oID or pID == firstOID then
                table.remove(PendingOrders, pIdx)
                break
            end
        end
    end

    if sender ~= "" and sender ~= myName and ns.SendSyncMessage then
        ns.SendSyncMessage(string.format("DONE:%s:%d:%s", oID, rID, myName), sender)
        if firstOID ~= "" and firstOID ~= oID then
            ns.SendSyncMessage(string.format("DONE:%s:%d:%s", firstOID, rID, myName), sender)
        end
    end
end

-- Wird von UI_Shopping.lua bei MAIL_SEND_SUCCESS oder beim Handel aufgerufen
function ns.RecordOrderDelivery(recipient, itemID, sentQty)
    recipient = (ns.NormalizeName and ns.NormalizeName(recipient)) or recipient
    itemID = tonumber(itemID)
    sentQty = tonumber(sentQty) or 1
    if not recipient or recipient == "" or not itemID or not IncomingOrders then return end

    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    for i = #IncomingOrders, 1, -1 do
        local order = IncomingOrders[i]
        local orderSender = (ns.NormalizeName and ns.NormalizeName(order.sender)) or order.sender
        local orderCrafter = (ns.NormalizeName and ns.NormalizeName(order.crafter)) or order.crafter
        local outItemID = ns.GetItemIDForRecipe and ns.GetItemIDForRecipe(order.recipeID)

        if orderSender == recipient and (not orderCrafter or orderCrafter == "" or orderCrafter == myName) and outItemID == itemID then
            local totalOrdered = tonumber(order.countOrdered) or ((tonumber(order.count) or 0) + (tonumber(order.countCrafted) or 0))
            if totalOrdered <= 0 then totalOrdered = 1 end
            local rName = (ns.GetLocalizedRecipeName and ns.GetLocalizedRecipeName(order.recipeID)) or ("Item #" .. itemID)

            if sentQty >= totalOrdered then
                ns.CompleteIncomingOrderByIndex(i)
            else
                order.countOrdered = math.max(1, totalOrdered - sentQty)
                order.count = math.max(0, (tonumber(order.count) or 0) - sentQty)
                order.countCrafted = math.max(0, (tonumber(order.countCrafted) or 0) - sentQty)
            end

            print(string.format(L["MSG_AUTO_DELIVERED"], sentQty, rName, ns.GetColoredPlayerName(recipient)))
            ns.RunOutOfCombat(function()
                if ns.UpdateOrdersList then ns.UpdateOrdersList() end
            end, "UpdateOrdersAfterDelivery")
            break
        end
    end
end

local function ExecuteCraftOrder(recipeID, count)
    recipeID = tonumber(recipeID)
    count = math.max(1, tonumber(count) or 1)
    if not recipeID then return end

    if not ns.HasReagentsForRecipe(recipeID) then
        print(L["MSG_MISSING_REAGENTS"])
    end

    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        pcall(C_TradeSkillUI.OpenRecipe, recipeID)
    elseif C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
        pcall(C_TradeSkillUI.OpenTradeSkill, recipeID)
    end

    if ProfessionsFrame and not ProfessionsFrame:IsShown() then
        pcall(ProfessionsFrame.Show, ProfessionsFrame)
    end

    local crafted = false
    if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
        local ok = pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
        if ok then crafted = true end
    end

    if not crafted and DoTradeSkill then
        local ok = pcall(DoTradeSkill, recipeID, count)
        if ok then crafted = true end
    end

    if not crafted and C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
                pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
            end
        end)
    end
end

local function GetRecipeNameAndIcon(recipeID)
    if ns.GetLocalizedRecipeName then
        local name, icon = ns.GetLocalizedRecipeName(recipeID)
        return name or ("Rezept #" .. tostring(recipeID)), icon or 134400
    end
    return "Rezept #" .. tostring(recipeID), 134400
end

-- ============================================================================
-- 3. UI-Bereich 1: Eingegangene Aufträge (Oben)
-- ============================================================================

local inHeader = OrdersView:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
inHeader:SetPoint("TOPLEFT", OrdersView, "TOPLEFT", 15, -32)
inHeader:SetText(L["ORDERS_IN_HEADER"])

local InScroll = CreateFrame("ScrollFrame", "BoisCraftIncomingScroll", OrdersView, "UIPanelScrollFrameTemplate")
InScroll:SetPoint("TOPLEFT", OrdersView, "TOPLEFT", 15, -55)
InScroll:SetPoint("BOTTOMRIGHT", OrdersView, "TOPRIGHT", -35, -215)

local InContent = CreateFrame("Frame", nil, InScroll)
InContent:SetSize(760, 160)
InScroll:SetScrollChild(InContent)

local inRows = {}

-- ============================================================================
-- 4. Trennbalken (Mitte)
-- ============================================================================

local MidDivider = OrdersView:CreateTexture(nil, "BORDER")
MidDivider:SetHeight(2)
MidDivider:SetPoint("TOPLEFT", OrdersView, "TOPLEFT", 15, -225)
MidDivider:SetPoint("TOPRIGHT", OrdersView, "TOPRIGHT", -15, -225)
MidDivider:SetColorTexture(0.35, 0.35, 0.35, 0.8)

-- ============================================================================
-- 5. UI-Bereich 2: Erteilte Aufträge (Unten)
-- ============================================================================

local outHeader = OrdersView:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
outHeader:SetPoint("TOPLEFT", OrdersView, "TOPLEFT", 15, -235)
outHeader:SetText(L["ORDERS_OUT_HEADER"])

local OutScroll = CreateFrame("ScrollFrame", "BoisCraftPendingScroll", OrdersView, "UIPanelScrollFrameTemplate")
OutScroll:SetPoint("TOPLEFT", OrdersView, "TOPLEFT", 15, -258)
OutScroll:SetPoint("BOTTOMRIGHT", OrdersView, "BOTTOMRIGHT", -35, 45)

local OutContent = CreateFrame("Frame", nil, OutScroll)
OutContent:SetSize(760, 160)
OutScroll:SetScrollChild(OutContent)

local outRows = {}

-- ============================================================================
-- 6. Render-Funktion
-- ============================================================================

function ns.UpdateOrdersList()
    ns.SyncAltOrders()

    inHeader:SetText(L["ORDERS_IN_HEADER"])
    outHeader:SetText(L["ORDERS_OUT_HEADER"])

    local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""

    -- 6a. Eingegangene Aufträge
    for _, r in ipairs(inRows) do r:Hide() end

    local inIndex = 0
    local inY = 0

    if IncomingOrders then
        for idx, order in ipairs(IncomingOrders) do
            local crafterNorm = (ns.NormalizeName and ns.NormalizeName(order.crafter)) or order.crafter
            if not crafterNorm or crafterNorm == "" or crafterNorm == myName then
                inIndex = inIndex + 1
                local row = inRows[inIndex] or CreateFrame("Frame", nil, InContent)
                inRows[inIndex] = row
                row:SetSize(750, 28)
                row:SetPoint("TOPLEFT", InContent, "TOPLEFT", 0, -inY)

                if not row.icon then
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(22, 22)
                    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                end
                row.icon:Show()

                if not row.doneBtn then
                    row.doneBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.doneBtn:SetSize(80, 22)
                    row.doneBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end
                row.doneBtn:SetText(L["BTN_DONE"])
                row.doneBtn:Show()

                if not row.sendItemBtn then
                    row.sendItemBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.sendItemBtn:SetSize(110, 22)
                    row.sendItemBtn:SetPoint("RIGHT", row.doneBtn, "LEFT", -4, 0)
                end
                row.sendItemBtn:SetText(L["BTN_SEND_ITEM"])
                row.sendItemBtn:Show()

                if not row.craftBtn then
                    row.craftBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.craftBtn:SetSize(95, 22)
                    row.craftBtn:SetPoint("RIGHT", row.sendItemBtn, "LEFT", -4, 0)
                end
                row.craftBtn:Show()

                if not row.text then
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                    row.text:SetPoint("RIGHT", row.craftBtn, "LEFT", -8, 0)
                    row.text:SetJustifyH("LEFT")
                end

                local rName, rIcon = GetRecipeNameAndIcon(order.recipeID)
                row.icon:SetTexture(rIcon)

                local remaining = tonumber(order.count)
                if remaining == nil then remaining = 1 end
                local craftedCount = tonumber(order.countCrafted) or 0
                local totalOrdered = tonumber(order.countOrdered) or (remaining + craftedCount)
                if totalOrdered < 1 then totalOrdered = 1 end

                local originPrefix = ""
                if order.origin == "MAIL" then
                    originPrefix = L["ORIGIN_MAIL"] or ""
                elseif order.isAltOrder or order.origin == "ALT" then
                    originPrefix = L["ORIGIN_ALT"] or ""
                end

                local coloredSender = (ns.GetColoredPlayerName and ns.GetColoredPlayerName(order.sender)) or (order.sender or "Unbekannt")
                local wantsText = string.format(L["ORDER_WANTS"] or "%s wants: |cFFFFFFFF%dx %s|r", coloredSender, totalOrdered, rName)
                if craftedCount > 0 or remaining == 0 then
                    local progText = string.format(L["ORDER_PROGRESS"] or "(%d/%d)", craftedCount, totalOrdered, remaining)
                    row.text:SetText(originPrefix .. wantsText .. " " .. progText)
                else
                    row.text:SetText(originPrefix .. wantsText)
                end

                if remaining > 0 then
                    row.craftBtn:SetText(string.format(L["BTN_CRAFT_AMOUNT"] or L["BTN_CRAFT"], remaining))
                    row.craftBtn:Enable()
                else
                    row.craftBtn:SetText(L["BTN_CRAFT"])
                    row.craftBtn:Disable()
                end

                local outItemID = ns.GetItemIDForRecipe and ns.GetItemIDForRecipe(order.recipeID)
                local inBags = outItemID and ((C_Item and C_Item.GetItemCount and C_Item.GetItemCount(outItemID, false))
                    or (GetItemCount and GetItemCount(outItemID)) or 0) or 0
                if inBags > 0 then
                    row.sendItemBtn:Enable()
                else
                    row.sendItemBtn:Disable()
                end

                row.craftBtn:SetScript("OnClick", function()
                    ExecuteCraftOrder(order.recipeID, math.max(1, remaining))
                end)

                row.sendItemBtn:SetScript("OnClick", function()
                    AttachCraftedItemToMail(order)
                end)

                row.doneBtn:SetScript("OnClick", function()
                    ns.CompleteIncomingOrderByIndex(idx)
                    ns.UpdateOrdersList()
                    print(string.format(L["MSG_ORDER_DONE"], coloredSender))
                end)

                row:Show()
                inY = inY + 30
            end
        end
    end

    if inIndex == 0 then
        inIndex = 1
        local emptyRow = inRows[inIndex] or CreateFrame("Frame", nil, InContent)
        inRows[inIndex] = emptyRow
        emptyRow:SetSize(750, 24)
        emptyRow:SetPoint("TOPLEFT", InContent, "TOPLEFT", 0, 0)
        if not emptyRow.text then
            emptyRow.text = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyRow.text:SetPoint("LEFT", emptyRow, "LEFT", 5, 0)
        end
        emptyRow.text:SetText(L["ORDERS_NONE_IN"])
        if emptyRow.craftBtn then emptyRow.craftBtn:Hide() end
        if emptyRow.sendItemBtn then emptyRow.sendItemBtn:Hide() end
        if emptyRow.doneBtn then emptyRow.doneBtn:Hide() end
        if emptyRow.icon then emptyRow.icon:Hide() end
        emptyRow:Show()
        inY = 26
    end
    InContent:SetHeight(math.max(150, inY + 10))

    -- 6b. Erteilte Aufträge
    for _, r in ipairs(outRows) do r:Hide() end

    local outIndex = 0
    local outY = 0

    if PendingOrders then
        for idx, order in ipairs(PendingOrders) do
            local senderNorm = (ns.NormalizeName and ns.NormalizeName(order.sender)) or order.sender
            if not senderNorm or senderNorm == "" or senderNorm == myName then
                outIndex = outIndex + 1
                local row = outRows[outIndex] or CreateFrame("Frame", nil, OutContent)
                outRows[outIndex] = row
                row:SetSize(750, 28)
                row:SetPoint("TOPLEFT", OutContent, "TOPLEFT", 0, -outY)

                if not row.icon then
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(22, 22)
                    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                end
                row.icon:Show()

                if not row.cancelBtn then
                    row.cancelBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.cancelBtn:SetSize(85, 22)
                    row.cancelBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
                end
                row.cancelBtn:SetText(L["BTN_CANCEL"])
                row.cancelBtn:Show()

                if not row.text then
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                    row.text:SetPoint("RIGHT", row.cancelBtn, "LEFT", -8, 0)
                    row.text:SetJustifyH("LEFT")
                end

                local rName, rIcon = GetRecipeNameAndIcon(order.recipeID)
                row.icon:SetTexture(rIcon)

                local targetCrafter = (ns.NormalizeName and ns.NormalizeName(order.crafter)) or order.crafter
                local coloredCrafter = (ns.GetColoredPlayerName and ns.GetColoredPlayerName(targetCrafter)) or targetCrafter
                local statusText
                if targetCrafter == myName or (BoisCraftSettings.myAlts and BoisCraftSettings.myAlts[targetCrafter]) then
                    statusText = L["STATUS_OWN_ALT"]
                elseif order.acked then
                    statusText = L["STATUS_ACKED"]
                elseif order.mailed then
                    statusText = L["STATUS_MAILED"]
                else
                    statusText = L["STATUS_WAITING"]
                end

                row.text:SetText(string.format("%s: |cFFFFFFFF%dx %s|r  %s", coloredCrafter, order.count or 1, rName, statusText))

                row.cancelBtn:SetScript("OnClick", function()
                    if ns.RemoveRecipeFromShoppingList then
                        ns.RemoveRecipeFromShoppingList(order.crafter, order.recipeID, order.count or 1)
                    end

                    local oID = order.orderID or ""
                    local rID = tonumber(order.recipeID) or 0
                    if ns.RecordOrderTombstone and oID ~= "" then
                        ns.RecordOrderTombstone(oID, "CANCELED", targetCrafter, rID)
                    end

                    table.remove(PendingOrders, idx)
                    if IncomingOrders then
                        for inIdx = #IncomingOrders, 1, -1 do
                            if IncomingOrders[inIdx].orderID == oID or IncomingOrders[inIdx].lastOrderID == oID then
                                table.remove(IncomingOrders, inIdx)
                                break
                            end
                        end
                    end

                    if targetCrafter ~= "" and targetCrafter ~= myName and ns.SendSyncMessage then
                        ns.SendSyncMessage(string.format("CANCEL:%s:%d:%s", oID, rID, myName), targetCrafter)
                    end

                    ns.UpdateOrdersList()
                    print(string.format(L["MSG_ORDER_CANCELED"], coloredCrafter))
                end)

                row:Show()
                outY = outY + 30
            end
        end
    end

    if outIndex == 0 then
        outIndex = 1
        local emptyRow = outRows[outIndex] or CreateFrame("Frame", nil, OutContent)
        outRows[outIndex] = emptyRow
        emptyRow:SetSize(750, 24)
        emptyRow:SetPoint("TOPLEFT", OutContent, "TOPLEFT", 0, 0)
        if not emptyRow.text then
            emptyRow.text = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyRow.text:SetPoint("LEFT", emptyRow, "LEFT", 5, 0)
        end
        emptyRow.text:SetText(L["ORDERS_NONE_OUT"])
        if emptyRow.cancelBtn then emptyRow.cancelBtn:Hide() end
        if emptyRow.icon then emptyRow.icon:Hide() end
        emptyRow:Show()
        outY = 26
    end
    OutContent:SetHeight(math.max(150, outY + 10))

    if ns.RefreshMainFrameLocale then
        ns.RefreshMainFrameLocale()
    end
end

-- ============================================================================
-- 7. Events zur Initialisierung & Taschen-Update
-- ============================================================================

local orderEvt = CreateFrame("Frame")
orderEvt:RegisterEvent("PLAYER_LOGIN")
orderEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
orderEvt:RegisterEvent("BAG_UPDATE_DELAYED")
orderEvt:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        if OrdersView and OrdersView:IsShown() and ns.UpdateOrdersList then
            ns.UpdateOrdersList()
        end
        return
    end
    ns.SyncAltOrders()
    if ns.UpdateOrdersList then
        ns.UpdateOrdersList()
    end
end)
