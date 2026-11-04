# BitsjUI 1.4.0

## New
- Ready for the **WoW Forever** launch (1.60.1): the melee and off-hand swing timer uses the game's new swing events and fades while you're out of range. The new empty bag-slot icons are hidden.
- Damage meter: its own settings window (the gear on the meter, or **/bui meter**) with text, font, outline, colours, title bar and update rates for each window. The title bar buttons are now icons.
- Nameplates: quest mobs are purple, so they stand out. Mobs you need for a quest item (like pelts) are found through Questie too, and on Classic / Forever through the tooltip's quest lines.
- MiniAuras: BitsjUI notices when MiniAuras is installed and offers to open the setup.

## Fixed
- Spell timers on target, focus and party frames sometimes showed auras from a previous target.
- The quest window cut its text off.
- The /bui menu couldn't be closed or minimized in combat.
- Unit frame borders: the rounded corners are filled and the small gaps around the frames are gone.

# BitsjUI 1.3.1

## New
- Nameplates: switches for friendly player and friendly NPC nameplates (/bui > Nameplates).
- Nameplates: neutral mobs have their own colour (no longer the same yellow as rogues). Change it under /bui > Nameplates > Mob colours.

# BitsjUI 1.3.0

## New
- Party tracking with **MiniAuras** (formerly MiniCC): crowd control right of each party tile, defensives left of it, and the party interrupt tracker right under the party frames, all styled to match BitsjUI. **MiniAuras is optional and only needed for this tracking**; BitsjUI works fine without it. Set it up in the installer or in /bui > Party & raid > Fit MiniAuras to BitsjUI.
- Nameplates: interrupt indicator. Your interrupt sits next to enemy castbars: a green frame when it's ready, grey with a countdown while on cooldown, and a line on the castbar where it comes back (red icon if it won't be back before the cast ends). Hidden on casts that can't be interrupted.
- Shields / absorbs on nameplates, unit frames and party / raid frames.
- Target frame: a buff row above the debuffs (/bui > Unit frames > Target).
- Party and raid frames show the unit tooltip on hover.

## Fixed
- Reload buttons were blocked by the game ("Interface action failed because of an AddOn").
- An error about nameplates after the UI scale changed inside a dungeon.

# BitsjUI 1.1.2

## Fixed
- The "What's new" window cut its text off after the first line. It now shows every change and grows to fit.

# BitsjUI 1.1.1

## New
- Defensives: a row of icons right above the player frame (over your name) while a defensive is active on you. It covers every class: Divine Shield, Ice Block, Barkskin, Shield Wall, Astral Shift, Cloak of Shadows, Obsidian Scales and many more, plus defensives others cast on you (Pain Suppression, Blessing of Protection, Ironbark...). Icons fade in and show the time left as a sweep and a countdown.
- Settings in /bui > Defensives: icon size, spacing, gap, max icons, and your own spell IDs to add or leave out.
