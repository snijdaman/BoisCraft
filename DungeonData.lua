local addonName, ns = ...

BoisCraftDropCache = BoisCraftDropCache or {}

-- Cache-Versionierung: Löscht einmalig alte Einträge mit grünem Punkt/Levelbereich oder doppelten Modul-Keys
if BoisCraftDropCache.__version ~= 3 then
    BoisCraftDropCache = { __version = 3 }
end

-- Entfernt Farben, Icons (grüner Beta-Punkt) und Levelbereiche "(13 - 18)" aus Namen
function ns.CleanAtlasLootText(text)
    if type(text) ~= "string" then return "" end
    return text
        :gsub("|c%x%x%x%x%x%x%x%x", "") -- Farb-Startcodes entfernen
        :gsub("|r", "")                 -- Farb-Endcodes entfernen
        :gsub("|T.-|t", "")             -- Texturen/Icons (grüner Kreis) entfernen
        :gsub("%s*%b()", "")            -- Klammern inkl. Levelbereich "(13 - 18)" entfernen
        :gsub("^%s+", "")               -- Leerzeichen am Anfang trimmen
        :gsub("%s+$", "")               -- Leerzeichen am Ende trimmen
        :gsub("%s+", " ")               -- Doppelte Leerzeichen (wo das Icon war) glätten
end

-- Lädt die AtlasLootClassic-Datenmodule automatisch, falls noch nicht geschehen
local modulesLoaded = false
local function EnsureAtlasLootModulesLoaded()
    if modulesLoaded then return end
    modulesLoaded = true

    local loadFunc = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not loadFunc then return end

    local subModules = {
        "AtlasLoot_Forever",
        "AtlasLootClassic_DungeonsAndRaids",
        "AtlasLootClassic_Crafting",
        "AtlasLootClassic_Collections",
        "AtlasLootClassic_PvP",
        "AtlasLootClassic_Factions",
        "AtlasLootClassic_Data",
        "AtlasLoot_OriginalWoW",
        "AtlasLoot_BurningCrusade",
        "AtlasLoot_WrathoftheLichKing",
        "AtlasLoot_DungeonAndRaid",
        "AtlasLoot_Data",
    }
    for _, mod in ipairs(subModules) do
        pcall(loadFunc, mod)
    end
end

local function CheckLootList(list, itemID)
    if type(list) ~= "table" then return false end
    for _, entry in pairs(list) do
        if type(entry) == "number" and entry == itemID then
            return true
        elseif type(entry) == "table" then
            if tonumber(entry[2]) == itemID or tonumber(entry[1]) == itemID then
                return true
            end
            if tonumber(entry.itemID) == itemID or tonumber(entry.id) == itemID then
                return true
            end
        end
    end
    return false
end

function ns.GetItemDropSources(itemID)
    itemID = tonumber(itemID)
    if not itemID then return {} end

    if not BoisCraftDropCache or BoisCraftDropCache.__version ~= 3 then
        BoisCraftDropCache = { __version = 3 }
    end

    if BoisCraftDropCache[itemID] and type(BoisCraftDropCache[itemID].sources) == "table" and #BoisCraftDropCache[itemID].sources > 0 then
        return BoisCraftDropCache[itemID].sources
    end

    EnsureAtlasLootModulesLoaded()

    local sources = {}
    local seen = {}

    local function AddSource(dungeonKey, dungeonName, bossName)
        local cleanKey  = tostring(dungeonKey or dungeonName or "UNKNOWN")
        local cleanName = ns.CleanAtlasLootText(tostring(dungeonName or cleanKey))
        local cleanBoss = ns.CleanAtlasLootText(tostring(bossName or "Boss"))

        if cleanName == "" then cleanName = cleanKey end
        if cleanBoss == "" then cleanBoss = "Boss" end

        local uniqueID = cleanName:lower() .. "::" .. cleanBoss:lower()
        if not seen[uniqueID] then
            seen[uniqueID] = true
            table.insert(sources, {
                dungeonKey  = cleanName, -- Konsistenter Schlüssel über alle AtlasLoot-Module hinweg
                dungeon     = cleanName, -- Sauberer Anzeigename ohne Punkt & Level
                boss        = cleanBoss, -- Sauberer Bossname
            })
        end
    end

    if _G.AtlasLoot and _G.AtlasLoot.ItemDB and type(_G.AtlasLoot.ItemDB.Storage) == "table" then
        for addonModule, moduleTable in pairs(_G.AtlasLoot.ItemDB.Storage) do
            if type(moduleTable) == "table" then
                for dungeonKey, dungeonData in pairs(moduleTable) do
                    if type(dungeonData) == "table" and not tostring(dungeonKey):match("^__") and type(dungeonData.items) == "table" then
                        local dName = dungeonKey
                        if type(dungeonData.GetName) == "function" then
                            local ok, res = pcall(dungeonData.GetName, dungeonData)
                            if ok and type(res) == "string" and res ~= "" then
                                dName = res
                            end
                        elseif type(dungeonData.name) == "string" then
                            dName = dungeonData.name
                        end

                        for bossIdx, bossData in pairs(dungeonData.items) do
                            if type(bossData) == "table" then
                                local bName = "Boss #" .. tostring(bossIdx)
                                if type(dungeonData.GetNameForItemTable) == "function" then
                                    local ok, res = pcall(dungeonData.GetNameForItemTable, dungeonData, bossIdx)
                                    if ok and type(res) == "string" and res ~= "" then
                                        bName = res
                                    end
                                elseif type(bossData.name) == "string" then
                                    bName = bossData.name
                                end

                                local foundInBoss = false
                                if CheckLootList(bossData, itemID) then
                                    foundInBoss = true
                                else
                                    for k, diffList in pairs(bossData) do
                                        if type(k) == "number" and type(diffList) == "table" then
                                            if CheckLootList(diffList, itemID) then
                                                foundInBoss = true
                                                break
                                            end
                                        end
                                    end
                                end

                                if foundInBoss then
                                    AddSource(dungeonKey, dName, bName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #sources > 0 then
        BoisCraftDropCache[itemID] = { sources = sources }
    end

    return sources
end