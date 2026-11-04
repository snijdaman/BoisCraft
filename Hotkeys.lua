local addonName, ns = ...
local L = ns.L

BoisCraftWishlist = BoisCraftWishlist or {}
BoisCraftWishlist.chars = BoisCraftWishlist.chars or {}

-- Eigener versteckter Tooltip zum sicheren Auslesen von "Einzigartig / Unique"
local scanTip = _G["BoisCraftScanTooltip"] or CreateFrame("GameTooltip", "BoisCraftScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Schutz gegen doppeltes Feuern im selben Frame (z.B. SetItemRef + HandleModifiedItemClick)
local lastToggleTime = 0
local lastToggleItem = nil

local function IsItemUnique(itemID)
    scanTip:ClearLines()
    if scanTip.SetItemByID then
        scanTip:SetItemByID(itemID)
    else
        scanTip:SetHyperlink("item:" .. tostring(itemID))
    end

    for i = 1, scanTip:NumLines() do
        local leftLine = _G["BoisCraftScanTooltipTextLeft" .. i]
        local text = leftLine and leftLine:GetText()
        if text then
            local lower = text:lower()
            if lower:find("einzigartig") or lower:find("unique") then
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- 1. Wunschliste umschalten (Toggle: Hinzufügen / Menge 2x / Entfernen)
-- ============================================================================

function ns.ToggleWishlistItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return end

    -- Entprellung: Verhindert, dass GLOBAL_MOUSE_DOWN (Drücken) und OnClick (Loslassen) doppelt schalten
    local now = GetTime()
    if lastToggleItem == itemID and (now - lastToggleTime) < 0.35 then
        return
    end
    lastToggleTime = now
    lastToggleItem = itemID

    -- Charakterspezifische Wunschliste abrufen
    local myList = ns.GetMyCharWishlist and ns.GetMyCharWishlist()
    if not myList then
        BoisCraftWishlist = BoisCraftWishlist or {}
        BoisCraftWishlist.chars = BoisCraftWishlist.chars or {}
        local myName = (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or "Unknown"
        BoisCraftWishlist.chars[myName] = BoisCraftWishlist.chars[myName] or {}
        myList = BoisCraftWishlist.chars[myName]
    end

    local itemName, itemLink = nil, nil
    if C_Item and C_Item.GetItemInfo then
        itemName, itemLink = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        itemName, itemLink = GetItemInfo(itemID)
    end
    local displayLink = itemLink or itemName or ("Item #" .. itemID)

    local isUnique = IsItemUnique(itemID)
    local entry = myList[itemID]

    if not entry or entry.status ~= "WANTED" then
        -- Option 1: Beim Hinzufügen prüfen, ob es ein Handwerks-Item oder Nicht-Dungeon-Item ist
        local sources = ns.GetItemDropSources and ns.GetItemDropSources(itemID) or {}
        if #sources == 0 then
            local crafters = ns.GetCraftersForItemID and ns.GetCraftersForItemID(itemID) or {}
            if #crafters > 0 then
                local parts = {}
                for _, c in ipairs(crafters) do
                    table.insert(parts, string.format("%s (%s)", ns.GetColoredPlayerName(c.name), ns.GetLocalizedProfName(c.profession)))
                end
                print(string.format(L["MSG_WL_CRAFTABLE_HINT"] or "|cFFFFFF00[BoisCraft]|r %s kann hergestellt werden von: %s!", displayLink, table.concat(parts, ", ")))
                return
            end
            -- Hinweis ausgeben, falls keine Dungeon-Quelle in AtlasLoot gefunden wurde, aber trotzdem zulassen
            if _G.AtlasLoot then
                print(string.format(L["MSG_WL_NOT_DUNGEON_DROP"] or "|cFFFF7777[BoisCraft]|r Hinweis: %s wurde in AtlasLoot keinem Boss zugeordnet.", displayLink))
            end
        end

        -- Neu hinzufügen (Soll: 1)
        myList[itemID] = {
            status = "WANTED",
            collected = 0,
            needed = 1,
            addedAt = time(),
        }
        if ns.SelectWishlistDungeonForItem then
            ns.SelectWishlistDungeonForItem(itemID)
        end
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        print(string.format(L["MSG_WL_ADDED"] or "|cFF00FF00[BoisCraft]|r %s (%dx) zur Wunschliste hinzugefügt!", displayLink, 1))
    else
        -- Bereits auf der Liste: Prüfen, ob 2x benötigt (z.B. Ringe / 1H-Waffen) und nicht Unique
        local needed = tonumber(entry.needed) or 1
        if needed < 2 and not isUnique then
            entry.needed = 2
            entry.status = "WANTED"
            if ns.SelectWishlistDungeonForItem then
                ns.SelectWishlistDungeonForItem(itemID)
            end
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            print(string.format(L["MSG_WL_ADDED"] or "|cFF00FF00[BoisCraft]|r %s (%dx) zur Wunschliste hinzugefügt!", displayLink, 2))
        else
            -- Ganz von der Liste entfernen
            myList[itemID] = nil
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
            print(string.format(L["MSG_WL_REMOVED"] or "|cFFFF7777[BoisCraft]|r %s von der Wunschliste entfernt.", displayLink))
        end
    end

    -- Mit Gruppe synchronisieren & UI aktualisieren
    if ns.BroadcastMyWishlist then
        ns.BroadcastMyWishlist()
    end
    if ns.UpdateDungeonsView then
        ns.UpdateDungeonsView()
    end
end

-- ============================================================================
-- 2. Globale Hooks für Chat, Taschen, Inventar & Tooltip-Fallback
-- ============================================================================

local function ExtractItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- A. Standard-Blizzard-Hook für modifizierte Item-Klicks
hooksecurefunc("HandleModifiedItemClick", function(link)
    if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        local itemID = ExtractItemIDFromLink(link)
        if itemID then
            ns.ToggleWishlistItem(itemID)
        end
    end
end)

-- B. Chat-Links (SetItemRef)
hooksecurefunc("SetItemRef", function(link, text, button)
    if button == "LeftButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        local itemID = ExtractItemIDFromLink(link)
        if itemID then
            ns.ToggleWishlistItem(itemID)
        end
    end
end)

-- C. Direkter Container-/Taschen-Hook (da Alt+Klick in manchen Classic-Clients keinen ModifiedClick auslöst)
if ContainerFrameItemButton_OnModifiedClick then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
            local bag = self:GetParent():GetID()
            local slot = self:GetID()
            local link = nil
            if C_Container and C_Container.GetContainerItemLink then
                link = C_Container.GetContainerItemLink(bag, slot)
            elseif GetContainerItemLink then
                link = GetContainerItemLink(bag, slot)
            end
            local itemID = ExtractItemIDFromLink(link)
            if itemID then
                ns.ToggleWishlistItem(itemID)
            end
        end
    end)
end

-- D. Universeller Alt+Linksklick-Detektor über den aktiven GameTooltip
-- (Greift zuverlässig in Taschen, Bank, Handelsfenster, Charakterfenster und AtlasLoot!)
local altClickListener = CreateFrame("Frame")
altClickListener:RegisterEvent("MODIFIER_STATE_CHANGED")

-- Wir prüfen Mausklicks über WorldFrame/UIParent, wenn ein Item-Tooltip offen ist
local function CheckTooltipAltClick(button)
    if button ~= "LeftButton" then return end
    if not (IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then return end

    if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then
        local _, link = GameTooltip:GetItem()
        local itemID = ExtractItemIDFromLink(link)
        if itemID then
            ns.ToggleWishlistItem(itemID)
        end
    end
end

-- Hook auf Global Mouse Down, damit jedes UI-Element (auch Custom-Frames wie AtlasLoot/Bagnon) abgedeckt ist
local mouseCatcher = CreateFrame("Frame")
mouseCatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
mouseCatcher:SetScript("OnEvent", function(self, event, button)
    CheckTooltipAltClick(button)
end)

-- ============================================================================
-- 3. Tooltip-Integration (Wunschlisten-Status im Mouseover)
-- ============================================================================

local function AddWishlistTooltipHint(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if not link then return end

    local itemID = ExtractItemIDFromLink(link)
    if not itemID then return end

    -- Eigener Status (aktueller Charakter)
    local myList, myName = nil, (ns.GetFullPlayerName and ns.GetFullPlayerName("player")) or UnitName("player") or ""
    if ns.GetMyCharWishlist then
        myList, myName = ns.GetMyCharWishlist()
    elseif BoisCraftWishlist and BoisCraftWishlist.chars then
        myList = BoisCraftWishlist.chars[myName]
    end
    local entry = myList and myList[itemID]
    if entry and entry.status == "WANTED" then
        tooltip:AddLine(string.format(L["TT_ON_WISHLIST_YOU"] or "|cFF00FF00[BoisCraft] Auf deiner Wunschliste (%d/%d)|r", entry.collected or 0, entry.needed or 1), 0, 1, 0, true)
    end

    -- Status eigener Twinks & Freunde
    local neededByOthers = {}
    local seenNames = {}
    if BoisCraftWishlist and BoisCraftWishlist.chars then
        for charName, cList in pairs(BoisCraftWishlist.chars) do
            if charName ~= myName and type(cList) == "table" and cList[itemID] and cList[itemID].status == "WANTED" then
                seenNames[charName] = true
                table.insert(neededByOthers, ns.GetColoredPlayerName(charName))
            end
        end
    end
    if BoisCraftWishlist and BoisCraftWishlist.friends then
        for friendName, fList in pairs(BoisCraftWishlist.friends) do
            if friendName ~= myName and not seenNames[friendName] and type(fList) == "table" and fList[itemID] and fList[itemID].status == "WANTED" then
                seenNames[friendName] = true
                table.insert(neededByOthers, ns.GetColoredPlayerName(friendName))
            end
        end
    end
    if #neededByOthers > 0 then
        tooltip:AddLine(string.format(L["TT_ON_WISHLIST_FRIENDS"] or "|cFFFFD100[BoisCraft] Benötigt von:|r %s", table.concat(neededByOthers, ", ")), 1, 0.82, 0, true)
    end

    if entry and entry.status == "WANTED" then
        tooltip:AddLine(L["TT_ALT_CLICK_REMOVE"] or "|cFF888888Alt+Linksklick: Wunschliste anpassen/entfernen|r", 0.7, 0.7, 0.7, true)
    else
        tooltip:AddLine(L["TT_ALT_CLICK_ADD"] or "|cFF888888Alt+Linksklick: Auf BoisCraft-Wunschliste setzen|r", 0.7, 0.7, 0.7, true)
    end
    tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddWishlistTooltipHint)
else
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", AddWishlistTooltipHint)
    end
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        ItemRefTooltip:HookScript("OnTooltipSetItem", AddWishlistTooltipHint)
    end
end