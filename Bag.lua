---------------------------------------------------------------------------
-- BazBags — bag panel UI
--
-- A faithful clone of Blizzard's combined-bag panel chrome:
--   * Frame: BazCore:CreatePortraitWindow → PortraitFrameFlatTemplate
--   * Slots: ContainerFrameItemButtonTemplate (Blizzard's own template,
--            including ItemSlotBackgroundCombinedBagsTemplate background
--            via :Initialize() — that's what fixes the "blue tint" on
--            empty slots; the leather/brown atlas only renders when the
--            slot's parent reports IsCombinedBagContainer() == true)
--   * Money:  ContainerMoneyFrameTemplate
--   * Search: BagSearchBoxTemplate
--   * Sort:   bags-button-autosort-up/down atlases
--
-- Layered on top of the clone: collapsible sections per bag type
-- (Bags + Reagents) — fold either away in the same window instead
-- of the separate-window UX Blizzard ships.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

local Bag = {}
addon.Bag = Bag

---------------------------------------------------------------------------
-- Layout constants — chosen to match Blizzard's combined bag exactly.
---------------------------------------------------------------------------

local DEFAULT_COLS      = 8       -- starting column count when no setting saved
local SLOT_SIZE         = 37      -- ContainerFrameItemButtonTemplate native size
local SLOT_SPACING_X    = 5       -- Blizzard's ITEM_SPACING_X
local SLOT_SPACING_Y    = 4
local SECTION_HEADER_H  = 20
local TOP_PAD           = 60      -- below title bar — leaves room for search/sort row
local BOTTOM_PAD        = 64      -- above footer (room for money + optional token row)
local SIDE_PAD          = 12

-- Live setting readers — re-evaluated on every Refresh so the panel
-- reshapes immediately when the user moves the Columns slider or
-- toggles Hide Empty on the General Settings page.
local function GetCols()
    local v = addon:GetSetting("cols")
    return (type(v) == "number" and v >= 1) and v or DEFAULT_COLS
end

local function HideEmpty()
    return addon:GetSetting("hideEmpty") and true or false
end

local function PanelWidthFor(cols)
    return cols * SLOT_SIZE + math.max(0, cols - 1) * SLOT_SPACING_X + SIDE_PAD * 2
end

-- Bag type → section definition. Order is the visual order top-to-bottom.
local SECTIONS = {
    {
        key    = "bags",
        title  = "Bags",
        bagIDs = {
            Enum.BagIndex.Backpack,
            Enum.BagIndex.Bag_1,
            Enum.BagIndex.Bag_2,
            Enum.BagIndex.Bag_3,
            Enum.BagIndex.Bag_4,
        },
    },
    {
        key    = "reagents",
        title  = "Reagents",
        bagIDs = {
            Enum.BagIndex.ReagentBag,
        },
    },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame                       -- top-level panel
local bagContexts   = {}          -- [bagID] = invisible parent (provides GetID + IsCombinedBagContainer for slots)
local slotButtons   = {}          -- [bagID] = { [slotID] = button }
local sections      = {}          -- [key]   = { header, body, ... }
local refreshPending = false

---------------------------------------------------------------------------
-- Section collapse persistence
---------------------------------------------------------------------------

local function IsCollapsed(key)
    local map = addon:GetSetting("sectionCollapsed") or {}
    return map[key] and true or false
end

local function SetCollapsed(key, val)
    local map = addon:GetSetting("sectionCollapsed") or {}
    map[key] = val and true or false
    addon:SetSetting("sectionCollapsed", map)
end

---------------------------------------------------------------------------
-- Bag context frames + item slot construction
--
-- Each slot needs to be parented to a frame whose GetID() returns the
-- bag ID. The slot template's mixin reads `parent:IsCombinedBagContainer()`
-- in Initialize() — when that returns true, it adds the proper
-- ItemSlotBackgroundCombinedBagsTemplate texture (leather/brown art),
-- which is what makes empty slots look like Blizzard's combined bag
-- instead of the default ItemButton "blue square" appearance.
---------------------------------------------------------------------------

local function GetOrCreateBagContext(bagID)
    if bagContexts[bagID] then return bagContexts[bagID] end
    local f = CreateFrame("Frame", nil, frame)
    f:SetID(bagID)
    f:SetSize(1, 1)
    -- Blizzard's slot Initialize checks this to add the combined-bag bg.
    f.IsCombinedBagContainer = function() return true end
    bagContexts[bagID] = f
    return f
end

local function GetOrCreateSlotButton(bagID, slotID)
    slotButtons[bagID] = slotButtons[bagID] or {}
    if slotButtons[bagID][slotID] then return slotButtons[bagID][slotID] end

    local parent = GetOrCreateBagContext(bagID)
    local name = "BazBagSlot_" .. bagID .. "_" .. slotID
    local btn = CreateFrame("ItemButton", name, parent, "ContainerFrameItemButtonTemplate")

    -- Initialize handles SetID, SetBagID attribute, ItemSlotBackground
    -- (the combined-bag leather background), and Show. Without this we
    -- get the default empty-slot appearance, which is the source of the
    -- blue tint on empty slots reported earlier.
    if btn.Initialize then
        btn:Initialize(bagID, slotID)
    else
        btn:SetID(slotID)
    end

    slotButtons[bagID][slotID] = btn
    return btn
end

---------------------------------------------------------------------------
-- Slot rendering — mirrors ContainerFrameMixin:UpdateItems exactly.
---------------------------------------------------------------------------

local function UpdateSlot(btn, bagID, slotID)
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    local texture   = info and info.iconFileID
    local count     = info and info.stackCount
    local locked    = info and info.isLocked
    local quality   = info and info.quality
    local link      = info and info.hyperlink
    local isFiltered = info and info.isFiltered
    local noValue   = info and info.hasNoValue
    local isBound   = info and info.isBound

    local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slotID)
    local isQuestItem = questInfo and questInfo.isQuestItem
    local questID     = questInfo and questInfo.questID
    local isActive    = questInfo and questInfo.isActive

    if ClearItemButtonOverlay then ClearItemButtonOverlay(btn) end

    if btn.SetHasItem then btn:SetHasItem(texture) end
    SetItemButtonTexture(btn, texture)
    SetItemButtonQuality(btn, quality, link, false, isBound)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)

    if btn.UpdateExtended         then btn:UpdateExtended() end
    if btn.UpdateQuestItem        then btn:UpdateQuestItem(isQuestItem, questID, isActive) end
    if btn.UpdateNewItem          then btn:UpdateNewItem(quality) end
    if btn.UpdateJunkItem         then btn:UpdateJunkItem(quality, noValue) end
    if btn.UpdateItemContextMatching then btn:UpdateItemContextMatching() end
    if btn.UpdateCooldown         then btn:UpdateCooldown(texture) end
    if btn.SetReadable            then btn:SetReadable(info and info.IsReadable) end
    if btn.SetMatchesSearch       then btn:SetMatchesSearch(not isFiltered) end
end

---------------------------------------------------------------------------
-- Section builder
---------------------------------------------------------------------------

local function BuildSection(def)
    local section = { def = def }

    local header = CreateFrame("Button", nil, frame)
    header:SetHeight(SECTION_HEADER_H)
    section.header = header

    local hover = header:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.04)
    hover:Hide()

    local toggle = header:CreateTexture(nil, "OVERLAY")
    toggle:SetSize(14, 14)
    toggle:SetPoint("LEFT", 4, 0)
    section.toggle = toggle

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", toggle, "RIGHT", 6, 0)
    title:SetText(def.title)
    title:SetTextColor(1.00, 0.82, 0.00)  -- suite gold to read as a "Baz section"
    section.title = title

    local count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("RIGHT", -8, 0)
    section.count = count

    header:SetScript("OnEnter", function() hover:Show() end)
    header:SetScript("OnLeave", function() hover:Hide() end)
    header:SetScript("OnClick", function()
        SetCollapsed(def.key, not IsCollapsed(def.key))
        Bag:Refresh()
    end)

    -- Body holds the slot buttons. Height is computed in Refresh().
    local body = CreateFrame("Frame", nil, frame)
    section.body = body

    return section
end

---------------------------------------------------------------------------
-- Top-level panel
---------------------------------------------------------------------------

local function BuildFrame()
    if frame then return frame end

    local panelW = PanelWidthFor(GetCols())

    -- BazCore handles the Blizzard-styled chrome (PortraitFrameFlatTemplate)
    -- including title bar, portrait, close button, drag, and ESC-close.
    -- Anything bag-specific (search, sort, money, slots) we add ourselves.
    frame = BazCore:CreatePortraitWindow("BazBagsFrame", {
        title          = "BazBags",
        portrait       = 5160585,  -- inv_misc_bag_horadricsatchel
        width          = panelW,
        height         = 400,
        savedAddon     = addon,
        savedKey       = "position",
        uiSpecialFrame = true,
    })

    -- Auto-sort button — Blizzard atlases at Blizzard's exact anchor
    -- (-9, -34) and size (28x26). Matches the combined-bag layout from
    -- ContainerFrame.lua:978 so it lines up vertically with the search
    -- box at TOPLEFT 62, -37 (centers within ~1 px of each other).
    frame.sort = CreateFrame("Button", nil, frame)
    frame.sort:SetSize(28, 26)
    frame.sort:SetNormalAtlas("bags-button-autosort-up")
    frame.sort:SetPushedAtlas("bags-button-autosort-down")
    frame.sort:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.sort:SetPoint("TOPRIGHT", -9, -34)
    frame.sort:SetScript("OnClick", function()
        if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        end
        if C_Container and C_Container.SortBags then
            C_Container.SortBags()
        end
    end)
    frame.sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self)
        GameTooltip_SetTitle(GameTooltip, BAG_CLEANUP_BAGS or "Clean Up Bags", HIGHLIGHT_FONT_COLOR)
        if BAG_CLEANUP_BAGS_DESCRIPTION then
            GameTooltip_AddNormalLine(GameTooltip, BAG_CLEANUP_BAGS_DESCRIPTION)
        end
        GameTooltip:Show()
    end)
    frame.sort:SetScript("OnLeave", GameTooltip_Hide)

    -- Search box — Blizzard's BagSearchBoxTemplate handles the icon,
    -- placeholder text, focus/blur visuals, and live filtering of
    -- ContainerFrameItemButton instances via SetMatchesSearch.
    frame.search = CreateFrame("EditBox", nil, frame, "BagSearchBoxTemplate")
    frame.search:SetHeight(18)
    frame.search:SetPoint("TOPLEFT", 62, -37)               -- Blizzard's exact anchor
    frame.search:SetPoint("RIGHT", frame.sort, "LEFT", -4, 0)

    -- Token (tracked-currency) row — full-width green-bordered box
    -- below the money row. Mirrors Blizzard's BackpackTokenFrame
    -- visually but built ourselves so we don't fight Blizzard for
    -- ownership of the singleton BackpackTokenFrame instance.
    -- Tracked-currency container. Holds an array of "row frames" —
    -- each row is its own green-bordered pill with its own tokens.
    -- When the user watches more currencies than fit on a single
    -- row, additional rows are added above so we can carry as many
    -- as they like without spilling off the side of the panel.
    frame.tokens = CreateFrame("Frame", nil, frame)
    frame.tokens.rows    = {}   -- array of row frames (built lazily)
    frame.tokens.entries = {}   -- flat pool of per-currency entries

    -- Money frame — Blizzard's exact gold/silver/copper readout.
    -- Position is set in Refresh() so we can stack it above the
    -- token row when currencies are visible, or alone at the bottom
    -- when there are none.
    frame.money = CreateFrame("Frame", nil, frame, "ContainerMoneyFrameTemplate")

    -- Build sections
    for _, def in ipairs(SECTIONS) do
        sections[def.key] = BuildSection(def)
    end

    return frame
end

---------------------------------------------------------------------------
-- Tracked-currency row update
--
-- Reads C_CurrencyInfo.GetBackpackCurrencyInfo iteratively until it
-- returns nil. Per-currency entries are pooled — we lazily create
-- new ones if the user starts watching more, and hide the trailing
-- ones if they unwatch some.
--
-- Each entry mirrors Blizzard's BackpackTokenTemplate visually:
-- 50 px wide button, 12 px icon on the right, count text right-
-- aligned to the icon's left. The whole row is itself anchored
-- right-to-left from the green border's right cap, so multiple
-- currencies stack like coins.
---------------------------------------------------------------------------

local TOKEN_ENTRY_H      = 12    -- match BackpackTokenTemplate height
local TOKEN_ICON_SIZE    = 10    -- a touch smaller than Blizzard's 12 so icons sit comfortably inside the 17-tall green border with no clipping
local TOKEN_ICON_Y       = 0     -- y=0 keeps icon perfectly centered (Blizzard uses y=1, which can clip on smaller borders)
local TOKEN_TEXT_ICON_GAP = 3    -- horizontal spacing between count text and its own icon
local TOKEN_GAP          = 10    -- horizontal spacing BETWEEN currency entries; tuned so short and long counts look evenly spaced
local TOKEN_RIGHT_PAD    = 14    -- inset from green border's right cap to first icon
local TOKEN_LEFT_PAD     = 14    -- mirror right pad so the green box looks symmetric
local TOKEN_TEXT_H       = 10    -- BackpackTokenTemplate.Count Size y="10" — keeps the glyphs vertically centered with the icon

local function GetOrCreateTokenEntry(parent, idx)
    if parent.entries[idx] then return parent.entries[idx] end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(TOKEN_ENTRY_H)
    -- Width is set per-render in UpdateTokens — depends on the
    -- count text length so entries don't carry dead space.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(TOKEN_ICON_SIZE, TOKEN_ICON_SIZE)
    btn.icon:SetPoint("RIGHT", 0, TOKEN_ICON_Y)

    -- Count text height fixed so its glyph baseline aligns with the
    -- icon center. Anchor RIGHT to icon.LEFT (centered y) and LEFT to
    -- the button's LEFT — text fills the button width with right-
    -- alignment, so the dynamic button width effectively sizes the
    -- text region.
    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.count:SetJustifyH("RIGHT")
    btn.count:SetHeight(TOKEN_TEXT_H)
    btn.count:SetPoint("LEFT")
    btn.count:SetPoint("RIGHT", btn.icon, "LEFT", -TOKEN_TEXT_ICON_GAP, 0)

    btn:SetScript("OnEnter", function(self)
        if not self._currencyID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetCurrencyByID then
            GameTooltip:SetCurrencyByID(self._currencyID)
        elseif GameTooltip.SetCurrencyToken then
            GameTooltip:SetCurrencyToken(self._index)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        -- Same behaviour as BackpackTokenMixin: open the full token UI
        -- where users can manage Show on Backpack per currency.
        if CharacterFrame and CharacterFrame.ToggleTokenFrame then
            CharacterFrame:ToggleTokenFrame()
        end
    end)

    parent.entries[idx] = btn
    return btn
end

local TOKEN_ROW_GAP    = 4    -- vertical gap between stacked token rows
local TOKEN_ROW_HEIGHT = nil  -- set in UpdateTokens to match money height

-- Build (or fetch) a row frame — its own green-bordered pill that
-- can hold a horizontal strip of token entries.
local function GetOrCreateTokenRow(parent, idx)
    if parent.rows[idx] then return parent.rows[idx] end

    local row = CreateFrame("Frame", nil, parent)
    row.entries = {}

    row.border = CreateFrame("Frame", nil, row, "ContainerFrameCurrencyBorderTemplate")
    row.border.leftEdge   = "common-currencybox-left"
    row.border.rightEdge  = "common-currencybox-right"
    row.border.centerEdge = "_common-currencybox-center"
    row.border:SetPoint("LEFT")
    row.border:SetPoint("RIGHT")
    if ContainerFrameCurrencyBorderMixin and ContainerFrameCurrencyBorderMixin.OnLoad then
        ContainerFrameCurrencyBorderMixin.OnLoad(row.border)
    end

    -- Click anywhere on a row → open Blizzard's TokenFrame for
    -- managing Show on Backpack.
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function()
        if CharacterFrame and CharacterFrame.ToggleTokenFrame then
            CharacterFrame:ToggleTokenFrame()
        end
    end)

    parent.rows[idx] = row
    return row
end

-- Build / refresh / size every entry, then pack them into rows
-- (right-to-left, top to bottom). Returns (rowCount, maxRowWidth)
-- so the caller can size the parent token frame.
local function UpdateTokens(maxRowWidth)
    if not frame or not frame.tokens then return 0, 0 end
    if not maxRowWidth or maxRowWidth <= 0 then maxRowWidth = 200 end

    local tokens = frame.tokens

    -- Step 1: build / refresh entries, sized to text content
    local visible = 0
    for i = 1, 50 do  -- ample upper bound; loop breaks at first nil
        local info = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
            and C_CurrencyInfo.GetBackpackCurrencyInfo(i) or nil
        if not info then break end

        visible = visible + 1
        local btn = GetOrCreateTokenEntry(tokens, visible)
        btn._index      = i
        btn._currencyID = info.currencyTypesID
        btn.icon:SetTexture(info.iconFileID)
        btn.count:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(info.quantity or 0) or tostring(info.quantity or 0))

        local textW = btn.count:GetStringWidth() or 0
        btn:SetWidth(textW + TOKEN_TEXT_ICON_GAP + TOKEN_ICON_SIZE)
        btn:Show()
    end

    -- Hide trailing entries no longer in use
    for i = visible + 1, #tokens.entries do
        tokens.entries[i]:Hide()
    end

    if visible == 0 then
        -- Hide all rows
        for _, row in ipairs(tokens.rows) do row:Hide() end
        return 0, 0
    end

    -- Step 2: greedy-pack entries into rows, right-to-left.
    -- Row 0 is the bottom-most row; if a row fills up, overflow
    -- entries go into row 1 (above), then row 2 (further above).
    local rowAvail = maxRowWidth - TOKEN_LEFT_PAD - TOKEN_RIGHT_PAD
    local rowAssignments = {}  -- [rowIdx] = { entryIdx, entryIdx, ... }
    local rowWidths      = {}  -- [rowIdx] = current content width
    local currentRow = 1
    rowAssignments[currentRow] = {}
    rowWidths[currentRow] = 0

    for i = 1, visible do
        local btn = tokens.entries[i]
        local btnW = btn:GetWidth() or 0
        local addedW = btnW + (#rowAssignments[currentRow] > 0 and TOKEN_GAP or 0)
        if rowWidths[currentRow] + addedW > rowAvail and #rowAssignments[currentRow] > 0 then
            -- Wrap to next row
            currentRow = currentRow + 1
            rowAssignments[currentRow] = {}
            rowWidths[currentRow] = 0
            addedW = btnW
        end
        table.insert(rowAssignments[currentRow], i)
        rowWidths[currentRow] = rowWidths[currentRow] + addedW
    end

    local rowCount = currentRow
    local rowHeight = TOKEN_ROW_HEIGHT or 17

    -- Step 3: position each row and assign entries to it
    -- Row 1 (the row containing the rightmost / first-fetched
    -- currencies) sits at the BOTTOM. Additional rows stack upward.
    local maxFullRowW = 0
    for r = 1, rowCount do
        local row = GetOrCreateTokenRow(tokens, r)
        local fullW = rowWidths[r] + TOKEN_LEFT_PAD + TOKEN_RIGHT_PAD
        if fullW > maxFullRowW then maxFullRowW = fullW end

        row:Show()
        row:SetSize(fullW, rowHeight)
        row:ClearAllPoints()
        row:SetPoint("BOTTOMRIGHT", tokens, "BOTTOMRIGHT", 0,
            (r - 1) * (rowHeight + TOKEN_ROW_GAP))

        -- Anchor this row's entries
        for col, entryIdx in ipairs(rowAssignments[r]) do
            local btn = tokens.entries[entryIdx]
            btn:SetParent(row)
            btn:ClearAllPoints()
            if col == 1 then
                btn:SetPoint("RIGHT", row, "RIGHT", -TOKEN_RIGHT_PAD, 0)
            else
                local prevIdx = rowAssignments[r][col - 1]
                btn:SetPoint("RIGHT", tokens.entries[prevIdx], "LEFT", -TOKEN_GAP, 0)
            end
        end
    end

    -- Hide any extra row frames left over from a previous render
    for r = rowCount + 1, #tokens.rows do
        tokens.rows[r]:Hide()
    end

    return rowCount, maxFullRowW
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Bag:Refresh()
    if not frame then return end

    -- Live settings — re-read on every refresh so toggling the Columns
    -- slider or Hide Empty toggle applies immediately.
    local cols       = GetCols()
    local hideEmpty  = HideEmpty()

    -- Resize the panel width to match the column count. The search bar
    -- + sort button + money frame are anchored relative to the panel
    -- edges so they reflow automatically.
    frame:SetWidth(PanelWidthFor(cols))

    -- Hide every existing slot button up front. Anything we still want
    -- visible gets re-shown + repositioned in the layout loop. This is
    -- the simplest way to handle (a) Hide Empty on/off, (b) bag size
    -- shrinking, and (c) section-collapsed-this-frame all at once.
    for _, slots in pairs(slotButtons) do
        for _, btn in pairs(slots) do
            btn:Hide()
        end
    end

    local y = -TOP_PAD

    for _, def in ipairs(SECTIONS) do
        local section = sections[def.key]
        local collapsed = IsCollapsed(def.key)

        -- Header
        section.header:ClearAllPoints()
        section.header:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
        section.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
        section.toggle:SetTexture(collapsed
            and "Interface\\Buttons\\UI-PlusButton-Up"
            or  "Interface\\Buttons\\UI-MinusButton-Up")
        y = y - SECTION_HEADER_H - 2

        -- Collect (bag, slot) pairs. When Hide Empty is on, skip slots
        -- that don't currently hold an item.
        local pairs_list = {}
        for _, bagID in ipairs(def.bagIDs) do
            local n = C_Container.GetContainerNumSlots(bagID) or 0
            for slotID = 1, n do
                if hideEmpty then
                    local info = C_Container.GetContainerItemInfo(bagID, slotID)
                    if info and info.iconFileID then
                        pairs_list[#pairs_list + 1] = { bagID = bagID, slotID = slotID }
                    end
                else
                    pairs_list[#pairs_list + 1] = { bagID = bagID, slotID = slotID }
                end
            end
        end

        -- Section count e.g. "3 / 24"
        local total, free = 0, 0
        for _, bagID in ipairs(def.bagIDs) do
            free  = free  + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
            total = total + (C_Container.GetContainerNumSlots(bagID) or 0)
        end
        section.count:SetText(string.format("|cff999999%d / %d|r", total - free, total))

        -- Body layout
        local rows  = math.ceil(#pairs_list / cols)
        local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
        if collapsed then bodyH = 0 end

        section.body:ClearAllPoints()
        section.body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
        section.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
        section.body:SetHeight(math.max(bodyH, 0.001))

        if not collapsed then
            for i, p in ipairs(pairs_list) do
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
        end

        if not collapsed then
            y = y - bodyH - 8
        else
            y = y - 4
        end
    end

    -- Compute bottom padding. Money is one row (~24 px). Tokens may
    -- now be multiple rows so we have to look at the live frame.
    -- Set the panel height once we've laid the footer below.
    local showMoney  = addon:GetSetting("showMoney")  ~= false
    local showTokens = addon:GetSetting("showTokens") ~= false
    -- Provisional placeholder; the real bottom pad depends on token
    -- row count which we compute below. We'll re-set the panel
    -- height after that's known.
    local provisional = (showMoney and 1 or 0) + (showTokens and 1 or 0)
    local bottomPad   = (provisional == 0) and 12 or 36
    frame:SetHeight(math.abs(y) + bottomPad)

    -- Title — toggle between BazBags and Blizzard's default.
    if frame.SetTitle then
        local useDefault = addon:GetSetting("useDefaultTitle") and true or false
        frame:SetTitle(useDefault and (COMBINED_BAG_TITLE or "Combined Backpack") or "BazBags")
    end

    -- Tracked currencies — only update + show if the user enabled
    -- the row AND has at least one currency marked Show on Backpack.
    -- We pass the available row width (panel width minus the same
    -- 12 px outer padding) so UpdateTokens can pack entries into
    -- multiple rows when the user is tracking more than fit on one.
    local rowCount, maxRowW = 0, 0
    if showTokens then
        local available = (frame:GetWidth() or 0) - 24  -- 12 + 12 outer padding
        TOKEN_ROW_HEIGHT = (frame.money and frame.money:GetHeight()) or 17
        rowCount, maxRowW = UpdateTokens(available)
    end
    local hasTokens = (rowCount or 0) > 0

    if hasTokens then
        local rowHeight  = TOKEN_ROW_HEIGHT or 17
        local totalH     = rowCount * rowHeight + math.max(0, rowCount - 1) * TOKEN_ROW_GAP
        frame.tokens:Show()
        frame.tokens:ClearAllPoints()
        frame.tokens:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
        frame.tokens:SetWidth(maxRowW)
        frame.tokens:SetHeight(totalH)

        -- Re-grow panel height to fit additional token rows. Each
        -- extra row beyond the first costs rowHeight + TOKEN_ROW_GAP.
        if rowCount > 1 then
            local extra = (rowCount - 1) * (rowHeight + TOKEN_ROW_GAP)
            frame:SetHeight(frame:GetHeight() + extra)
        end
    else
        frame.tokens:Hide()
    end

    -- Money frame: refresh values, then optionally collapse to gold-only
    -- by hiding silver + copper and re-anchoring gold to the right edge
    -- of the money frame so it doesn't sit alone in the middle of empty
    -- space where silver/copper used to be.
    if frame.money then
        if not showMoney then
            frame.money:Hide()
        else
            frame.money:Show()

            -- Position: above the token row when one is shown, or at
            -- the bottom-right corner of the panel when there are no
            -- tracked currencies. The 3 px gap between rows matches
            -- Blizzard's combined-bag layout (ContainerFrame.lua:2492).
            frame.money:ClearAllPoints()
            if hasTokens then
                -- 6 px gap between the green and gold rows so they
                -- read as a coordinated pair rather than touching.
                frame.money:SetPoint("BOTTOMRIGHT", frame.tokens, "TOPRIGHT", 0, 6)
            else
                frame.money:SetPoint("BOTTOMRIGHT", -12, 12)
            end

            if MoneyFrame_Update then
                MoneyFrame_Update(frame.money:GetName() or frame.money, GetMoney())
            end

            local goldOnly = addon:GetSetting("goldOnly") and true or false
            if frame.money.SilverButton then frame.money.SilverButton:SetShown(not goldOnly) end
            if frame.money.CopperButton then frame.money.CopperButton:SetShown(not goldOnly) end
            if frame.money.GoldButton then
                frame.money.GoldButton:ClearAllPoints()
                if goldOnly then
                    -- Match Blizzard's pattern for the rightmost coin
                    -- (-13 from frame RIGHT) so the gold icon sits inside
                    -- the border's decorative right cap.
                    frame.money.GoldButton:SetPoint("RIGHT", frame.money, "RIGHT", -13, 0)
                elseif frame.money.SilverButton then
                    -- Restore the template's default anchor relationship
                    frame.money.GoldButton:SetPoint("RIGHT", frame.money.SilverButton, "LEFT", -4, 0)
                end
            end

            -- Tighten the frame width to fit visible content. See the
            -- detailed comment block elsewhere — MoneyFrame_Update's
            -- own width formula adds an iconWidth pad that nothing
            -- fills, so the gold border ends up wider than the coins.
            local mf = frame.money
            local goldB, silverB, copperB = mf.GoldButton, mf.SilverButton, mf.CopperButton
            local leftButton
            if goldB and goldB:IsShown() then leftButton = goldB
            elseif silverB and silverB:IsShown() then leftButton = silverB
            elseif copperB and copperB:IsShown() then leftButton = copperB
            end
            if leftButton then
                C_Timer.After(0, function()
                    local L = leftButton:GetLeft()
                    local R = mf:GetRight()
                    if L and R and R > L then
                        mf:SetWidth(R - L + 13)
                    end
                end)
            end
        end

    end
end

---------------------------------------------------------------------------
-- Show / Hide / Toggle
---------------------------------------------------------------------------

function Bag:Show()
    BuildFrame()
    self:Refresh()
    frame:Show()
end

function Bag:Hide()
    if frame then frame:Hide() end
end

function Bag:Toggle()
    BuildFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Refresh()
        frame:Show()
    end
end

---------------------------------------------------------------------------
-- Event-driven refresh (coalesced to one Refresh per frame)
---------------------------------------------------------------------------

local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        if frame and frame:IsShown() then
            Bag:Refresh()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")    -- watched-currency VALUE changes
events:SetScript("OnEvent", ScheduleRefresh)

-- "Show on Backpack" toggles fire an EventRegistry callback rather
-- than a regular Blizzard event (BackpackTokenFrameMixin uses the
-- same callback at Blizzard_TokenUI.lua:641). Register so we refresh
-- the moment the user marks/unmarks a currency in the Currency UI.
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("TokenFrame.OnTokenWatchChanged", ScheduleRefresh, addon)
end

---------------------------------------------------------------------------
-- Override Blizzard's bag toggles so the B key (and any addon that
-- calls these functions) opens BazBags instead of Blizzard's combined
-- bag. We replace ToggleAllBags / OpenAllBags / OpenBackpack — every
-- way Blizzard's UI normally triggers the bag opens lands on us.
--
-- Hooks happen at file-scope so they're in place before PLAYER_LOGIN.
-- Inside the replacement we still call the original function for
-- close paths, so closing all panels (escape from a UI panel) clears
-- both BazBags and any Blizzard bag state.
---------------------------------------------------------------------------

local function HookBlizzardBagToggles()
    if Bag._blizzHooked then return end
    Bag._blizzHooked = true

    local origToggleAllBags = ToggleAllBags
    ToggleAllBags = function()
        -- Mirror Blizzard's "if any bag panel is open, close all"
        -- behaviour but with our panel as the open/close target.
        if frame and frame:IsShown() then
            Bag:Hide()
        else
            Bag:Show()
        end
    end

    local origOpenAllBags = OpenAllBags
    OpenAllBags = function()
        Bag:Show()
    end

    local origOpenBackpack = OpenBackpack
    OpenBackpack = function()
        Bag:Show()
    end

    -- Closing the bag should close ours. Both names exist in Blizzard.
    if CloseAllBags then
        local origClose = CloseAllBags
        CloseAllBags = function()
            Bag:Hide()
            -- Defensive: if Blizzard's combined bag was somehow shown
            -- (e.g. another addon opened it directly), close it too.
            if origClose then pcall(origClose) end
        end
    end
end

BazCore:QueueForLogin(HookBlizzardBagToggles)

---------------------------------------------------------------------------
-- Bypass Blizzard's "TOO_MANY_WATCHED_TOKENS" cap.
--
-- Blizzard caps the number of currencies you can mark "Show on
-- Backpack" via floor(BackpackTokenFrame.width / 50). Their bag is
-- narrow so the cap is small. BazBags re-flows currencies into
-- multiple rows so we don't actually need a cap at all — patch
-- BackpackTokenFrame:GetMaxTokensWatched to return a huge number
-- so the Currency UI never refuses a toggle.
--
-- The frame doesn't exist until Blizzard_TokenUI loads (it's load
-- on demand). Force-load it, then patch.
---------------------------------------------------------------------------

local function PatchTokenCap()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TokenUI")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_TokenUI")
    end

    if BackpackTokenFrame and BackpackTokenFrame.GetMaxTokensWatched then
        BackpackTokenFrame.GetMaxTokensWatched = function() return 999 end
    end
end

BazCore:QueueForLogin(PatchTokenCap)
