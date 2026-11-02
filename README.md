# BitsjUI

A clean, minimal UI for World of Warcraft **Retail (Midnight 12.x)** and **WoW Forever** with its own config menu and drag and drop for everything. Built for **2560x1440 / 27"** at **UI scale 0.62**.

## Installation
1. Unzip and put the `BitsjUI` folder in
   `World of Warcraft\_retail_\Interface\AddOns\` (or `_forever_` for WoW Forever)
2. Start the game (or `/reload`). The setup opens on its own the first time.
3. Turn on **Action Bar 2-5** under *Options > Gameplay > Action Bars* (so the keybinds work; BitsjUI hides Blizzard's graphics).

## Optional: MiniAuras (party tracking)
Crowd control, defensive and interrupt tracking on the party frames comes from the free addon **MiniAuras** (formerly MiniCC). It is **optional**: BitsjUI works fine without it, you just don't get that tracking. With MiniAuras installed, the setup (or `/bui` > Party & raid > *Fit MiniAuras to BitsjUI*) places and styles it to match BitsjUI's party frames.

## Commands
| Command | What it does |
|---|---|
| `/bui` | Opens the BitsjUI menu |
| `/bui move` | Unlocks / locks all frames (drag and drop) |
| `/bui reset` | Resets all positions |
| `/bui install` | Runs the setup again |
| `/bui delete <name>` | Deletes a profile |
| `/rl` | Reloads the UI |

You can also click the BitsjUI button by the minimap (right-click = move mode) or open it from the addon compartment (puzzle-piece icon).

## Move mode
- Drag with the left mouse button. Snaps to the grid (hold **Alt** while releasing to skip snapping).
- Arrow keys: 1 px. Shift + arrow: one grid cell.
- Right-click a frame: back to its default position.
- Positions are saved relative to the nearest screen edge, so they survive changes to scale and resolution.

## What BitsjUI replaces
| Element | How |
|---|---|
| Action bars 1-8, pet bar, stance bar | Blizzard's own buttons moved into BitsjUI bars (keybinds, cooldowns, proc glows and Quick Keybind keep working). Size, rows, spacing, mouseover fade, range coloring, shortened hotkeys. |
| Player / target / target-of-target / focus / pet | Custom frames: class color or dark health, health text, power, target debuffs, raid icons, combat/resting icons. Class resources (combo points, runes and so on) follow the player frame. |
| Castbar (player, target, focus) | Custom, with icon, timer, spark, latency zone and a separate color for non-interruptible casts. |
| Nameplates | Blizzard's plates restyled: flat texture, 1 px border, health percent, cast colors. |
| Minimap | Square, 1 px border, scroll-wheel zoom, zone name on hover, coordinates. |
| Chat, tooltip | Font, no button clutter, dark tooltips with a class-colored border. |
| Fonts | Barlow Semi Condensed (default), Inter, Outfit, Instrument Sans, Big Shoulders, Poppins, Fira Sans (Light, Medium, Bold), Barlow Condensed, Changa, Cinzel Decorative, Exo, Russo One, Ubuntu + Blizzard fonts. One overall font plus an optional font per part of the UI (/bui > General). Can replace the font in the whole game. |

## Button feel
Every press (key or mouse) gives a short flash and a small "click" in the icon. Holding the key keeps the button darker. Blizzard's own cast animations on the buttons are hidden by default, because they look cluttered on smaller buttons. Settings: *Action bars → Button feel*.

## Cooldown Manager
BitsjUI styles Blizzard's built-in Cooldown Manager (Essential, Utility, buff icons and buff bars): square icons, 1 px border, darker swipe and its own font sizes. You pick which spells to track in Blizzard's Cooldown settings, and set placement in Edit Mode. The *Cooldown Manager* page has buttons for both.

## Damage meter
Up to 3 windows with the same kinds of settings as the big meter addons: view (damage, DPS, healing, HPS, absorbs, interrupts, dispels, damage taken, deaths …), fight/segment, bar height, spacing, texture, font, class colors, spec icons, rank, number format, percent, "always show me", visibility (always / combat / group), fade out of combat, plus presets (BitsjUI dark, Classic, Minimal).
Title-bar buttons: **M** view, **S** fight, **X** reset, **R** report to chat. Hover a player to see a breakdown by spell.
The meter reads Blizzard's built-in meter data (Midnight doesn't give addons the combat log). The damage meter must be turned on in Blizzard's settings. Numbers are hidden from addons during combat, so percentages and chat reports only appear after the fight.

What BitsjUI does **not** replace (buffs, quest tracker, XP bar, extra button, micro menu position, minimap size) you move with Blizzard's **Edit Mode**. There's a button for it under *Movement* in the menu.

## Your own font
Put a `.ttf` file at `BitsjUI\Media\Fonts\Custom.ttf`, restart the game completely, and pick **Custom (Custom.ttf)**.

## Profiles
Profiles are shared across all your characters. Under *Profiles* you can export a string (`BUI1:...`) and import it on another account or computer.

## About Midnight and "secret values"
In Midnight, Blizzard hides some combat values from addons. BitsjUI sends health, power and cast data straight into Blizzard's own widgets, which accept these values. If a number is hidden, the text falls back to something simpler instead of throwing errors (for example, the castbar shows the spell name without a timer).

## WoW Forever
The TOC also includes interface `16001` (Forever runs on the Retail client), so the addon loads there too. It's built and tested for Retail first. Forever may have its own limitations.

## License
Code: free to use and modify. Fonts in `Media/Fonts` are under the SIL Open Font License 1.1 (see `OFL.txt`).
