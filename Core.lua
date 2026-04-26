---------------------------------------------------------------------------
-- BazBags — lightweight unified bag panel
--
-- Core registration: BazCore addon entry, slash commands, profiles,
-- minimap menu entry, options pages. The actual bag UI lives in Bag.lua.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"

local addon
addon = BazCore:RegisterAddon(ADDON_NAME, {
    title         = "BazBags",
    savedVariable = "BazBagsDB",
    profiles      = true,
    defaults = {
        -- Layout
        cols          = 12,    -- columns wide; 4..20 via the slider — 12 fits a typical bag in 2-3 rows
        hideEmpty     = true,  -- skip empty slots by default — most first-time users prefer the compact view

        -- Grouping mode:
        --   "bags"       (default) — Blizzard-style sections per bag/reagent
        --   "categories"           — group items by category (Equipment,
        --                            Consumables, etc.) regardless of bag
        bagMode = "bags",

        -- When bagMode == "categories", picks how categories render:
        --   "sections" — full-width header per category with its own grid
        --   "flow"     — items pack continuously, inline pill labels mark
        --                category boundaries (no wasted rows for tiny
        --                categories)
        --   "hybrid"   — section headers like "sections", but partial
        --                last rows pack the next category inline before
        --                starting a fresh header
        categoryLayout = "flow",

        -- Custom categories. Keys are auto-generated at creation time
        -- ("custom1", "custom2", ...). Values are { name, order }. Empty
        -- by default; the management UI lives in Settings → Categories
        -- (planned for v2 — storage exists already so v1 doesn't break
        -- the data shape).
        customCategories = {},

        -- Item-to-custom-category overrides. {[itemID] = categoryKey}.
        -- Wins over the auto-classifier in ClassifyItem so a user-
        -- pinned Iron Bar sits in their custom "Crafting" group rather
        -- than the built-in "tradegoods".
        itemCategories = {},

        -- Footer
        showMoney       = true,   -- gold/silver/copper row at the bottom
        showTokens      = true,   -- tracked-currency (green) row below the money
        goldOnly        = false,  -- hide silver + copper in the money display
        useDefaultTitle = false,  -- show "Combined Backpack" instead of "BazBags"

        -- Section collapse state. Per-section, persisted across
        -- sessions so the user's preference sticks. Built-in bag
        -- sections + every category key share this map.
        sectionCollapsed = {
            bags     = false,
            reagents = false,
        },
        -- Window position. nil = first-run default (set in Bag.lua).
        position = nil,
    },

    slash = { "/bbg", "/bazbags" },
    commands = {
        toggle = {
            desc = "Toggle the BazBags panel",
            handler = function()
                if addon.Bag and addon.Bag.Toggle then
                    addon.Bag:Toggle()
                end
            end,
        },
        sort = {
            desc = "Sort bag contents (calls Blizzard's C_Container.SortBags)",
            handler = function()
                if C_Container and C_Container.SortBags then
                    C_Container.SortBags()
                end
            end,
        },
    },
    -- Bare slash with no subcommand toggles the panel — most common
    -- intent and matches how addons like Bagnon/Baganator behave.
    defaultHandler = function()
        if addon.Bag and addon.Bag.Toggle then
            addon.Bag:Toggle()
        end
    end,

    minimap = {
        label = "BazBags",
        icon  = 5160585,  -- inv_misc_bag_horadricsatchel
        onClick = function()
            if addon.Bag and addon.Bag.Toggle then
                addon.Bag:Toggle()
            end
        end,
    },
})

---------------------------------------------------------------------------
-- Options pages
---------------------------------------------------------------------------

local function GetLandingPage()
    return BazCore:CreateLandingPage("BazBags", {
        subtitle    = "Unified bag panel",
        description = "A lightweight combined bag panel that merges " ..
            "all bags into one window with collapsible sections per " ..
            "bag type. The reagent bag lives in the same panel as the " ..
            "main bags — fold it away when you don't need it instead " ..
            "of juggling a separate window.",
        features = "Single combined panel for bags + reagent bag. " ..
            "Collapsible sections per bag type, state persisted. " ..
            "Native item button template (cooldown sweep, quality " ..
            "border, drag/drop, click-to-use all work as Blizzard " ..
            "intends). Sort + free-slot indicator. Minimap entry " ..
            "and slash-command toggle.",
        guide = {
            { "/bbg",        "Toggle the panel" },
            { "Click a section header", "Fold or expand that bag type" },
            { "Drag the title bar",     "Move the panel" },
            { "Sort button",            "Calls Blizzard's bag sort" },
        },
    })
end

---------------------------------------------------------------------------
-- Settings page — landing page sub-category
---------------------------------------------------------------------------

local function GetSettingsPage()
    return {
        name = "Settings",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type  = "lead",
                text  = "Configure how the bag panel renders. Changes apply live — open the panel with /bbg to see them.",
            },

            layoutHeader = {
                order = 1,
                type  = "header",
                name  = "Layout",
            },
            cols = {
                order = 2,
                type  = "range",
                name  = "Columns",
                desc  = "How many slots wide the panel should be. The window resizes around this; rows are added or removed automatically.",
                min   = 4,
                max   = 20,
                step  = 1,
                get   = function() return addon:GetSetting("cols") or 8 end,
                set   = function(_, val)
                    addon:SetSetting("cols", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            hideEmpty = {
                order = 3,
                type  = "toggle",
                name  = "Hide Empty Slots",
                desc  = "Skip empty slots when rendering — shows only slots with items. Compact view; the panel shrinks vertically when many slots are empty.",
                get   = function() return addon:GetSetting("hideEmpty") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("hideEmpty", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
                disabled = function() return addon:GetSetting("bagMode") == "categories" end,
            },

            groupingHeader = {
                order = 5,
                type  = "header",
                name  = "Grouping",
            },
            bagMode = {
                order = 6,
                type  = "select",
                name  = "Mode",
                desc  = "Bags shows one collapsible section per equipped bag (the default Blizzard layout). Categories regroups items by what they are — Equipment, Consumables, Trade Goods, Quest Items, Junk, Other — regardless of which bag holds them.",
                values = {
                    bags       = "Bags (per-bag sections)",
                    categories = "Categories (group by item type)",
                },
                get = function() return addon:GetSetting("bagMode") or "bags" end,
                set = function(_, val)
                    addon:SetSetting("bagMode", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                    BazCore:RefreshOptions("BazBags-Settings")
                end,
            },
            categoryLayout = {
                order = 7,
                type  = "select",
                name  = "Category Layout",
                desc  = "How categories arrange themselves. Sections is the most familiar (header + grid per category). Flow packs items continuously with inline pill labels — best for small categories. Hybrid uses sections, but tiny categories pack inline onto a previous section's partial last row.",
                values = {
                    sections = "Sections (header + grid per category)",
                    flow     = "Flow (continuous, inline labels)",
                    hybrid   = "Hybrid (sections + last-row packing)",
                },
                get = function() return addon:GetSetting("categoryLayout") or "flow" end,
                set = function(_, val)
                    addon:SetSetting("categoryLayout", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
                disabled = function() return addon:GetSetting("bagMode") ~= "categories" end,
            },

            titleHeader = {
                order = 8,
                type  = "header",
                name  = "Title",
            },
            useDefaultTitle = {
                order = 9,
                type  = "toggle",
                name  = "Use Default Title",
                desc  = "Show \"Combined Backpack\" (Blizzard's default title) instead of \"BazBags\" in the panel's title bar.",
                get   = function() return addon:GetSetting("useDefaultTitle") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("useDefaultTitle", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },

            footerHeader = {
                order = 10,
                type  = "header",
                name  = "Footer",
            },
            showMoney = {
                order = 11,
                type  = "toggle",
                name  = "Show Money",
                desc  = "Show your gold / silver / copper at the bottom of the panel.",
                get   = function() return addon:GetSetting("showMoney") ~= false end,
                set   = function(_, val)
                    addon:SetSetting("showMoney", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            showTokens = {
                order = 12,
                type  = "toggle",
                name  = "Show Currency Tracker",
                desc  = "Show the tracked-currency row (green box) below the money. The list of currencies is whatever you've marked as \"Show on Backpack\" in Blizzard's Currency UI.",
                get   = function() return addon:GetSetting("showTokens") ~= false end,
                set   = function(_, val)
                    addon:SetSetting("showTokens", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            goldOnly = {
                order = 13,
                type  = "toggle",
                name  = "Gold Only",
                desc  = "Show only your gold count in the money row; hide silver and copper. Useful at high gold totals where the silver/copper digits add visual noise.",
                get   = function() return addon:GetSetting("goldOnly") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("goldOnly", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
                disabled = function() return addon:GetSetting("showMoney") == false end,
            },
        },
    }
end

addon.config.onLoad = function(self)
    BazCore:RegisterOptionsTable(ADDON_NAME, GetLandingPage)
    BazCore:AddToSettings(ADDON_NAME, "BazBags")

    BazCore:RegisterOptionsTable(ADDON_NAME .. "-Settings", GetSettingsPage)
    BazCore:AddToSettings(ADDON_NAME .. "-Settings", "General Settings", ADDON_NAME)
end
