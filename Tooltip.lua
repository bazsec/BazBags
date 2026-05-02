-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazBags - tooltip augmentation
--
-- Appends an "Expansion" line to item tooltips when the
-- "Show Expansion" option is on. The expansion comes from
-- C_Item.GetItemInfo's expansionID return (15th value), mapped
-- to the localized EXPANSION_NAME{n} global Blizzard ships.
--
-- Hooks via TooltipDataProcessor so the line shows up wherever an
-- item tooltip is rendered (bags, character pane, merchant, AH,
-- chat-link hover, etc.) - not just inside our own panel.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

local function ExpansionLabel(expacID)
    if not expacID then return nil end
    local key = "EXPANSION_NAME" .. tostring(expacID)
    local localized = _G[key]
    if type(localized) == "string" and localized ~= "" then
        return localized
    end
    return "Expansion " .. tostring(expacID)
end

local function OnItemTooltip(tooltip, data)
    if not addon:GetSetting("showExpacInTooltip") then return end
    if not tooltip or not data then return end

    -- TooltipData carries the item's hyperlink and/or numeric id.
    -- id is most reliable; fall back to parsing the hyperlink.
    local id = data.id
    if not id then
        local link = data.hyperlink
        if type(link) == "string" then
            id = tonumber(link:match("item:(%d+)"))
        end
    end
    if not id then return end

    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expacID =
        C_Item.GetItemInfo(id)
    if not expacID then return end

    tooltip:AddDoubleLine("Expansion", ExpansionLabel(expacID),
        0.6, 0.6, 0.6, 1, 0.82, 0)
end

local function Install()
    if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(
        Enum.TooltipDataType.Item, OnItemTooltip)
end

BazCore:QueueForLogin(Install)
