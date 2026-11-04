local addonName, ns = ...
local L = ns.L

-- Gespeicherte Variablen beim Laden absichern
BoisCraftSettings = BoisCraftSettings or {}
BoisCraftSettings.language = BoisCraftSettings.language or "AUTO"

-- Die Auswahl wird als Community-ID gespeichert, nie als Chatkanal.
local function GetLanguageDisplayText(code)
    if not code or code == "AUTO" then
        return L["LANG_AUTO"]
    end
    if ns.Locales and ns.Locales[code] and ns.Locales[code]["LANG_SELF_NAME"] then
        return ns.Locales[code]["LANG_SELF_NAME"]
    end
    if code == "deDE" then
        return L["LANG_DE"]
    elseif code == "enUS" then
        return L["LANG_EN"]
    end
    return tostring(code)
end

function ns.SetAddonLanguage(langCode)
    if not langCode or not ns.Locales or not ns.Locales[langCode] then
        langCode = "AUTO"
    end

    local oldLang = BoisCraftSettings.language or "AUTO"
    BoisCraftSettings.language = langCode

    -- Alle offenen Fenster und Texte live im Spiel aktualisieren
    if ns.RefreshAllLocaleTexts then
        ns.RefreshAllLocaleTexts()
    end

    if oldLang ~= langCode then
        local label = GetLanguageDisplayText(langCode)
        print(string.format(L["MSG_LANG_CHANGED"], label))
    end
end

-- ============================================================================
-- 2. Optionen-Fenster Frame & UI-Elemente
-- ============================================================================

local OptionsFrame = CreateFrame("Frame", "BoisCraftOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
OptionsFrame:SetSize(440, 350)
OptionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
OptionsFrame:SetMovable(true)
OptionsFrame:EnableMouse(true)
OptionsFrame:RegisterForDrag("LeftButton")
OptionsFrame:SetScript("OnDragStart", OptionsFrame.StartMoving)
OptionsFrame:SetScript("OnDragStop", OptionsFrame.StopMovingOrSizing)
OptionsFrame:SetFrameStrata("DIALOG")
OptionsFrame:Hide()

-- Schließen mit der Escape-Taste ermöglichen
tinsert(UISpecialFrames, "BoisCraftOptionsFrame")

-- Fenstertitel
OptionsFrame.title = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
OptionsFrame.title:SetPoint("TOP", OptionsFrame, "TOP", 0, -5)

-- Abschnitt 1: Netzwerk & Synchronisation
local netHeader = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
netHeader:SetPoint("TOPLEFT", OptionsFrame, "TOPLEFT", 20, -38)

local descText = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
descText:SetPoint("TOPLEFT", netHeader, "BOTTOMLEFT", 0, -8)
descText:SetPoint("RIGHT", OptionsFrame, "RIGHT", -20, 0)
descText:SetJustifyH("LEFT")

local communityLabel = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
communityLabel:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -14)
communityLabel:SetText("WoW-Community für BoisCraft")

local CommunityDropdown = CreateFrame("Frame", "BoisCraftCommunityDropdown", OptionsFrame, "UIDropDownMenuTemplate")
CommunityDropdown:SetPoint("TOPLEFT", communityLabel, "BOTTOMLEFT", -16, -4)
if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(CommunityDropdown, 260) end
local selectedCommunityID

local communityInfo = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
communityInfo:SetPoint("TOPLEFT", CommunityDropdown, "BOTTOMLEFT", 16, -4)
communityInfo:SetPoint("RIGHT", OptionsFrame, "RIGHT", -20, 0)
communityInfo:SetJustifyH("LEFT")
communityInfo:SetText("Nur Mitglieder dieser Community werden synchronisiert.")

function ns.UpdateOptionsCommunityStatus()
    if not communityInfo then return end
    if not selectedCommunityID then
        communityInfo:SetText(L["COMMUNITY_NO_SELECTION"] or "|cFF888888Bitte oben eine WoW-Community auswählen.|r")
        return
    end
    local status, total, online, connected = ns.GetCommunitySyncStatus()
    if status == "NO_SELECTION" then
        communityInfo:SetText(L["COMMUNITY_NO_SELECTION"] or "|cFF888888Bitte oben eine WoW-Community auswählen.|r")
    elseif status == "MEMBERS_NOT_LOADED" or status == "NAMES_NOT_LOADED" or (total or 0) == 0 then
        communityInfo:SetText(L["COMMUNITY_NOT_LOADED_HINT"] or "|cFFFFAA00Mitgliederliste noch nicht geladen – bitte öffne einmal kurz das Community-Fenster.|r")
    else
        local fmt = L["COMMUNITY_STATUS_FMT"] or "Mitglieder: %d | Online: %d | Verbunden: %d"
        communityInfo:SetText(string.format(fmt, total or 0, online or 0, connected or 0))
    end
end

local function CommunityText(id)
    if not id then return "Bitte Community auswählen" end
    for _, community in ipairs(ns.GetAvailableSyncCommunities()) do
        if tonumber(community.id) == tonumber(id) then return community.name end
    end
    return "Community nicht verfügbar (" .. tostring(id) .. ")"
end

local function InitCommunityDropdown(self, level)
    if not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then return end
    local communities = ns.GetAvailableSyncCommunities()
    if #communities == 0 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Keine WoW-Community geladen"
        info.disabled = true
        UIDropDownMenu_AddButton(info, level)
        return
    end
    for _, community in ipairs(communities) do
        local info = UIDropDownMenu_CreateInfo()
        local id = community.id
        info.text = community.name
        info.value = id
        info.checked = tonumber(selectedCommunityID) == tonumber(id)
        info.func = function()
            selectedCommunityID = id
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(CommunityDropdown, community.name) end
            if ns.SetSyncCommunity then ns.SetSyncCommunity(id) end
            ns.UpdateOptionsCommunityStatus()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Abschnitt 2: Sprachauswahl (Unabhängig vom Client)
local langHeader = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
langHeader:SetPoint("TOPLEFT", communityInfo, "BOTTOMLEFT", 0, -18)
local langLabel = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
langLabel:SetPoint("TOPLEFT", langHeader, "BOTTOMLEFT", 0, -10)

local LangDropdown = CreateFrame("Frame", "BoisCraftLangDropdown", OptionsFrame, "UIDropDownMenuTemplate")
LangDropdown:SetPoint("TOPLEFT", langLabel, "BOTTOMLEFT", -16, -4)
if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(LangDropdown, 210)
end

local selectedLangCode = "AUTO"

local function InitLangDropdown(self, level)
    if not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then return end

    -- Dynamische Liste aller in Locales.lua vorhandenen Sprachen aufbauen
    local availableCodes = { "AUTO" }
    local sortedCustomCodes = {}

    if ns.Locales then
        for code, _ in pairs(ns.Locales) do
            table.insert(sortedCustomCodes, code)
        end
    end
    table.sort(sortedCustomCodes)

    for _, code in ipairs(sortedCustomCodes) do
        table.insert(availableCodes, code)
    end

    for _, code in ipairs(availableCodes) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = GetLanguageDisplayText(code)
        info.value = code
        info.checked = (selectedLangCode == code)
        info.func = function()
            selectedLangCode = code
            if UIDropDownMenu_SetText then
                UIDropDownMenu_SetText(LangDropdown, GetLanguageDisplayText(selectedLangCode))
            end
            -- Sprache direkt beim Auswählen live umschalten
            ns.SetAddonLanguage(selectedLangCode)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Speichern- und Schließen-Buttons
local SaveBtn = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
SaveBtn:SetSize(130, 24)
SaveBtn:SetPoint("BOTTOMLEFT", OptionsFrame, "BOTTOMLEFT", 20, 16)

local CloseBtn = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
CloseBtn:SetSize(100, 24)
CloseBtn:SetPoint("LEFT", SaveBtn, "RIGHT", 10, 0)

-- ============================================================================
-- 3. Lokalisierung des Optionen-Fensters & Event-Handler
-- ============================================================================

function ns.RefreshOptionsLocale()
    OptionsFrame.title:SetText(L["OPTIONS_TITLE"])
    netHeader:SetText(L["OPTIONS_NET_HEADER"])
    descText:SetText("Die ausgewählte WoW-Community bestimmt, mit wem BoisCraft Daten austauscht.\nDie Übertragung erfolgt direkt per Addon-Whisper (nicht über den Community-Chat).")
    communityLabel:SetText("WoW-Community auswählen:")
    langHeader:SetText(L["OPTIONS_LANG_HEADER"])
    langLabel:SetText(L["OPTIONS_LANG_LABEL"])
    SaveBtn:SetText(L["BTN_SAVE"])
    CloseBtn:SetText(L["BTN_CLOSE"])

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(CommunityDropdown, InitCommunityDropdown)
        UIDropDownMenu_Initialize(LangDropdown, InitLangDropdown)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(CommunityDropdown, CommunityText(selectedCommunityID))
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(LangDropdown, GetLanguageDisplayText(selectedLangCode))
    end
    ns.UpdateOptionsCommunityStatus()
end

CloseBtn:SetScript("OnClick", function()
    OptionsFrame:Hide()
end)

SaveBtn:SetScript("OnClick", function()
    if ns.SetSyncCommunity then ns.SetSyncCommunity(selectedCommunityID) end
    ns.SetAddonLanguage(selectedLangCode)
    OptionsFrame:Hide()
end)

OptionsFrame:SetScript("OnShow", function()
    BoisCraftSettings = BoisCraftSettings or {}
    selectedCommunityID = BoisCraftSettings.syncCommunityId
    selectedLangCode = BoisCraftSettings.language or "AUTO"
    if ns.DiscoverCommunityPeers then ns.DiscoverCommunityPeers(false) end
    ns.RefreshOptionsLocale()
end)

function ns.ToggleOptions()
    if OptionsFrame:IsShown() then
        OptionsFrame:Hide()
    else
        OptionsFrame:Show()
    end
end