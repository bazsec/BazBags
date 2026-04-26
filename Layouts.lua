---------------------------------------------------------------------------
-- BazBags — Category layout module
--
-- One layout: thin full-width divider rows mark each category, items
-- pack into a regular grid below. Each category always starts a fresh
-- row with its own divider, so the reading order is top-to-bottom in
-- clean chapters.
--
-- Compared to a chunky Sections-style header this saves ~6 px of
-- vertical space per category while still being instantly scannable.
-- Bag.lua's Refresh dispatches here when bagMode == "categories".
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

addon.Layouts = addon.Layouts or {}
local Layouts = addon.Layouts

---------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------

local DIVIDER_HEIGHT       = 18
local DIVIDER_GAP_BELOW    = 4   -- gap between divider and first item row
local CATEGORY_GAP         = 6   -- gap between one category's items and the next divider
local TITLE_COLOR          = { 1.00, 0.82, 0.00 }    -- suite gold, matches headers
local DIVIDER_LINE_COLOR   = { 0.55, 0.42, 0.18, 0.85 }

---------------------------------------------------------------------------
-- Divider-row pool — one per category. A divider is a thin (~18 px)
-- full-width Button containing a chevron + category name + a subtle
-- horizontal line that fades out to the right edge. Reads like the
-- title rule on a chapter divider.
---------------------------------------------------------------------------

local dividerRows = {}

local function GetOrCreateDividerRow(parent, key)
    local row = dividerRows[key]
    if row then
        row:SetParent(parent)
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(DIVIDER_HEIGHT)

    -- Hover background (subtle so it doesn't compete with the items).
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.04)
    hover:Hide()
    row.hover = hover

    -- Collapse / expand chevron, anchored to the very left of the row.
    row.toggle = row:CreateTexture(nil, "OVERLAY")
    row.toggle:SetSize(12, 12)
    row.toggle:SetPoint("LEFT", 4, 0)

    -- Category title in suite gold.
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
    row.text:SetTextColor(unpack(TITLE_COLOR))

    -- Faint horizontal rule that fills the rest of the row beyond the
    -- title text. Visible without competing with the icons below.
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetColorTexture(unpack(DIVIDER_LINE_COLOR))

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)

    dividerRows[key] = row
    return row
end

local function HideAllDividerRows()
    for _, row in pairs(dividerRows) do
        row:Hide()
    end
end

-- Public hide-all so Bag.lua can clear our chrome when it switches
-- back to bag mode (otherwise stale dividers remain visible).
function Layouts.HideAll()
    HideAllDividerRows()
end

---------------------------------------------------------------------------
-- Render — the only category layout.
--
-- Each category gets a thin full-width divider row, then its items
-- in a regular grid below. Items wrap inside the category. The next
-- category always starts on a fresh row.
--
-- ctx is a table of frame primitives Bag.lua hands us so this module
-- doesn't have to re-look up addon state.
---------------------------------------------------------------------------

function Layouts.Render(ctx)
    local frame          = ctx.frame
    local cols           = ctx.cols
    local SLOT_SIZE      = ctx.SLOT_SIZE
    local SLOT_SPACING_X = ctx.SLOT_SPACING_X
    local SLOT_SPACING_Y = ctx.SLOT_SPACING_Y
    local SIDE_PAD       = ctx.SIDE_PAD
    local TOP_PAD        = ctx.TOP_PAD
    local IsCollapsed    = ctx.IsCollapsed
    local SetCollapsed   = ctx.SetCollapsed
    local GetOrCreateSlotButton = ctx.GetOrCreateSlotButton
    local UpdateSlot     = ctx.UpdateSlot
    local Refresh        = ctx.Refresh

    local Categories = addon.Categories
    local byCategory = Categories.GetPairsByCategory()
    local catList    = Categories.GetOrdered()

    -- Hide bag-mode section chrome in case the user just switched modes.
    for _, sec in pairs(addon.Bag.sections) do
        sec.header:Hide()
        sec.body:Hide()
    end
    HideAllDividerRows()

    local y = -TOP_PAD

    for _, cat in ipairs(catList) do
        local items = byCategory[cat.key]
        if items and #items > 0 then
            local collapsed = IsCollapsed(cat.key)

            -- Divider row spans the full width.
            local divider = GetOrCreateDividerRow(frame, cat.key)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
            divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
            divider.text:SetText(cat.title)
            divider.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            local key = cat.key
            divider:SetScript("OnClick", function()
                SetCollapsed(key, not IsCollapsed(key))
                if Refresh then Refresh() end
            end)
            divider:Show()

            y = y - DIVIDER_HEIGHT - DIVIDER_GAP_BELOW

            if not collapsed then
                for i, p in ipairs(items) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        SIDE_PAD + col * (SLOT_SIZE + SLOT_SPACING_X),
                        y - row * (SLOT_SIZE + SLOT_SPACING_Y))
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                end

                local rows  = math.ceil(#items / cols)
                local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
                y = y - bodyH - CATEGORY_GAP
            else
                y = y - CATEGORY_GAP
            end
        end
    end

    return y
end
