---------------------------------------------------------------------------
-- BazBags - Categories settings page
--
-- Built on BazCore:CreateManagedListPage so the page is automatically
-- cohesive with the User Manual's visual chrome - same title bar,
-- gold-gradient list selection, auto-h1 detail title, rich content
-- blocks (paragraph, h3, note, divider) interleaved with form widgets
-- (input, range, execute).
--
-- Each category becomes a row on the left; selecting one shows its
-- editable detail (display name, order, pinned items, delete) on the
-- right. Default categories include an "auto-classifier" intro
-- paragraph so users understand what the category does for them
-- before they tinker with it.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

local PAGE_KEY = ADDON_NAME .. "-Categories"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Format an item ID as a display string. Tries GetItemInfo for a
-- proper name; falls back to the ID. Pins use the cache when warm,
-- so this gradually fills in over time.
local function ItemDisplayName(itemID)
    if not itemID then return "?" end
    if GetItemInfo then
        local name, link = GetItemInfo(itemID)
        if name then
            -- Prefer the colored link if available so quality colours come through.
            return link or name
        end
    end
    return "Item " .. itemID
end

-- Best-effort itemID extraction from either an item link or a raw
-- numeric/string ID. Lets the user shift-click an item link from
-- chat/tooltip into the input box and have it resolve correctly.
local function ParseItemID(text)
    if not text or text == "" then return nil end
    local id = tonumber(text)
    if id then return id end
    -- Item link pattern: |Hitem:12345:...
    local linkID = text:match("|Hitem:(%d+):")
    if linkID then return tonumber(linkID) end
    return nil
end

-- Refresh the bag panel + the settings page. Called after every CRUD
-- op so the user sees their change immediately in both surfaces.
local function RefreshAll()
    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
    BazCore:RefreshOptions(PAGE_KEY)
end

---------------------------------------------------------------------------
-- Per-category detail blocks
--
-- Returns an array of opt tables (content blocks + form widgets) in
-- display order. CreateManagedListPage handles converting this into
-- the keyed args table the renderer expects, and auto-prepends an h1
-- with the category name above whatever this returns.
---------------------------------------------------------------------------

-- One short paragraph per default category explaining what the
-- auto-classifier does for that key. Custom categories don't have
-- one - they only show items the user has pinned to them.
local AUTO_BLURB = {
    equipment   = "Auto-classifies items in the Weapons and Armor item classes.",
    consumables = "Auto-classifies items in the Consumables item class.",
    tradegoods  = "Auto-classifies Trade Goods, Recipes, Gems, and Item Enhancements.",
    questitems  = "Auto-classifies items in the Quest Items class.",
    junk        = "Auto-classifies items with quality Poor (grey).",
    other       = "Catch-all - anything no other default category claims lands here.",
}

local function BuildCategoryDetail(item)
    local key       = item.key
    local isDefault = item.isDefault and true or false

    local blocks = {}

    if AUTO_BLURB[key] then
        blocks[#blocks+1] = { type = "paragraph", text = AUTO_BLURB[key] }
    end

    blocks[#blocks+1] = {
        type  = "note",
        style = "info",
        text  = isDefault
            and "You can rename this category, reorder it (use the up/down arrows on the left list), or pin extra items below. The auto-classifier still uses the original key, so renaming doesn't break anything."
            or  "Custom category - only items you pin below will appear here.",
    }

    blocks[#blocks+1] = { type = "h3", name = "Identity" }

    blocks[#blocks+1] = {
        type = "input",
        name = "Display Name",
        desc = "Shown in the bag panel's category divider.",
        get  = function()
            local entry = addon.Categories.Get(key)
            return entry and entry.name or ""
        end,
        set  = function(_, val)
            if not val or val == "" then return end
            addon.Categories.Rename(key, val)
            RefreshAll()
        end,
    }

    blocks[#blocks+1] = {
        type = "toggle",
        name = "Hide from bag panel",
        desc = "When on, this category's divider and items don't appear in the bag panel. Items still occupy their real bag slots - Hide is a display preference, not a delete. Pin an item to a hidden category (via shift+right-click on the item) to keep it out of view.",
        get  = function()
            local entry = addon.Categories.Get(key)
            return entry and entry.hidden or false
        end,
        set  = function(_, val)
            addon.Categories.SetHidden(key, val)
            RefreshAll()
        end,
    }

    blocks[#blocks+1] = { type = "divider" }

    blocks[#blocks+1] = { type = "h3", name = "Pinned Items" }

    blocks[#blocks+1] = {
        type  = "note", style = "tip",
        text  = "Shift-click an item link in chat into the input box below to pin it here. Pinned items override the auto-classifier and always appear in this category.",
    }

    blocks[#blocks+1] = {
        type = "input",
        name = "Pin Item ID or Link",
        desc = "Type or paste an item ID, or shift-click an item link from chat / your bag / a tooltip.",
        get  = function() return "" end,
        set  = function(_, val)
            local id = ParseItemID(val)
            if not id then return end
            addon.Categories.AddItem(id, key)
            RefreshAll()
        end,
    }

    -- One execute button per pinned item - clicking unpins it.
    local pins = addon.Categories.GetPinnedItems(key)
    if #pins == 0 then
        blocks[#blocks+1] = {
            type = "paragraph",
            text = "|cff999999No items pinned yet.|r",
        }
    else
        for _, itemID in ipairs(pins) do
            blocks[#blocks+1] = {
                type  = "execute",
                name  = "Remove " .. ItemDisplayName(itemID),
                width = "full",
                func  = function()
                    addon.Categories.RemoveItem(itemID)
                    RefreshAll()
                end,
            }
        end
    end

    blocks[#blocks+1] = { type = "divider" }

    blocks[#blocks+1] = { type = "h3", name = "Delete" }

    blocks[#blocks+1] = {
        type  = "note",
        style = isDefault and "warning" or "danger",
        text  = isDefault
            and "Deleting a default category lets you reset it back later via Reset to Defaults at the top of the page. Items pinned to this category will fall back to the auto-classifier."
            or  "Permanently removes this custom category. Items pinned to it will fall back to their default category (or 'Other').",
    }

    blocks[#blocks+1] = {
        type = "execute",
        name = "Delete This Category",
        func = function()
            addon.Categories.Delete(key)
            RefreshAll()
        end,
    }

    return blocks
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

if BazCore.QueueForLogin then
    BazCore:QueueForLogin(function()
        if not BazCore.RegisterOptionsTable then return end

        local pageFunc = BazCore:CreateManagedListPage(ADDON_NAME, {
            pageName = "Categories",
            intro    = "Categories group items by what they are. Default categories auto-classify by item type; custom categories collect items you pin to them. Pick a category on the left to rename it, reorder it, pin items, or delete it.",

            getItems    = function()
                -- Decorate hidden categories with a grey "(hidden)"
                -- suffix in the list so the user can see at a glance
                -- which ones are excluded from the bag panel without
                -- having to click into each one.
                local cats = addon.Categories.GetAll()
                for _, c in ipairs(cats) do
                    if c.hidden then
                        c.name = (c.name or c.key) .. "  |cff888888(hidden)|r"
                    end
                end
                return cats
            end,
            buildDetail = BuildCategoryDetail,

            onCreate = function()
                addon.Categories.Create("New Category")
                RefreshAll()
            end,
            createButtonText = "Create New Category",

            onReset = function()
                -- Reset is destructive: presets are restored but any
                -- user-tweaked names / order changes are gone. Gate
                -- behind a confirm so an accidental click doesn't
                -- silently overwrite a polished setup.
                if BazCore.Confirm then
                    BazCore:Confirm({
                        title       = "Reset categories?",
                        body        = "Reset every category back to its default name and order? Your tweaks to category names and ordering are wiped. Custom (user-created) categories are preserved.",
                        acceptLabel = "Reset",
                        acceptStyle = "destructive",
                        onAccept    = function()
                            addon.Categories.ResetDefaults(false)
                            RefreshAll()
                        end,
                    })
                end
            end,
            resetButtonText = "Reset to Defaults",

            -- Up/down arrows on every row replace the old "Order" range
            -- slider in the detail pane. Click the arrow, the row jumps
            -- one slot, the bag panel re-renders. Top/bottom rows
            -- render their boundary arrow disabled automatically (the
            -- shared row renderer handles the greying based on whether
            -- we hand it a callback for that direction).
            onMoveUp = function(item)
                addon.Categories.MoveUp(item.key)
                RefreshAll()
            end,
            onMoveDown = function(item)
                addon.Categories.MoveDown(item.key)
                RefreshAll()
            end,
        })

        BazCore:RegisterOptionsTable(PAGE_KEY, pageFunc)
        BazCore:AddToSettings(PAGE_KEY, "Categories", ADDON_NAME)
    end)
end
