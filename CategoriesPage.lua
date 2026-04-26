---------------------------------------------------------------------------
-- BazBags — Categories settings page
--
-- A managed-list page that mirrors the User Manual's visual chrome:
-- gold-gradient selection rows on the left, rich-block content on the
-- right. Built entirely on BazCore's standard option-table pattern —
-- nested `type = "group"` args automatically route through
-- BuildListDetailPanel, which uses the shared selection highlight
-- and title bar from BazCore 050+.
--
-- The detail panel for each category interleaves rich content blocks
-- (h3, paragraph, note, divider) with form widgets (input, execute)
-- so the page reads like a User Manual page that happens to have
-- editable fields.
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

---------------------------------------------------------------------------
-- Per-category detail group
--
-- Each category becomes a `type = "group"` whose `args` render in the
-- detail panel when the category is selected in the list. Args mix
-- rich content blocks (paragraph, h3, note) with form widgets
-- (input, execute) so the read/edit experience matches the User
-- Manual's visual style.
---------------------------------------------------------------------------

local function BuildCategoryDetail(catEntry)
    local key       = catEntry.key
    local isDefault = catEntry.isDefault and true or false

    local args = {}
    local order = 1

    -- Read-only intro paragraph for default categories so the user
    -- understands what the auto-classifier does for this key. Custom
    -- categories don't have one — they start out with whatever the
    -- user pins to them.
    local autoBlurb = ({
        equipment   = "Auto-classifies items in the Weapons and Armor item classes.",
        consumables = "Auto-classifies items in the Consumables item class.",
        tradegoods  = "Auto-classifies Trade Goods, Recipes, Gems, and Item Enhancements.",
        questitems  = "Auto-classifies items in the Quest Items class.",
        junk        = "Auto-classifies items with quality Poor (grey).",
        other       = "Catch-all — anything no other default category claims lands here.",
    })[key]

    if autoBlurb then
        args["aboutPara"] = {
            order = order, type = "paragraph", text = autoBlurb,
        }
        order = order + 1
    end

    args["pinNote"] = {
        order = order, type = "note", style = "info",
        text = isDefault
            and "You can rename this category, change its order, or pin extra items below. The auto-classifier still uses the original key, so renaming doesn't break anything."
            or  "Custom category — only items you pin below will appear here.",
    }
    order = order + 1

    args["identityH"] = {
        order = order, type = "h3", name = "Identity",
    }
    order = order + 1

    args["nameInput"] = {
        order = order, type = "input",
        name  = "Display Name",
        desc  = "Shown in the bag panel's category divider.",
        get = function()
            local entry = addon.Categories.Get(key)
            return entry and entry.name or ""
        end,
        set = function(_, val)
            if not val or val == "" then return end
            addon.Categories.Rename(key, val)
            if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
            BazCore:RefreshOptions(PAGE_KEY)
        end,
    }
    order = order + 1

    args["orderInput"] = {
        order = order, type = "range",
        name  = "Order",
        desc  = "Lower numbers appear first. Default categories use 10/20/30/40/50/60; pick a value between two existing categories to slot in between them.",
        min   = 1, max = 200, step = 1,
        get   = function()
            local entry = addon.Categories.Get(key)
            return entry and entry.order or 100
        end,
        set   = function(_, val)
            addon.Categories.Reorder(key, val)
            if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
            BazCore:RefreshOptions(PAGE_KEY)
        end,
    }
    order = order + 1

    args["divider1"] = { order = order, type = "divider" }
    order = order + 1

    args["itemsH"] = {
        order = order, type = "h3", name = "Pinned Items",
    }
    order = order + 1

    args["itemsNote"] = {
        order = order, type = "note", style = "tip",
        text = "Shift-click an item link in chat into the input box below to pin it here. Pinned items override the auto-classifier and always appear in this category.",
    }
    order = order + 1

    -- Add-item input. On commit, resolves the text to an item ID
    -- (raw number or item link) and pins it.
    args["addItemInput"] = {
        order = order, type = "input",
        name  = "Pin Item ID or Link",
        desc  = "Type or paste an item ID, or shift-click an item link from chat / your bag / a tooltip.",
        get   = function() return "" end,
        set   = function(_, val)
            local id = ParseItemID(val)
            if not id then return end
            addon.Categories.AddItem(id, key)
            if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
            BazCore:RefreshOptions(PAGE_KEY)
        end,
    }
    order = order + 1

    -- One execute button per pinned item — clicking unpins it.
    local pins = addon.Categories.GetPinnedItems(key)
    if #pins == 0 then
        args["noPins"] = {
            order = order, type = "paragraph",
            text  = "|cff999999No items pinned yet.|r",
        }
        order = order + 1
    else
        for i, itemID in ipairs(pins) do
            args["pin_" .. itemID] = {
                order = order, type = "execute",
                name  = "Remove " .. ItemDisplayName(itemID),
                width = "full",
                func  = function()
                    addon.Categories.RemoveItem(itemID)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                    BazCore:RefreshOptions(PAGE_KEY)
                end,
            }
            order = order + 1
        end
    end

    args["divider2"] = { order = order, type = "divider" }
    order = order + 1

    args["deleteH"] = {
        order = order, type = "h3", name = "Delete",
    }
    order = order + 1

    args["deleteNote"] = {
        order = order, type = "note", style = isDefault and "warning" or "danger",
        text = isDefault
            and "Deleting a default category lets you reset it back later via Reset to Defaults at the top of the page. Items pinned to this category will fall back to the auto-classifier."
            or  "Permanently removes this custom category. Items pinned to it will fall back to their default category (or 'Other').",
    }
    order = order + 1

    args["deleteBtn"] = {
        order = order, type = "execute",
        name  = "Delete This Category",
        func  = function()
            addon.Categories.Delete(key)
            if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
            BazCore:RefreshOptions(PAGE_KEY)
        end,
    }
    order = order + 1

    return {
        order = catEntry.order or 100,
        type  = "group",
        name  = catEntry.name or key,
        args  = args,
    }
end

---------------------------------------------------------------------------
-- Page builder
---------------------------------------------------------------------------

local function GetCategoriesPage()
    local cats = addon.Categories.GetAll()

    local args = {
        intro = {
            order = -2, type = "lead",
            text  = "Categories group items by what they are. Default categories auto-classify by item type; custom categories collect items you pin to them. Pick a category on the left to rename it, reorder it, pin items, or delete it.",
        },
        createBtn = {
            order = 0, type = "execute",
            name  = "Create New Category",
            desc  = "Adds a fresh empty category to the end of the list. Custom categories don't auto-classify anything — they show whatever items you pin to them.",
            func  = function()
                addon.Categories.Create("New Category")
                if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                BazCore:RefreshOptions(PAGE_KEY)
            end,
        },
        resetBtn = {
            order = 1, type = "execute",
            name  = "Reset to Defaults",
            desc  = "Restores the default category names and order. Your custom categories and item pins are kept (use Wipe Customs in the future if a hard reset is added).",
            func  = function()
                addon.Categories.ResetDefaults(false)
                if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                BazCore:RefreshOptions(PAGE_KEY)
            end,
        },
    }

    -- One nested group per category — these become the list rows on
    -- the left. The selected one's args render in the detail panel.
    for _, cat in ipairs(cats) do
        args["cat_" .. cat.key] = BuildCategoryDetail(cat)
    end

    return {
        name = "Categories",
        type = "group",
        args = args,
    }
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

if BazCore.QueueForLogin then
    BazCore:QueueForLogin(function()
        if not BazCore.RegisterOptionsTable then return end
        BazCore:RegisterOptionsTable(PAGE_KEY, GetCategoriesPage)
        BazCore:AddToSettings(PAGE_KEY, "Categories", ADDON_NAME)
    end)
end
