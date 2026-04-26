---------------------------------------------------------------------------
-- BazBags — bag panel UI
--
-- Single combined window with one collapsible section per bag type:
--   * Bags     — main backpack + equipped bags 1-4 (Enum.BagIndex 0..4)
--   * Reagents — reagent bag (Enum.BagIndex.ReagentBag)
--
-- Each section header uses the same +/- toggle textures the User
-- Manual tree and source-grouped widget list do, so the visual
-- language stays consistent across the suite.
--
-- We use Blizzard's `ContainerFrameItemButtonTemplate` for the slots,
-- which gives us cooldown sweep, quality border, drag/drop wiring,
-- click-to-use, and all the secure handling for combat items for free.
-- The button reads its bag id from its parent frame's GetID(), so we
-- create a tiny "bag context" parent per bag id and put the buttons
-- there even though the buttons themselves are positioned in our
-- visual grid via SetPoint.
---------------------------------------------------------------------------

local ADDON_NAME = "BazBags"
local addon = BazCore:GetAddon(ADDON_NAME)
if not addon then return end

local Bag = {}
addon.Bag = Bag

---------------------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------------------

local COLS              = 8           -- slots per row
local SLOT_SIZE         = 37
local SLOT_GAP          = 2
local SECTION_HEADER_H  = 22
local PANEL_PAD         = 10
local TITLE_BAR_H       = 28
local FOOTER_H          = 28

-- Bag type → section definition. Order here is the visual order in
-- the panel (top to bottom).
local SECTIONS = {
    {
        key     = "bags",
        title   = "Bags",
        bagIDs  = {
            Enum.BagIndex.Backpack,
            Enum.BagIndex.Bag_1,
            Enum.BagIndex.Bag_2,
            Enum.BagIndex.Bag_3,
            Enum.BagIndex.Bag_4,
        },
    },
    {
        key     = "reagents",
        title   = "Reagents",
        bagIDs  = {
            Enum.BagIndex.ReagentBag,
        },
    },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame                       -- top-level panel
local bagContexts   = {}          -- [bagID] = invisible parent (provides GetID for ItemButton template)
local slotButtons   = {}          -- [bagID] = { [slotID] = button }
local sections      = {}          -- [key] = { header, body, ... } built from SECTIONS
local refreshPending = false

---------------------------------------------------------------------------
-- Helpers
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

local function GetOrCreateBagContext(bagID)
    if bagContexts[bagID] then return bagContexts[bagID] end
    local f = CreateFrame("Frame", nil, frame)
    f:SetID(bagID)
    f:SetSize(1, 1)  -- invisible — exists only to provide GetID() for child buttons
    bagContexts[bagID] = f
    return f
end

local function GetOrCreateSlotButton(bagID, slotID)
    slotButtons[bagID] = slotButtons[bagID] or {}
    if slotButtons[bagID][slotID] then return slotButtons[bagID][slotID] end

    local parent = GetOrCreateBagContext(bagID)
    local name = "BazBagSlot_" .. bagID .. "_" .. slotID
    local btn = CreateFrame("ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
    btn:SetID(slotID)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)

    slotButtons[bagID][slotID] = btn
    return btn
end

---------------------------------------------------------------------------
-- Section builder
---------------------------------------------------------------------------

local function BuildSection(def)
    local section = { def = def }

    -- Header (clickable to toggle collapse)
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

    -- Body — holds the slot buttons; height is computed in Refresh()
    local body = CreateFrame("Frame", nil, frame)
    section.body = body

    return section
end

---------------------------------------------------------------------------
-- Top-level panel
---------------------------------------------------------------------------

local function BuildFrame()
    if frame then return frame end

    local f = CreateFrame("Frame", "BazBagsFrame", UIParent, "BackdropTemplate")
    f:SetSize(COLS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + PANEL_PAD * 2, 200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:Hide()

    -- Restore saved position or default to centered
    local saved = addon:GetSetting("position")
    f:ClearAllPoints()
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point,
                   saved.x or 0, saved.y or 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon:SetSetting("position", {
            point    = point,
            relPoint = relPoint,
            x        = x,
            y        = y,
        })
    end)

    -- Backdrop — dark with gold edge, matches BNC's panel style
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
    f:SetBackdropBorderColor(0.6, 0.5, 0.2)

    -- Title bar
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetText("BazBags")

    -- Close button
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -2, -2)
    f.close:SetScript("OnClick", function() Bag:Hide() end)

    -- Sort button (bottom-left of footer)
    f.sort = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sort:SetSize(60, 22)
    f.sort:SetPoint("BOTTOMLEFT", 8, 6)
    f.sort:SetText("Sort")
    f.sort:SetScript("OnClick", function()
        if C_Container and C_Container.SortBags then
            C_Container.SortBags()
        end
    end)

    -- Free / total slots indicator (bottom-right of footer)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMRIGHT", -10, 12)

    -- ESC closes
    tinsert(UISpecialFrames, "BazBagsFrame")

    frame = f

    -- Build sections after the panel exists
    for _, def in ipairs(SECTIONS) do
        sections[def.key] = BuildSection(def)
    end

    return f
end

---------------------------------------------------------------------------
-- Slot rendering
---------------------------------------------------------------------------

local function RenderSlot(btn, bagID, slotID)
    local info = C_Container and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bagID, slotID) or nil

    if info and info.iconFileID then
        SetItemButtonTexture(btn, info.iconFileID)
        SetItemButtonCount(btn, info.stackCount or 1)
        SetItemButtonQuality(btn, info.quality, info.hyperlink)
        SetItemButtonDesaturated(btn, info.isLocked)
    else
        SetItemButtonTexture(btn, "")
        SetItemButtonCount(btn, 0)
        SetItemButtonQuality(btn, 0)
        SetItemButtonDesaturated(btn, false)
    end

    -- Cooldown
    if btn.Cooldown then
        local cd = C_Container.GetContainerItemCooldown
            and { C_Container.GetContainerItemCooldown(bagID, slotID) } or nil
        if cd and cd[1] then
            CooldownFrame_Set(btn.Cooldown, cd[1], cd[2], cd[3])
        else
            btn.Cooldown:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Refresh — primary layout + content update
---------------------------------------------------------------------------

function Bag:Refresh()
    if not frame then return end

    local y = -TITLE_BAR_H

    for _, def in ipairs(SECTIONS) do
        local section = sections[def.key]
        local collapsed = IsCollapsed(def.key)

        -- Header positioning
        section.header:ClearAllPoints()
        section.header:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PANEL_PAD, y)
        section.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PANEL_PAD, y)
        section.toggle:SetTexture(collapsed
            and "Interface\\Buttons\\UI-PlusButton-Up"
            or  "Interface\\Buttons\\UI-MinusButton-Up")
        y = y - SECTION_HEADER_H

        -- Body — collect this section's (bag, slot) pairs in order
        local pairs_list = {}
        for _, bagID in ipairs(def.bagIDs) do
            local n = (C_Container and C_Container.GetContainerNumSlots
                       and C_Container.GetContainerNumSlots(bagID)) or 0
            for slotID = 1, n do
                pairs_list[#pairs_list + 1] = { bagID = bagID, slotID = slotID }
            end
        end

        -- Section count text e.g. "16 / 24"
        local total = 0
        local free  = 0
        for _, bagID in ipairs(def.bagIDs) do
            free  = free  + ((C_Container and C_Container.GetContainerNumFreeSlots
                              and C_Container.GetContainerNumFreeSlots(bagID)) or 0)
            total = total + ((C_Container and C_Container.GetContainerNumSlots
                              and C_Container.GetContainerNumSlots(bagID)) or 0)
        end
        section.count:SetText(string.format("|cff999999%d / %d|r", total - free, total))

        -- Layout the slot buttons in a grid inside the body
        local rows = math.ceil(#pairs_list / COLS)
        local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_GAP
        if collapsed then bodyH = 0 end

        section.body:ClearAllPoints()
        section.body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PANEL_PAD,  y)
        section.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PANEL_PAD, y)
        section.body:SetHeight(math.max(bodyH, 0.001))

        for i, p in ipairs(pairs_list) do
            local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)

            btn:ClearAllPoints()
            if collapsed then
                btn:Hide()
            else
                btn:SetPoint("TOPLEFT", section.body, "TOPLEFT",
                    col * (SLOT_SIZE + SLOT_GAP),
                    -row * (SLOT_SIZE + SLOT_GAP))
                btn:Show()
                RenderSlot(btn, p.bagID, p.slotID)
            end
        end

        if not collapsed then
            y = y - bodyH - 6  -- small gap below body
        else
            y = y - 4
        end
    end

    -- Hide stale buttons (e.g. if a bag was unequipped and is smaller now)
    for bagID, slots in pairs(slotButtons) do
        local n = (C_Container and C_Container.GetContainerNumSlots
                   and C_Container.GetContainerNumSlots(bagID)) or 0
        for slotID, btn in pairs(slots) do
            if slotID > n then
                btn:Hide()
                btn:ClearAllPoints()
            end
        end
    end

    -- Total panel height: title + sections + footer
    local totalH = math.abs(y) + FOOTER_H
    frame:SetHeight(totalH)

    -- Footer status
    local totalFree, totalSlots = 0, 0
    for _, def in ipairs(SECTIONS) do
        for _, bagID in ipairs(def.bagIDs) do
            totalFree  = totalFree  + ((C_Container and C_Container.GetContainerNumFreeSlots
                                         and C_Container.GetContainerNumFreeSlots(bagID)) or 0)
            totalSlots = totalSlots + ((C_Container and C_Container.GetContainerNumSlots
                                         and C_Container.GetContainerNumSlots(bagID)) or 0)
        end
    end
    frame.status:SetText(string.format("%d / %d slots", totalSlots - totalFree, totalSlots))
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
-- Event-driven refresh (coalesced)
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
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", ScheduleRefresh)

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

BazCore:QueueForLogin(function()
    -- Build lazily — frame is created on first Toggle/Show. We could
    -- pre-build here for instant first-show but that wastes memory if
    -- the user never opens the panel.
end)
