-- SPDX-License-Identifier: GPL-2.0-or-later
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

-- Forward-declare the Add Tag popup helpers so BuildCategoryDetail
-- can reference them. They're defined at file scope below.
local OpenAddTagPopup

local function BuildCategoryDetail(item)
    local key       = item.key
    local isDefault = item.isDefault and true or false

    local blocks = {}

    blocks[#blocks+1] = {
        type  = "note",
        style = "info",
        text  = isDefault
            and "You can rename this category, reorder it (use the up/down arrows on the left list), edit its match rules below, or pin extra items as overrides. The category's internal key is locked, so renaming doesn't break anything."
            or  "Custom category. Add match rules below to auto-include items, or shift+right-click items in the bag to pin them here manually.",
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

    -----------------------------------------------------------------
    -- Match Rules - the tag-based auto-classifier for this category.
    -- Items matching the rules (under the Match Mode) auto-fall into
    -- this category. Pinned Items below override the rules. Both
    -- default and custom categories use the same tag system - the
    -- defaults ship with predefined tags (e.g. Equipment ships with
    -- "Class is Weapon" + "Class is Armor", matchMode = "any") which
    -- the user can edit, extend, or reset back to factory.
    -----------------------------------------------------------------

    blocks[#blocks+1] = { type = "h3", name = "Match Rules" }

    blocks[#blocks+1] = {
        type  = "note", style = "info",
        text  = "Items that pass these rules drop into this category automatically. Pinned items (further down) override the rules.",
    }

    blocks[#blocks+1] = {
        type   = "select",
        name   = "Match Mode",
        desc   = "All - the item must match every rule (AND). Any - the item lands here as soon as one rule hits (OR).",
        values = {
            all = "All  (item must match every rule)",
            any = "Any  (item matches if it hits any rule)",
        },
        get = function() return addon.Categories.GetMatchMode(key) end,
        set = function(_, val)
            addon.Categories.SetMatchMode(key, val)
            RefreshAll()
        end,
    }

    -- Add Match Rule (and Reset on defaults) goes ABOVE the existing
    -- rule list. Separating the actions from the list visually so
    -- the "Add" button doesn't read as just-another-row in the
    -- Remove-rule stack below it. For default categories the two
    -- buttons pair side-by-side at half-width; for custom categories
    -- the Add button takes the full row alone.
    blocks[#blocks+1] = {
        type  = "execute",
        name  = "Add Match Rule",
        width = isDefault and "half" or "full",
        func  = function()
            if OpenAddTagPopup then OpenAddTagPopup(key) end
        end,
    }

    if isDefault then
        blocks[#blocks+1] = {
            type  = "execute",
            name  = "Reset Rules to Default",
            width = "half",
            confirm            = true,
            confirmTitle       = "Reset rules?",
            confirmText        = "Restore the factory match rules for this category, discarding your edits? Pinned items are not affected.",
            confirmStyle       = "destructive",
            confirmAcceptLabel = "Reset",
            func = function()
                addon.Categories.ResetTagsToDefault(key)
                RefreshAll()
            end,
        }
    end

    -- Header + thin spacer rule between the actions above and the
    -- Remove-rule list below. The "Current Rules" h4 doubles as the
    -- empty-state label - its paragraph note swaps out to "No rules
    -- yet." text when the tag list is empty.
    blocks[#blocks+1] = { type = "h4", name = "Current Rules" }

    -- Render each existing tag as a full-width "Remove rule: ..." button.
    -- Same idiom the Pinned Items section uses below for consistency.
    local tags = addon.Categories.GetTags(key)
    if #tags == 0 then
        blocks[#blocks+1] = {
            type = "paragraph",
            text = "|cff999999No rules yet. Items will only land here via pins (or the catch-all if this is the Other category).|r",
        }
    else
        for i, tag in ipairs(tags) do
            local idx = i  -- capture for closure
            blocks[#blocks+1] = {
                type  = "execute",
                name  = "Remove rule:  " .. addon.Categories.FormatTag(tag),
                width = "full",
                func  = function()
                    addon.Categories.RemoveTag(key, idx)
                    RefreshAll()
                end,
            }
        end
    end

    blocks[#blocks+1] = { type = "divider" }

    blocks[#blocks+1] = { type = "h3", name = "Pinned Items" }

    -- This section is a VIEW + UNPIN surface. Adding pins lives in the
    -- bag UI itself (Categorize Mode + the shift+right-click context
    -- menu) where it's faster and more visual - the settings page used
    -- to also have a "type or paste an item ID" input box, but it was
    -- a redundant text-only fallback nobody reached for when the bag
    -- UI was right there. Kept here: the list of currently-pinned
    -- items with one-click unpin buttons, useful for auditing pins
    -- without having to find the item in your bag.
    blocks[#blocks+1] = {
        type  = "note", style = "tip",
        text  = "To pin items into this category, use |cffffd700Categorize Mode|r in the bag panel (middle-click the portrait, then drop items onto the gold |cffffd700+|r slot at the end of this category's row), or |cffffd700shift+right-click|r any bag item and pick this category from the menu. Pinned items override the auto-classifier and always appear in this category. Unpin them from the list below.",
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
-- Add Match Rule popup (two-step flow)
--
-- Step 1: pick the tag type from a dropdown of all supported types.
-- Step 2: pick the operator + value with type-specific widgets so the
-- user never has to type a free-form value (no guessing class names,
-- no remembering INVTYPE_* strings - everything's a dropdown or a
-- numeric input).
--
-- The two steps share state via closure-captured tables, and the
-- popup primitive's button onClick gets a snapshot of all current
-- field values, so we just read them out at click time.
---------------------------------------------------------------------------

-- Convert an array of {value, label} options into the {key=label} map
-- shape the popup's "select" field expects.
local function ToValuesMap(opts)
    local m = {}
    for _, o in ipairs(opts) do m[o.value] = o.label end
    return m
end

-- Subclass values are composite (class + subclass) so we encode them
-- as "class:subclass" string keys for the dropdown, and decode on
-- save. Same trick as item-set IDs would use if we added that tag
-- type later.
local function SubclassMap()
    local m = {}
    for _, o in ipairs(addon.Categories.SUBCLASS_OPTIONS) do
        local k = tostring(o.class) .. ":" .. tostring(o.subclass)
        m[k] = o.label
    end
    return m
end

local function ParseSubclassKey(k)
    if not k or type(k) ~= "string" then return nil end
    local c, s = k:match("^(%-?%d+):(%-?%d+)$")
    if not c then return nil end
    return { tonumber(c), tonumber(s) }
end

local OPS_MAP = {
    name      = { contains = "contains", equals = "equals", regex = "matches regex" },
    quality   = { [">="] = "at least",   ["="] = "exactly", ["<="] = "at most" },
    ilvl      = { [">="] = "at least",   ["="] = "exactly", ["<="] = "at most" },
    -- single-op types (class / subclass / equipSlot) skip the op
    -- dropdown entirely - "is" is the only sensible choice.
}

-- Step 2: type-specific value editor. `tagType` is the chosen filter
-- type from step 1. Builds the right widgets for that type and
-- commits the tag on Add.
local function OpenAddTagPopup_PickValue(categoryKey, tagType)
    local fields = {}
    local body
    local buildTag

    if tagType == "name" then
        body = "Match items whose name contains the substring (case-insensitive), is exactly equal to it, or matches a Lua pattern."
        fields = {
            { key = "op",    type = "select", label = "Operator",
              values = OPS_MAP.name, default = "contains" },
            { key = "value", type = "input",  label = "Text",
              default = "" },
        }
        buildTag = function(v)
            return { type = "name", op = v.op or "contains",
                     value = tostring(v.value or "") }
        end

    elseif tagType == "class" then
        body = "Match items belonging to a specific WoW item class."
        fields = {
            { key = "value", type = "select", label = "Item Class",
              values = ToValuesMap(addon.Categories.CLASS_OPTIONS),
              default = Enum.ItemClass.Weapon },
        }
        buildTag = function(v)
            return { type = "class", op = "equals",
                     value = tonumber(v.value) }
        end

    elseif tagType == "subclass" then
        body = "Match items in a specific item subclass (Cloth Armor, Daggers, Potions, etc.)."
        fields = {
            { key = "value", type = "select", label = "Subclass",
              values = SubclassMap(),
              default = "4:1" },  -- Armor:Cloth
        }
        buildTag = function(v)
            local pair = ParseSubclassKey(v.value)
            if not pair then return nil end
            return { type = "subclass", op = "equals", value = pair }
        end

    elseif tagType == "equipSlot" then
        body = "Match items that go into a specific equipment slot. Two-handed weapons use their own slot; one-handed and main/off-hand are distinct - pick the slot the item actually shows in its tooltip."
        fields = {
            { key = "value", type = "select", label = "Equip Slot",
              values = ToValuesMap(addon.Categories.EQUIP_SLOT_OPTIONS),
              default = "INVTYPE_HEAD" },
        }
        buildTag = function(v)
            return { type = "equipSlot", op = "equals",
                     value = tostring(v.value or "") }
        end

    elseif tagType == "quality" then
        body = "Match items by their quality colour. \"At least Rare\" catches Rare, Epic, Legendary, Artifact, and Heirloom."
        fields = {
            { key = "op",    type = "select", label = "Operator",
              values = OPS_MAP.quality, default = ">=" },
            { key = "value", type = "select", label = "Quality",
              values = ToValuesMap(addon.Categories.QUALITY_OPTIONS),
              default = 3 },
        }
        buildTag = function(v)
            return { type = "quality", op = v.op or ">=",
                     value = tonumber(v.value) or 3 }
        end

    elseif tagType == "ilvl" then
        body = "Match items by item level (the displayed number, accounting for upgrades)."
        fields = {
            { key = "op",    type = "select", label = "Operator",
              values = OPS_MAP.ilvl, default = ">=" },
            { key = "value", type = "input",  label = "Item Level",
              default = "100" },
        }
        buildTag = function(v)
            local n = tonumber(v.value)
            if not n then return nil end
            return { type = "ilvl", op = v.op or ">=", value = n }
        end

    else
        return  -- unknown type, abort
    end

    -- Look up the friendly type label for the popup title.
    local typeLabel = tagType
    for _, t in ipairs(addon.Categories.TYPE_OPTIONS) do
        if t.value == tagType then typeLabel = t.label; break end
    end

    BazCore:OpenPopup({
        title  = "Add Match Rule - " .. typeLabel,
        body   = body,
        width  = 400,
        fields = fields,
        buttons = {
            { label = "Cancel", style = "default", onClick = function() end },
            {
                label   = "Add Rule",
                style   = "primary",
                onClick = function(values)
                    local tag = buildTag(values)
                    if not tag then
                        if addon.core then
                            addon.core:Print("|cffff8800Couldn't parse rule value.|r")
                        end
                        return
                    end
                    addon.Categories.AddTag(categoryKey, tag)
                    RefreshAll()
                end,
            },
        },
    })
end

-- Step 1: pick the tag type. On Next, closes itself and opens the
-- type-specific Step 2 popup.
OpenAddTagPopup = function(categoryKey)
    BazCore:OpenPopup({
        title = "Add Match Rule",
        body  = "What do you want to filter by? Pick a type, then the next step lets you set the operator and value.",
        width = 380,
        fields = {
            { key = "tagType", type = "select", label = "Filter by",
              values = ToValuesMap(addon.Categories.TYPE_OPTIONS),
              default = "name" },
        },
        buttons = {
            { label = "Cancel", style = "default", onClick = function() end },
            {
                label   = "Next",
                style   = "primary",
                onClick = function(values)
                    OpenAddTagPopup_PickValue(categoryKey, values.tagType or "name")
                end,
            },
        },
    })
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
