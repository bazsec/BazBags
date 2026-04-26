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

        -- Footer
        showMoney       = true,   -- gold/silver/copper row at the bottom
        showTokens      = true,   -- tracked-currency (green) row below the money
        goldOnly        = false,  -- hide silver + copper in the money display
        useDefaultTitle = false,  -- show "Combined Backpack" instead of "BazBags"

        -- Section collapse state. Per-section, persisted across
        -- sessions so the user's preference sticks.
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
