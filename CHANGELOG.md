# BazBags Changelog

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
