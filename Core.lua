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

addon.config.onLoad = function(self)
    BazCore:RegisterOptionsTable(ADDON_NAME, GetLandingPage)
    BazCore:AddToSettings(ADDON_NAME, "BazBags")
end
