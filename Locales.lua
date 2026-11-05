local addonName, ns = ...

ns.Locales = {
    enUS = {},
    deDE = {},
}

-- ============================================================================
-- 1. Englische Sprachdaten (enUS)
-- ============================================================================

local en = ns.Locales.enUS
en["LANG_SELF_NAME"]            = "English"

-- Fenstertitel & Tabs
en["MAIN_TITLE"]                = "BoisCraft"
en["TAB_RECIPES"]               = "Recipes"
en["TAB_ORDERS"]                = "Orders (%d)"
en["TAB_SHOPPING"]              = "Shopping List"
en["TAB_DUNGEONS"]              = "Dungeons"

-- Berufe (Anzeigenamen)
en["PROF_ALCHEMY"]              = "Alchemy"
en["PROF_BLACKSMITHING"]        = "Blacksmithing"
en["PROF_ENCHANTING"]           = "Enchanting"
en["PROF_ENGINEERING"]          = "Engineering"
en["PROF_LEATHERWORKING"]       = "Leatherworking"
en["PROF_TAILORING"]            = "Tailoring"
en["PROF_COOKING"]              = "Cooking"
en["PROF_FIRSTAID"]             = "First Aid"

-- Tab 1: Katalog & Vorschau
en["SEARCH_PLACEHOLDER"]        = "Search recipes..."
en["FILTER_CRAFTABLE"]          = "Have Materials"
en["REQUIRED_MATERIALS"]        = "|cFFFFD100Required Materials:|r"
en["NO_REAGENTS_DATA"]          = "|cFF888888No reagent data available.|r"
en["NO_RECIPE_SELECTED"]        = "No Recipe"
en["NO_CRAFTER_AVAILABLE"]      = "No Crafter"
en["QTY_LABEL"]                 = "Qty:"
en["BTN_ORDER"]                 = "Order"
en["BTN_SYNC"]                  = "Sync"
en["TT_SYNC_BTN"]               = "Synchronize professions, orders, and wishlists with online community members."

-- Tab 2: Aufträge (UI_Orders.lua)
en["ORDERS_IN_HEADER"]          = "|cFFFFD100Incoming Orders (for this character):|r"
en["ORDERS_OUT_HEADER"]         = "|cFFFFD100Placed Orders (my requests):|r"
en["ORDERS_NONE_IN"]            = "|cFF888888No incoming crafting orders for this character.|r"
en["ORDERS_NONE_OUT"]           = "|cFF888888No open outgoing orders.|r"
en["ORDER_WANTS"]               = "%s wants: |cFFFFFFFF%dx %s|r"
en["ORDER_PROGRESS"]            = "|cFFAAAAAA(Crafted: %d/%d | Remaining: %d)|r"
en["BTN_CRAFT"]                 = "Craft"
en["BTN_CRAFT_AMOUNT"]          = "Craft (%d)"
en["BTN_SEND_ITEM"]             = "Mail Item"
en["BTN_DONE"]                  = "Done"
en["BTN_CANCEL"]                = "Cancel"
en["NO_ORDERS"]                 = "|cFF888888No open crafting orders.|r"
en["STATUS_OWN_ALT"]            = "|cFF00FF00[Own Alt]|r"
en["STATUS_ACKED"]              = "|cFF00FF00[Received by Crafter]|r"
en["STATUS_MAILED"]             = "|cFF00CCFF[Sent via Mail]|r"
en["STATUS_WAITING"]            = "|cFFFFFF00[Waiting / Queued]|r"
en["ORIGIN_MAIL"]               = "|cFF00CCFF[Mail]|r "
en["ORIGIN_ALT"]                = "|cFF00FF00[Alt]|r "

-- Tab 3: Einkaufsliste & Post (UI_Shopping.lua)
en["SHOPPING_HEADER"]           = "Send to %s via Mail:"
en["SHOPPING_ITEM_LINE"]        = "%s (Needed: %d | In Bags: |cFF%s%d|r)"
en["BANK_COUNT_SUFFIX"]         = " |cFF88CCFF[Bank: %d]|r"
en["BTN_MAIL_SEND"]             = "Attach"
en["BTN_MAIL_ORDER"]            = "Mail Order & Mats"
en["BTN_CLEAR_SHOPPING"]        = "Clear List"
en["NO_SHOPPING_ITEMS"]         = "|cFF888888Your shopping list is empty.|r"
en["MAIL_SUBJECT_ORDER"]        = "[BoisCraft] Crafting Order"
en["MAIL_SUBJECT_RETURN"]       = "[BoisCraft] Crafted Item"
en["TT_MAIL_ORDER_BTN"]         = "Fills recipient, subject, order codes (for offline friends) and attaches all available materials."

-- Tab 4: Dungeon-Planer & Beute-Log
en["DUNGEON_PRIORITY_HEADER"]   = "Dungeon Priority"
en["DUNGEON_WISHES_COUNT"]      = "%s (%d)"
en["DUNGEON_GROUP_WISHES"]      = "%s (%d Group Wishes)"
en["FILTER_ONLINE_GROUP"]       = "Current Group / Online Only"
en["BTN_LOOTED"]                = "Looted"
en["BTN_REMOVE"]                = "Remove"
en["BTN_SHARE_PARTY"]           = "Share in Party Chat"
en["BTN_OPEN_LOOTLOG"]          = "Loot Log >>"
en["BTN_CLOSE_LOOTLOG"]         = "<< Close"
en["LOOTLOG_TITLE"]             = "Group Loot History"
en["LOOTLOG_STATS_PREFIX"]      = "Looted: "
en["LOOTLOG_EMPTY"]             = "|cFF888888No loot recorded yet.|r"
en["ALSO_DROPS_FROM"]           = "|cFF888888Also drops from: %s|r"
en["ATLASLOOT_MISSING"]         = "|cFFFF5555AtlasLoot is required for Dungeon Loot tables.|r"
en["WL_FALLBACK_DUNGEON"]       = "Wishlist (General)"
en["WL_FALLBACK_BOSS"]          = "Unassigned / World Drops"
en["DUNGEON_EMPTY_HINT"]        = "|cFF888888No items on your Wishlist yet.\nUse |cFFFFD100Alt + Left-Click|cFF888888 on any item to add it!|r"

-- Optionen & Minimap
en["OPTIONS_TITLE"]             = "BoisCraft - Settings"
en["OPTIONS_NET_HEADER"]        = "Network & Synchronization"
en["OPTIONS_NET_DESC"]          = "Enter the secret chat channel name. All friends or guild members must use the same channel name to share recipes, orders, and wishlists."
en["OPTIONS_CHANNEL_LABEL"]     = "Chat Channel Name:"
en["OPTIONS_LANG_HEADER"]       = "Language / Display"
en["OPTIONS_LANG_LABEL"]        = "Addon Language:"
en["LANG_AUTO"]                 = "Client Default (Auto)"
en["LANG_DE"]                   = "Deutsch (German)"
en["LANG_EN"]                   = "English"
en["BTN_SAVE"]                  = "Save"
en["BTN_CLOSE"]                 = "Close"
en["COMMUNITY_NOT_LOADED_HINT"] = "|cFFFFAA00Member list not loaded yet – please open the WoW Communities window once.|r"
en["COMMUNITY_NO_SELECTION"]    = "|cFF888888Please select a WoW Community above.|r"
en["COMMUNITY_STATUS_FMT"]      = "Members: %d | Online: %d | Connected: %d"
en["MINIMAP_TT_LEFT"]           = "Left-Click: Open/Close BoisCraft"
en["MINIMAP_TT_RIGHT"]          = "Right-Click: Settings"
en["MINIMAP_TT_DRAG"]           = "Drag: Move button around Minimap"

-- Tooltips & Hotkeys
en["TT_CRAFTABLE_BY"]           = "|cFFFFD100[BoisCraft] Craftable by:|r %s"
en["TT_ON_WISHLIST_YOU"]        = "|cFF00FF00[BoisCraft] On your Wishlist (%d/%d)|r"
en["TT_ON_WISHLIST_FRIENDS"]    = "|cFFFFD100[BoisCraft] Needed by:|r %s"
en["TT_ALT_CLICK_ADD"]          = "|cFF888888Alt+Left-Click: Add to BoisCraft Wishlist|r"
en["TT_ALT_CLICK_REMOVE"]       = "|cFF888888Alt+Left-Click: Update/Remove from Wishlist|r"

-- Chat-Meldungen
en["MSG_RECIPES_SAVED"]         = "|cFF00FF00[BoisCraft]|r %d recipes saved for %s (%s)!"
en["MSG_CHANNEL_JOINING"]       = "|cFFFFFF00[BoisCraft]|r Joining channel '%s'... Please click Order again in 2 seconds!"
en["MSG_CHANNEL_CHANGED"]       = "|cFF00FF00[BoisCraft]|r Chat channel set to '|cFFFFD100%s|r'!"
en["MSG_LANG_CHANGED"]          = "|cFF00FF00[BoisCraft]|r Language set to '|cFFFFD100%s|r'!"
en["MSG_ORDER_SENT"]            = "|cFF00FF00[BoisCraft]|r Order for %dx %s sent to %s!"
en["MSG_ORDER_QUEUED"]          = "|cFFFFFF00[BoisCraft]|r Order for %dx %s queued for %s (sent on login or via mail)."
en["MSG_ORDER_RECEIVED"]        = "|cFF00FF00[BoisCraft]|r New crafting order received from %s!"
en["MSG_ORDER_ACKED"]           = "|cFF00FF00[BoisCraft]|r %s received your crafting order!"
en["MSG_ORDER_DONE"]            = "|cFF00FF00[BoisCraft]|r Order from %s marked as done."
en["MSG_ORDER_CANCELED"]        = "|cFFFFFF00[BoisCraft]|r Order for %s canceled and materials removed from Shopping List."
en["MSG_MAIL_ORDERS_IMPORTED"]  = "|cFF00FF00[BoisCraft]|r %d crafting order(s) imported from mailbox!"
en["MSG_CRAFT_COMPLETE"]        = "|cFF00FF00[BoisCraft]|r Order for %s completely crafted!"
en["MSG_CRAFT_PARTIAL"]         = "|cFFFFFF00[BoisCraft]|r Partial craft for %s (%d remaining)."
en["MSG_MISSING_REAGENTS"]      = "|cFFFF7777[BoisCraft]|r Missing reagents in your bags to craft this recipe!"
en["MSG_OPEN_MAILBOX_FIRST"]    = "|cFFFF7777[BoisCraft]|r Please open a mailbox first to attach items!"
en["MSG_ITEM_ATTACHED_RET"]     = "|cFF00FF00[BoisCraft]|r Attached %dx %s for %s. Click 'Send' in the mailbox!"
en["MSG_AUTO_DELIVERED"]        = "|cFF00FF00[BoisCraft]|r Delivered %dx %s to %s - order updated!"
en["MSG_SHOPPING_CLEARED"]      = "|cFFFFFF00[BoisCraft]|r Shopping list cleared."
en["MSG_SHOPPING_ATTACHED"]     = "|cFF00FF00[BoisCraft]|r Attached %dx %s for %s (including order code in mail body)!"
en["MSG_SHOPPING_NO_ITEMS"]     = "|cFFFF7777[BoisCraft]|r You do not have %s in your bags!"
en["MSG_SHOPPING_MAIL_SENT"]    = "|cFF00FF00[BoisCraft]|r Mail sent to %s - materials updated in Shopping List!"
en["MSG_INACTIVE_CLEANED"]      = "|cFFFFFF00[BoisCraft]|r Cleaned %d inactive crafter(s) (>60 days offline)."
en["MSG_WL_ADDED"]              = "|cFF00FF00[BoisCraft]|r Added %s (%dx) to your Wishlist!"
en["MSG_WL_REMOVED"]            = "|cFFFF7777[BoisCraft]|r Removed %s from your Wishlist."
en["MSG_WL_CRAFTABLE_HINT"]     = "|cFFFFFF00[BoisCraft]|r %s is not a dungeon drop, but can be crafted by: %s!"
en["MSG_WL_NOT_DUNGEON_DROP"]   = "|cFFFF7777[BoisCraft]|r %s is not a known dungeon/raid drop."
en["MSG_LOOT_CONGRATS"]         = "|cFF00FF00[BoisCraft]|r %s looted %s!"
en["MSG_PARTY_SHARE_HEADER"]    = "[BoisCraft] Wishlist for %s:"
en["MSG_PARTY_SHARE_NONE"]      = "|cFFFF7777[BoisCraft]|r No active wishes for the selected dungeon."

-- ============================================================================
-- 2. Deutsche Sprachdaten (deDE)
-- ============================================================================

local de = ns.Locales.deDE
de["LANG_SELF_NAME"]            = "Deutsch"

-- Fenstertitel & Tabs
de["MAIN_TITLE"]                = "BoisCraft"
de["TAB_RECIPES"]               = "Rezepte"
de["TAB_ORDERS"]                = "Aufträge (%d)"
de["TAB_SHOPPING"]              = "Einkaufsliste"
de["TAB_DUNGEONS"]              = "Dungeons"

-- Berufe (Anzeigenamen)
de["PROF_ALCHEMY"]              = "Alchimie"
de["PROF_BLACKSMITHING"]        = "Schmiedekunst"
de["PROF_ENCHANTING"]           = "Verzauberkunst"
de["PROF_ENGINEERING"]          = "Ingenieurskunst"
de["PROF_LEATHERWORKING"]       = "Lederverarbeitung"
de["PROF_TAILORING"]            = "Schneiderei"
de["PROF_COOKING"]              = "Kochkunst"
de["PROF_FIRSTAID"]             = "Erste Hilfe"

-- Tab 1: Katalog & Vorschau
de["SEARCH_PLACEHOLDER"]        = "Rezepte suchen..."
de["FILTER_CRAFTABLE"]          = "Mats vorhanden"
de["REQUIRED_MATERIALS"]        = "|cFFFFD100Benötigte Materialien:|r"
de["NO_REAGENTS_DATA"]          = "|cFF888888Keine Reagenzien-Daten verfügbar.|r"
de["NO_RECIPE_SELECTED"]        = "Kein Rezept"
de["NO_CRAFTER_AVAILABLE"]      = "Kein Crafter"
de["QTY_LABEL"]                 = "Menge:"
de["BTN_ORDER"]                 = "Bestellen"
de["BTN_SYNC"]                  = "Sync"
de["TT_SYNC_BTN"]               = "Synchronisiert Berufe, Aufträge und Wunschlisten mit den online erkannten Community-Mitgliedern."

-- Tab 2: Aufträge (UI_Orders.lua)
de["ORDERS_IN_HEADER"]          = "|cFFFFD100Eingegangene Aufträge (für diesen Charakter):|r"
de["ORDERS_OUT_HEADER"]         = "|cFFFFD100Erteilte Aufträge (meine Bestellungen):|r"
de["ORDERS_NONE_IN"]            = "|cFF888888Keine eingegangenen Aufträge für diesen Charakter vorhanden.|r"
de["ORDERS_NONE_OUT"]           = "|cFF888888Keine offenen erteilten Aufträge vorhanden.|r"
de["ORDER_WANTS"]               = "%s möchte: |cFFFFFFFF%dx %s|r"
de["ORDER_PROGRESS"]            = "|cFFAAAAAA(Hergestellt: %d/%d | Offen: %d)|r"
de["BTN_CRAFT"]                 = "Herstellen"
de["BTN_CRAFT_AMOUNT"]          = "Herstellen (%d)"
de["BTN_SEND_ITEM"]             = "Per Post senden"
de["BTN_DONE"]                  = "Erledigt"
de["BTN_CANCEL"]                = "Abbrechen"
de["NO_ORDERS"]                 = "|cFF888888Keine offenen Handwerksaufträge.|r"
de["STATUS_OWN_ALT"]            = "|cFF00FF00[Eigener Twink]|r"
de["STATUS_ACKED"]              = "|cFF00FF00[Vom Crafter empfangen]|r"
de["STATUS_MAILED"]             = "|cFF00CCFF[Per Post gesendet]|r"
de["STATUS_WAITING"]            = "|cFFFFFF00[Wartend / Gesendet]|r"
de["ORIGIN_MAIL"]               = "|cFF00CCFF[Post]|r "
de["ORIGIN_ALT"]                = "|cFF00FF00[Twink]|r "

-- Tab 3: Einkaufsliste & Post (UI_Shopping.lua)
de["SHOPPING_HEADER"]           = "An %s per Post senden:"
de["SHOPPING_ITEM_LINE"]        = "%s (Benötigt: %d | Inventar: |cFF%s%d|r)"
de["BANK_COUNT_SUFFIX"]         = " |cFF88CCFF[Bank: %d]|r"
de["BTN_MAIL_SEND"]             = "Versenden"
de["BTN_MAIL_ORDER"]            = "Auftrag & Mats senden"
de["BTN_CLEAR_SHOPPING"]        = "Liste leeren"
de["NO_SHOPPING_ITEMS"]         = "|cFF888888Deine Einkaufsliste ist leer.|r"
de["MAIL_SUBJECT_ORDER"]        = "[BoisCraft] Handwerksauftrag"
de["MAIL_SUBJECT_RETURN"]       = "[BoisCraft] Fertiges Item"
de["TT_MAIL_ORDER_BTN"]         = "Trägt Empfänger, Betreff sowie den Auftrags-Code (für Offline-Freunde) ein und hängt alle vorhandenen Materialien an."

-- Tab 4: Dungeon-Planer & Beute-Log
de["DUNGEON_PRIORITY_HEADER"]   = "Dungeon-Priorität"
de["DUNGEON_WISHES_COUNT"]      = "%s (%d)"
de["DUNGEON_GROUP_WISHES"]      = "%s (%d Gruppen-Wünsche)"
de["FILTER_ONLINE_GROUP"]       = "Nur aktuelle Gruppe / Online"
de["BTN_LOOTED"]                = "Erhalten"
de["BTN_REMOVE"]                = "Löschen"
de["BTN_SHARE_PARTY"]           = "Im Gruppenchat teilen"
de["BTN_OPEN_LOOTLOG"]          = "Beute-Log >>"
de["BTN_CLOSE_LOOTLOG"]         = "<< Schließen"
de["LOOTLOG_TITLE"]             = "Gruppen-Beutehistorie"
de["LOOTLOG_STATS_PREFIX"]      = "Erbeutet: "
de["LOOTLOG_EMPTY"]             = "|cFF888888Noch keine Beute erfasst.|r"
de["ALSO_DROPS_FROM"]           = "|cFF888888Droppt auch bei: %s|r"
de["ATLASLOOT_MISSING"]         = "|cFFFF5555AtlasLoot wird für Dungeon-Beutelisten benötigt.|r"
de["WL_FALLBACK_DUNGEON"]       = "Wunschliste (Allgemein)"
de["WL_FALLBACK_BOSS"]          = "Ohne Zuordnung / Weltdrops"
de["DUNGEON_EMPTY_HINT"]        = "|cFF888888Noch keine Items auf der Wunschliste.\nNutze |cFFFFD100Alt + Linksklick|cFF888888 auf ein beliebiges Item, um es hinzuzufügen!|r"

-- Optionen & Minimap
de["OPTIONS_TITLE"]             = "BoisCraft - Einstellungen"
de["OPTIONS_NET_HEADER"]        = "Netzwerk & Synchronisation"
de["OPTIONS_NET_DESC"]          = "Trage hier den Namen des geheimen Chat-Kanals ein. Alle Freunde oder Gildenmitglieder müssen denselben Kanalnamen verwenden, um Rezepte, Aufträge und Wunschlisten auszutauschen."
de["OPTIONS_CHANNEL_LABEL"]     = "Chat-Kanalname:"
de["OPTIONS_LANG_HEADER"]       = "Sprache & Anzeige"
de["OPTIONS_LANG_LABEL"]        = "Addon-Sprache:"
de["LANG_AUTO"]                 = "Client-Standard (Automatisch)"
de["LANG_DE"]                   = "Deutsch"
de["LANG_EN"]                   = "English (Englisch)"
de["BTN_SAVE"]                  = "Speichern"
de["BTN_CLOSE"]                 = "Schließen"
de["COMMUNITY_NOT_LOADED_HINT"] = "|cFFFFAA00Mitgliederliste noch nicht geladen – bitte öffne einmal kurz das Community-Fenster.|r"
de["COMMUNITY_NO_SELECTION"]    = "|cFF888888Bitte oben eine WoW-Community auswählen.|r"
de["COMMUNITY_STATUS_FMT"]      = "Mitglieder: %d | Online: %d | Verbunden: %d"
de["MINIMAP_TT_LEFT"]           = "Linksklick: BoisCraft öffnen/schließen"
de["MINIMAP_TT_RIGHT"]          = "Rechtsklick: Einstellungen"
de["MINIMAP_TT_DRAG"]           = "Ziehen: Icon um die Minimap bewegen"

-- Tooltips & Hotkeys
de["TT_CRAFTABLE_BY"]           = "|cFFFFD100[BoisCraft] Herstellbar von:|r %s"
de["TT_ON_WISHLIST_YOU"]        = "|cFF00FF00[BoisCraft] Auf deiner Wunschliste (%d/%d)|r"
de["TT_ON_WISHLIST_FRIENDS"]    = "|cFFFFD100[BoisCraft] Benötigt von:|r %s"
de["TT_ALT_CLICK_ADD"]          = "|cFF888888Alt+Linksklick: Auf BoisCraft-Wunschliste setzen|r"
de["TT_ALT_CLICK_REMOVE"]       = "|cFF888888Alt+Linksklick: Wunschliste anpassen/entfernen|r"

-- Chat-Meldungen
de["MSG_RECIPES_SAVED"]         = "|cFF00FF00[BoisCraft]|r %d Rezepte für %s (%s) gespeichert!"
de["MSG_CHANNEL_JOINING"]       = "|cFFFFFF00[BoisCraft]|r Trete Kanal '%s' bei... Bitte in 2 Sekunden erneut klicken!"
de["MSG_CHANNEL_CHANGED"]       = "|cFF00FF00[BoisCraft]|r Chat-Kanal auf '|cFFFFD100%s|r' umgestellt!"
de["MSG_LANG_CHANGED"]          = "|cFF00FF00[BoisCraft]|r Sprache auf '|cFFFFD100%s|r' umgestellt!"
de["MSG_ORDER_SENT"]            = "|cFF00FF00[BoisCraft]|r Bestellung für %dx %s an %s gesendet!"
de["MSG_ORDER_QUEUED"]          = "|cFFFFFF00[BoisCraft]|r Auftrag für %dx %s an %s vorgemerkt (wird bei Login oder per Post übertragen)."
de["MSG_ORDER_RECEIVED"]        = "|cFF00FF00[BoisCraft]|r Neuer Handwerksauftrag von %s erhalten!"
de["MSG_ORDER_ACKED"]           = "|cFF00FF00[BoisCraft]|r %s hat deinen Auftrag empfangen!"
de["MSG_ORDER_DONE"]            = "|cFF00FF00[BoisCraft]|r Auftrag von %s als erledigt markiert."
de["MSG_ORDER_CANCELED"]        = "|cFFFFFF00[BoisCraft]|r Auftrag bei %s abgebrochen und Materialien aus Einkaufsliste entfernt."
de["MSG_MAIL_ORDERS_IMPORTED"]  = "|cFF00FF00[BoisCraft]|r %d Handwerksauftrag/-aufträge aus dem Briefkasten importiert!"
de["MSG_CRAFT_COMPLETE"]        = "|cFF00FF00[BoisCraft]|r Auftrag für %s vollständig hergestellt!"
de["MSG_CRAFT_PARTIAL"]         = "|cFFFFFF00[BoisCraft]|r Teil-Herstellung für %s (%d verbleibend)."
de["MSG_MISSING_REAGENTS"]      = "|cFFFF7777[BoisCraft]|r Es fehlen noch Materialien in deinen Taschen!"
de["MSG_OPEN_MAILBOX_FIRST"]    = "|cFFFF7777[BoisCraft]|r Bitte öffne zuerst einen Briefkasten!"
de["MSG_ITEM_ATTACHED_RET"]     = "|cFF00FF00[BoisCraft]|r %dx %s für %s in den Brief gelegt. Klicke im Postfenster auf 'Senden'!"
de["MSG_AUTO_DELIVERED"]        = "|cFF00FF00[BoisCraft]|r %dx %s an %s übergeben - Auftrag aktualisiert!"
de["MSG_SHOPPING_CLEARED"]      = "|cFFFFFF00[BoisCraft]|r Einkaufsliste wurde geleert."
de["MSG_SHOPPING_ATTACHED"]     = "|cFF00FF00[BoisCraft]|r %dx %s für %s in den Brief gelegt (inkl. Auftrags-Code im Brieftext)!"
de["MSG_SHOPPING_NO_ITEMS"]     = "|cFFFF7777[BoisCraft]|r Du hast kein %s in deinen Taschen!"
de["MSG_SHOPPING_MAIL_SENT"]    = "|cFF00FF00[BoisCraft]|r Post an %s verschickt - Materialien in der Einkaufsliste abgeglichen!"
de["MSG_INACTIVE_CLEANED"]      = "|cFFFFFF00[BoisCraft]|r %d inaktive(r) Crafter (>60 Tage offline) bereinigt."
de["MSG_WL_ADDED"]              = "|cFF00FF00[BoisCraft]|r %s (%dx) zur Wunschliste hinzugefügt!"
de["MSG_WL_REMOVED"]            = "|cFFFF7777[BoisCraft]|r %s von der Wunschliste entfernt."
de["MSG_WL_CRAFTABLE_HINT"]     = "|cFFFFFF00[BoisCraft]|r %s ist kein Dungeon-Drop, kann aber hergestellt werden von: %s!"
de["MSG_WL_NOT_DUNGEON_DROP"]   = "|cFFFF7777[BoisCraft]|r %s ist kein bekannter Dungeon-/Raid-Drop."
de["MSG_LOOT_CONGRATS"]         = "|cFF00FF00[BoisCraft]|r %s hat %s erhalten!"
de["MSG_PARTY_SHARE_HEADER"]    = "[BoisCraft] Wunschliste für %s:"
de["MSG_PARTY_SHARE_NONE"]      = "|cFFFF7777[BoisCraft]|r Keine aktiven Wünsche für den ausgewählten Dungeon."

-- ============================================================================
-- 3. Dynamische Sprach-Auflösung (Generisch für alle Sprachen in ns.Locales)
-- ============================================================================

function ns.GetActiveLocale()
    local pref = BoisCraftSettings and BoisCraftSettings.language
    if pref and ns.Locales[pref] then
        return pref
    end

    local clientLoc = GetLocale and GetLocale() or "enUS"
    if ns.Locales[clientLoc] then
        return clientLoc
    end

    return "enUS"
end

-- Proxy-Tabelle: Sucht den Schlüssel live in der aktiven Sprache aus Locales.lua
ns.L = setmetatable({}, {
    __index = function(_, key)
        local activeLoc = ns.GetActiveLocale()
        local activeDict = ns.Locales[activeLoc] or ns.Locales.enUS
        if activeDict[key] ~= nil then
            return activeDict[key]
        end
        if ns.Locales.enUS[key] ~= nil then
            return ns.Locales.enUS[key]
        end
        return tostring(key)
    end
})

function ns.RefreshAllLocaleTexts()
    if ns.RefreshMainFrameLocale then ns.RefreshMainFrameLocale() end
    if ns.RefreshCatalogLocale then ns.RefreshCatalogLocale() end
    if ns.RenderProfessions then ns.RenderProfessions() end
    if ns.selectedProfession and ns.DisplayRecipesForProfession then
        ns.DisplayRecipesForProfession(ns.selectedProfession)
    end
    if ns.UpdateOrdersList then ns.UpdateOrdersList() end
    if ns.UpdateShoppingListView then ns.UpdateShoppingListView() end
    if ns.UpdateDungeonsView then ns.UpdateDungeonsView() end
    if ns.UpdateLootLogView then ns.UpdateLootLogView() end
    if ns.RefreshOptionsLocale then ns.RefreshOptionsLocale() end
end