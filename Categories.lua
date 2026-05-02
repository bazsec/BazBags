-- SPDX-License-Identifier: GPL-2.0-or-later
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
    {
        key = "equipment", name = "Equipment", order = 10,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Weapon },
            { type = "class", op = "equals", value = Enum.ItemClass.Armor  },
        },
    },
    {
        key = "consumables", name = "Consumables", order = 20,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Consumable },
        },
    },
    {
        key = "tradegoods", name = "Trade Goods", order = 30,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Tradegoods      },
            { type = "class", op = "equals", value = Enum.ItemClass.Recipe          },
            { type = "class", op = "equals", value = Enum.ItemClass.Gem             },
            { type = "class", op = "equals", value = Enum.ItemClass.ItemEnhancement },
        },
    },
    {
        key = "questitems", name = "Quest Items", order = 40,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Questitem },
        },
    },
    {
        -- Junk has a quality=0 rule. It sits at display order 50 (low
        -- in the bag panel) but Classify checks it BEFORE the other
        -- defaults via a hardcoded shortcut, so a grey weapon still
        -- goes to Junk rather than Equipment regardless of order.
        key = "junk", name = "Junk", order = 50,
        matchMode = "all",
        tags = {
            { type = "quality", op = "=", value = 0 },
        },
    },
    {
        -- Catch-all. No tags - any item that doesn't match any other
        -- category's tags lands here via the FallbackKey("other") call
        -- at the end of Classify.
        key = "other", name = "Other", order = 60,
        matchMode = "all",
        tags = {},
    },
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
            -- Brand-new entry: copy the whole factory record (tags,
            -- matchMode, the works).
            cats[def.key] = {
                name      = def.name,
                order     = def.order,
                isDefault = true,
                matchMode = def.matchMode,
                tags      = def.tags and (function()
                    -- Deep-copy tags so mutating SV doesn't poison the
                    -- factory table. Pairs of {type, op, value} are
                    -- shallow-copied; values that are tables (subclass)
                    -- are also copied.
                    local out = {}
                    for i, t in ipairs(def.tags) do
                        local copy = { type = t.type, op = t.op }
                        if type(t.value) == "table" then
                            local vc = {}
                            for k, v in pairs(t.value) do vc[k] = v end
                            copy.value = vc
                        else
                            copy.value = t.value
                        end
                        out[i] = copy
                    end
                    return out
                end)() or nil,
            }
        else
            -- Existing entry: backfill the tag-related fields on
            -- defaults that pre-date the tag system (v062 and earlier
            -- shipped no tags). Don't clobber - only fill if missing.
            -- Custom categories (isDefault ~= true) are left alone.
            if cats[def.key].isDefault and not cats[def.key].tags then
                cats[def.key].matchMode = def.matchMode
                local out = {}
                for i, t in ipairs(def.tags or {}) do
                    local copy = { type = t.type, op = t.op }
                    if type(t.value) == "table" then
                        local vc = {}
                        for k, v in pairs(t.value) do vc[k] = v end
                        copy.value = vc
                    else
                        copy.value = t.value
                    end
                    out[i] = copy
                end
                cats[def.key].tags = out
            end
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

---------------------------------------------------------------------------
-- MoveUp / MoveDown
--
-- Swap the order value with the adjacent neighbour in the currently
-- sorted list. The Categories settings page wires its row up/down
-- arrow buttons to these so the user never has to hand-pick numeric
-- order values - they just nudge the row up or down and the
-- orderings shuffle to match.
--
-- Both no-op cleanly at the list edges, matching the renderer which
-- greys out the boundary arrow.
---------------------------------------------------------------------------

local function SwapOrders(keyA, keyB)
    local cats = addon:GetSetting("categories") or {}
    if not cats[keyA] or not cats[keyB] then return end
    local oa, ob = cats[keyA].order or 0, cats[keyB].order or 0
    -- Defensive: if both share the same order (which the GetAll
    -- tie-break tolerates) bump one off by 1 so they actually swap
    -- positions instead of staying coincident.
    if oa == ob then ob = oa + 1 end
    cats[keyA].order, cats[keyB].order = ob, oa
    addon:SetSetting("categories", cats)
end

function Categories.MoveUp(key)
    local list = Categories.GetAll()
    for i, c in ipairs(list) do
        if c.key == key then
            if i == 1 then return end
            SwapOrders(key, list[i-1].key)
            return
        end
    end
end

function Categories.MoveDown(key)
    local list = Categories.GetAll()
    for i, c in ipairs(list) do
        if c.key == key then
            if i == #list then return end
            SwapOrders(key, list[i+1].key)
            return
        end
    end
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
-- Tag-based match rules (Tier 1)
--
-- Custom categories can carry an array of tags that the classifier
-- evaluates BEFORE the default item-class auto-router. If any tag rule
-- matches (under the category's `matchMode` of "all" or "any"), the
-- item lands in that custom category. Manual pins still win above
-- everything (they short-circuit at the very top of Classify).
--
-- Tag schema:
--   { type = "name",      op = "contains|equals|regex", value = string }
--   { type = "class",     op = "equals", value = <classID> }
--   { type = "subclass",  op = "equals", value = { <classID>, <subclassID> } }
--   { type = "equipSlot", op = "equals", value = "INVTYPE_*" }
--   { type = "quality",   op = ">=|=|<=", value = <0-7> }
--   { type = "ilvl",      op = ">=|=|<=", value = <number> }
---------------------------------------------------------------------------

-- User-friendly enums and lookup tables. The classID / subclassID
-- numbers come from Enum.ItemClass / Enum.ItemArmorSubclass etc but
-- we publish stable string keys so the SV doesn't break if Blizzard
-- ever renumbers (they almost never do, but defensive).

Categories.CLASS_OPTIONS = {
    { value = Enum.ItemClass.Weapon,         label = "Weapon"      },
    { value = Enum.ItemClass.Armor,          label = "Armor"       },
    { value = Enum.ItemClass.Consumable,     label = "Consumable"  },
    { value = Enum.ItemClass.Tradegoods,     label = "Trade Goods" },
    { value = Enum.ItemClass.Recipe,         label = "Recipe"      },
    { value = Enum.ItemClass.Gem,            label = "Gem"         },
    { value = Enum.ItemClass.Questitem,      label = "Quest Item"  },
    { value = Enum.ItemClass.Miscellaneous,  label = "Miscellaneous" },
    { value = Enum.ItemClass.Battlepet,      label = "Battle Pet"  },
    { value = Enum.ItemClass.Container,      label = "Container"   },
    { value = Enum.ItemClass.Glyph,          label = "Glyph"       },
    { value = Enum.ItemClass.ItemEnhancement, label = "Item Enhancement" },
    { value = Enum.ItemClass.Profession,     label = "Profession"  },
}

-- Maps composite "class:subclass" pair to a friendly label. Subclass
-- IDs aren't unique across classes so each entry needs both. Only the
-- common-use subclasses are listed - exotic ones like specific rare
-- weapon types can be added on demand.
Categories.SUBCLASS_OPTIONS = {
    -- Armor (classID 4)
    { class = 4, subclass = 1, label = "Cloth Armor"        },
    { class = 4, subclass = 2, label = "Leather Armor"      },
    { class = 4, subclass = 3, label = "Mail Armor"         },
    { class = 4, subclass = 4, label = "Plate Armor"        },
    { class = 4, subclass = 5, label = "Cosmetic Armor"     },
    { class = 4, subclass = 6, label = "Shield"             },
    -- Weapon (classID 2)
    { class = 2, subclass = 0,  label = "Axe (1H)"          },
    { class = 2, subclass = 1,  label = "Axe (2H)"          },
    { class = 2, subclass = 2,  label = "Bow"               },
    { class = 2, subclass = 3,  label = "Gun"               },
    { class = 2, subclass = 4,  label = "Mace (1H)"         },
    { class = 2, subclass = 5,  label = "Mace (2H)"         },
    { class = 2, subclass = 6,  label = "Polearm"           },
    { class = 2, subclass = 7,  label = "Sword (1H)"        },
    { class = 2, subclass = 8,  label = "Sword (2H)"        },
    { class = 2, subclass = 9,  label = "Warglaive"         },
    { class = 2, subclass = 10, label = "Staff"             },
    { class = 2, subclass = 13, label = "Fist Weapon"       },
    { class = 2, subclass = 15, label = "Dagger"            },
    { class = 2, subclass = 18, label = "Crossbow"          },
    { class = 2, subclass = 19, label = "Wand"              },
    -- Consumable (classID 0)
    { class = 0, subclass = 1, label = "Potion"             },
    { class = 0, subclass = 2, label = "Elixir"             },
    { class = 0, subclass = 3, label = "Flask"              },
    { class = 0, subclass = 5, label = "Food & Drink"       },
    { class = 0, subclass = 6, label = "Bandage"            },
    { class = 0, subclass = 8, label = "Other Consumable"   },
    -- Trade Goods (classID 7)
    { class = 7, subclass = 4, label = "Cloth (Trade Good)"     },
    { class = 7, subclass = 5, label = "Leather (Trade Good)"   },
    { class = 7, subclass = 6, label = "Metal & Stone"          },
    { class = 7, subclass = 7, label = "Cooking Material"       },
    { class = 7, subclass = 8, label = "Herb"                   },
    { class = 7, subclass = 9, label = "Elemental"              },
    { class = 7, subclass = 12, label = "Enchanting Material"   },
    { class = 7, subclass = 13, label = "Inscription Material"  },
}

-- Friendly equip-slot list. Maps to INVTYPE_* strings under the hood.
Categories.EQUIP_SLOT_OPTIONS = {
    { value = "INVTYPE_HEAD",          label = "Head"            },
    { value = "INVTYPE_NECK",          label = "Neck"            },
    { value = "INVTYPE_SHOULDER",      label = "Shoulder"        },
    { value = "INVTYPE_CLOAK",         label = "Cloak / Back"    },
    { value = "INVTYPE_CHEST",         label = "Chest"           },
    { value = "INVTYPE_ROBE",          label = "Robe"            },
    { value = "INVTYPE_BODY",          label = "Shirt"           },
    { value = "INVTYPE_TABARD",        label = "Tabard"          },
    { value = "INVTYPE_WRIST",         label = "Wrist"           },
    { value = "INVTYPE_HAND",          label = "Hands"           },
    { value = "INVTYPE_WAIST",         label = "Waist"           },
    { value = "INVTYPE_LEGS",          label = "Legs"            },
    { value = "INVTYPE_FEET",          label = "Feet"            },
    { value = "INVTYPE_FINGER",        label = "Ring"            },
    { value = "INVTYPE_TRINKET",       label = "Trinket"         },
    { value = "INVTYPE_WEAPON",        label = "One-Handed Weapon"   },
    { value = "INVTYPE_2HWEAPON",      label = "Two-Handed Weapon"   },
    { value = "INVTYPE_WEAPONMAINHAND", label = "Main Hand"      },
    { value = "INVTYPE_WEAPONOFFHAND", label = "Off Hand"        },
    { value = "INVTYPE_HOLDABLE",      label = "Held In Off-Hand" },
    { value = "INVTYPE_SHIELD",        label = "Shield Slot"     },
    { value = "INVTYPE_RANGED",        label = "Ranged"          },
    { value = "INVTYPE_RANGEDRIGHT",   label = "Ranged (Wand/Crossbow)" },
    { value = "INVTYPE_BAG",           label = "Bag"             },
}

Categories.QUALITY_OPTIONS = {
    { value = 0, label = "Poor (Grey)"        },
    { value = 1, label = "Common (White)"     },
    { value = 2, label = "Uncommon (Green)"   },
    { value = 3, label = "Rare (Blue)"        },
    { value = 4, label = "Epic (Purple)"      },
    { value = 5, label = "Legendary (Orange)" },
    { value = 6, label = "Artifact (Red)"     },
    { value = 7, label = "Heirloom (Cyan)"    },
}

Categories.TYPE_OPTIONS = {
    { value = "name",      label = "Name"           },
    { value = "class",     label = "Item Class"     },
    { value = "subclass",  label = "Item Subclass"  },
    { value = "equipSlot", label = "Equip Slot"     },
    { value = "quality",   label = "Quality"        },
    { value = "ilvl",      label = "Item Level"     },
}

-- Valid operators per tag type. Used by the popup to filter the op
-- dropdown to only those that make sense for the chosen type.
Categories.OPS_FOR_TYPE = {
    name      = { { value = "contains", label = "contains"   },
                  { value = "equals",   label = "equals"     },
                  { value = "regex",    label = "matches regex" } },
    class     = { { value = "equals",   label = "is" } },
    subclass  = { { value = "equals",   label = "is" } },
    equipSlot = { { value = "equals",   label = "is" } },
    quality   = { { value = ">=", label = "at least" },
                  { value = "=",  label = "exactly"  },
                  { value = "<=", label = "at most"  } },
    ilvl      = { { value = ">=", label = "at least" },
                  { value = "=",  label = "exactly"  },
                  { value = "<=", label = "at most"  } },
}

-- Lookup helpers for friendly label rendering.
local function ClassLabel(classID)
    for _, o in ipairs(Categories.CLASS_OPTIONS) do
        if o.value == classID then return o.label end
    end
    return tostring(classID)
end

local function SubclassLabel(classID, subclassID)
    for _, o in ipairs(Categories.SUBCLASS_OPTIONS) do
        if o.class == classID and o.subclass == subclassID then return o.label end
    end
    return ClassLabel(classID) .. ":" .. tostring(subclassID)
end

local function EquipSlotLabel(invtype)
    for _, o in ipairs(Categories.EQUIP_SLOT_OPTIONS) do
        if o.value == invtype then return o.label end
    end
    return invtype or "?"
end

local function QualityLabel(q)
    for _, o in ipairs(Categories.QUALITY_OPTIONS) do
        if o.value == q then return o.label end
    end
    return tostring(q)
end

-- Pretty-print a tag for display in the rules list. Format reads as
-- a natural-language clause: "Name contains 'PoE'", "Quality at least Rare".
function Categories.FormatTag(tag)
    if not tag or not tag.type then return "(invalid rule)" end
    local t, op, v = tag.type, tag.op or "equals", tag.value
    if t == "name" then
        local opLabel = (op == "contains" and "contains")
            or (op == "equals" and "equals")
            or (op == "regex" and "matches regex")
            or op
        return string.format("Name %s |cffffd700\"%s\"|r",
            opLabel, tostring(v or ""))
    elseif t == "class" then
        return "Item Class is |cffffd700" .. ClassLabel(v) .. "|r"
    elseif t == "subclass" then
        if type(v) == "table" then
            return "Item Subclass is |cffffd700" .. SubclassLabel(v[1], v[2]) .. "|r"
        end
        return "Item Subclass is " .. tostring(v)
    elseif t == "equipSlot" then
        return "Equip Slot is |cffffd700" .. EquipSlotLabel(v) .. "|r"
    elseif t == "quality" then
        local opLabel = (op == ">=" and "at least")
            or (op == "<=" and "at most")
            or "exactly"
        return string.format("Quality %s |cffffd700%s|r",
            opLabel, QualityLabel(tonumber(v) or 0))
    elseif t == "ilvl" then
        local opLabel = (op == ">=" and "at least")
            or (op == "<=" and "at most")
            or "exactly"
        return string.format("Item Level %s |cffffd700%d|r",
            opLabel, tonumber(v) or 0)
    end
    return "(unknown rule type: " .. tostring(t) .. ")"
end

-- Pull metadata for matching. Returns nil if GetItemInfo hasn't cached
-- the item yet (the bag refresh loop will hit the same item again on
-- the next refresh once Blizzard fills the cache).
local function ItemMeta(itemID)
    if not itemID then return nil end
    local name, _, quality, ilvl, minLvl, _, _, stack,
          equipLoc, _, _, classID, subclassID, bindType,
          expacID, setID, isCraftingReagent = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    return {
        name              = name,
        quality           = quality,
        ilvl              = ilvl,
        minLvl            = minLvl,
        stack             = stack,
        equipLoc          = equipLoc,
        classID           = classID,
        subclassID        = subclassID,
        bindType          = bindType,
        expacID           = expacID,
        setID             = setID,
        isCraftingReagent = isCraftingReagent,
    }
end

-- Single-tag match. Returns true/false. Defensive against malformed
-- tag tables - bad ops just fail-match rather than throwing.
local function MatchTag(tag, meta)
    if not tag or not tag.type or not meta then return false end
    local t  = tag.type
    local op = tag.op or "equals"
    local v  = tag.value

    if t == "name" then
        local n = (meta.name or ""):lower()
        local s = tostring(v or "")
        if op == "contains" then
            return n:find(s:lower(), 1, true) ~= nil
        elseif op == "equals" then
            return n == s:lower()
        elseif op == "regex" then
            local ok, m = pcall(string.match, meta.name or "", s)
            return ok and m ~= nil
        end
        return false
    elseif t == "class" then
        return meta.classID == tonumber(v)
    elseif t == "subclass" then
        if type(v) == "table" then
            return meta.classID == v[1] and meta.subclassID == v[2]
        end
        return false
    elseif t == "equipSlot" then
        return meta.equipLoc == v
    elseif t == "quality" then
        local q = meta.quality or 0
        local n = tonumber(v) or 0
        if op == ">=" then return q >= n end
        if op == "=" then return q == n end
        if op == "<=" then return q <= n end
        return false
    elseif t == "ilvl" then
        local i = meta.ilvl or 0
        local n = tonumber(v) or 0
        if op == ">=" then return i >= n end
        if op == "=" then return i == n end
        if op == "<=" then return i <= n end
        return false
    end
    return false
end

-- Returns true if `itemID` passes ALL (or ANY, depending on matchMode)
-- of the tags on `categoryKey`. False if the category has no tags or
-- the item info isn't cached yet.
function Categories.MatchesCategory(itemID, categoryKey)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[categoryKey]
    if not cat or not cat.tags or #cat.tags == 0 then return false end

    local meta = ItemMeta(itemID)
    if not meta then return false end

    local mode = cat.matchMode or "all"
    if mode == "all" then
        for _, tag in ipairs(cat.tags) do
            if not MatchTag(tag, meta) then return false end
        end
        return true
    else
        for _, tag in ipairs(cat.tags) do
            if MatchTag(tag, meta) then return true end
        end
        return false
    end
end

---------------------------------------------------------------------------
-- Tag CRUD
---------------------------------------------------------------------------

function Categories.GetTags(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    return (cat and cat.tags) or {}
end

function Categories.AddTag(key, tag)
    if not key or not tag then return end
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat then return end
    cat.tags = cat.tags or {}
    cat.tags[#cat.tags + 1] = tag
    addon:SetSetting("categories", cats)
end

function Categories.RemoveTag(key, index)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or not cat.tags then return end
    table.remove(cat.tags, index)
    addon:SetSetting("categories", cats)
end

function Categories.GetMatchMode(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    return (cat and cat.matchMode) or "all"
end

function Categories.SetMatchMode(key, mode)
    if mode ~= "all" and mode ~= "any" then return end
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat then return end
    cat.matchMode = mode
    addon:SetSetting("categories", cats)
end

-- Restore the factory tags + matchMode for a default category. No-op
-- on custom categories (they have no factory state to restore).
function Categories.ResetTagsToDefault(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or not cat.isDefault then return end
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        if def.key == key then
            cat.matchMode = def.matchMode
            local out = {}
            for i, t in ipairs(def.tags or {}) do
                local copy = { type = t.type, op = t.op }
                if type(t.value) == "table" then
                    local vc = {}
                    for k, v in pairs(t.value) do vc[k] = v end
                    copy.value = vc
                else
                    copy.value = t.value
                end
                out[i] = copy
            end
            cat.tags = out
            addon:SetSetting("categories", cats)
            return
        end
    end
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
    -- 1. Manual pin override always wins.
    local pins = addon:GetSetting("itemCategories")
    if pins and itemID and pins[itemID] then
        local catKey = pins[itemID]
        local cats = addon:GetSetting("categories") or {}
        if cats[catKey] then return catKey end
        -- Pin points at a category that no longer exists; drop to auto.
    end

    -- 2. Junk shortcut: quality=0 always goes to Junk (if it still
    -- exists), regardless of category display order. This preserves
    -- the original behaviour where a grey weapon lands in Junk
    -- rather than Equipment - users typically batch-vendor greys
    -- together, so the quality flag wins over the class flag for
    -- low-quality items. If the user has deleted the Junk category
    -- or it has no quality=0 tag any more, fall through to normal
    -- tag-based matching.
    if quality == 0 then
        local cats = addon:GetSetting("categories") or {}
        if cats.junk then return "junk" end
    end

    -- 3. Tag-based matching for ALL categories (default + custom).
    -- Walk in display order; first category whose tags match wins.
    -- Categories with no tags (e.g. "Other" by design) are skipped
    -- so they only ever match via the catch-all fallback below.
    local list = Categories.GetAll()
    for _, entry in ipairs(list) do
        local cats = addon:GetSetting("categories") or {}
        local cat  = cats[entry.key]
        if cat and cat.tags and #cat.tags > 0 then
            if Categories.MatchesCategory(itemID, entry.key) then
                return entry.key
            end
        end
    end

    -- 4. Catch-all: nothing claimed it. Land in "other" if it still
    -- exists, otherwise the lowest-ordered surviving category.
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
