> **Warning: Requires [BazCore](https://www.curseforge.com/wow/addons/bazcore).** If you use the CurseForge app, it will be installed automatically. Manual users must install BazCore separately.

# BazBags

![WoW](https://img.shields.io/badge/WoW-12.0_Midnight-blue) ![License](https://img.shields.io/badge/License-GPL_v2-green) ![Version](https://img.shields.io/github/v/tag/bazsec/BazBags?label=Version&color=orange&sort=date)

A unified bag panel for World of Warcraft. All bags + the reagent bag in one window with two display modes, six auto-classified categories, custom categories, hidden categories, three ways to pin items, and a per-bag separation option.

BazBags replaces Blizzard's combined bag UI - the B key, the minimap bag icon, and any addon that calls the standard bag-toggle hooks all open BazBags instead.

***

## Features

### One Panel, Two Display Modes

*   **Bags mode (default)** - collapsible sections per bag type, Blizzard-style
*   **Categories mode** - thin dividers separating items by what they are
*   Switch any time via Settings → BazBags → General Settings → Grouping → Mode
*   Native ContainerFrameItemButtonTemplate slots - cooldown sweep, quality borders, drag/drop, click-to-use all behave exactly as Blizzard intends

### Six Auto-Classified Default Categories

Items get auto-routed into one of six default categories based on item class and quality:

*   **Equipment** - Weapons + Armor
*   **Consumables** - potions, food, scrolls, etc.
*   **Trade Goods** - Trade Goods + Recipes + Gems + Item Enhancements
*   **Quest Items**
*   **Junk** - anything Poor (grey) quality
*   **Other** - catch-all

The classifier looks up by internal key, not display name - so renaming a default category never breaks the auto-routing.

### Per-Category Editing

A dedicated Categories sub-page (Settings → BazBags → Categories) lets you:

*   **Rename** any category
*   **Reorder** via a 1-200 range slider (defaults are spaced by 10 so custom categories can slot in between)
*   **Hide** categories from the bag panel - items still classify but the divider/grid is suppressed
*   **Delete** with sensible fallback - items return to the auto-classifier
*   **Pin items** to specific categories (overrides the classifier)
*   **Create custom categories** for any organisation scheme

### Three Ways to Pin Items

Pick whichever fits the situation - all three update the same shared list of pins:

1.  **Shift+right-click** any bag item → MenuUtil context menu listing every category, with current pin highlighted in gold and an Unpin entry
2.  **Categorize mode** (middle-click portrait or `/bbg categorize`) - gold "+" drop slots appear at the end of every category's grid; pick up an item, click a slot, pinned
3.  **Settings page** - paste an item ID or shift-click an item link from chat into the input box

### Hidden Categories

Toggle Hide on any category to suppress it entirely from the bag panel. Items still occupy real bag slots - hiding is a display preference, not a delete. Useful for stashing junk or items you want out of view. Hidden categories surface during Categorize mode (with a "(hidden)" tag) so you can pin items to them.

### Per-Bag Sections

Bags mode renders one thin-divider section per equipped bag by default - Backpack, Bag 1, Bag 2, ..., Reagent Bag - each labelled with the equipped bag's actual name in grey parens:

```
Backpack
Bag 1 (Wildercloth Bag)
Bag 2 (Reaver's Reagent Pouch)
```

Same divider style Categories mode uses, with click-to-collapse on each. Toggle "Separate Each Bag" off in settings if you'd rather see one merged Bags section + a Reagents section (Blizzard's combined-bag style).

### Categorize Mode

Middle-click the bag's portrait icon to enter Categorize mode:

*   Every category divider shows up - including empty + hidden categories
*   Each category gets a gold "+" drop slot at the end of its grid
*   Pick up + drop items to pin them
*   Middle-click again to exit

State is in-memory only - every fresh /reload starts in normal mode. `/bbg categorize` is the slash equivalent for users without a middle-button mouse.

### Three-Button Portrait Icon

| Click | Action |
| --- | --- |
| **Left-click** | Sort (`C_Container.SortBags`) |
| **Middle-click** | Toggle Categorize mode |
| **Right-click** | Bag-change popup |

Hover the portrait for a tooltip listing all three.

### Search

A search box at the top-left filters every bag at once - type a partial name, item type ("potion"), quality ("epic"), or any tooltip-text fragment and non-matches dim. Uses Blizzard's BagSearchBoxTemplate so it behaves identically to the default UI.

### Money & Currency

*   **Inline gold display** next to the search bar (Gold Only toggle to hide silver/copper at high totals)
*   **Tracked-currency strip** at the bottom (green border) with left/center/right alignment
*   **Removes Blizzard's Show on Backpack cap** - track as many currencies as you like and they pack into multiple rows automatically

### Layout Customization

*   **Columns** (4-20)
*   **Max Rows** (3-30) - panel scrolls past the cap, or grow with content
*   **Background Opacity** (0-100%)
*   **Frame Strata** (Low / Medium / High / Dialog)
*   **Hide Empty Slots** (Bags mode)
*   **Use Default Title** (BazBags vs Combined Backpack)
*   **Steady title bar** — when the panel resizes (toggling Categorize mode, changing modes, etc.) it grows downward instead of expanding outward, so the title bar and portrait icon stay put

### Bag-Change Popup

Right-click the portrait → small popup with one button per equipped bag slot. Drag a bag from inventory onto a slot to equip it; drag the slot icon off to unequip. Mirrors Blizzard's character-pane Bags tab, just one click closer.

### Profiles

Per-character profiles via BazCore. Use different defaults per character:

*   A crafter alt with Categories mode + Hide Junk + tall Max Rows
*   A leveling alt with Bags mode + Hide Empty + compact Max Rows

Each character's profile travels with that character automatically.

***

## Slash Commands

| Command | Description |
| --- | --- |
| `/bbg` | Toggle the panel |
| `/bbg toggle` | Same as bare `/bbg` |
| `/bbg sort` | Run Blizzard's bag sort (same as left-click portrait) |
| `/bbg categorize` | Toggle Categorize mode (same as middle-click portrait) |
| `/bazbags` | Alias for `/bbg` - every subcommand works on either form |

***

## Installation

### CurseForge / WoW Addon Manager

Search for **BazBags**. BazCore will install automatically as a dependency.

### Manual Installation

1.  Install [BazCore](https://www.curseforge.com/wow/addons/bazcore) first
2.  Download the latest BazBags release
3.  Extract to `World of Warcraft/_retail_/Interface/AddOns/BazBags/`
4.  Reload UI (`/reload`)

***

## Compatibility

*   **WoW Version:** Retail 12.0 (Midnight)
*   **Native item buttons** — cooldown sweep, quality borders, drag/drop, click-to-use, shift-click to link in chat all behave exactly as in Blizzard's default bags
*   **Replaces Blizzard's combined bag** — the B key, the minimap bag icon, and any addon that opens bags all open BazBags
*   **No cap on tracked currencies** — Blizzard limits how many you can show on the backpack; BazBags removes the cap and packs them into multiple rows
*   **Combat-safe** — no protected-frame interactions during combat

***

## Dependencies

**Required:**

*   [BazCore](https://www.curseforge.com/wow/addons/bazcore) - shared framework for Baz Suite addons (installed automatically by the CurseForge app)

***

## Part of the Baz Suite

BazBags is part of the **Baz Suite** of addons, all built on the [BazCore](https://www.curseforge.com/wow/addons/bazcore) framework:

*   **[BazBars](https://www.curseforge.com/wow/addons/bazbars)** - Custom extra action bars
*   **[BazWidgetDrawers](https://www.curseforge.com/wow/addons/bazwidgetdrawers)** - Slide-out widget drawer
*   **[BazWidgets](https://www.curseforge.com/wow/addons/bazwidgets)** - Widget pack for BazWidgetDrawers
*   **[BazNotificationCenter](https://www.curseforge.com/wow/addons/baznotificationcenter)** - Toast notification system
*   **[BazLootNotifier](https://www.curseforge.com/wow/addons/bazlootnotifier)** - Animated loot popups
*   **[BazFlightZoom](https://www.curseforge.com/wow/addons/bazflightzoom)** - Auto zoom on flying mounts
*   **[BazMap](https://www.curseforge.com/wow/addons/bazmap)** - Resizable map and quest log window
*   **[BazMapPortals](https://www.curseforge.com/wow/addons/bazmapportals)** - Mage portal/teleport map pins

***

## License

BazBags is licensed under the **GNU General Public License v2** (GPL v2).
