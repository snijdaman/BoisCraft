local addonName, ns = ...

-- Pfad zum eigenen Logo
local ICON_PATH = "Interface/AddOns/BoisCraft/Assets/logo.tga"

-- Einstellungen initialisieren (Startposition 190°, um AtlasLoot bei 218° nicht zu verdecken)
BoisCraftSettings = BoisCraftSettings or {}
BoisCraftSettings.minimap = BoisCraftSettings.minimap or {
    minimapPos = 190,
    hide = false,
}

local function InitializeMinimapButton()
    local LibStub = _G.LibStub
    if not LibStub then return end

    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    local LDBIcon = LibStub:GetLibrary("LibDBIcon-1.0", true)

    if not LDB or not LDBIcon then return end

    -- Verhindern, dass das Objekt doppelt registriert wird
    if LDB:GetDataObjectByName("BoisCraft") then return end

local dataObject = LDB:NewDataObject("BoisCraft", {
        type = "launcher",
        text = "BoisCraft",
        icon = ICON_PATH,
        OnClick = function(self, button)
            if button == "LeftButton" and ns.MainFrame then
                if ns.MainFrame:IsShown() then
                    ns.MainFrame:Hide()
                else
                    ns.MainFrame:Show()
                end
            elseif button == "RightButton" and ns.ToggleOptions then
                ns.ToggleOptions()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("|cFF00FF00BoisCraft|r", 1, 1, 1)
            tooltip:AddLine("Linksklick: Handwerkskatalog öffnen/schließen", 1, 1, 1)
            tooltip:AddLine("Rechtsklick: Einstellungen (Chat-Kanal)", 1, 0.82, 0)
            tooltip:AddLine("Ziehen: Icon um die Minimap verschieben", 0.7, 0.7, 0.7)
        end,
    })

    LDBIcon:Register("BoisCraft", dataObject, BoisCraftSettings.minimap)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    InitializeMinimapButton()
end)