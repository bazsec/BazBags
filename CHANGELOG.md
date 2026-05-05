# BazBags Changelog

## 075 — Drop divider above Split stack

Removed the divider above "Split stack..." in the shift+right-click
menu - it's just another regular item in the BazBags section now.

## 074 — Cleaner context menu + split stack on tap

Continuing on the BazCore 116 shared context-menu refactor with a
handful of polish passes:

- The 8-10 categories that used to fill the menu collapse into a
  single "Category ▶" entry that opens a flyout submenu on hover
  (using the new `submenu` shape in BazCore 117).
- New "Split stack..." entry on stacks > 1. Blizzard's default
  shift+right-click split-stack trigger is suppressed on BazBags
  slots so the only path to the dialog is the menu entry, and the
  StackSplitFrame is bumped to FULLSCREEN_DIALOG strata so the
  dialog reliably pops on top of the bag panel.
- The redundant item-link title is removed from the menu - the bag
  slot's icon sits right next to the menu, you can already see what
  you're acting on.

## 073 — Bag-item context menu uses BazCore's shared registry

Shift+right-clicking a bag slot still shows the same category-pin
menu, but it's now built via BazCore's `OpenContextMenu("bag-item",
...)`. Other addons that register a section under the same scope
(BazTooltipEditor's "Inspect this tooltip" entry being the first
example) appear in the menu automatically alongside the categories.

## 072 — User guide refresh

The in-game User Manual now documents the full set of custom-category
rule types (Item Class, Quality, Equip Slot, Expansion, Trade Skill /
Reagent), and the Tooltip extras section covers the Show Expansion in
Tooltip toggle.

## 071 - Expansion category tag + tooltip option
- New **Expansion** category rule type. Match items by which expansion they were added in (resolved via `C_Item.GetItemInfo`'s `expansionID` return). Operators: is / is at least / is at most. Use it for "Dragonflight Gear", "Current Expansion Only", "Pre-Cataclysm Quest Items", etc.
- Expansion list is built lazily from Blizzard's `EXPANSION_NAME{n}` globals so future expansions appear automatically without an addon update.
- New **Show Expansion** tooltip option (Settings > BazBags > General Settings > Tooltip). Off by default. When on, item tooltips append an "Expansion: <name>" line everywhere they appear (bags, character pane, merchant, AH). New `Tooltip.lua` module hooks `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)` so it's a no-op until the option is toggled.

## 001 - Initial release
- Combined single-panel bag UI: main bags + reagent bag in one window
- Collapsible sections per bag type, state persisted
- Native `ContainerFrameItemButtonTemplate` slots (cooldown, quality, drag/drop, click-to-use)
- Sort button calls `C_Container.SortBags`
- Free / total slot indicator at footer
- Draggable, position persisted per profile
- ESC closes, `/bb` toggles, minimap entry
