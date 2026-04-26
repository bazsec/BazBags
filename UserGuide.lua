---------------------------------------------------------------------------
-- BazBags User Manual
---------------------------------------------------------------------------

if not BazCore or not BazCore.RegisterUserGuide then return end

BazCore:RegisterUserGuide("BazBags", {
    title = "BazBags",
    intro = "A lightweight unified bag panel that merges all bags into one window with collapsible sections per bag type. The reagent bag lives in the same panel as your main bags.",
    pages = {
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazBags is a clone-and-iterate take on Blizzard's combined bag UI: instead of a separate window for the reagent bag, everything sits in one panel with collapsible sections you can fold individually." },
                { type = "h2", text = "Why BazBags?" },
                { type = "list", items = {
                    "One panel for all bags + reagent bag — fold sections you don't want visible",
                    "Native Blizzard item button template — cooldown sweep, quality border, drag/drop, click-to-use all behave exactly as you'd expect",
                    "Stays out of the way: no auto-categorization, no aggressive sort heuristics — Sort calls Blizzard's own logic",
                    "Position remembered between sessions",
                }},
                { type = "note", style = "tip", text = "Click any section header to fold or expand it. The collapse state is saved per profile, so your preference sticks across reloads." },
            },
        },
        {
            title = "Slash Commands",
            blocks = {
                { type = "table",
                  columns = { "Command", "Action" },
                  rows = {
                      { "/bbg",        "Toggle the panel" },
                      { "/bbg sort",   "Trigger Blizzard's bag sort" },
                      { "/bbg toggle", "Same as bare /bbg" },
                      { "/bazbags",    "Alias for /bbg" },
                  }},
            },
        },
        {
            title = "Sections",
            blocks = {
                { type = "h3", text = "Bags" },
                { type = "paragraph", text = "Your main backpack and any equipped bag containers (slots 1-4). All slots from these bags are merged into one grid." },
                { type = "h3", text = "Reagents" },
                { type = "paragraph", text = "Your reagent bag (the special profession-reagent slot Blizzard added in Dragonflight). Collapse this section if you don't actively craft and want a more compact panel." },
                { type = "note", style = "info", text = "Future versions may add per-equipped-bag sections, an Embellished section that highlights items with embellishments, and a search bar." },
            },
        },
    },
})
