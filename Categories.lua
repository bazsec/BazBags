---------------------------------------------------------------------------
-- BazBags - Categories module
--
-- Owns the category data model + classification logic. Categories are
-- persisted in the `categories` saved variable as { [key] = { name,
-- order, isDefault } }; on first load FACTORY_DEFAULTS is folded in
-- so out-of-the-box users get six built-in groupings. Default
-- categories are renameable / reorderable / deletable like custom
-- ones, but the auto-classifier in Classify() is tied to their
-- *key* (not label) - so renaming "Equipment" > "Gear" doesn't
-- break the Weapon/Armor > equipment routing.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

addon.Categories = addon.Categories or {}
local Categories = addon.Categories

---------------------------------------------------------------------------
-- Factory defaults - the categories any first-time user starts with.
-- The Reset Defaults button in the Settings page restores from this
-- table. Order is spaced by 10 so user-added categories can slot in
-- between (Reset preserves their `order` if Soft mode).
---------------------------------------------------------------------------

Categories.FACTORY_DEFAULTS = {
    { key = "equipment",   name = "Equipment",   order = 10 },
    { key = "consumables", name = "Consumables", order = 20 },
    { key = "tradegoods",  name = "Trade Goods", order = 30 },
    { key = "questitems",  name = "Quest Items", order = 40 },
    { key = "junk",        name = "Junk",        order = 50 },
    { key = "other",       name = "Other",       order = 60 },
}

-- Set of bags we scan when bagMode == "categories".
Categories.ALL_BAG_IDS = {
    Enum.BagIndex.Backpack,
    Enum.BagIndex.Bag_1,
    Enum.BagIndex.Bag_2,
    Enum.BagIndex.Bag_3,
    Enum.BagIndex.Bag_4,
    Enum.BagIndex.ReagentBag,
}

---------------------------------------------------------------------------
-- EnsureDefaults
--
-- Called once at addon load. If the persisted `categories` map is
-- empty (first run) or missing any default keys (user upgraded from
-- a build that didn't track them), backfill from FACTORY_DEFAULTS.
-- Never overwrites user-edited names or orders - only fills holes.
---------------------------------------------------------------------------

function Categories.EnsureDefaults()
    local cats = addon:GetSetting("categories") or {}
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        if not cats[def.key] then
            cats[def.key] = {
                name      = def.name,
                order     = def.order,
                isDefault = true,
            }
        end
    end
    addon:SetSetting("categories", cats)
end

---------------------------------------------------------------------------
-- GetAll
--
-- Returns the persisted category list as an array sorted by `order`,
-- with stable tie-break on `key`. Each entry is the saved record plus
-- the `key` field copied in for convenience.
---------------------------------------------------------------------------

function Categories.GetAll()
    local cats = addon:GetSetting("categories") or {}
    local list = {}
    for key, info in pairs(cats) do
        list[#list + 1] = {
            key       = key,
            name      = info.name or key,
            order     = info.order or 100,
            isDefault = info.isDefault or false,
            hidden    = info.hidden  or false,
        }
    end
    table.sort(list, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    return list
end

function Categories.Get(key)
    local cats = addon:GetSetting("categories") or {}
    return cats[key]
end

---------------------------------------------------------------------------
-- CRUD operations
---------------------------------------------------------------------------

function Categories.Rename(key, newName)
    if not key or not newName or newName == "" then return end
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].name = newName
    addon:SetSetting("categories", cats)
end

function Categories.Reorder(key, newOrder)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].order = newOrder
    addon:SetSetting("categories", cats)
end

-- Hidden categories still exist in the data model - items can still be
-- classified/pinned to them - but the bag layout skips them entirely
-- (no divider, no items, no drop slot). Useful for "Junk" so grey
-- items don't visually clutter the bag while still occupying their
-- real container slots, and for stashing items the user wants out of
-- the way without permanently removing them.
function Categories.SetHidden(key, hidden)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].hidden = hidden and true or false
    addon:SetSetting("categories", cats)
end

-- Generates a unique key (custom_<n>) and inserts a new entry. New
-- categories slot at the end of the list (max-order + 10) so they
-- don't accidentally jump above defaults.
function Categories.Create(name)
    name = name and name ~= "" and name or "New Category"
    local cats = addon:GetSetting("categories") or {}

    local maxOrder = 0
    local n = 0
    for _, info in pairs(cats) do
        if (info.order or 0) > maxOrder then maxOrder = info.order end
        n = n + 1
    end

    local key
    repeat
        n = n + 1
        key = "custom_" .. n
    until not cats[key]

    cats[key] = {
        name  = name,
        order = maxOrder + 10,
    }
    addon:SetSetting("categories", cats)
    return key
end

-- Removes a category outright. Items pinned to it via itemCategories
-- are unpinned (drop back to auto-classify) so they still appear in
-- the bag - just under whatever default category their class implies.
function Categories.Delete(key)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key] = nil
    addon:SetSetting("categories", cats)

    local pins = addon:GetSetting("itemCategories") or {}
    local changed = false
    for itemID, catKey in pairs(pins) do
        if catKey == key then
            pins[itemID] = nil
            changed = true
        end
    end
    if changed then addon:SetSetting("itemCategories", pins) end
end

-- ResetDefaults
--   wipeCustoms = false > restore default labels + order, keep customs + pins
--   wipeCustoms = true  > also delete all user-created categories +
--                          itemCategories, leaving only factory state
function Categories.ResetDefaults(wipeCustoms)
    local cats = addon:GetSetting("categories") or {}
    if wipeCustoms then
        cats = {}
        addon:SetSetting("itemCategories", {})
    end
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        cats[def.key] = {
            name      = def.name,
            order     = def.order,
            isDefault = true,
        }
    end
    addon:SetSetting("categories", cats)
end

---------------------------------------------------------------------------
-- Item pinning
---------------------------------------------------------------------------

function Categories.AddItem(itemID, categoryKey)
    if not itemID or not categoryKey then return end
    local pins = addon:GetSetting("itemCategories") or {}
    pins[itemID] = categoryKey
    addon:SetSetting("itemCategories", pins)
end

function Categories.RemoveItem(itemID)
    local pins = addon:GetSetting("itemCategories") or {}
    pins[itemID] = nil
    addon:SetSetting("itemCategories", pins)
end

function Categories.GetPinnedItems(categoryKey)
    local out = {}
    local pins = addon:GetSetting("itemCategories") or {}
    for itemID, key in pairs(pins) do
        if key == categoryKey then
            out[#out + 1] = itemID
        end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- Classify
--
-- Maps a single item to a category key. Lookup chain:
--   1. itemCategories[itemID]    - explicit pin wins
--   2. quality == 0              > junk
--   3. ItemClass-based rules     > equipment / consumables / tradegoods / questitems
--   4. catch-all                 > other
--
-- The default keys (equipment, consumables, etc.) keep working even if
-- the user renames or reorders them - the classifier only cares about
-- the *key*, not the displayed label. If the user has deleted a
-- default category entirely, items that would have landed there fall
-- through to "other" (assuming "other" still exists; otherwise the
-- first remaining category by order).
---------------------------------------------------------------------------

local function FallbackKey(preferred)
    local cats = addon:GetSetting("categories") or {}
    if cats[preferred] then return preferred end
    -- Pick the lowest-ordered surviving category as a final fallback.
    local list = Categories.GetAll()
    return list[1] and list[1].key or preferred
end

function Categories.Classify(itemID, quality, classID)
    local pins = addon:GetSetting("itemCategories")
    if pins and itemID and pins[itemID] then
        local catKey = pins[itemID]
        local cats = addon:GetSetting("categories") or {}
        if cats[catKey] then return catKey end
        -- Pin points at a category that no longer exists; drop to auto.
    end

    if quality == 0 then return FallbackKey("junk") end

    if classID == Enum.ItemClass.Weapon
       or classID == Enum.ItemClass.Armor then
        return FallbackKey("equipment")
    end
    if classID == Enum.ItemClass.Consumable then
        return FallbackKey("consumables")
    end
    if classID == Enum.ItemClass.Tradegoods
       or classID == Enum.ItemClass.Recipe
       or classID == Enum.ItemClass.Gem
       or classID == Enum.ItemClass.ItemEnhancement then
        return FallbackKey("tradegoods")
    end
    if classID == Enum.ItemClass.Questitem then
        return FallbackKey("questitems")
    end
    return FallbackKey("other")
end

---------------------------------------------------------------------------
-- Backwards-compatible alias for callers that still ask for GetOrdered.
-- New code should call GetAll directly (returns the same shape - list
-- of { key, name, order, isDefault }).
---------------------------------------------------------------------------

function Categories.GetOrdered()
    local list = Categories.GetAll()
    -- Layouts.Render expects { key, title, order } - copy `name` to
    -- `title` for backwards compat.
    for _, entry in ipairs(list) do
        entry.title = entry.name
    end
    return list
end

---------------------------------------------------------------------------
-- GetPairsByCategory
--
-- Walks every bag, classifies each occupied slot, returns a
-- { [categoryKey] = { {bagID, slotID}, ... } } table. Empty slots are
-- always skipped - they have no category to live in.
---------------------------------------------------------------------------

function Categories.GetPairsByCategory()
    local byCategory = {}
    for _, bagID in ipairs(Categories.ALL_BAG_IDS) do
        local n = C_Container.GetContainerNumSlots(bagID) or 0
        for slotID = 1, n do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and info.iconFileID then
                local link    = info.hyperlink
                local quality = info.quality
                local classID = info.classID
                if (not classID or not quality) and link and GetItemInfo then
                    local _, _, q, _, _, _, _, _, _, _, _, c = GetItemInfo(link)
                    quality = quality or q
                    classID = classID or c
                end
                local catKey = Categories.Classify(info.itemID, quality or 1, classID)
                local bucket = byCategory[catKey]
                if not bucket then
                    bucket = {}
                    byCategory[catKey] = bucket
                end
                bucket[#bucket + 1] = { bagID = bagID, slotID = slotID }
            end
        end
    end
    return byCategory
end

---------------------------------------------------------------------------
-- Init: backfill defaults at addon load. SafeForLogin so addon.db is
-- ready by the time we read/write settings.
---------------------------------------------------------------------------

if BazCore.QueueForLogin then
    BazCore:QueueForLogin(function() Categories.EnsureDefaults() end)
end
