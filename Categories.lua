---------------------------------------------------------------------------
-- BazBags — Categories module
--
-- Every piece of code that decides "what category does this item belong
-- to" or "what's the canonical ordering of categories" lives here.
-- Bag.lua calls into this module to populate its render lists; the
-- layout modules in Layouts.lua use the same data to draw.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

addon.Categories = addon.Categories or {}
local Categories = addon.Categories

---------------------------------------------------------------------------
-- Built-in category list. Order is spaced by 10 so user-created custom
-- categories can slot anywhere via their own `order` field.
---------------------------------------------------------------------------

Categories.BUILTIN = {
    { key = "equipment",   title = "Equipment",   order = 10 },
    { key = "consumables", title = "Consumables", order = 20 },
    { key = "tradegoods",  title = "Trade Goods", order = 30 },
    { key = "questitems",  title = "Quest Items", order = 40 },
    { key = "junk",        title = "Junk",        order = 50 },
    { key = "other",       title = "Other",       order = 60 },
}

-- Set of bags we scan when bagMode == "categories". Same union as the
-- SECTIONS list in Bag.lua, lifted out so the collector can iterate
-- once without re-listing the bag indices.
Categories.ALL_BAG_IDS = {
    Enum.BagIndex.Backpack,
    Enum.BagIndex.Bag_1,
    Enum.BagIndex.Bag_2,
    Enum.BagIndex.Bag_3,
    Enum.BagIndex.Bag_4,
    Enum.BagIndex.ReagentBag,
}

---------------------------------------------------------------------------
-- ClassifyItem
--
-- Maps a single item to a category key. The lookup chain is:
--   1. User's itemCategories override (v2 will surface a UI to pin
--      items; the storage already exists so we honour it today).
--   2. Quality 0 → junk (vendor trash) regardless of class.
--   3. Item class buckets — Weapon/Armor → equipment, Consumable →
--      consumables, Tradegoods/Recipe/Gem/Enhancement → tradegoods,
--      Questitem → questitems.
--   4. Everything else → other (catch-all so no item slips through).
---------------------------------------------------------------------------

function Categories.Classify(itemID, quality, classID)
    -- Custom override (v2 will let users pin items)
    local custom = addon:GetSetting("itemCategories")
    if custom and itemID and custom[itemID] then
        return custom[itemID]
    end

    if quality == 0 then return "junk" end

    if classID == Enum.ItemClass.Weapon
       or classID == Enum.ItemClass.Armor then
        return "equipment"
    end
    if classID == Enum.ItemClass.Consumable then
        return "consumables"
    end
    if classID == Enum.ItemClass.Tradegoods
       or classID == Enum.ItemClass.Recipe
       or classID == Enum.ItemClass.Gem
       or classID == Enum.ItemClass.ItemEnhancement then
        return "tradegoods"
    end
    if classID == Enum.ItemClass.Questitem then
        return "questitems"
    end
    return "other"
end

---------------------------------------------------------------------------
-- GetOrdered
--
-- Returns the full list of category defs (built-in + user custom)
-- sorted by `order`. Each entry is { key, title, order }. Empty
-- categories are NOT filtered here — that's the caller's job, since
-- some layouts may want to render an empty placeholder.
---------------------------------------------------------------------------

function Categories.GetOrdered()
    local list = {}
    for _, cat in ipairs(Categories.BUILTIN) do
        list[#list + 1] = { key = cat.key, title = cat.title, order = cat.order }
    end
    local custom = addon:GetSetting("customCategories") or {}
    for key, info in pairs(custom) do
        list[#list + 1] = {
            key   = key,
            title = info.name or key,
            order = info.order or 100,
        }
    end
    table.sort(list, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    return list
end

---------------------------------------------------------------------------
-- GetPairsByCategory
--
-- Walks every bag we own, classifies each occupied slot, and returns
-- a { [categoryKey] = { {bagID, slotID}, ... } } table. Empty slots
-- are always skipped — they have no category to live in, so the
-- "Hide Empty Slots" setting is implied in category mode.
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
                -- GetContainerItemInfo doesn't always populate quality/
                -- classID immediately; fall back to GetItemInfo when the
                -- item-info cache is warm.
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
