> **Warning: Requires [BazCore](https://www.curseforge.com/wow/addons/bazcore).** If you use the CurseForge app, it will be installed automatically. Manual users must install BazCore separately.

# BazBags

![WoW](https://img.shields.io/badge/WoW-12.0_Midnight-blue) ![License](https://img.shields.io/badge/License-GPL_v2-green) ![Version](https://img.shields.io/github/v/tag/bazsec/BazBags?label=Version&color=orange&sort=date)

A lightweight unified bag panel for World of Warcraft. All bags + the reagent bag in one window, with collapsible sections per bag type.

***

## Features

*   **One combined panel** for the main bags and the reagent bag — no separate window for reagents
*   **Collapsible sections** per bag type — fold the reagent grid away when you don't need it
*   **Native item buttons** — cooldown sweep, quality border, drag/drop, click-to-use all behave exactly as Blizzard intends because we use the standard `ContainerFrameItemButtonTemplate`
*   **Sort button** — calls Blizzard's own `C_Container.SortBags`, no custom heuristics
*   **Free / total slot indicator** at the panel footer
*   **Draggable** — position remembered per profile
*   **ESC closes**, `/bb` toggles, minimap entry available

***

## Slash Commands

| Command | Action |
| ------- | ------ |
| `/bb` | Toggle the panel |
| `/bb sort` | Trigger Blizzard's bag sort |
| `/bazbags` | Alias for `/bb` |

***

## Roadmap

Planned for upcoming releases:

*   **Item categories** — auto-grouped sections for *Equipment*, *Consumables*, *Trade Goods*, *Quest*, *Junk*, etc., layered on top of the existing per-bag-type sections so you can choose to view by bag or by category
*   **Search bar** — fuzzy match item names, gray out non-matches
*   **Bank panel** — same collapsible-section design, opens at the bank
*   **Per-equipped-bag sections** as an optional alternative to the merged "Bags" section, for people who specifically want to see each container separately

The guiding principle stays the same: small footprint, native item buttons, no auto-magic that fights you.

***

## Compatibility

*   **WoW Version:** Retail 12.0 (Midnight)

***

## Dependencies

**Required:**

*   [BazCore](https://www.curseforge.com/wow/addons/bazcore) — shared framework for Baz Suite addons

***

## Part of the Baz Suite

BazBags is part of the **Baz Suite** of addons, all built on the [BazCore](https://www.curseforge.com/wow/addons/bazcore) framework:

*   **[BazBars](https://www.curseforge.com/wow/addons/bazbars)** — Custom extra action bars
*   **[BazWidgetDrawers](https://www.curseforge.com/wow/addons/bazwidgetdrawers)** — Slide-out widget drawer
*   **[BazWidgets](https://www.curseforge.com/wow/addons/bazwidgets)** — Widget pack for BazWidgetDrawers
*   **[BazNotificationCenter](https://www.curseforge.com/wow/addons/baznotificationcenter)** — Toast notification system
*   **[BazLootNotifier](https://www.curseforge.com/wow/addons/bazlootnotifier)** — Animated loot popups
*   **[BazFlightZoom](https://www.curseforge.com/wow/addons/bazflightzoom)** — Auto zoom on flying mounts
*   **[BazMap](https://www.curseforge.com/wow/addons/bazmap)** — Resizable map and quest log window
*   **[BazMapPortals](https://www.curseforge.com/wow/addons/bazmapportals)** — Mage portal/teleport map pins

***

## License

BazBags is licensed under the **GNU General Public License v2** (GPL v2).
