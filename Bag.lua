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
    frame.tokens = CreateFrame("Frame", nil, frame)
    -- Final size + position is set in Refresh() — height matches the
    -- money frame so the two rows feel like a pair, width sizes to
    -- the visible entries.

    frame.tokens.border = CreateFrame("Frame", nil, frame.tokens, "ContainerFrameCurrencyBorderTemplate")
    frame.tokens.border.leftEdge   = "common-currencybox-left"
    frame.tokens.border.rightEdge  = "common-currencybox-right"
    frame.tokens.border.centerEdge = "_common-currencybox-center"
    frame.tokens.border:SetPoint("LEFT")
    frame.tokens.border:SetPoint("RIGHT")
    -- Invoke the template's OnLoad manually so the three border
    -- pieces pick up our green-currency atlases (template only
    -- reads .leftEdge/.rightEdge/.centerEdge from KeyValues at OnLoad).
    if ContainerFrameCurrencyBorderMixin and ContainerFrameCurrencyBorderMixin.OnLoad then
        ContainerFrameCurrencyBorderMixin.OnLoad(frame.tokens.border)
    end

    -- Click anywhere on the row → open Blizzard's full TokenFrame
    -- (where the user manages "Show on Backpack" per currency).
    frame.tokens:EnableMouse(true)
    frame.tokens:SetScript("OnMouseDown", function()
        if CharacterFrame and CharacterFrame.ToggleTokenFrame then
            CharacterFrame:ToggleTokenFrame()
        end
    end)

    -- Pool of per-currency entries (count text + icon). Sized to
    -- match BackpackTokenTemplate (50 x 12) so a row of them at the
    -- panel's bottom looks identical to Blizzard's.
    frame.tokens.entries = {}

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

local TOKEN_ENTRY_W    = 50    -- match BackpackTokenTemplate width
local TOKEN_ENTRY_H    = 12    -- match BackpackTokenTemplate height
local TOKEN_ICON_SIZE  = 10    -- a touch smaller than Blizzard's 12 so icons sit comfortably inside the 17-tall green border with no clipping
local TOKEN_ICON_Y     = 0     -- y=0 keeps icon perfectly centered (Blizzard uses y=1, which can clip on smaller borders)
local TOKEN_GAP        = 0     -- BackpackTokenFrameMixin:GetTokenLayout uses x-spacing=0
local TOKEN_RIGHT_PAD  = 17    -- BackpackTokenFrameMixin:GetInitialTokenAnchor uses RIGHT,-17,-1
local TOKEN_LEFT_PAD   = 17    -- mirror right pad so the green box looks symmetric
local TOKEN_TEXT_H     = 10    -- BackpackTokenTemplate.Count Size y="10" — keeps the glyphs vertically centered with the icon

local function GetOrCreateTokenEntry(parent, idx)
    if parent.entries[idx] then return parent.entries[idx] end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(TOKEN_ENTRY_W, TOKEN_ENTRY_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(TOKEN_ICON_SIZE, TOKEN_ICON_SIZE)
    btn.icon:SetPoint("RIGHT", 0, TOKEN_ICON_Y)

    -- FontString height fixed to TOKEN_TEXT_H so its glyph baseline
    -- sits vertically aligned with the icon's center. Anchor RIGHT
    -- to icon.LEFT (centered y) instead of TOPLEFT — Blizzard's
    -- TOPLEFT anchor only happens to align because their button
    -- height equals their text height; ours doesn't.
    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.count:SetJustifyH("RIGHT")
    btn.count:SetHeight(TOKEN_TEXT_H)
    btn.count:SetPoint("RIGHT", btn.icon, "LEFT", -3, 0)

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

local function UpdateTokens()
    if not frame or not frame.tokens then return false end

    local tokens = frame.tokens
    local visible = 0

    for i = 1, 30 do  -- ample upper bound; loop breaks at first nil
        local info = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
            and C_CurrencyInfo.GetBackpackCurrencyInfo(i) or nil
        if not info then break end

        visible = visible + 1
        local btn = GetOrCreateTokenEntry(tokens, visible)
        btn._index      = i
        btn._currencyID = info.currencyTypesID
        btn.icon:SetTexture(info.iconFileID)
        btn.count:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(info.quantity or 0) or tostring(info.quantity or 0))
        btn:Show()
    end

    -- Hide trailing entries that aren't needed anymore
    for i = visible + 1, #tokens.entries do
        tokens.entries[i]:Hide()
    end

    -- Layout entries right-to-left so they stack like coins.
    -- entries[1] is the rightmost token (matches Blizzard's
    -- TopRightToBottomLeft grid direction in BackpackTokenFrame).
    for i = 1, visible do
        local btn = tokens.entries[i]
        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint("RIGHT", tokens, "RIGHT", -TOKEN_RIGHT_PAD, 0)
        else
            btn:SetPoint("RIGHT", tokens.entries[i - 1], "LEFT", -TOKEN_GAP, 0)
        end
    end

    return visible
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

    -- Compute bottom padding based on which footer rows the user
    -- has enabled. Both shown → room for two stacked rows. One
    -- shown → one row. Neither → just panel border padding.
    local showMoney  = addon:GetSetting("showMoney")  ~= false
    local showTokens = addon:GetSetting("showTokens") ~= false
    local visibleRows = (showMoney and 1 or 0) + (showTokens and 1 or 0)
    local bottomPad
    if visibleRows == 2 then
        bottomPad = BOTTOM_PAD
    elseif visibleRows == 1 then
        bottomPad = 36
    else
        bottomPad = 12
    end
    frame:SetHeight(math.abs(y) + bottomPad)

    -- Title — toggle between BazBags and Blizzard's default.
    if frame.SetTitle then
        local useDefault = addon:GetSetting("useDefaultTitle") and true or false
        frame:SetTitle(useDefault and (COMBINED_BAG_TITLE or "Combined Backpack") or "BazBags")
    end

    -- Tracked currencies — only update + show if the user enabled
    -- the row AND has at least one currency marked Show on Backpack.
    local tokenCount = 0
    if showTokens then tokenCount = UpdateTokens() or 0 end
    local hasTokens = tokenCount > 0

    if hasTokens then
        -- Dynamic width: left cap + entries (each TOKEN_ENTRY_W with
        -- TOKEN_GAP between) + right cap. Symmetric with the money
        -- frame's gold border.
        local contentW = tokenCount * TOKEN_ENTRY_W
                       + math.max(0, tokenCount - 1) * TOKEN_GAP
        local totalW   = contentW + TOKEN_LEFT_PAD + TOKEN_RIGHT_PAD

        frame.tokens:Show()
        frame.tokens:ClearAllPoints()
        frame.tokens:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
        frame.tokens:SetWidth(totalW)
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

        -- Match the tokens row height to the money row height so the
        -- two pill-shaped boxes feel like a coordinated pair. The
        -- money frame's height is set by MoneyFrame_Update earlier
        -- in this branch, so by here it's stable for this refresh.
        if hasTokens and frame.money:IsShown() then
            local h = frame.money:GetHeight()
            if h and h > 0 then
                frame.tokens:SetHeight(h)
            end
        end
    end

    -- Fallback height if money is hidden but tokens are shown. Use a
    -- sensible default so the row still has presence.
    if hasTokens and not frame.money:IsShown() then
        frame.tokens:SetHeight(20)
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
events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")    -- watched-currency value or watch-state changes
events:SetScript("OnEvent", ScheduleRefresh)

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
