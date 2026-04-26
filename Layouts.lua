---------------------------------------------------------------------------
-- BazBags — Category layout module
--
-- Three layout strategies for category mode:
--
--   Sections  Each category gets a full-width header + its own grid.
--             Same chrome as bag-mode sections, just one per category.
--             Wastes vertical space when categories have few items.
--
--   Flow      All items pack into a single continuous grid. Category
--             boundaries are inline pill-shaped label cells (1.5–2
--             slots wide) that flow with the items. Zero wasted rows.
--
--   Hybrid    Like Sections, but when a category's last row is partial
--             AND the next category has few items, the next category's
--             label + items pack into the same row. Best of both —
--             clear separation for big categories, no waste for small.
--
-- Bag.lua's Refresh dispatches to one of these based on the
-- categoryLayout setting.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

addon.Layouts = addon.Layouts or {}
local Layouts = addon.Layouts

---------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------

local LABEL_CELLS_WIDE = 2     -- how many slot widths a flow label takes
local PILL_BG_COLOR    = { 0.18, 0.13, 0.05, 0.85 }
local PILL_BORDER      = { 0.55, 0.42, 0.18, 0.85 }
local TITLE_COLOR      = { 1.00, 0.82, 0.00 }    -- suite gold, matches headers

---------------------------------------------------------------------------
-- Pill / label cell pool — used by the Hybrid layout. Each pill is a
-- slot-sized Button that flows alongside item slots, marking the
-- start of a new category inline on a partial row.
--
-- Flow used to share this pool but moved to a thin full-row divider
-- (see GetOrCreateDividerRow below) — that style reads cleaner when
-- categories own their own rows from the start.
---------------------------------------------------------------------------

local labelCells = {}

local function GetOrCreateLabelCell(parent, key, slotSize, slotSpacingX)
    local cell = labelCells[key]
    if cell then
        cell:SetParent(parent)
        return cell
    end

    local width = slotSize * LABEL_CELLS_WIDE + slotSpacingX * (LABEL_CELLS_WIDE - 1)
    cell = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cell:SetSize(width, slotSize)
    cell:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 8,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    cell:SetBackdropColor(unpack(PILL_BG_COLOR))
    cell:SetBackdropBorderColor(unpack(PILL_BORDER))

    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("CENTER", 0, 0)
    cell.text:SetTextColor(unpack(TITLE_COLOR))

    cell.toggle = cell:CreateTexture(nil, "OVERLAY")
    cell.toggle:SetSize(10, 10)
    cell.toggle:SetPoint("LEFT", 4, 0)

    cell:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.28, 0.20, 0.08, 0.9)
    end)
    cell:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(PILL_BG_COLOR))
    end)

    labelCells[key] = cell
    return cell
end

local function HideAllLabelCells()
    for _, cell in pairs(labelCells) do
        cell:Hide()
    end
end

---------------------------------------------------------------------------
-- Divider-row pool — used by the Flow layout. A divider is a thin
-- (~18 px) full-width row containing a chevron + category name + a
-- subtle horizontal line that fades out to the right edge. Reads
-- like the title rule on a chapter divider, packing into far less
-- vertical space than a Sections-style header without sacrificing
-- scannability.
---------------------------------------------------------------------------

local DIVIDER_HEIGHT = 18
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
    -- title text. The 0.5 alpha keeps it visible without competing
    -- with the icons below for attention.
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetColorTexture(unpack(PILL_BORDER))

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
-- back to bag mode (otherwise stale dividers / pills remain visible).
function Layouts.HideAll()
    HideAllLabelCells()
    HideAllDividerRows()
end

---------------------------------------------------------------------------
-- Sections layout
--
-- One header + grid block per category. Reuses Bag.lua's section
-- builder via addon.Bag.GetOrCreateSection so the chrome (collapse
-- chevron, hover, click handler, count) matches bag-mode exactly.
---------------------------------------------------------------------------

function Layouts.RenderSections(ctx)
    local frame        = ctx.frame
    local cols         = ctx.cols
    local SLOT_SIZE    = ctx.SLOT_SIZE
    local SLOT_SPACING_X = ctx.SLOT_SPACING_X
    local SLOT_SPACING_Y = ctx.SLOT_SPACING_Y
    local SECTION_HEADER_H = ctx.SECTION_HEADER_H
    local SIDE_PAD     = ctx.SIDE_PAD
    local TOP_PAD      = ctx.TOP_PAD
    local IsCollapsed  = ctx.IsCollapsed
    local GetOrCreateSection = ctx.GetOrCreateSection
    local GetOrCreateSlotButton = ctx.GetOrCreateSlotButton
    local UpdateSlot   = ctx.UpdateSlot

    local Categories = addon.Categories
    local byCategory = Categories.GetPairsByCategory()
    local catList    = Categories.GetOrdered()

    HideAllLabelCells()
    HideAllDividerRows()

    local y = -TOP_PAD
    for _, cat in ipairs(catList) do
        local items = byCategory[cat.key]
        if items and #items > 0 then
            local section = GetOrCreateSection({ key = cat.key, title = cat.title })
            local collapsed = IsCollapsed(cat.key)

            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
            section.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
            section.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            section.title:SetText(cat.title)
            section.count:SetText(string.format("|cff999999%d|r", #items))
            section.header:Show()
            y = y - SECTION_HEADER_H - 2

            local rows  = math.ceil(#items / cols)
            local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
            if collapsed then bodyH = 0 end

            section.body:ClearAllPoints()
            section.body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
            section.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
            section.body:SetHeight(math.max(bodyH, 0.001))
            section.body:Show()

            if not collapsed then
                for i, p in ipairs(items) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", section.body, "TOPLEFT",
                        col * (SLOT_SIZE + SLOT_SPACING_X),
                        -row * (SLOT_SIZE + SLOT_SPACING_Y))
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                end
                y = y - bodyH - 8
            else
                y = y - 4
            end
        end
    end

    return y  -- caller uses |y| as the content height
end

---------------------------------------------------------------------------
-- Flow layout
--
-- Each category gets a thin full-width divider row (chevron + name +
-- a faint horizontal rule that runs to the right edge). Items pack
-- in a regular grid below the divider; when items wrap, they wrap
-- inside that category. The next category always starts on a fresh
-- row with its own divider, so the eye reads top-to-bottom in clean
-- chapters instead of hunting for inline pills.
--
-- Compared to Sections this saves vertical space (one ~18 px line
-- per category instead of a full chrome header), and unlike the
-- earlier pill-cell flavour it never lands a label in the middle of
-- a row.
---------------------------------------------------------------------------

local FLOW_DIVIDER_GAP_BELOW = 4   -- gap between divider and first item row
local FLOW_CATEGORY_GAP      = 6   -- gap between one category's items and the next divider

function Layouts.RenderFlow(ctx)
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

    -- Hide bag-mode section chrome and the Hybrid pill cells in case
    -- the user just switched layouts.
    for _, sec in pairs(addon.Bag.sections) do
        sec.header:Hide()
        sec.body:Hide()
    end
    HideAllLabelCells()
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

            y = y - DIVIDER_HEIGHT - FLOW_DIVIDER_GAP_BELOW

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
                y = y - bodyH - FLOW_CATEGORY_GAP
            else
                y = y - FLOW_CATEGORY_GAP
            end
        end
    end

    return y
end

---------------------------------------------------------------------------
-- Hybrid layout
--
-- Sections rendering with a tweak: when a category's last row is
-- partial and the *next* category's items would fit in the remaining
-- columns, the next category gets an inline pill label + its items
-- packed onto the same partial row instead of starting a fresh
-- header + row of its own. Anything that doesn't fit reverts to the
-- normal section header treatment.
--
-- This is the most code but produces the densest readable layout.
-- Categories with many items still get their own clear header; tiny
-- 1-2 item categories stop wasting whole rows.
---------------------------------------------------------------------------

function Layouts.RenderHybrid(ctx)
    local frame        = ctx.frame
    local cols         = ctx.cols
    local SLOT_SIZE    = ctx.SLOT_SIZE
    local SLOT_SPACING_X = ctx.SLOT_SPACING_X
    local SLOT_SPACING_Y = ctx.SLOT_SPACING_Y
    local SECTION_HEADER_H = ctx.SECTION_HEADER_H
    local SIDE_PAD     = ctx.SIDE_PAD
    local TOP_PAD      = ctx.TOP_PAD
    local IsCollapsed  = ctx.IsCollapsed
    local SetCollapsed = ctx.SetCollapsed
    local GetOrCreateSection = ctx.GetOrCreateSection
    local GetOrCreateSlotButton = ctx.GetOrCreateSlotButton
    local UpdateSlot   = ctx.UpdateSlot
    local Refresh      = ctx.Refresh

    local Categories = addon.Categories
    local byCategory = Categories.GetPairsByCategory()
    local catList    = Categories.GetOrdered()

    HideAllLabelCells()
    HideAllDividerRows()
    -- Hide all sections up front; we'll re-show as we render.
    for _, sec in pairs(addon.Bag.sections) do
        sec.header:Hide()
        sec.body:Hide()
    end

    local y = -TOP_PAD
    local rowCol = 0  -- current column offset within the active row
    local rowY   = nil -- y of the current partial row (nil when no row open)

    local function StartFreshRow()
        rowCol = 0
        rowY   = y
    end

    for catIdx, cat in ipairs(catList) do
        local items = byCategory[cat.key]
        if items and #items > 0 then
            local collapsed = IsCollapsed(cat.key)

            -- Decide: inline-pack into the existing partial row, or
            -- start a fresh section header?
            -- Inline if: there's an open partial row with room for a
            -- 2-cell label + at least one item, AND the category's
            -- item count would fit on this single shared row.
            local canInline = rowY ~= nil
                and (cols - rowCol) >= (LABEL_CELLS_WIDE + 1)
                and (#items <= (cols - rowCol - LABEL_CELLS_WIDE))
                and not collapsed

            if canInline then
                -- Inline pill label + items continuing on the current row.
                local lbl = GetOrCreateLabelCell(frame, cat.key, SLOT_SIZE, SLOT_SPACING_X)
                lbl:ClearAllPoints()
                lbl:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    SIDE_PAD + rowCol * (SLOT_SIZE + SLOT_SPACING_X), rowY)
                lbl.text:SetText(cat.title)
                lbl.toggle:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
                local key = cat.key
                lbl:SetScript("OnClick", function()
                    SetCollapsed(key, not IsCollapsed(key))
                    if Refresh then Refresh() end
                end)
                lbl:Show()
                rowCol = rowCol + LABEL_CELLS_WIDE

                for _, p in ipairs(items) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        SIDE_PAD + rowCol * (SLOT_SIZE + SLOT_SPACING_X), rowY)
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                    rowCol = rowCol + 1
                end
            else
                -- Full section: header + grid.
                local section = GetOrCreateSection({ key = cat.key, title = cat.title })

                section.header:ClearAllPoints()
                section.header:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
                section.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
                section.toggle:SetTexture(collapsed
                    and "Interface\\Buttons\\UI-PlusButton-Up"
                    or  "Interface\\Buttons\\UI-MinusButton-Up")
                section.title:SetText(cat.title)
                section.count:SetText(string.format("|cff999999%d|r", #items))
                section.header:Show()
                y = y - SECTION_HEADER_H - 2

                local rows  = math.ceil(#items / cols)
                local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
                if collapsed then bodyH = 0 end

                section.body:ClearAllPoints()
                section.body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
                section.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
                section.body:SetHeight(math.max(bodyH, 0.001))
                section.body:Show()

                if not collapsed then
                    for i, p in ipairs(items) do
                        local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                        local col = (i - 1) % cols
                        local row = math.floor((i - 1) / cols)
                        btn:ClearAllPoints()
                        btn:SetPoint("TOPLEFT", section.body, "TOPLEFT",
                            col * (SLOT_SIZE + SLOT_SPACING_X),
                            -row * (SLOT_SIZE + SLOT_SPACING_Y))
                        btn:Show()
                        UpdateSlot(btn, p.bagID, p.slotID)
                    end
                    y = y - bodyH - 8

                    -- If the last row is partial, keep it open for inline
                    -- packing of the next small category. Last row's top
                    -- in frame coordinates after the section completes is
                    -- always (y + SLOT_SIZE + 8) regardless of how many
                    -- rows the section has — the +8 is the BLOCK_GAP we
                    -- subtracted from y just above; the SLOT_SIZE puts
                    -- us at the top of the *last* row instead of below
                    -- the section as a whole.
                    local lastRowItems = #items - (rows - 1) * cols
                    if not collapsed and lastRowItems < cols then
                        rowCol = lastRowItems
                        rowY   = y + SLOT_SIZE + 8
                    else
                        rowCol = 0
                        rowY   = nil
                    end
                else
                    y = y - 4
                    rowCol = 0
                    rowY   = nil
                end
            end
        end
    end

    return y
end
