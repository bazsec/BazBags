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

-- Category data and layouts live in their own modules — see
-- Categories.lua and Layouts.lua. Bag.lua keeps the panel chrome,
-- the bag-mode rendering, and the Refresh dispatcher.

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame                       -- top-level panel
local bagContexts   = {}          -- [bagID] = invisible parent (provides GetID + IsCombinedBagContainer for slots)
local slotButtons   = {}          -- [bagID] = { [slotID] = button }
local sections      = {}          -- [key]   = { header, body, ... }
local refreshPending = false
local categorizeMode = false      -- toggled via left-click on the portrait;
                                  -- when on, the category layout shows drop
                                  -- slots + empty categories so the user can
                                  -- pin items by dropping them. In-memory
                                  -- only — resets to off on /reload.

-- Sections is exposed so the Layouts module can hide them when it
-- takes over (e.g. switching from Sections to Flow mode). Other
-- internals are exposed at the bottom of the section-builder block
-- once the helpers are defined.
addon.Bag.sections = sections

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
    -- Parent to scrollChild (when it exists) so slot buttons live
    -- inside the scroll hierarchy and get clipped + translated when
    -- the panel scrolls. Falls back to frame for the (vanishingly
    -- small) window between BuildFrame's first lines and the scroll
    -- frame's creation.
    local parent = (frame and frame.scrollChild) or frame
    local f = CreateFrame("Frame", nil, parent)
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

    -- Shift+right-click → category context menu. PreClick fires before
    -- the secure action handler (which would normally use the item on
    -- right-click), so we can show our menu without losing the rest of
    -- the slot's standard behaviour. shift+right is unbound by default
    -- in modern WoW so this doesn't compete with use-item / split-stack.
    btn:HookScript("PreClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" and IsShiftKeyDown() then
            Bag:ShowCategoryMenuForSlot(self, bagID, slotID)
        end
    end)

    slotButtons[bagID][slotID] = btn
    return btn
end

---------------------------------------------------------------------------
-- Category context menu (shift+right-click on a bag item)
--
-- Shows a MenuUtil context menu listing every category with the
-- current pin highlighted. Clicking a category pins the item there;
-- clicking the already-pinned category unpins. An explicit "Unpin"
-- entry is included whenever a pin exists for ergonomic discovery.
---------------------------------------------------------------------------

-- Small green check icon used to mark the active pin in the menu.
local CHECK_GLYPH = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"

function Bag:ShowCategoryMenuForSlot(anchor, bagID, slotID)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end

    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if not info or not info.itemID then return end  -- empty slot

    local itemID = info.itemID
    local link   = info.hyperlink

    local pins       = addon:GetSetting("itemCategories") or {}
    local currentKey = pins[itemID]

    local Categories = addon.Categories
    if not Categories then return end
    local cats = Categories.GetAll() or {}

    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(link or ("Item " .. itemID))

        for _, cat in ipairs(cats) do
            local label = cat.name or cat.key
            -- Hidden categories still appear in the menu — pinning to
            -- a hidden category is a deliberate "stash this item out
            -- of view" action — but get a grey suffix so the user
            -- knows what they're picking.
            if cat.hidden then
                label = label .. "  |cff888888(hidden)|r"
            end
            -- Mark the current pin with a check + gold colour so the
            -- user immediately sees where the item lives.
            if cat.key == currentKey then
                label = "|cffffd700" .. CHECK_GLYPH .. " " .. label .. "|r"
            end
            local capturedKey = cat.key
            root:CreateButton(label, function()
                if capturedKey == currentKey then
                    Categories.RemoveItem(itemID)  -- toggle off
                else
                    Categories.AddItem(itemID, capturedKey)
                end
                if Bag.Refresh then Bag:Refresh() end
            end)
        end

        if currentKey then
            root:CreateDivider()
            root:CreateButton("Unpin (auto-classify)", function()
                Categories.RemoveItem(itemID)
                if Bag.Refresh then Bag:Refresh() end
            end)
        end
    end)
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

    -- Sections live inside scrollChild so they scroll with the rest of
    -- the bag content. Falls back to frame in the unlikely case the
    -- scroll frame isn't built yet.
    local parent = (frame and frame.scrollChild) or frame

    local header = CreateFrame("Button", nil, parent)
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
    local body = CreateFrame("Frame", nil, parent)
    section.body = body

    return section
end

-- Public API surface for the Layouts module. Capturing the locals
-- on addon.Bag means Layouts.lua can drive the same rendering
-- primitives without re-implementing them.
addon.Bag.IsCollapsed           = IsCollapsed
addon.Bag.SetCollapsed          = SetCollapsed
addon.Bag.GetOrCreateSlotButton = GetOrCreateSlotButton
addon.Bag.UpdateSlot            = UpdateSlot

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
        -- DIALOG by default so the bag floats above the BazCore
        -- Settings window (HIGH) — see the Strata setting in
        -- Settings → Layout for picking a different layer.
        strata         = addon:GetSetting("strata") or "DIALOG",

        -- Hover the portrait → tooltip explaining the click actions.
        -- Left-click sorts the bag (Blizzard's C_Container.SortBags).
        -- Middle-click toggles Categorize mode (drop slots + every
        -- category visible, for batch-pinning items). Right-click
        -- opens the bag-change popup. Drag from anywhere else on
        -- the title bar still works to move the frame.
        portraitTooltip = {
            title = "BazBags",
            lines = {
                "|cffffd700Left-click|r to sort bags",
                "|cffffd700Middle-click|r to toggle Categorize mode",
                "|cffffd700Right-click|r to change bags",
                "|cffffd700Drag the title bar|r to move the panel",
            },
        },
        portraitOnClick = function(_, button)
            if button == "LeftButton" then
                if C_Container and C_Container.SortBags then
                    C_Container.SortBags()
                end
            elseif button == "MiddleButton" then
                Bag:ToggleCategorizeMode()
            elseif button == "RightButton" then
                Bag:ToggleBagChangePopup()
            end
        end,
    })

    -- Search box — Blizzard's BagSearchBoxTemplate handles the icon,
    -- placeholder text, focus/blur visuals, and live filtering of
    -- ContainerFrameItemButton instances via SetMatchesSearch. The
    -- right edge anchors to the money frame's LEFT so the search box
    -- automatically shrinks when the player's gold total grows wider.
    -- (We dropped Blizzard's auto-sort 'broom' button — /bbg sort
    -- still runs C_Container.SortBags on demand, and the corner real
    -- estate is now used for the money display.)
    frame.search = CreateFrame("EditBox", nil, frame, "BagSearchBoxTemplate")
    frame.search:SetHeight(18)
    frame.search:SetPoint("TOPLEFT", 62, -37)

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

    -- Solid backing layer behind the panel's translucent stock
    -- background. PortraitFrameFlatTemplate's Bg uses
    -- PANEL_BACKGROUND_COLOR which has built-in alpha (~0.7) — so
    -- frame.Bg:SetAlpha(1) still reads as see-through. This extra
    -- texture sits *under* frame.Bg at sub-level -1 so the dark
    -- overlay still tints the panel, but at 100% opacity the result
    -- is fully solid. Both layers scale together with the bgAlpha
    -- setting (Refresh applies SetAlpha to both).
    --
    -- Uses Blizzard's "spec-background" atlas — the same textured
    -- mid-grey backdrop the BazCore standalone options window uses,
    -- so the bag panel matches the settings page rather than reading
    -- as a stark dark void.
    frame.solidBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.solidBg:SetAtlas("spec-background")
    frame.solidBg:SetPoint("TOPLEFT",     2, -20)
    frame.solidBg:SetPoint("BOTTOMRIGHT", -2, 3)

    -- Money frame — Blizzard's exact gold/silver/copper readout.
    -- Anchored where Blizzard's auto-sort button used to live so the
    -- player's gold sits next to the title bar instead of taking a
    -- whole row at the bottom of the panel.
    --
    -- Anchored by its RIGHT (right-middle) edge instead of TOPRIGHT so
    -- the vertical centre lines up with the search bar's centre
    -- regardless of the money frame's intrinsic height (which varies
    -- with Blizzard's template). Search bar centre:
    --   TOPLEFT y = -37, height 18  →  centre y = -46
    -- Pinning money's right-middle to (-12, -46) puts both centres on
    -- the same horizontal line.
    frame.money = CreateFrame("Frame", nil, frame, "ContainerMoneyFrameTemplate")
    frame.money:ClearAllPoints()
    frame.money:SetPoint("RIGHT", frame, "TOPRIGHT", -12, -47)
    frame.search:SetPoint("RIGHT", frame.money, "LEFT", -8, 0)

    -- Match the money frame's gold-coinbox border height to the
    -- search bar (plus 1 px) so the chrome reads as the same row,
    -- with the gold border just barely taller — pure-flat search bar
    -- looks slightly shorter than the textured coinbox at equal
    -- heights, and 1 px makes the optical illusion balance out.
    -- ContainerMoneyFrameTemplate's Border child is
    -- ContainerFrameCurrencyBorderTemplate at a fixed y=17 with 8x17
    -- Left/Right cap textures and a stretching Middle.
    local moneyH = (frame.search:GetHeight() or 18) + 2
    frame.money:SetHeight(moneyH)
    if frame.money.Border then
        frame.money.Border:SetHeight(moneyH)
        if frame.money.Border.Left  then frame.money.Border.Left:SetHeight(moneyH)  end
        if frame.money.Border.Right then frame.money.Border.Right:SetHeight(moneyH) end
        -- Middle anchors TOPLEFT/BOTTOMRIGHT to Left/Right corners, so
        -- it stretches automatically to fill the new height.
    end

    -- Scroll container for the bag content (sections, dividers, slots).
    -- All content anchors to scrollChild so when the player has more
    -- items than the maxHeight setting allows, scrollFrame clips the
    -- overflow and the mouse wheel handler shifts the visible slice.
    -- Positioned between the search bar (top chrome) and the
    -- money/tokens row (bottom chrome) — its exact height is
    -- recomputed every Refresh. We deliberately use a bare ScrollFrame
    -- without a scrollbar template (Blizzard's modern minimal scrollbar
    -- is wired to ScrollBox, not plain ScrollFrame) and rely on the
    -- mouse wheel for scrolling.
    local sf = CreateFrame("ScrollFrame", nil, frame)
    sf:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD, -TOP_PAD)
    sf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, -TOP_PAD)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        if (self.bazMaxScroll or 0) <= 0 then return end
        local cur = self:GetVerticalScroll() or 0
        local next = cur - delta * 30
        if next < 0 then next = 0 end
        if next > self.bazMaxScroll then next = self.bazMaxScroll end
        self:SetVerticalScroll(next)
    end)
    frame.scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(1, 1)  -- resized per refresh; width tracks scrollFrame
    sf:SetScrollChild(sc)
    frame.scrollChild = sc

    -- Divider rule between the scroll area and the footer chrome
    -- (money + tokens). Without it the last row of items reads as
    -- bleeding into the gold / currency strip — this gives the eye
    -- a clear "end of bag content" line. Same warm-gold tone as the
    -- category dividers inside the scroll area for consistency.
    frame.contentDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.contentDivider:SetHeight(1)
    frame.contentDivider:SetColorTexture(0.55, 0.42, 0.18, 0.85)
    frame.contentDivider:SetPoint("TOPLEFT",  sf, "BOTTOMLEFT",  0, -3)
    frame.contentDivider:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 0, -3)

    -- Build sections
    for _, def in ipairs(SECTIONS) do
        sections[def.key] = BuildSection(def)
    end

    -- Expose the live frame so settings setters (e.g. Frame Strata)
    -- can poke it directly without going through Refresh.
    addon.Bag.frame = frame

    return frame
end

---------------------------------------------------------------------------
-- Bag-change popup
--
-- A small floating panel anchored under the portrait. Holds five bag
-- slot buttons — the four equipped bag slots plus the reagent bag.
-- Drag a bag from your inventory onto a slot to equip it; drag a slot
-- icon off to clear it. Mirrors what Blizzard surfaces via the
-- character pane's "Bags" tab, just one click closer.
---------------------------------------------------------------------------

-- Resolve the inventory slot IDs for the player's equipped bags.
--
-- Earlier we hardcoded {20, 21, 22, 23, 24} (the INVSLOT_BAG_* values
-- from TWW 11.x), but Midnight 12.0 renumbered the equipped slots:
-- INVSLOT_BAG_* aren't exported as globals anymore, and slot 20 in
-- particular is now a profession tool slot — that's why the popup
-- was showing alchemy tools instead of bags.
--
-- C_Container.ContainerIDToInventoryID is the canonical mapping from
-- a container's bag index to its inventory slot, and Blizzard's own
-- character pane goes through it. We resolve once on first use so
-- we don't pay the lookup cost on every popup show.
local BAG_SLOT_INV_IDS
local function ResolveBagSlots()
    if BAG_SLOT_INV_IDS then return BAG_SLOT_INV_IDS end

    local slots = {}
    local C = C_Container
    if not (C and C.ContainerIDToInventoryID) then
        -- Defensive: very old clients fall back to the legacy values.
        -- Modern retail always has the API, so this branch is dead in
        -- practice but keeps the popup from crashing if it's missing.
        BAG_SLOT_INV_IDS = { 20, 21, 22, 23, 24 }
        return BAG_SLOT_INV_IDS
    end

    -- Backpack is bag index 0 (and lives at INVSLOT_BACKPACK / cursor
    -- slot 0); the four equipable bag slots are indices 1..4 and the
    -- reagent bag is index 5. Width-defensive on NUM_BAG_SLOTS so we
    -- pick up the count Blizzard exposes rather than assuming four.
    local numBags = NUM_BAG_SLOTS or 4
    for bagID = 1, numBags do
        local invID = C.ContainerIDToInventoryID(bagID)
        if invID then slots[#slots + 1] = invID end
    end

    if (NUM_REAGENTBAG_SLOTS or 0) > 0 then
        local reagentBagID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag)
                             or (numBags + 1)
        local invID = C.ContainerIDToInventoryID(reagentBagID)
        if invID then slots[#slots + 1] = invID end
    end

    BAG_SLOT_INV_IDS = slots
    return slots
end

local function UpdateBagSlotButton(btn)
    local slot = btn.invSlot
    local link    = GetInventoryItemLink("player", slot)
    local texture = GetInventoryItemTexture("player", slot)

    btn:SetIconTexture(texture)
    if link then
        local _, _, quality = GetItemInfo(link)
        btn:SetQuality(quality, link)
    else
        btn:SetQuality(0)
    end
end

local function BuildBagSlotButton(parent, invSlot, isReagent)
    -- BazCore:CreateItemButton hands us an ItemButton-styled frame
    -- (icon + quality border + slot background + highlight + pushed)
    -- without going through ItemButtonTemplate / BagSlotButtonTemplate
    -- — both of those exist in Blizzard's XML but aren't exposed as
    -- runtime CreateFrame targets in retail Midnight. The bag-slot
    -- background uses the same "bags-item-slot64" atlas as Blizzard's
    -- combined bag, so empty slots show the familiar slot artwork.
    local btn = BazCore:CreateItemButton(parent, {
        size      = 36,
        slotAtlas = "bags-item-slot64",
    })
    btn:SetID(invSlot)
    btn.invSlot = invSlot
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not GameTooltip:SetInventoryItem("player", self.invSlot) then
            GameTooltip:SetText(isReagent and (REAGENT_BAG_HELP_TEXT or "Reagent Bag")
                                or "Bag Slot")
            GameTooltip:AddLine("Drag a bag here to equip it.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self)
        -- If the cursor has an item, drop it into this slot.
        -- Otherwise no-op (don't toggle a bag — that's not the
        -- popup's purpose).
        if CursorHasItem() then
            PutItemInBag(self.invSlot)
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        PickupBagFromSlot(self.invSlot)
    end)

    btn:SetScript("OnReceiveDrag", function(self)
        PutItemInBag(self.invSlot)
    end)

    return btn
end

local bagPopup
local function BuildBagChangePopup()
    if bagPopup then return bagPopup end
    if not frame then return nil end

    local PAD = 8
    local SLOT_SIZE = 36
    local SLOT_GAP  = 4
    local invSlots  = ResolveBagSlots()
    local slotCount = #invSlots

    local p = CreateFrame("Frame", "BazBagsBagChangePopup", frame, "BackdropTemplate")
    p:SetSize(PAD * 2 + slotCount * SLOT_SIZE + (slotCount - 1) * SLOT_GAP,
              PAD * 2 + SLOT_SIZE + 18)
    p:SetFrameStrata("DIALOG")
    p:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0, 0, 0, 0.92)
    p:SetBackdropBorderColor(0.6, 0.5, 0.2)
    p:Hide()

    -- Position is set per-Show in PositionBagPopup so we adapt to the
    -- bag's current screen position (above when there's room, below
    -- otherwise) — see the comment block on PositionBagPopup.

    -- Header label
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", PAD, -PAD)
    p.title:SetText("Bag Slots")
    p.title:SetTextColor(1.00, 0.82, 0.00)

    -- Bag buttons in a row
    p.buttons = {}
    for i, invSlot in ipairs(invSlots) do
        local isReagent = (i == #invSlots) and (NUM_REAGENTBAG_SLOTS or 0) > 0
        local btn = BuildBagSlotButton(p, invSlot, isReagent)
        btn:SetSize(SLOT_SIZE, SLOT_SIZE)
        btn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT",
            PAD + (i - 1) * (SLOT_SIZE + SLOT_GAP), PAD)
        p.buttons[i] = btn
    end

    -- Refresh on inventory changes
    local ev = CreateFrame("Frame", nil, p)
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ev:SetScript("OnEvent", function()
        if not p:IsShown() then return end
        for _, b in ipairs(p.buttons) do UpdateBagSlotButton(b) end
    end)

    bagPopup = p
    return p
end

-- Position the popup outside the bag panel so it doesn't obscure
-- bag contents. We pick the side adaptively: above the bag when
-- there's screen room (so the popup floats near the portrait the
-- user just clicked), below the bag when the panel is already near
-- the top of the screen. The 80 px threshold leaves a comfortable
-- gap for the popup's ~62 px height plus the small visual offset.
local function PositionBagPopup(p)
    if not p or not frame then return end
    p:ClearAllPoints()

    local screenH    = UIParent and UIParent:GetHeight() or 1080
    local bagTop     = frame:GetTop() or screenH
    local roomAbove  = screenH - bagTop

    if roomAbove >= 80 then
        -- Above the bag, x-offset clears the portrait so the popup
        -- sits beside it rather than under it.
        p:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 56, 4)
    else
        -- Below the bag, aligned to the left edge.
        p:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
    end
end

function Bag:ToggleBagChangePopup()
    local p = BuildBagChangePopup()
    if not p then return end
    if p:IsShown() then
        p:Hide()
    else
        PositionBagPopup(p)
        for _, b in ipairs(p.buttons) do UpdateBagSlotButton(b) end
        p:Show()
    end
end

---------------------------------------------------------------------------
-- Categorize mode
--
-- When on, the category layout reveals every category (including
-- hidden ones and ones with no items currently) and shows a gold "+"
-- drop slot at the end of each grid. Click a drop slot or release a
-- drag onto it to pin the held item. Toggle off to return to the
-- normal "only categories with items" view. Triggered by left-click
-- on the bag's portrait icon. State is in-memory only — every fresh
-- /reload starts in normal mode.
---------------------------------------------------------------------------

function Bag:IsCategorizeMode()
    return categorizeMode
end

function Bag:ToggleCategorizeMode()
    categorizeMode = not categorizeMode
    Bag:Refresh()
end

---------------------------------------------------------------------------
-- Money frame state
--
-- ContainerMoneyFrameTemplate registers PLAYER_MONEY itself and calls
-- MoneyFrame_UpdateMoney whenever the player's gold changes. That
-- helper re-shows SilverButton + CopperButton based on the money
-- value, which silently clobbers any hide we did during the previous
-- Refresh. From the user's perspective the Gold Only toggle "doesn't
-- save" — the setting is persisted, but Blizzard's auto-update keeps
-- bringing silver/copper back the next time their gold changes.
--
-- ApplyMoneyState centralises the visibility + anchor logic so we can
-- call it both during Refresh and from a hooksecurefunc on
-- MoneyFrame_UpdateMoney. The hook fires after Blizzard's logic, so
-- our state always wins regardless of who triggered the update.
---------------------------------------------------------------------------

local function ApplyMoneyState(mf)
    if not mf then return end
    local goldOnly = addon:GetSetting("goldOnly") and true or false
    if mf.SilverButton then mf.SilverButton:SetShown(not goldOnly) end
    if mf.CopperButton then mf.CopperButton:SetShown(not goldOnly) end
    if mf.GoldButton then
        mf.GoldButton:ClearAllPoints()
        if goldOnly then
            -- Match Blizzard's pattern for the rightmost coin
            -- (-13 from frame RIGHT) so the gold icon sits inside
            -- the border's decorative right cap.
            mf.GoldButton:SetPoint("RIGHT", mf, "RIGHT", -13, 0)
        elseif mf.SilverButton then
            -- Restore the template's default anchor relationship.
            mf.GoldButton:SetPoint("RIGHT", mf.SilverButton, "LEFT", -4, 0)
        end
    end
end

-- Re-apply our gold-only state every time Blizzard's MoneyFrame logic
-- runs for our money frame (e.g. PLAYER_MONEY events fired by the
-- template's own OnEvent handler). Installed once at file load; the
-- closure null-checks `frame` so it's safe to register before the
-- frame is built.
hooksecurefunc("MoneyFrame_UpdateMoney", function(moneyFrame)
    if frame and moneyFrame == frame.money then
        ApplyMoneyState(moneyFrame)
    end
end)

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

    -- Pin the frame to its current top-left corner before any resize
    -- so width/height changes grow toward bottom-right rather than
    -- expanding outward from the centre. Without this, toggling
    -- Categorize mode (or any setting that changes height) visually
    -- shifts the title bar / portrait icon — reads as jittery.
    -- BazCore's drag-stop handler re-saves whichever anchor GetPoint
    -- returns, so converting to TOPLEFT here is durable: the next
    -- drag will persist a TOPLEFT-anchored position.
    do
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end

    -- Live settings — re-read on every refresh so toggling the Columns
    -- slider or Hide Empty toggle applies immediately.
    local cols       = GetCols()
    local hideEmpty  = HideEmpty()

    -- Resize the panel width to match the column count. The search bar
    -- + sort button + money frame are anchored relative to the panel
    -- edges so they reflow automatically.
    frame:SetWidth(PanelWidthFor(cols))

    -- Apply the bg-opacity setting. frame.Bg is the stock
    -- FlatPanelBackgroundTemplate (a translucent dark overlay).
    -- frame.solidBg is the solid-black layer we added behind it so
    -- that 100% actually reads as opaque rather than the stock's
    -- ~70%. Scaling both together gives a clean fade from solid
    -- (100%) to fully see-through (0%).
    local bgAlpha = addon:GetSetting("bgAlpha") or 1.0
    if frame.Bg      then frame.Bg:SetAlpha(bgAlpha)      end
    if frame.solidBg then frame.solidBg:SetAlpha(bgAlpha) end

    -- Hide every existing slot button up front. Anything we still want
    -- visible gets re-shown + repositioned in the layout loop. This is
    -- the simplest way to handle (a) Hide Empty on/off, (b) bag size
    -- shrinking, and (c) section-collapsed-this-frame all at once.
    for _, slots in pairs(slotButtons) do
        for _, btn in pairs(slots) do
            btn:Hide()
        end
    end

    -- Width the inner content gets — match scrollChild to scrollFrame.
    -- ScrollFrame's width comes from its TOPLEFT/TOPRIGHT anchors
    -- (= frame width minus the two SIDE_PADs), so we read it back
    -- rather than recomputing.
    if frame.scrollChild and frame.scrollFrame then
        frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth() or 1)
    end

    -- Content y-cursor starts at 0 (top of scrollChild) instead of
    -- -TOP_PAD relative to frame — the chrome lives outside the
    -- scroll area now.
    local y = 0

    -- Dispatch to the appropriate layout. Bag mode renders the static
    -- bag/reagent sections inline (kept here because it's the simple
    -- common case). Category mode hands off to the Layouts module.
    local mode = addon:GetSetting("bagMode") or "bags"

    if mode == "categories" and addon.Layouts and addon.Layouts.Render then
        -- Hide bag-mode sections when category mode is active so a
        -- pooled section frame from a previous render doesn't peek
        -- through the category layout.
        for _, def in ipairs(SECTIONS) do
            local section = sections[def.key]
            if section then
                section.header:Hide()
                section.body:Hide()
            end
        end

        y = addon.Layouts.Render({
            -- Layouts anchor relative to scrollChild now so the bag
            -- content scrolls cleanly when content > maxHeight.
            frame                 = frame.scrollChild or frame,
            cols                  = cols,
            SLOT_SIZE             = SLOT_SIZE,
            SLOT_SPACING_X        = SLOT_SPACING_X,
            SLOT_SPACING_Y        = SLOT_SPACING_Y,
            SIDE_PAD              = 0,   -- scrollChild already has the side pad applied
            TOP_PAD               = 0,   -- scrollChild already starts below the chrome
            IsCollapsed           = IsCollapsed,
            SetCollapsed          = SetCollapsed,
            GetOrCreateSlotButton = GetOrCreateSlotButton,
            UpdateSlot            = UpdateSlot,
            Refresh               = function() Bag:Refresh() end,
        })
    elseif addon:GetSetting("perBagSections")
           and addon.Layouts and addon.Layouts.RenderPerBag then
        -- Bags mode + Separate Each Bag — render one thin-divider
        -- section per equipped bag, sharing the divider chrome with
        -- Categories mode.
        for _, def in ipairs(SECTIONS) do
            local section = sections[def.key]
            if section then
                section.header:Hide()
                section.body:Hide()
            end
        end

        y = addon.Layouts.RenderPerBag({
            frame                 = frame.scrollChild or frame,
            cols                  = cols,
            SLOT_SIZE             = SLOT_SIZE,
            SLOT_SPACING_X        = SLOT_SPACING_X,
            SLOT_SPACING_Y        = SLOT_SPACING_Y,
            SIDE_PAD              = 0,
            TOP_PAD               = 0,
            IsCollapsed           = IsCollapsed,
            SetCollapsed          = SetCollapsed,
            GetOrCreateSlotButton = GetOrCreateSlotButton,
            UpdateSlot            = UpdateSlot,
            Refresh               = function() Bag:Refresh() end,
            hideEmpty             = hideEmpty,
        })
    else
        -- Bag mode (the default). Clear any category chrome left over
        -- from a Flow / Hybrid render before drawing the bag sections.
        if addon.Layouts and addon.Layouts.HideAll then
            addon.Layouts.HideAll()
        end
        -- One section per bag type with the existing collapse / count chrome.
        local anchor = frame.scrollChild or frame
        for _, def in ipairs(SECTIONS) do
            local section = sections[def.key]
            local collapsed = IsCollapsed(def.key)

            -- Header
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT",  anchor, "TOPLEFT",  0, y)
            section.header:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, y)
            section.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            section.title:SetText(def.title)
            section.header:Show()
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
            section.body:SetPoint("TOPLEFT",  anchor, "TOPLEFT",  0, y)
            section.body:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, y)
            section.body:SetHeight(math.max(bodyH, 0.001))
            section.body:Show()

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
    end

    -- Compute bottom padding. The money frame lives in the top-right
    -- chrome now, so only tokens (the green tracked-currency strip)
    -- contribute to the bottom area.
    --
    -- Math for the tokens case (token height ~17, anchored 12 px from
    -- frame bottom, divider sits 3 px below the scroll area):
    --   gap between divider and tokens top = bottomPad - 33
    -- bottomPad = 44 yields ~11 px of breathing room above the
    -- currency strip — earlier 30 left only ~1 px and the items above
    -- looked like they were stacked right on top of the strip.
    local showTokens = addon:GetSetting("showTokens") ~= false
    local bottomPad  = showTokens and 44 or 12

    -- Cap the scroll area at the user's maxRows setting (one row =
    -- SLOT_SIZE + SLOT_SPACING_Y ≈ 41 px). Anything taller scrolls;
    -- anything shorter shrinks the panel to fit content.
    local contentH = math.abs(y)
    local maxRows  = addon:GetSetting("maxRows") or 15
    local maxH     = maxRows * (SLOT_SIZE + SLOT_SPACING_Y)
    local scrollH  = math.min(contentH, maxH)

    if frame.scrollChild then
        frame.scrollChild:SetHeight(math.max(contentH, 1))
    end
    if frame.scrollFrame then
        frame.scrollFrame:SetHeight(math.max(scrollH, 1))
        frame.scrollFrame.bazMaxScroll = math.max(0, contentH - scrollH)
        -- Clamp current scroll so it never points past the new content
        -- height (e.g. user emptied the bag while scrolled to bottom).
        local cur = frame.scrollFrame:GetVerticalScroll() or 0
        if cur > frame.scrollFrame.bazMaxScroll then
            frame.scrollFrame:SetVerticalScroll(frame.scrollFrame.bazMaxScroll)
        end
    end

    -- Frame height = top chrome (search/sort) + scroll area + bottom
    -- chrome (money/tokens). Token-row growth adds onto this below
    -- so multi-row currency strips don't get clipped.
    frame:SetHeight(TOP_PAD + scrollH + bottomPad)

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
        -- Currency strip alignment — left, center, or right edge of the
        -- panel. Internal token packing (right-to-left within each row)
        -- doesn't change; only the strip's anchor point on the panel.
        local align = addon:GetSetting("tokenAlignment") or "right"
        if align == "left" then
            frame.tokens:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
        elseif align == "center" then
            frame.tokens:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
        else
            frame.tokens:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
        end
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

    -- Money frame lives in the top-right chrome (anchored once in
    -- BuildFrame). Per refresh we just update its values and the
    -- gold-only state — its position never changes. Width auto-fits
    -- visible content via the deferred SetWidth at the end so the
    -- search bar (anchored to money's LEFT) shrinks/grows in lock-step.
    -- The "Show Money" toggle was removed in favour of always showing
    -- gold; with the money frame in the top-right corner there's no
    -- vertical real estate to reclaim by hiding it.
    if frame.money then
        do
            frame.money:Show()

            if MoneyFrame_Update then
                MoneyFrame_Update(frame.money:GetName() or frame.money, GetMoney())
            end
            -- Always re-apply our gold-only state. The hooksecurefunc on
            -- MoneyFrame_UpdateMoney catches event-driven refreshes
            -- (PLAYER_MONEY etc.) but Refresh calls MoneyFrame_Update
            -- directly, which doesn't go through UpdateMoney — so
            -- without this explicit call the Gold Only toggle had no
            -- effect when triggered from the Settings page.
            ApplyMoneyState(frame.money)

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

-- Show the panel for the first time? On the very first BuildFrame
-- the scroll-frame's anchor-derived width hasn't propagated yet, so
-- the first Refresh's contentH / scrollH math comes out off and the
-- player sees a tall, mostly-empty panel until they close + reopen.
-- Trigger a one-frame-deferred re-refresh on first show to recompute
-- with the now-settled layout.
local function ShowPanel(self)
    -- Always start at the top of the scroll area when the panel is
    -- shown — without this, ScrollFrame can come up at a stale scroll
    -- position (e.g. saved from a prior session) and items render
    -- below the visible window, making the panel look empty.
    if frame.scrollFrame and frame.scrollFrame.SetVerticalScroll then
        frame.scrollFrame:SetVerticalScroll(0)
    end

    self:Refresh()
    frame:Show()

    if not self._firstShownDone then
        self._firstShownDone = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if frame and frame:IsShown() then self:Refresh() end
            end)
        end
    end
end

function Bag:Show()
    BuildFrame()
    ShowPanel(self)
end

function Bag:Hide()
    if frame then frame:Hide() end
end

function Bag:Toggle()
    BuildFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        ShowPanel(self)
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
events:RegisterEvent("INVENTORY_SEARCH_UPDATE")    -- search box text → re-evaluate isFiltered
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
