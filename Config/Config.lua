--[[
	BitsjUI - Config window
	/bui (or /bitsjui) opens the menu. Every option applies live where the
	client allows it; options marked with * need a /reload.
]]
local _, B = ...
local W = B.Widgets
local C = W.colors

local Config = {}
B.Config = Config

local WIDTH, HEIGHT = 920, 640
local SIDEBAR = 190
local CONTENT_W = WIDTH - SIDEBAR - 60

-------------------------------------------------------------------------------
-- option helpers bound to a db path
-------------------------------------------------------------------------------
local function Updater(module)
	return function()
		if type(module) == "function" then return module() end
		local m = B:GetModule(module)
		if m and m.Update then B:Try(m.Update, m) end
	end
end

local O = {}

-- options whose label ends with * need a reload; remember that one changed
local function Track(label)
	if label and label:find("%*") then Config:MarkReload() end
end
function O.check(lay, label, path, module, tooltip)
	local update = Updater(module)
	return lay:Add(W.Check(lay.content, label,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update(); Track(label) end, tooltip))
end

function O.slider(lay, label, path, minV, maxV, step, module, fmt, tooltip)
	local update = Updater(module)
	return lay:Add(W.Slider(lay.content, label, minV, maxV, step,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); Track(label) end, fmt, update, tooltip))
end

function O.dropdown(lay, label, path, options, module, tooltip)
	local update = Updater(module)
	return lay:Add(W.Dropdown(lay.content, label, options,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update(); Track(label) end, tooltip))
end

function O.color(lay, label, path, module, hasAlpha)
	local update = Updater(module)
	return lay:Add(W.Color(lay.content, label,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update(); Track(label) end, hasAlpha))
end

-- text setting, saved when Enter is pressed or focus leaves the box
function O.input(lay, label, path, module)
	local update = Updater(module)
	local w = lay:Add(W.Input(lay.content, label))
	w.edit:SetText(tostring(B:GetPath(path) or ""))
	local function save(eb)
		B:SetPath(path, eb:GetText()); update(); Track(label)
	end
	w.edit:SetScript("OnEnterPressed", function(eb) save(eb); eb:ClearFocus() end)
	w.edit:SetScript("OnEditFocusLost", save)
	return w
end

local function FontOptions()
	local out = {}
	for _, name in ipairs(B:GetFontList()) do
		local file = B.media.fonts[name]
		out[#out + 1] = { value = name, label = name, font = file and not name:find("Custom") and file or nil }
	end
	return out
end

local function TextureOptions()
	local out = {}
	for _, name in ipairs(B:GetTextureList()) do out[#out + 1] = { value = name, label = name } end
	return out
end

local function ReloadNotice(lay)
	lay:Text("Options marked with * need a /reload to take effect.")
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
local pages = {}
local state = { bar = 1, unit = "player", cast = "player", meter = 1 }

local HEALTH_TEXT = {
	{ value = "split", label = "Value left, percent right" },
	{ value = "curmax", label = "Current / max" },
	{ value = "curmaxpct", label = "Current / max (percent)" },
	{ value = "both", label = "Current | percent" },
	{ value = "current", label = "Current" },
	{ value = "percent", label = "Percent" },
	{ value = "none", label = "None" },
}

pages[#pages + 1] = { key = "general", label = "General", build = function(lay)
	lay:Header("Scale")
	O.slider(lay, "UI scale", "general.uiScale", 0.40, 1.15, 0.01, function() B:ApplyUIScale() end, "%.2f",
		"Blizzard's own slider stops at 0.64. BitsjUI sets the scale directly, so 0.62 works.")
	lay:Add(W.Button(lay.content, "Set 0.62 (1440p, 27\")", 220, 26, function()
		B.db.general.uiScale = 0.62
		B:ApplyUIScale()
		lay:RefreshAll()
	end))
	local w, h = GetPhysicalScreenSize()
	lay:Text("Your screen is " .. tostring(w) .. "x" .. tostring(h) .. ". Pixel-perfect scale for 1440p is 0.533; 0.62 makes everything a little larger while staying crisp.")

	lay:Header("Font and texture")
	O.dropdown(lay, "Font", "general.font", FontOptions, function()
		B:GetModule("General"):Update(); B:UpdateAll()
	end)
	O.dropdown(lay, "Outline", "general.fontOutline", B.outlines, function() B:RefreshFonts(); B:UpdateAll() end)
	O.dropdown(lay, "Bar texture", "general.texture", TextureOptions, function() B:RefreshTextures(); B:UpdateAll() end)
	O.slider(lay, "Bar colour brightness", "general.colorBrightness", 0.5, 1, 0.01, function() B:RefreshBarColors() end, "%.2f",
		"Darkens every bar colour (unit frames, raid, nameplates, meter...). 1 = full Blizzard colours.")
	O.slider(lay, "Bar colour strength", "general.colorSaturation", 0.3, 1, 0.01, function() B:RefreshBarColors() end, "%.2f",
		"Lower = calmer, greyer colours. 1 = full Blizzard colours.")
	O.check(lay, "Text shadow", "general.fontShadow", function() B:RefreshFonts() end)
	O.check(lay, "Sharp text (vector rendering) *", "general.sharpText", function() B:RefreshFonts() end,
		"Draws text as smooth vectors so it stays crisp at 0.62 UI scale. Blizzard's own text changes after a reload.")
	O.dropdown(lay, "Frame corners", "general.borderStyle", {
		{ value = "rounded", label = "Rounded" },
		{ value = "sharp", label = "Sharp" },
	}, function() B:RefreshBorders() end)
	O.slider(lay, "Corner roundness", "general.cornerRadius", 2, 8, 1, function() B:RefreshBorders() end)
	O.slider(lay, "Icon crop", "general.iconZoom", 0, 0.2, 0.01, function() B:RefreshIcons() end, "%.2f")
	O.slider(lay, "Icon inner shadow", "general.iconShadow", 0, 1, 0.05, function() B:RefreshIcons() end, "%.2f")
	O.slider(lay, "Icon gloss", "general.iconGloss", 0, 1, 0.05, function() B:RefreshIcons() end, "%.2f")
	O.check(lay, "Use the font in the whole game *", "general.replaceGameFonts", "General",
		"Replaces Blizzard's fonts (quests, menus, tooltips) with the chosen font. Names above heads need a /reload.")

	lay:Header("Colours")
	lay:Header("Theme")
	O.dropdown(lay, "Theme colour *", "general.themeMode", {
		{ value = "class", label = "Your class" },
		{ value = "faction", label = "Your faction" },
		{ value = "custom", label = "Custom (accent colour below)" },
	}, "General", "Highlights, lines, the menu and move mode take on this colour. Changes with every character you log in to.")
	O.color(lay, "Accent colour (custom) *", "general.accent", function() end)
	O.slider(lay, "Panel tint *", "general.themeTint", 0, 0.3, 0.01, "General", "%.2f",
		"How much dark panels take on the theme colour.")
	O.check(lay, "Borders in the theme colour *", "general.themeBorders", "General",
		"A deep shade of your class / faction colour instead of black.")
	O.check(lay, "Faction emblem on the minimap bar", "general.factionCrest", "Minimap")
	O.check(lay, "Greeting at login", "general.welcome", "General")
	O.check(lay, "BitsjUI button in the Esc menu", "general.gameMenuButton", "General", "Opens this menu from the Esc (game) menu.")
	O.color(lay, "Background *", "general.backdrop", function() end, true)

	lay:Header("Declutter")
	O.check(lay, "Hide the bag bar", "general.hideBagsBar", "General", "Bags still open with B.")
	O.check(lay, "Micro menu on mouseover only", "general.microMenuMouseover", "General")
	O.check(lay, "Hide talking heads", "general.hideTalkingHead", "General")
	O.check(lay, "Hide red error text", "general.hideErrors", "General", "\"Not enough rage\" and similar.")
	O.check(lay, "Minimap button", "general.minimapButton.show", function() Config:UpdateMinimapButton() end)
	O.check(lay, "Preview while this menu is open", "general.previewInMenu", function() B:SetPreview(B.db.general.previewInMenu) end,
		"Shows your own character in the target / focus / pet frames, sample castbars, spell timers and a sample nameplate, so you see every change right away.")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "actionbars", label = "Action bars", build = function(lay, rebuild)
	local AB = B:GetModule("ActionBars")
	lay:Header("All bars")
	O.check(lay, "Enable BitsjUI action bars *", "actionbars.enabled", "ActionBars")
	O.check(lay, "Red icon when out of range", "actionbars.range", "ActionBars")
	O.check(lay, "Show keybinds", "actionbars.showHotkey", "ActionBars")
	O.check(lay, "Short keybinds (S1, C2, M4)", "actionbars.abbreviate", "ActionBars")
	O.check(lay, "Show macro names", "actionbars.showMacro", "ActionBars")
	O.check(lay, "Show counts (charges)", "actionbars.showCount", "ActionBars")
	O.check(lay, "Show empty buttons", "actionbars.emptyButtons", "ActionBars")
	lay:Add(W.Button(lay.content, "Set keybinds (Quick Keybind)", 280, 26, function()
		if InCombatLockdown() then return end
		if QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end
	end))
	O.slider(lay, "Keybind size", "actionbars.hotkeySize", 8, 20, 1, "ActionBars")
	O.slider(lay, "Count size", "actionbars.countSize", 8, 20, 1, "ActionBars")

	lay:Header("Cooldowns")
	O.check(lay, "BitsjUI cooldown display", "actionbars.bitsjCooldowns", "ActionBars",
		"Draws the cooldown swipe and numbers from the game's own cooldown data. Works in combat in Midnight.")
	O.check(lay, "Dim icon while on cooldown", "actionbars.desaturateCD", "ActionBars", "Also for charge spells at 0 charges.")
	O.slider(lay, "Button border thickness", "actionbars.borderSize", 1, 4, 1, "ActionBars")
	O.check(lay, "Show global cooldown (light swipe)", "actionbars.showGCD", "ActionBars")

	lay:Header("Button feel")
	O.check(lay, "Animation on press", "actionbars.pressAnim", "ActionBars",
		"A short flash and a small \"click\" in the icon every time a button is pressed, by key or mouse.")
	O.dropdown(lay, "Style", "actionbars.pressStyle", {
		{ value = "both", label = "Flash + click" },
		{ value = "flash", label = "Flash only" },
		{ value = "pop", label = "Click only (shrink)" },
	}, "ActionBars")
	O.check(lay, "Flash in accent colour", "actionbars.pressAccent", "ActionBars")
	O.check(lay, "Hide Blizzard's cast animation on buttons", "actionbars.hideCastAnim", "ActionBars",
		"Blizzard's animations are made for bigger buttons and look messy on BitsjUI buttons.")

	lay:Header("Choose bar")
	local opts = {}
	for _, id in ipairs(AB.order) do opts[#opts + 1] = { value = id, label = AB.BARS[id].label } end
	lay:Add(W.Dropdown(lay.content, "Bar", opts, function() return state.bar end, function(v) state.bar = v; rebuild() end))
	lay:NewLine()

	local p = "actionbars.bars." .. tostring(state.bar) .. "."
	local maxButtons = AB.BARS[state.bar].num
	O.check(lay, "Show this bar", p .. "enabled", "ActionBars")
	O.check(lay, "Show on mouseover only", p .. "mouseover", "ActionBars")
	O.slider(lay, "Buttons", p .. "buttons", 1, maxButtons, 1, "ActionBars")
	O.slider(lay, "Buttons per row", p .. "perRow", 1, maxButtons, 1, "ActionBars")
	O.slider(lay, "Button size", p .. "size", 16, 64, 1, "ActionBars")
	O.slider(lay, "Spacing", p .. "spacing", 0, 12, 1, "ActionBars")
	O.slider(lay, "Opacity", p .. "alpha", 0, 1, 0.05, "ActionBars", "%.2f")
	O.slider(lay, "Opacity without mouse", p .. "mouseoverAlpha", 0, 1, 0.05, "ActionBars", "%.2f")
	lay:Text("Tip: keep Blizzard's action bars 2-8 enabled under Options > Action Bars so their keybinds work. BitsjUI hides their art.")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "unitframes", label = "Unit frames", build = function(lay, rebuild)
	local UF = B:GetModule("UnitFrames")
	lay:Header("All frames")
	O.check(lay, "Enable BitsjUI unit frames *", "unitframes.enabled", "UnitFrames")
	O.dropdown(lay, "Style", "unitframes.style", {
		{ value = "clean", label = "Clean (slim bars, level above)" },
		{ value = "portrait", label = "Portrait (round portrait, values)" },
	}, "UnitFrames")
	O.dropdown(lay, "Portrait", "unitframes.portraitStyle", {
		{ value = "3d", label = "Character portrait" },
		{ value = "class", label = "Class icon (players)" },
		{ value = "none", label = "No portrait" },
	}, "UnitFrames")
	O.dropdown(lay, "Health colour", "unitframes.healthColor", {
		{ value = "class", label = "Class / reaction" },
		{ value = "dark", label = "Dark" },
		{ value = "custom", label = "Custom" },
	}, "UnitFrames")
	O.dropdown(lay, "Name colour", "unitframes.nameColor", {
		{ value = "gold", label = "Gold" },
		{ value = "class", label = "Class / reaction" },
		{ value = "white", label = "White" },
	}, "UnitFrames")
	O.color(lay, "Custom health colour", "unitframes.customHealth", "UnitFrames")
	O.color(lay, "Dark health colour", "unitframes.darkHealth", "UnitFrames")
	O.slider(lay, "Bar background (share of colour)", "unitframes.bgMultiplier", 0, 1, 0.05, "UnitFrames", "%.2f")
	O.slider(lay, "Border thickness", "unitframes.borderSize", 1, 5, 1, "UnitFrames")
	O.slider(lay, "Health text size", "unitframes.fontSize", 8, 24, 1, "UnitFrames")
	O.slider(lay, "Power text size", "unitframes.smallFontSize", 7, 20, 1, "UnitFrames")
	O.slider(lay, "Name size", "unitframes.nameSize", 7, 20, 1, "UnitFrames")

	if not B.isClassic then
		lay:Header("Cooldown Manager")
		lay:Text("Player and target frames sit on either side of Blizzard's Cooldown Manager (the Essential row) and move out or in as it grows or shrinks. Pet and target of target follow. Place the Cooldown Manager itself with Edit Mode.")
		O.check(lay, "Fit around the Cooldown Manager", "unitframes.fitCDM", "UnitFrames")
		O.slider(lay, "Gap to the Cooldown Manager", "unitframes.cdmGap", 0, 40, 1, "UnitFrames")
	end

	lay:Header("Choose frame")
	local opts = {}
	for _, def in ipairs(UF.UNITS) do opts[#opts + 1] = { value = def.key, label = def.label } end
	lay:Add(W.Dropdown(lay.content, "Frame", opts, function() return state.unit end, function(v) state.unit = v; rebuild() end))
	lay:NewLine()

	local p = "unitframes." .. state.unit .. "."
	O.check(lay, "Show this frame *", p .. "enabled", "UnitFrames", "Turning it off again needs a /reload to bring back Blizzard's frame.")
	O.check(lay, "Show name", p .. "showName", "UnitFrames")
	if state.unit == "target" or state.unit == "focus" then
		O.check(lay, "Level badge", p .. "showLevel", "UnitFrames")
	end
	if state.unit == "pet" and B.classicContent then
		O.check(lay, "Pet happiness", p .. "happiness", "UnitFrames", "Hunter pets: a face beside the frame (green happy, yellow content, red unhappy). Hover it for damage and loyalty.")
	end
	lay:NewLine()
	O.dropdown(lay, "Health text", p .. "healthText", HEALTH_TEXT, "UnitFrames")
	O.dropdown(lay, "Power text", p .. "powerText", {
		{ value = "curmax", label = "Current / max" },
		{ value = "current", label = "Current" },
		{ value = "percent", label = "Percent" },
		{ value = "none", label = "None" },
	}, "UnitFrames")
	O.slider(lay, "Bar width", p .. "width", 40, 400, 1, "UnitFrames")
	O.slider(lay, "Portrait size", p .. "portraitSize", 0, 120, 1, "UnitFrames")
	O.slider(lay, "Health height", p .. "healthHeight", 4, 60, 1, "UnitFrames")
	O.slider(lay, "Power height", p .. "powerHeight", 0, 30, 1, "UnitFrames")
	if state.unit == "target" then
		lay:Header("Target auras")
		O.check(lay, "Show auras", p .. "auras.enabled", "UnitFrames")
		O.check(lay, "Mine only", p .. "auras.onlyPlayer", "UnitFrames")
		O.check(lay, "Buffs instead of debuffs", p .. "auras.buffs", "UnitFrames")
		lay:NewLine()
		O.slider(lay, "Count", p .. "auras.num", 1, 16, 1, "UnitFrames")
		O.slider(lay, "Size *", p .. "auras.size", 14, 48, 1, "UnitFrames")
	end
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "raidframes", label = "Party & raid", build = function(lay, rebuild)
	lay:Header("Party & raid frames")
	local RF = B:GetModule("RaidFrames")
	lay:Add(W.Button(lay.content, "Preview party", 140, 26, function() RF:SetPreview("party") end))
	lay:Add(W.Button(lay.content, "Preview raid (20)", 160, 26, function() RF:SetPreview("raid20") end))
	lay:Add(W.Button(lay.content, "Preview raid (40)", 160, 26, function() RF:SetPreview("raid40") end))
	lay:Add(W.Button(lay.content, "Hide preview", 140, 26, function() RF:SetPreview(nil) end))
	lay:NewLine()
	if _G.MiniAurasApi then
		lay:Header("MiniAuras")
		lay:Text("MiniAuras puts its crowd control, defensive and important-buff icons on BitsjUI's party and raid tiles. This button sets its size, placement and font to match BitsjUI (crowd control right of each party tile, defensives left of it). Reloads the UI.")
		lay:Add(W.Button(lay.content, "Fit MiniAuras to BitsjUI", 200, 26, function() B:GetModule("MiniAuras"):ApplyLayout() end))
		lay:NewLine()
	end
	O.check(lay, "BitsjUI party / raid frames *", "raidframes.enabled", "RaidFrames")
	O.check(lay, "Hide Blizzard's party / raid frames *", "raidframes.hideBlizzard", "RaidFrames")

	lay:Header("Settings for")
	state.rf = state.rf or "party"
	lay:Add(W.Dropdown(lay.content, "Frames", { { value = "party", label = "Party (5)" }, { value = "raid", label = "Raid" } },
		function() return state.rf end,
		function(v)
			state.rf = v
			if RF.previewKind then RF:SetPreview(v == "party" and "party" or "raid20") end
			rebuild()
		end))
	lay:NewLine()
	local p = "raidframes." .. state.rf .. "."
	O.check(lay, state.rf == "party" and "Use in party" or "Use in raid", p .. "show", "RaidFrames")
	lay:Header("Size")
	O.slider(lay, "Width", p .. "width", 50, 220, 1, "RaidFrames")
	O.slider(lay, "Height", p .. "height", 20, 100, 1, "RaidFrames")
	O.slider(lay, "Spacing", p .. "spacing", 0, 20, 1, "RaidFrames")
	O.slider(lay, "Border thickness", p .. "borderSize", 1, 4, 1, "RaidFrames")
	lay:Header("Look")
	O.dropdown(lay, "Health colour", p .. "colorMode", {
		{ value = "class", label = "Class colour" },
		{ value = "dark", label = "Dark (missing health in class colour)" },
	}, "RaidFrames")
	O.dropdown(lay, "Name colour", p .. "nameColor", {
		{ value = "white", label = "White" },
		{ value = "class", label = "Class colour" },
	}, "RaidFrames")
	O.slider(lay, "Name size", p .. "nameSize", 7, 18, 1, "RaidFrames")
	if state.rf == "raid" then
		O.check(lay, "\"Group N\" labels", p .. "groupLabels", "RaidFrames")
		O.dropdown(lay, "Groups shown", p .. "groups", {
			{ value = "auto", label = "By raid size (20 = groups 1-4)" },
			{ value = "all", label = "All 8 groups" },
		}, "RaidFrames", "Inside a raid it follows the raid's size (Mythic 20 shows groups 1-4). Outside: by how many are in the group.")
	end
	O.check(lay, "Summon / resurrection icon", p .. "summonIcon", "RaidFrames")
	O.check(lay, "Tank / healer icon", p .. "roleIcon", "RaidFrames")
	O.check(lay, "Red edge when the unit has aggro", p .. "aggro", "RaidFrames")
	O.slider(lay, "Opacity out of range", p .. "rangeAlpha", 0.1, 1, 0.05, "RaidFrames", "%.2f")
	lay:Header("Auras")
	O.check(lay, "Important debuffs (bottom right)", p .. "debuffs", "RaidFrames")
	O.slider(lay, "Debuff size *", p .. "debuffSize", 10, 30, 1, "RaidFrames")
	O.check(lay, "Your HoTs / buffs (bottom left)", p .. "myBuffs", "RaidFrames")
	O.slider(lay, "Buff size *", p .. "buffSize", 8, 26, 1, "RaidFrames")
end }

pages[#pages + 1] = { key = "classpower", label = "Resource bar", build = function(lay)
	lay:Header("Class resource")
	lay:Text("Holy Power, combo points, chi, soul shards, arcane charges, essence and runes. The bar hides itself for specs without a class resource.")
	O.check(lay, "Show resource bar", "classpower.enabled", "ClassPower")
	O.check(lay, "Fade when idle out of combat", "classpower.fadeOOC", "ClassPower")
	O.check(lay, "Extra power bar (mana / energy) below", "classpower.showPowerBar", "ClassPower")
	O.check(lay, "Attach under the player frame (same width)", "classpower.attachToPlayer", "ClassPower")
	lay:NewLine()
	O.slider(lay, "Width", "classpower.width", 60, 400, 1, "ClassPower")
	O.slider(lay, "Height", "classpower.height", 4, 30, 1, "ClassPower")
	O.slider(lay, "Spacing", "classpower.spacing", 0, 10, 1, "ClassPower")
	O.slider(lay, "Power bar height", "classpower.powerHeight", 3, 20, 1, "ClassPower")
end }

pages[#pages + 1] = { key = "buffs", label = "Buffs", build = function(lay)
	lay:Header("Your buffs and debuffs")
	lay:Text("A row of your buffs (and debuffs below) next to the minimap, with time left under each icon. Right-click a buff to cancel it. Blizzard's own buff frame is hidden while this is on.")
	O.check(lay, "Show BitsjUI buffs *", "buffs.enabled", "Buffs")
	O.check(lay, "Hide Blizzard's buff frame *", "buffs.hideBlizzard", "Buffs")
	O.slider(lay, "Icon size *", "buffs.size", 16, 60, 1, "Buffs")
	O.slider(lay, "Icons per row", "buffs.perRow", 4, 24, 1, "Buffs")
	O.slider(lay, "Spacing", "buffs.spacing", 0, 12, 1, "Buffs")
	O.slider(lay, "Max buffs", "buffs.maxBuffs", 1, 40, 1, "Buffs")
	O.slider(lay, "Max debuffs", "buffs.maxDebuffs", 0, 16, 1, "Buffs")
	O.slider(lay, "Time text size *", "buffs.fontSize", 8, 18, 1, "Buffs")
	O.check(lay, "Hide permanent buffs", "buffs.collapsePassive", "Buffs",
		"Buffs without a timer (zone, warband, faction...) are hidden. Your paladin auras and the always-show list stay.")
	O.input(lay, "Always show (spell IDs, comma separated)", "buffs.alwaysShow", "Buffs")
	lay:Text("Move the buff block with /bui move (\"Buffs\").")
end }

pages[#pages + 1] = { key = "defensives", label = "Defensives", build = function(lay)
	lay:Header("Defensives")
	lay:Text("Icons right above your player frame while a defensive is active on you: your own (Divine Shield, Ice Block, Barkskin, Shield Wall, Astral Shift...) and ones others cast on you (Pain Suppression, Blessing of Protection, Ironbark...). All classes are covered. The sweep and number show the time left.")
	O.check(lay, "Show defensives *", "defensives.enabled", "Defensives")
	O.check(lay, "Above the player frame", "defensives.attach", "Defensives", "Turn off to place the icons freely with /bui move.")
	O.slider(lay, "Icon size *", "defensives.size", 16, 48, 1, "Defensives")
	O.slider(lay, "Spacing", "defensives.spacing", 0, 10, 1, "Defensives")
	O.slider(lay, "Gap above the name", "defensives.gap", 0, 30, 1, "Defensives")
	O.slider(lay, "Max icons", "defensives.max", 1, 10, 1, "Defensives")
	O.input(lay, "Also show (spell IDs, comma separated)", "defensives.extra", "Defensives")
	O.input(lay, "Never show (spell IDs, comma separated)", "defensives.ignore", "Defensives")
end }

pages[#pages + 1] = { key = "swing", label = "Swing timer", build = function(lay)
	lay:Header("Swing timer")
	lay:Text("Bars right above your castbar for your next white hit: main hand, off hand (dual wield) and ranged (Auto Shot, wands, throwing). They pop up while running or while you auto-attack. Heroic Strike, Cleave, Maul and Raptor Strike count as swings, and parrying speeds up your swing like it does in the game.")
	if B.isForever then lay:Text("|cffffd060WoW Forever hides the combat log from addons, so only the ranged bar (Auto Shot, wands, throwing) works here.|r") end
	O.check(lay, "Show swing timer *", "swing.enabled", "Swing")
	O.check(lay, "Above the player castbar", "swing.attachToCastbar", "Swing", "Same width as the castbar. Turn off to move it freely with the movers.")
	O.check(lay, "Melee", "swing.melee", "Swing")
	O.check(lay, "Off hand", "swing.offhand", "Swing")
	O.check(lay, "Ranged", "swing.ranged", "Swing")
	O.check(lay, "Labels and time left", "swing.showText", "Swing")
	lay:NewLine()
	O.color(lay, "Main hand colour", "swing.meleeColor", "Swing")
	O.color(lay, "Off hand colour", "swing.offColor", "Swing")
	O.color(lay, "Ranged colour", "swing.rangedColor", "Swing")
	lay:NewLine()
	O.slider(lay, "Bar height", "swing.height", 4, 30, 1, "Swing")
	O.slider(lay, "Space between bars", "swing.spacing", 0, 10, 1, "Swing")
	O.slider(lay, "Gap above the castbar", "swing.gap", 0, 30, 1, "Swing")
	O.slider(lay, "Width (when not attached)", "swing.width", 80, 600, 1, "Swing")
	O.slider(lay, "Text size", "swing.fontSize", 7, 18, 1, "Swing")
end }

pages[#pages + 1] = { key = "timers", label = "Spell timers", build = function(lay)
	lay:Header("Spell timers")
	lay:Text("Timer bars for your debuffs on the target and your own buffs. Since patch 12.1 the client itself fills in the icon, name, bar and time (it also works in combat). The bars stack downwards from the mover. Size and colour changes need a /reload.")
	O.slider(lay, "Max buffs", "timers.buffNum", 1, 16, 1, "Timers")
	O.slider(lay, "Max debuffs", "timers.debuffNum", 1, 16, 1, "Timers")
	O.check(lay, "Show spell timers", "timers.enabled", "Timers")
	O.check(lay, "My buffs", "timers.playerBuffs", "Timers")
	O.check(lay, "My debuffs on target", "timers.targetDebuffs", "Timers")
	O.check(lay, "Attach under the player frame", "timers.attachToPlayer", "Timers", "Same width as the player frame, growing downwards (below the class resource bar if that is attached too). Turn off to move the timers freely.")
	O.slider(lay, "Gap under the player frame", "timers.attachGap", 0, 30, 1, "Timers")
	O.check(lay, "Grow upwards (when not attached)", "timers.growUp", "Timers")
	O.color(lay, "Buff colour *", "timers.buffColor", "Timers")
	O.color(lay, "Debuff colour *", "timers.debuffColor", "Timers")
	O.slider(lay, "Width *", "timers.width", 100, 400, 1, "Timers")
	O.slider(lay, "Height *", "timers.height", 12, 40, 1, "Timers")
	O.slider(lay, "Spacing", "timers.spacing", 0, 10, 1, "Timers")
	O.slider(lay, "Gap between buffs and debuffs", "timers.groupGap", 0, 30, 1, "Timers")
	O.slider(lay, "Max bars", "timers.maxBars", 1, 20, 1, "Timers")
	O.slider(lay, "Text size *", "timers.fontSize", 8, 20, 1, "Timers")
end }

pages[#pages + 1] = { key = "castbars", label = "Castbars", build = function(lay, rebuild)
	local CB = B:GetModule("Castbars")
	lay:Header("All castbars")
	O.check(lay, "Enable BitsjUI castbars *", "castbars.enabled", "Castbars")
	O.slider(lay, "Text size", "castbars.fontSize", 8, 20, 1, "Castbars")
	O.color(lay, "Cast", "castbars.castColor", "Castbars")
	O.color(lay, "Channel", "castbars.channelColor", "Castbars")
	O.color(lay, "Not interruptible", "castbars.nonInterruptColor", "Castbars")
	O.color(lay, "Interrupted / failed", "castbars.failColor", "Castbars")

	lay:Header("Choose castbar")
	local opts = {}
	for _, def in ipairs(CB.UNITS) do opts[#opts + 1] = { value = def.key, label = def.label } end
	lay:Add(W.Dropdown(lay.content, "Castbar", opts, function() return state.cast end, function(v) state.cast = v; rebuild() end))
	lay:NewLine()
	local p = "castbars." .. state.cast .. "."
	O.check(lay, "Show castbar *", p .. "enabled", "Castbars")
	O.check(lay, "Icon", p .. "icon", "Castbars")
	if state.cast ~= "player" then
		O.check(lay, "Attach under the unit frame (same width)", p .. "attach", "Castbars")
	end
	O.check(lay, "Timer", p .. "timer", "Castbars")
	O.check(lay, "Spark", p .. "spark", "Castbars")
	if state.cast == "player" then
		O.check(lay, "Show latency", p .. "latency", "Castbars", "Red zone at the end = time you can queue the next spell.")
	end
	lay:NewLine()
	O.slider(lay, "Width", p .. "width", 80, 600, 1, "Castbars")
	O.slider(lay, "Height", p .. "height", 8, 48, 1, "Castbars")
	lay:Text("Castbars show a preview while frames are unlocked, so you can drag them.")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "nameplates", label = "Nameplates", build = function(lay)
	lay:Header("Nameplates")
	lay:Text("BitsjUI draws its own clean plate and makes Blizzard's plates invisible (they can still be clicked). Note: friendly plates inside instances are locked by Blizzard, so they become invisible too while BitsjUI plates are on.")
	O.check(lay, "BitsjUI nameplates *", "nameplates.enabled", "Nameplates")
	O.check(lay, "Class colours on players", "nameplates.classColors", "Nameplates")
	O.check(lay, "Show level", "nameplates.showLevel", "Nameplates")
	O.check(lay, "Name above the bar", "nameplates.nameAbove", "Nameplates")
	O.check(lay, "Stack plates (no overlap) *", "nameplates.stacking", "Nameplates")
	O.dropdown(lay, "Health text", "nameplates.healthText", {
		{ value = "both", label = "2.0K (64.1%)" },
		{ value = "value", label = "2.0K" },
		{ value = "percent", label = "64.1%" },
		{ value = "none", label = "None" },
	}, "Nameplates")
	lay:NewLine()
	O.slider(lay, "Width", "nameplates.width", 60, 300, 1, "Nameplates")
	O.slider(lay, "Height", "nameplates.height", 4, 40, 1, "Nameplates")
	O.slider(lay, "Health text size", "nameplates.fontSize", 6, 18, 1, "Nameplates")
	O.slider(lay, "Name size", "nameplates.nameSize", 6, 20, 1, "Nameplates")
	O.slider(lay, "Target size", "nameplates.targetScale", 1, 1.6, 0.02, "Nameplates", "%.2f")
	O.check(lay, "Glow behind your target", "nameplates.targetGlow", "Nameplates")
	O.check(lay, "Arrows beside your target", "nameplates.targetArrows", "Nameplates")
	O.color(lay, "Target highlight colour", "nameplates.targetColor", "Nameplates")
	O.slider(lay, "Opacity of non-targets", "nameplates.nonTargetAlpha", 0.2, 1, 0.05, "Nameplates", "%.2f")
	O.slider(lay, "Max distance", "nameplates.maxDistance", 20, 60, 1, "Nameplates")

	lay:Header("Mob colours")
	O.check(lay, "Colour by mob type", "nameplates.colorByType", "Nameplates",
		"Quest mobs, casters (mobs with mana) and other elites (melee) get their own colour. Normal mobs stay red.")
	O.color(lay, "Quest mobs", "nameplates.questColor", "Nameplates")
	O.color(lay, "Casters", "nameplates.casterColor", "Nameplates")
	O.color(lay, "Melee (elites)", "nameplates.meleeColor", "Nameplates")

	lay:Header("Aggro")
	O.check(lay, "Show aggro edge", "nameplates.threat", "Nameplates",
		"Tank: green = you hold aggro, orange = losing it, red = not on you. Damage / healer: red = it's on you, orange = you're about to pull it.")
	O.color(lay, "Safe (tank holds it)", "nameplates.threatHigh", "Nameplates")
	O.color(lay, "Warning", "nameplates.threatWarn", "Nameplates")
	O.color(lay, "Danger", "nameplates.threatLow", "Nameplates")
	local NP = B:GetModule("Nameplates")
	local found = (#NP.stackCVars > 0) and table.concat(NP.stackCVars, ", ") or "none found"
	lay:Text("Stacking uses Blizzard's own \"Stack Nameplates\" option. BitsjUI switches it on for you (settings found: " .. found .. "). If plates still overlap, turn on Options > Nameplates > Stack Nameplates.")

	lay:Header("Debuffs and castbar")
	O.check(lay, "Show debuffs", "nameplates.debuffs", "Nameplates")
	O.check(lay, "Mine only", "nameplates.onlyMine", "Nameplates")
	O.slider(lay, "Debuff size *", "nameplates.debuffSize", 12, 40, 1, "Nameplates")
	O.slider(lay, "Max debuffs", "nameplates.debuffNum", 1, 10, 1, "Nameplates")
	lay:Header("Enemy buffs")
	O.check(lay, "Show buffs on enemies", "nameplates.buffs", "Nameplates")
	O.check(lay, "Glow on dispellable / stealable buffs *", "nameplates.dispelGlow", "Nameplates",
		"Pulsing border on buffs that can be purged or stolen (by you or someone in your group).")
	O.slider(lay, "Buff size *", "nameplates.buffSize", 12, 40, 1, "Nameplates")
	O.slider(lay, "Max buffs", "nameplates.buffNum", 1, 8, 1, "Nameplates")
	O.color(lay, "Glow colour *", "nameplates.glowColor", "Nameplates")
	lay:NewLine()
	lay:Header("Castbar")
	O.check(lay, "Show castbar", "nameplates.castbar", "Nameplates")
	O.slider(lay, "Castbar height", "nameplates.castHeight", 4, 24, 1, "Nameplates")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "cdm", label = "Cooldown Manager", build = function(lay)
	local CDM = B:GetModule("CooldownManager")
	lay:Header("Blizzard Cooldown Manager")
	lay:Text("Styles Blizzard's built-in Cooldown Manager (Essential, Utility, buff icons and buff bars) to match BitsjUI. Pick which spells to track in Blizzard's Cooldown Settings; position and size in Edit Mode.")
	lay:Add(W.Button(lay.content, "Choose spells (Cooldown Settings)", 300, 30, function() CDM:OpenSettings() end))
	lay:Add(W.Button(lay.content, "Move / resize (Edit Mode)", 300, 30, function()
		if InCombatLockdown() then return end
		Config:Hide()
		if EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
	end))
	lay:Header("Style")
	O.check(lay, "Style the Cooldown Manager *", "cdm.enabled", "CooldownManager")
	O.check(lay, "Square, zoomed icons", "cdm.zoom", "CooldownManager")
	O.check(lay, "1px border", "cdm.border", "CooldownManager")
	O.check(lay, "Hide Blizzard's icon frame", "cdm.hideOverlay", "CooldownManager")
	O.check(lay, "Flat buff bars", "cdm.styleBars", "CooldownManager")
	lay:NewLine()
	O.slider(lay, "Cooldown darkness", "cdm.swipeAlpha", 0, 1, 0.05, "CooldownManager", "%.2f")
	O.slider(lay, "Cooldown numbers", "cdm.countdownSize", 8, 28, 1, "CooldownManager")
	O.slider(lay, "Stacks / charges", "cdm.countSize", 8, 24, 1, "CooldownManager")
	O.slider(lay, "Buff bar text", "cdm.barFontSize", 8, 20, 1, "CooldownManager")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "meter", label = "Damage meter", build = function(lay, rebuild)
	local DMM = B:GetModule("DamageMeter")
	lay:Header("Damage meter")
	if B.isClassic then
		lay:Text("Reads the combat log, like Details: damage, healing, absorbs, interrupts, dispels, damage taken, deaths and damage per enemy. Pets and totems count for their owner. A fight ends when your whole group leaves combat and is named after the enemy that took the most damage. Title bar buttons: M = display, S = fight, X = reset, R = report.")
	else
		lay:Text("Built on Blizzard's built-in damage meter data (Midnight no longer gives addons the combat log). Numbers are hidden from addons in combat, so percentages and chat reports appear when the fight is over. Title bar buttons: M = display, S = fight, X = reset, R = report. Hover a player for a spell breakdown.")
	end
	O.check(lay, "Enable BitsjUI damage meter *", "meter.enabled", "DamageMeter")
	O.check(lay, "Hide Blizzard's meter window", "meter.hideBlizzard", "DamageMeter")
	O.slider(lay, "Update rate in combat (sec)", "meter.updateInterval", 0.1, 2, 0.1, "DamageMeter", "%.1f")
	O.check(lay, "Jump to the current fight when combat starts", "meter.autoCurrent", "DamageMeter")
	lay:Add(W.Text(lay.content, "Hover a player for every spell (trinkets, racials, pets). Left-click opens the full breakdown. Right-click a bar or scroll on the title to step through fights; < > in the title do the same."), true)
	lay:Add(W.Dropdown(lay.content, "Preset", DMM.PRESETS,
		function() return B.db.meter.preset end,
		function(v) DMM:ApplyPreset(v); rebuild() end,
		"Sets the look of all windows. You can tweak everything afterwards."))

	lay:Header("Choose window")
	lay:Add(W.Dropdown(lay.content, "Window", {
		{ value = 1, label = "Window 1" }, { value = 2, label = "Window 2" }, { value = 3, label = "Window 3" },
	}, function() return state.meter or 1 end, function(v) state.meter = v; rebuild() end))
	lay:NewLine()
	local p = "meter.windows." .. (state.meter or 1) .. "."
	O.check(lay, "Show window", p .. "enabled", "DamageMeter")
	O.dropdown(lay, "Display", p .. "meterType", DMM.TYPES, "DamageMeter")
	lay:Add(W.Dropdown(lay.content, "Fight", DMM.SESSIONS,
		function() return B:GetPath(p .. "sessionType") end,
		function(v)
			B:SetPath(p .. "sessionType", v)
			B:SetPath(p .. "sessionID", nil)
			DMM:Update()
		end))
	O.dropdown(lay, "Visibility", p .. "visibility", {
		{ value = "always", label = "Always" },
		{ value = "combat", label = "In combat only" },
		{ value = "group", label = "In a group only" },
	}, "DamageMeter")

	lay:Header("Text")
	O.dropdown(lay, "Number format", p .. "textFormat", {
		{ value = "both", label = "Total (per second)" },
		{ value = "total", label = "Total only" },
		{ value = "persec", label = "Per second only" },
	}, "DamageMeter")
	O.slider(lay, "Text size", p .. "fontSize", 8, 20, 1, "DamageMeter")
	O.check(lay, "Show percent", p .. "showPercent", "DamageMeter")
	O.check(lay, "Show rank (1. 2. 3.)", p .. "showRank", "DamageMeter")
	O.check(lay, "Always show me", p .. "alwaysShowMe", "DamageMeter", "If you're below the visible rows, you're shown at the bottom.")
	O.check(lay, "Show title bar", p .. "showTitle", "DamageMeter")

	lay:Header("Bars")
	O.check(lay, "Class colours", p .. "classColors", "DamageMeter")
	O.check(lay, "Spec icons", p .. "showIcons", "DamageMeter")
	O.slider(lay, "Bar height", p .. "barHeight", 10, 40, 1, "DamageMeter")
	O.slider(lay, "Spacing", p .. "barSpacing", 0, 8, 1, "DamageMeter")
	O.slider(lay, "Bar opacity", p .. "barAlpha", 0.1, 1, 0.05, "DamageMeter", "%.2f")
	O.slider(lay, "Bar background", p .. "barBgAlpha", 0, 1, 0.05, "DamageMeter", "%.2f")
	O.dropdown(lay, "Texture", p .. "texture", function()
		local out = { { value = "", label = "Same as the rest of the UI" } }
		for _, o in ipairs(TextureOptions()) do out[#out + 1] = o end
		return out
	end, "DamageMeter")
	lay:NewLine()

	lay:Header("Window")
	O.slider(lay, "Width", p .. "width", 140, 900, 1, "DamageMeter")
	O.slider(lay, "Height", p .. "height", 60, 900, 1, "DamageMeter")
	O.slider(lay, "Background", p .. "bgAlpha", 0, 1, 0.05, "DamageMeter", "%.2f")
	O.check(lay, "Fade out of combat", p .. "fadeOOC", "DamageMeter")
	O.slider(lay, "Opacity out of combat", p .. "fadeAlpha", 0, 1, 0.05, "DamageMeter", "%.2f")
	lay:Text("Move the window by dragging its title bar (or in move mode). Resize from the bottom-right corner. Scroll with the mouse wheel to see more.")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "minimap", label = "Minimap", build = function(lay)
	lay:Header("Minimap")
	O.check(lay, "Style the minimap *", "minimap.enabled", "Minimap")
	O.check(lay, "Square", "minimap.square", "Minimap")
	O.check(lay, "1px border", "minimap.border", "Minimap")
	O.check(lay, "Zoom with mouse wheel", "minimap.mouseZoom", "Minimap")
	O.check(lay, "Hide zoom buttons", "minimap.hideZoomButtons", "Minimap")
	O.dropdown(lay, "Clock", "minimap.clock", {
		{ value = "header", label = "In the header (right)" },
		{ value = "below", label = "Box below the map" },
		{ value = "off", label = "Off" },
	}, "Minimap")
	O.check(lay, "Coordinates", "minimap.coords", "Minimap")
	O.dropdown(lay, "Minimap buttons", "minimap.buttons", {
		{ value = "hover", label = "Show on mouseover" },
		{ value = "show", label = "Always show" },
		{ value = "hide", label = "Hide" },
	}, "Minimap", "Tracking, calendar, expansion summary, addon buttons and Blizzard's coordinates. Mail and dungeon difficulty always stay visible.")
	O.dropdown(lay, "Zone name", "minimap.zoneText", {
		{ value = "header", label = "Header above the map" },
		{ value = "hover", label = "On mouseover" },
		{ value = "hide", label = "Hidden" },
		{ value = "blizzard", label = "Blizzard's" },
	}, "Minimap")
	lay:Text("Minimap size and position are set in Edit Mode (see Movement).")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "chat", label = "Chat", build = function(lay)
	lay:Header("Chat")
	O.check(lay, "Style the chat *", "chat.enabled", "Chat")
	O.check(lay, "Hide chat buttons", "chat.hideButtons", "Chat")
	O.check(lay, "Flat edit box *", "chat.styleEditBox", "Chat")
	O.check(lay, "Clean tabs", "chat.styleTabs", "Chat")
	O.check(lay, "Text shadow", "chat.shadow", "Chat")
	O.slider(lay, "Text size (0 = Blizzard)", "chat.fontSize", 0, 24, 1, "Chat")
	O.check(lay, "Dark rounded chat panel", "chat.panel", "Chat")
	O.slider(lay, "Panel opacity", "chat.panelAlpha", 0, 1, 0.05, "Chat", "%.2f")
	O.slider(lay, "Border thickness", "chat.borderSize", 1, 4, 1, "Chat")
	O.slider(lay, "Tab text size", "chat.tabFontSize", 8, 20, 1, "Chat")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "tooltip", label = "Tooltips", build = function(lay)
	lay:Header("Tooltips")
	O.check(lay, "Dark tooltips *", "tooltip.enabled", "Tooltip")
	O.check(lay, "Class coloured border on players", "tooltip.classBorder", "Tooltip")
	O.check(lay, "Show health bar", "tooltip.healthBar", "Tooltip")
	O.check(lay, "Follow the mouse", "tooltip.cursor", "Tooltip")
	O.check(lay, "Hide unit tooltips in combat", "tooltip.hideInCombat", "Tooltip")
	ReloadNotice(lay)
end }

pages[#pages + 1] = { key = "character", label = "Character", build = function(lay)
	lay:Header("Character window")
	O.check(lay, "Restyle the character window *", "character.enabled", "Character",
		"Dark panel, flat tabs and clean gear icons with quality borders. Turning it off needs a reload.")
	O.check(lay, "Item level on each piece", "character.showIlvl", "Character", "Shown on the item icon in its quality colour.")
	O.check(lay, "Upgrade track (e.g. 4/6)", "character.showTrack", "Character", "Coloured by track: Veteran, Champion, Hero, Myth.")
	O.check(lay, "Enchant names", "character.showEnchants", "Character", "The enchant on each piece, in green, next to the slot.")
	O.check(lay, "Warn about missing enchants", "character.missingEnchants", "Character",
		"\"No enchant\" in red on helm, shoulders, chest, boots, rings and weapons when they have none.")
	O.check(lay, "Average item level in the title", "character.showAverage", "Character")
	O.check(lay, "Detailed stats *", "character.betterStats", "Character",
		"Secondary stats with two decimals and the rating behind them (e.g. 28.41%  1,234), item level as equipped / overall, flat headers.")
	O.check(lay, "Extra stats", "character.extraStats", "Character", "Mythic+ rating, movement speed and lowest durability under the stats.")
	O.slider(lay, "Item level text size", "character.ilvlSize", 8, 20, 1, "Character")
	O.slider(lay, "Enchant text size", "character.enchantSize", 7, 16, 1, "Character")
end }

pages[#pages + 1] = { key = "quests", label = "Quest tracker", build = function(lay)
	lay:Header("Quest tracker")
	O.check(lay, "Restyle the quest tracker *", "quests.enabled", "Quests",
		"Flat headers with a theme-coloured line and the UI font. Turning it off needs a reload.")
	O.check(lay, "Closest quest on top", "quests.sortByDistance", "Quests",
		"Re-sorts your tracked quests by distance every few seconds while you move (out of combat). Blizzard only does this when you change zone.")
	O.slider(lay, "Header text size", "quests.headerSize", 10, 20, 1, "Quests")
	O.slider(lay, "Quest text size", "quests.lineSize", 8, 18, 1, "Quests")
	O.check(lay, "Outlined text", "quests.outline", "Quests", "Easier to read on bright backgrounds.")
end }

pages[#pages + 1] = { key = "friends", label = "Friends", build = function(lay)
	lay:Header("Friends list")
	O.check(lay, "Restyle the friends list *", "friends.enabled", "Friends",
		"Dark panel and tiles in the BitsjUI look. Turning it off needs a reload.")
	O.check(lay, "Character names in class colour", "friends.classColors", "Friends")
	O.check(lay, "Class icon instead of the WoW logo", "friends.classIcons", "Friends")
	O.check(lay, "Faction tint on online friends", "friends.factionTint", "Friends",
		"A faint blue (Alliance) or red (Horde) wash on friends playing retail WoW.")
end }

pages[#pages + 1] = { key = "bags", label = "Bags", build = function(lay)
	lay:Header("Bags")
	O.check(lay, "Restyle Blizzard's bags *", "bags.enabled", "Bags", "Dark panel, clean icons and quality borders. Turning it off needs a reload.")
	O.slider(lay, "Panel opacity", "bags.alpha", 0.3, 1, 0.01, "Bags", "%.2f")
	O.check(lay, "Item border in quality colour", "bags.qualityBorders", "Bags")
	O.slider(lay, "Stack count size", "bags.countSize", 8, 18, 1, "Bags")
end }

pages[#pages + 1] = { key = "qol", label = "QoL", build = function(lay)
	lay:Header("Quality of life")
	O.check(lay, "Enable QoL features *", "qol.enabled", "QoL")
	lay:Header("Merchant & loot")
	O.check(lay, "Auto repair", "qol.autoRepair", "QoL")
	O.check(lay, "Use guild bank for repairs", "qol.guildRepair", "QoL", "Falls back to your own gold if the guild bank can't pay.")
	O.check(lay, "Auto sell junk (grey items)", "qol.sellJunk", "QoL")
	O.check(lay, "Fast loot", "qol.fastLoot", "QoL", "Loots everything at once. Hold Shift to see the loot window.")
	O.check(lay, "Type DELETE for you", "qol.autoDelete", "QoL", "Fills in the confirmation when deleting a good item.")
	O.check(lay, "Auction house: current expansion only", "qol.ahCurrentExpansion", "QoL")
	lay:Header("Cutscenes")
	O.check(lay, "Skip cinematics and movies", "qol.skipCinematics", "QoL", "Hold Shift when it starts to watch it anyway.")
	lay:Header("Group finder")
	O.check(lay, "Insert Mythic+ keystone automatically", "qol.autoKeystone", "QoL")
	O.check(lay, "Double-click a group to sign up", "qol.quickSignup", "QoL", "Also clicks Sign Up in the role dialog. Hold Shift to pick roles yourself.")
	O.check(lay, "Tell the group when you reset instances", "qol.announceReset", "QoL")
	lay:Header("Extras")
	O.check(lay, "FPS / latency text", "qol.fpsText", "QoL", "Move it with Unlock frames.")
	O.slider(lay, "FPS text size", "qol.fpsSize", 8, 20, 1, "QoL")
	O.check(lay, "Low durability warning", "qol.durabilityWarning", "QoL")
	O.slider(lay, "Warn below (%)", "qol.durabilityPercent", 5, 75, 5, "QoL")
	O.check(lay, "Open bags / caches automatically", "qol.openContainers", "QoL", "Out of combat, one at a time.")
	O.check(lay, "Hide the screenshot message", "qol.hideScreenshotText", "QoL")
end }

pages[#pages + 1] = { key = "movers", label = "Movement", build = function(lay)
	lay:Header("Drag and drop")
	lay:Add(W.Button(lay.content, "Unlock / lock frames", 260, 30, function() B.Movers:Toggle() end))
	lay:Add(W.Button(lay.content, "Reset all positions", 260, 30, function()
		StaticPopup_Show("BITSJUI_RESET_POSITIONS")
	end))
	O.slider(lay, "Grid size", "movers.grid", 4, 64, 2, function() B:Fire("UPDATE_ALL") end)
	O.check(lay, "Snap to grid", "movers.snap", function() end)
	O.check(lay, "Show grid in move mode", "movers.showGrid", function() end)
	lay:NewLine()
	lay:Text("Drag a frame with the left mouse button. Arrow keys move 1 pixel (Shift = one grid step). Hold Alt while dropping to skip snapping. Right-click resets the frame.")

	lay:Header("Layout")
	lay:Add(W.Button(lay.content, "Apply the BitsjUI default layout", 300, 30, function()
		StaticPopup_Show("BITSJUI_APPLY_LAYOUT")
	end))
	lay:Text("Puts every frame back to the default \"classic clean\" layout (portrait frames top left, spell timers and action bars bottom centre) and resets sizes.")

	lay:Header("Blizzard frames")
	lay:Text("Things BitsjUI does not replace (buffs, minimap, quest tracker, XP bar, extra button, micro menu) are moved with Blizzard's own drag and drop: Edit Mode.")
	lay:Add(W.Button(lay.content, "Open Edit Mode", 260, 30, function()
		if InCombatLockdown() then return end
		Config:Hide()
		if EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
	end))
end }

pages[#pages + 1] = { key = "profiles", label = "Profiles", build = function(lay, rebuild)
	lay:Header("Active profile")
	lay:Text("Active profile: |cffffffff" .. B.profileKey .. "|r. Profiles are shared by all characters on the account.")
	local function profileOptions()
		local out = {}
		for _, name in ipairs(B:GetProfiles()) do out[#out + 1] = { value = name, label = name } end
		return out
	end
	lay:Add(W.Dropdown(lay.content, "Switch profile", profileOptions, function() return B.profileKey end, function(v)
		B:SetProfile(v); B:UpdateAll(); rebuild()
	end))
	lay:Add(W.Dropdown(lay.content, "Copy from", profileOptions, function() return "" end, function(v)
		B:CopyProfile(v); B:UpdateAll(); rebuild()
	end))
	local input = lay:Add(W.Input(lay.content, "New profile (name)"))
	lay:Add(W.Button(lay.content, "Create and switch", 200, 26, function()
		local name = input.edit:GetText()
		if name and name ~= "" then B:SetProfile(name); B:UpdateAll(); rebuild() end
	end))
	lay:Add(W.Button(lay.content, "Reset this profile", 260, 26, function()
		StaticPopup_Show("BITSJUI_RESET_PROFILE")
	end))
	lay:Add(W.Button(lay.content, "Delete the profile named above", 260, 26, function()
		local name = input.edit:GetText()
		if name and BitsjUIDB.profiles[name] and B:DeleteProfile(name) then
			B:Print("Deleted profile " .. name); rebuild()
		else
			B:Print("Can't delete that one (doesn't exist, is active, or is Default).")
		end
	end))

	lay:Header("Export / import")
	local box = lay:Add(W.EditBox(lay.content, 140), true)
	lay:Add(W.Button(lay.content, "Export", 160, 26, function()
		box.edit:SetText(B:ExportProfile())
		box.edit:HighlightText()
		box.edit:SetFocus()
	end))
	local status = W.Text(lay.content, "")
	lay:Add(W.Button(lay.content, "Import (paste above)", 220, 26, function()
		local ok, msg = B:ImportProfile(box.edit:GetText())
		status.text:SetText(msg)
		if ok then B:UpdateAll() end
	end))
	lay:Add(status, true)
	lay:Text("Ctrl+C copies the export. Importing replaces the active profile.")
end }

pages[#pages + 1] = { key = "errors", label = "Errors", build = function(lay, rebuild)
	lay:Header("Caught errors")
	local log = B.errorLog or {}
	if #log == 0 then
		lay:Text("No BitsjUI errors this session.")
		return
	end
	lay:Text(#log .. " unique error(s) this session. Copy the text below (Ctrl+A, Ctrl+C) and send it if something looks wrong.")
	local box = lay:Add(W.EditBox(lay.content, 300), true)
	local lines = {}
	for _, e in ipairs(log) do
		lines[#lines + 1] = string.format("[%s] x%d  %s", e.time or "", e.count or 1, e.msg)
		if e.stack then lines[#lines + 1] = e.stack end
		lines[#lines + 1] = ""
	end
	box.edit:SetText(table.concat(lines, "\n"))
	lay:Add(W.Button(lay.content, "Clear", 120, 26, function()
		wipe(B.errorLog); wipe(B.errorSeen); rebuild()
	end))
end }

pages[#pages + 1] = { key = "about", label = "Help", build = function(lay)
	lay:Header(B:TitleText() .. "  v" .. B.version)
	lay:Text("Commands:\n/bui  - open this menu\n/bui move  - unlock / lock frames (drag and drop)\n/bui reset  - reset all positions\n/bui errors  - show caught errors\n/bui install  - run the setup again\n/bui delete <name>  - delete a profile\n/bui version  - your version and the newest one seen\n/bui whatsnew  - what changed in this version\n/rl  - reload the UI")
	lay:Header("Updates")
	lay:Text("Addons can't go online, so BitsjUI hears about new versions from other BitsjUI users in your guild and group (a hidden addon message). Install updates with the CurseForge / Wago app, then /reload.")
	O.check(lay, "Tell me when a newer version is out", "general.updateNotify", "Update")
	O.check(lay, "Show \"What's new\" after updating", "general.whatsNew", "Update")
	lay:Add(W.Button(lay.content, "What's new", 140, 26, function() B:GetModule("Update"):ShowWhatsNew() end))
	lay:Header("About")
	lay:Text("Made for Retail (Midnight 12.x) at 2560x1440 with UI scale 0.62. Frames use Blizzard's own buttons and APIs, so combat data the client hides from addons (\"secret values\") is still shown correctly.")
	lay:Text("Your own font: put a .ttf file at Interface\\AddOns\\BitsjUI\\Media\\Fonts\\Custom.ttf, restart the game and pick \"Custom (Custom.ttf)\".")
end }

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local frame, current

-------------------------------------------------------------------------------
-- Page groups (sidebar sections) and one-line descriptions
-------------------------------------------------------------------------------
local GROUPS = { "Look & feel", "Combat", "Frames", "Interface", "Tools", "Help" }
local META = {
	general     = { "Look & feel", "UI scale, fonts, bar textures, colours and the class / faction theme." },
	actionbars  = { "Combat", "Action bar size, layout, mouseover, cooldowns and the button-press feel." },
	cdm         = { "Combat", "Restyles Blizzard's Cooldown Manager (the tracked spell and buff icons)." },
	castbars    = { "Combat", "Player, target and focus castbars: size, colours, icon and where they sit." },
	timers      = { "Combat", "Bars for your own debuffs on the target, with time left." },
	swing       = { "Combat", "Melee and ranged swing timers right above your castbar." },
	defensives  = { "Combat", "Your active defensives (and ones cast on you) as icons above the player frame." },
	classpower  = { "Combat", "Holy Power, combo points, runes and other class resources." },
	unitframes  = { "Frames", "Player, target, focus, pet and target-of-target frames." },
	raidframes  = { "Frames", "Party and raid frames, with separate settings for each. Use Preview to set them up solo." },
	nameplates  = { "Frames", "Enemy nameplates: size, target highlight, mob colours, aggro, debuffs and castbars." },
	buffs       = { "Frames", "Your buffs and debuffs next to the minimap." },
	meter       = { "Interface", "The damage meter windows: what they show, look and fights (segments)." },
	minimap     = { "Interface", "Square minimap, zone and clock bar, and tidy minimap buttons." },
	chat        = { "Interface", "Chat font, panel, tabs and edit box." },
	tooltip     = { "Interface", "Tooltip look and extra information." },
	bags        = { "Interface", "Dark bag windows with clean icons and quality borders." },
	character   = { "Interface", "Character window: item level, enchants and gems on every piece of gear." },
	quests      = { "Interface", "Quest tracker look (fonts, flat headers) and keeping the closest quest on top." },
	friends     = { "Interface", "Friends list with class colours, class icons and the BitsjUI look." },
	qol         = { "Tools", "Small automations: repair, sell junk, fast loot, keystones, sign-up and more." },
	movers      = { "Tools", "Move every frame, grid and snapping, and reset positions." },
	profiles    = { "Tools", "Save, switch, copy, import and export your whole setup." },
	errors      = { "Help", "Lua errors BitsjUI has caught, ready to copy." },
	about       = { "Help", "Commands and how BitsjUI works." },
}

-- sort: by group, then alphabetically inside the group
-- pages for systems this client doesn't have
local CLASSIC_HIDDEN = { cdm = true }
local RETAIL_HIDDEN = { swing = true }   -- needs the combat log

local function SortPages()
	local hidden = (B.isClassic and CLASSIC_HIDDEN) or (B.isRetail and RETAIL_HIDDEN) or {}
	for i = #pages, 1, -1 do
		if hidden[pages[i].key] then table.remove(pages, i) end
	end
	local order = {}
	for i, g in ipairs(GROUPS) do order[g] = i end
	for _, p in ipairs(pages) do
		local m = META[p.key]
		p.group = m and m[1] or "Tools"
		p.desc = m and m[2] or ""
	end
	table.sort(pages, function(a, b)
		local ga, gb = order[a.group] or 99, order[b.group] or 99
		if ga ~= gb then return ga < gb end
		if a.key == "general" then return true elseif b.key == "general" then return false end
		return a.label < b.label
	end)
end

local function BuildPage(page)
	if not frame then return end
	if frame.pageFrame then frame.pageFrame:Hide() end
	local scroll = frame.scroll
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(CONTENT_W, 10)
	scroll:SetScrollChild(content)
	scroll:SetVerticalScroll(0)
	frame.pageFrame = content

	local lay = W.Layout(content, CONTENT_W)
	local function rebuild() BuildPage(page) end
	lay:PageTitle(page.label, page.desc)
	local ok, err = pcall(page.build, lay, rebuild)
	if not ok then B:Error(err) end
	content:SetHeight(lay:Height())
	current = page
	for _, btn in ipairs(frame.nav) do
		local active = btn.page == page
		btn.bar:SetShown(active)
		if active then btn.text:SetTextColor(1, 1, 1) else btn.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3]) end
		btn.bg:SetShown(active)
	end
end

-- build every page once into a hidden frame and remember its option labels
local function BuildIndex()
	if Config.indexed then return end
	Config.indexed = true
	local scratch = CreateFrame("Frame")
	scratch:Hide()
	for _, page in ipairs(pages) do
		local content = CreateFrame("Frame", nil, scratch)
		local lay = W.Layout(content, CONTENT_W)
		local words = { page.label, page.desc or "" }
		pcall(page.build, lay, function() end)
		for _, w in ipairs(lay.widgets) do
			for _, key in ipairs({ "label", "text" }) do
				local r = w[key]
				if type(r) == "table" and r.GetText then
					local t = r:GetText()
					if type(t) == "string" then words[#words + 1] = t end
				end
			end
		end
		page.index = table.concat(words, " "):lower()
	end
end

function Config:UpdateNavThumb()
	if not frame or not frame.navScroll then return end
	local sc, content, thumb = frame.navScroll, frame.navContent, frame.navThumb
	local view, total = sc:GetHeight(), content:GetHeight()
	if total <= view + 1 or view <= 0 then thumb:Hide(); return end
	local h = math.max(20, view * view / total)
	local pos = sc:GetVerticalScroll() / (total - view)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -2, -(view - h) * pos)
	thumb:SetHeight(h)
	thumb:Show()
end

-- place the page buttons under their section headers; match = nil shows all
function Config:LayoutNav(match)
	local y, lastGroup, first = 0, nil, nil
	for _, h in pairs(frame.navHeaders) do h:Hide() end
	for _, b in ipairs(frame.nav) do
		local show = not match or match[b.page]
		b:SetShown(show and true or false)
		if show then
			if b.page.group ~= lastGroup then
				lastGroup = b.page.group
				local h = frame.navHeaders[lastGroup]
				if h then
					y = y + (y > 0 and 10 or 4)
					h:ClearAllPoints()
					h:SetPoint("TOPLEFT", frame.navContent, "TOPLEFT", 16, -y)
					h:Show()
					y = y + 18
				end
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame.navContent, "TOPLEFT", 0, -y)
			y = y + 28
			first = first or b.page
		end
	end
	frame.navContent:SetHeight(math.max(1, y))
	frame.navScroll:SetVerticalScroll(0)
	self:UpdateNavThumb()
	return first
end

function Config:FilterPages(q)
	if not frame then return end
	if q ~= "" then BuildIndex() end
	local match
	if q ~= "" then
		match = {}
		for _, b in ipairs(frame.nav) do
			if (b.page.index or b.page.label:lower()):find(q, 1, true) then match[b.page] = true end
		end
	end
	local first = self:LayoutNav(match)
	if q ~= "" and first and current ~= first and not (current and (current.index or ""):find(q, 1, true)) then
		BuildPage(first)
	end
end

local function CreateWindow()
	frame = CreateFrame("Frame", "BitsjUIConfig", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:Hide()
	tinsert(UISpecialFrames, "BitsjUIConfig")
	W.Fill(frame, C.bg)
	B:CreateBorder(frame, 0, 0, 0, 1)

	-- header
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(48)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	W.Fill(header, C.panel)
	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(B.mediaPath .. "Textures\\Logo")
	logo:SetSize(30, 30)
	logo:SetPoint("LEFT", 14, 0)
	local title = header:CreateFontString(nil, "OVERLAY")
	W.Font(title, 20)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(B:TitleText())
	local ver = header:CreateFontString(nil, "OVERLAY")
	W.Font(ver, 12, C.sub)
	ver:SetPoint("LEFT", title, "RIGHT", 8, -2)
	ver:SetText("v" .. B.version)
	logo:SetVertexColor(B:AccentColor())
	-- who's logged in: class icon + race / class / faction in the theme colour
	local me = B:Identity()
	local who = header:CreateFontString(nil, "OVERLAY")
	W.Font(who, 12)
	who:SetTextColor(B:AccentColor())
	who:SetText(string.format("%s %s%s", me.race or "", me.className or "",
		(me.faction == "Alliance" or me.faction == "Horde") and ("  -  " .. me.factionName) or ""))
	frame.identity = who
	local accentLine = header:CreateTexture(nil, "ARTWORK")
	accentLine:SetColorTexture(B:AccentColor())
	accentLine:SetPoint("BOTTOMLEFT")
	accentLine:SetPoint("BOTTOMRIGHT")
	accentLine:SetHeight(1)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(32, 32)
	close:SetPoint("RIGHT", -8, 0)
	close.text = close:CreateFontString(nil, "OVERLAY")
	W.Font(close.text, 18, C.sub)
	close.text:SetPoint("CENTER")
	close.text:SetText("x")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.4, 0.4) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3]) end)
	close:SetScript("OnClick", function() frame:Hide() end)

	-- "reload needed" notice
	local notice = CreateFrame("Frame", nil, header)
	notice:SetSize(300, 26)
	notice:SetPoint("RIGHT", close, "LEFT", -8, 0)
	notice.text = notice:CreateFontString(nil, "OVERLAY")
	W.Font(notice.text, 12)
	notice.text:SetTextColor(1, 0.75, 0.3)
	notice.text:SetText("Some changes need a reload")
	local rb = W.Button(notice, "Reload now", 100, 24, function() ReloadUI() end)
	rb:SetPoint("RIGHT", notice, "RIGHT", 0, 0)
	notice.text:SetPoint("RIGHT", rb, "LEFT", -8, 0)
	notice:SetShown(Config.needsReload and true or false)
	frame.notice = notice

	-- minimise: fold the menu down to its title bar so you can look at the UI
	-- (preview stays on); click again or double-click the bar to open it
	local mini = CreateFrame("Button", nil, header)
	mini:SetSize(32, 32)
	mini:SetPoint("RIGHT", close, "LEFT", -2, 0)
	mini.text = mini:CreateFontString(nil, "OVERLAY")
	W.Font(mini.text, 18, C.sub)
	mini.text:SetPoint("CENTER", 0, 2)
	mini.text:SetText("-")
	mini:SetScript("OnEnter", function(self)
		self.text:SetTextColor(B:AccentColor())
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(frame.minimized and "Open the menu" or "Minimise (keep the preview)", 1, 1, 1)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function(self) self.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3]); GameTooltip:Hide() end)
	mini:SetScript("OnClick", function() Config:ToggleMinimize() end)
	header:SetScript("OnMouseDown", function(_, button)
		local now = GetTime()
		if button == "LeftButton" and frame.lastHeaderClick and now - frame.lastHeaderClick < 0.35 then
			Config:ToggleMinimize()
		end
		frame.lastHeaderClick = now
	end)
	frame.miniButton = mini
	notice:ClearAllPoints()
	notice:SetPoint("RIGHT", mini, "LEFT", -8, 0)

	-- preview toggle
	local pv = W.Button(header, "", 120, 24, function(self)
		B.db.general.previewInMenu = not B.db.general.previewInMenu
		B:SetPreview(B.db.general.previewInMenu)
		self.text:SetText(B.db.general.previewInMenu and "Preview: on" or "Preview: off")
	end, "Shows sample frames, castbars, timers and a nameplate while the menu is open.")
	pv:SetPoint("LEFT", ver, "RIGHT", 16, 0)
	frame.identity:SetPoint("LEFT", pv, "RIGHT", 14, 0)
	pv.text:SetText(B.db.general.previewInMenu and "Preview: on" or "Preview: off")
	frame.previewButton = pv

	frame:SetScript("OnHide", function()
		B:SetPreview(false)
		local RF = B:GetModule("RaidFrames")
		if RF and RF.previewKind then RF:SetPreview(nil) end
		if Config.needsReload then StaticPopup_Show("BITSJUI_RELOAD") end
	end)

	-- sidebar
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", 0, -48)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDEBAR)
	W.Fill(side, C.panel)
	SortPages()
	frame.nav = {}
	local ROW = 28
	-- the page list scrolls (mouse wheel) between the search box and the footer buttons
	local navScroll = CreateFrame("ScrollFrame", nil, side)
	navScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -44)
	navScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 92)
	navScroll:EnableMouseWheel(true)
	local navContent = CreateFrame("Frame", nil, navScroll)
	navContent:SetSize(SIDEBAR, #pages * ROW)
	navScroll:SetScrollChild(navContent)
	navScroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, navContent:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW * 2)))
	end)
	-- thin scroll position marker on the right edge
	local thumb = side:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 1, 1, 0.18)
	thumb:SetWidth(3)
	navScroll:SetScript("OnVerticalScroll", function(self) Config:UpdateNavThumb() end)
	navScroll:SetScript("OnSizeChanged", function() Config:UpdateNavThumb() end)
	frame.navScroll, frame.navContent, frame.navThumb = navScroll, navContent, thumb
	for i, page in ipairs(pages) do
		local b = CreateFrame("Button", nil, navContent)
		b:SetSize(SIDEBAR, ROW)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
		b.page = page
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 1, 1, 0.05)
		b.bg:Hide()
		b.bar = b:CreateTexture(nil, "ARTWORK")
		b.bar:SetColorTexture(B:AccentColor())
		b.bar:SetPoint("TOPLEFT")
		b.bar:SetPoint("BOTTOMLEFT")
		b.bar:SetWidth(3)
		b.bar:Hide()
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.04)
		b.text = b:CreateFontString(nil, "OVERLAY")
		W.Font(b.text, 14, C.sub)
		b.text:SetPoint("LEFT", 22, 0)
		b.text:SetText(page.label)
		b:SetScript("OnClick", function() BuildPage(page) end)
		frame.nav[i] = b
	end
	-- section headers between the groups
	frame.navHeaders = {}
	for _, g in ipairs(GROUPS) do
		local h = navContent:CreateFontString(nil, "OVERLAY")
		W.Font(h, 11, C.sub)
		h:SetText(g:upper())
		h:SetTextColor(B:AccentColor())
		h:SetAlpha(0.85)
		frame.navHeaders[g] = h
	end
	Config:LayoutNav(nil)

	-- search: filters the page list by every option label on each page
	local search = W.Input(side, "")
	search:SetHeight(26)
	search.label:Hide()
	search:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -10)
	search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -12, -10)
	local hint = search.edit:CreateFontString(nil, "OVERLAY")
	W.Font(hint, 12, C.sub)
	hint:SetPoint("LEFT", 0, 0)
	hint:SetText("Search options...")
	search.edit:SetScript("OnTextChanged", function(self)
		local q = (self:GetText() or ""):lower()
		hint:SetShown(q == "")
		Config:FilterPages(q)
	end)
	frame.search = search

	-- footer buttons in the sidebar
	local unlock = W.Button(side, "Unlock frames", SIDEBAR - 24, 30, function() B.Movers:Toggle() end)
	unlock:SetPoint("BOTTOM", 0, 52)
	local reload = W.Button(side, "Reload UI", SIDEBAR - 24, 30, function() ReloadUI() end)
	reload:SetPoint("BOTTOM", 0, 14)

	-- scrolling content
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", SIDEBAR + 28, -64)
	scroll:SetPoint("BOTTOMRIGHT", -32, 16)
	scroll:EnableMouseWheel(true)
	frame.scroll = scroll

	local track = CreateFrame("Frame", nil, frame)
	track:SetPoint("TOPRIGHT", -12, -64)
	track:SetPoint("BOTTOMRIGHT", -12, 16)
	track:SetWidth(4)
	W.Fill(track, C.element)
	local thumb = track:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(B:AccentColor())
	thumb:SetWidth(4)
	local function UpdateThumb()
		local child = scroll:GetScrollChild()
		if not child then return end
		local viewH, totalH = scroll:GetHeight(), child:GetHeight()
		if totalH <= viewH then track:Hide(); return end
		track:Show()
		local th = math.max(30, track:GetHeight() * viewH / totalH)
		thumb:SetHeight(th)
		local pct = scroll:GetVerticalScroll() / (totalH - viewH)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(track:GetHeight() - th) * pct)
	end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local child = self:GetScrollChild()
		local maxScroll = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
		self:SetVerticalScroll(B.Clamp(self:GetVerticalScroll() - delta * 50, 0, maxScroll))
		UpdateThumb()
	end)
	scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
	frame:SetScript("OnShow", function() C_Timer.After(0, UpdateThumb) end)
	frame.fold = { side, scroll, track }
end

function Config:ToggleMinimize()
	if not frame then return end
	-- keep the title bar where it is while the height changes
	local left, top = frame:GetLeft(), frame:GetTop()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	frame.minimized = not frame.minimized
	for _, f in ipairs(frame.fold) do f:SetShown(not frame.minimized) end
	frame:SetHeight(frame.minimized and 48 or HEIGHT)
	frame.miniButton.text:SetText(frame.minimized and "+" or "-")
	-- minimised = you want to look at things: make sure the preview is on
	if frame.minimized and not B.previewing then
		B.db.general.previewInMenu = true
		B:SetPreview(true)
		frame.previewButton.text:SetText("Preview: on")
	end
end

function Config:Show(pageKey)
	if not frame then CreateWindow() end
	local target = pages[1]
	for _, p in ipairs(pages) do if p.key == pageKey then target = p end end
	BuildPage(pageKey and target or current or pages[1])
	if frame.minimized then Config:ToggleMinimize() end
	frame:Show()
	if B.db.general.previewInMenu then B:SetPreview(true) end
end

function Config:MarkReload()
	self.needsReload = true
	if frame and frame.notice then frame.notice:Show() end
end

function Config:Hide()
	if frame then frame:Hide() end
end

function Config:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

-------------------------------------------------------------------------------
-- Popups
-------------------------------------------------------------------------------
StaticPopupDialogs["BITSJUI_RESET_POSITIONS"] = {
	text = "Reset all BitsjUI frame positions?",
	button1 = YES, button2 = NO,
	OnAccept = function() B.Movers:ResetAll() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
-- put the "classic clean" layout back: positions and sizes of BitsjUI frames
function B:ApplyDefaultLayout()
	wipe(self.db.positions)
	for _, key in ipairs({ "unitframes", "castbars", "nameplates", "timers", "classpower", "minimap", "buffs" }) do
		self.db[key] = B.MergeDefaults({}, B.defaults[key])
		BitsjUIDB.profiles[self.profileKey][key] = self.db[key]
	end
	self.db.actionbars.bars = B.MergeDefaults({}, B.defaults.actionbars.bars)
end

StaticPopupDialogs["BITSJUI_RELOAD"] = {
	text = "Some BitsjUI changes need a reload. Reload the UI now?",
	button1 = "Reload now", button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["BITSJUI_APPLY_LAYOUT"] = {
	text = "Apply the BitsjUI default layout? Frame positions and sizes are reset and the UI reloads.",
	button1 = YES, button2 = NO,
	OnAccept = function() B:ApplyDefaultLayout(); ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["BITSJUI_RESET_PROFILE"] = {
	text = "Reset the active BitsjUI profile to defaults? The UI will reload.",
	button1 = YES, button2 = NO,
	OnAccept = function() B:ResetProfile(); ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------
local mmb
local function PositionMinimapButton()
	local angle = math.rad(B.db.general.minimapButton.angle or 220)
	local x, y = math.cos(angle), math.sin(angle)
	local r = Minimap:GetWidth() / 2 + 6
	if B.db.minimap.square then
		-- push the button out to the edge of a square map
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m, y / m
		r = Minimap:GetWidth() / 2 + 10
	end
	mmb:ClearAllPoints()
	mmb:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

function Config:UpdateMinimapButton()
	if not mmb then
		mmb = CreateFrame("Button", "BitsjUIMinimapButton", Minimap)
		mmb:SetSize(26, 26)
		mmb:SetFrameStrata("MEDIUM")
		mmb:SetFrameLevel(Minimap:GetFrameLevel() + 10)
		mmb:RegisterForClicks("AnyUp")
		mmb:RegisterForDrag("LeftButton")
		local icon = mmb:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexture(B.mediaPath .. "Textures\\Logo")
		local hl = mmb:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.15)
		mmb:SetScript("OnClick", function(_, button)
			if button == "RightButton" then B.Movers:Toggle() else Config:Toggle() end
		end)
		mmb:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", function()
				local mx, my = Minimap:GetCenter()
				local cx, cy = GetCursorPosition()
				local s = Minimap:GetEffectiveScale()
				B.db.general.minimapButton.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
				PositionMinimapButton()
			end)
		end)
		mmb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		mmb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(B:TitleText())
			GameTooltip:AddLine("Left-click: menu", 1, 1, 1)
			GameTooltip:AddLine("Right-click: move frames", 1, 1, 1)
			GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		mmb:SetScript("OnLeave", GameTooltip_Hide)
	end
	PositionMinimapButton()
	mmb:SetShown(B.db.general.minimapButton.show)
end

-------------------------------------------------------------------------------
-- Addon compartment (the puzzle-piece button by the minimap)
-------------------------------------------------------------------------------
function BitsjUI_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then B.Movers:Toggle() else Config:Toggle() end
end
function BitsjUI_OnAddonCompartmentEnter(_, frameRef)
	GameTooltip:SetOwner(frameRef or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine(B:TitleText())
	GameTooltip:AddLine("Left-click: menu  |  Right-click: move frames", 1, 1, 1)
	GameTooltip:Show()
end
function BitsjUI_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_BITSJUI1 = "/bui"
SLASH_BITSJUI2 = "/bitsjui"
SlashCmdList.BITSJUI = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	if cmd == "move" or cmd == "unlock" or cmd == "lock" then
		B.Movers:Toggle()
	elseif cmd == "reset" then
		StaticPopup_Show("BITSJUI_RESET_POSITIONS")
	elseif cmd == "buffdebug" then
		-- what the client says about each of your buffs (readable out of combat)
		B:Print("Your buffs (name, spell ID, duration, cast by):")
		for i = 1, 40 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok or type(a) ~= "table" then break end
			local line = string.format("%d. %s  id=%s  duration=%s  from=%s  mine=%s", i,
				tostring(B.Plain(a.name, "?")), tostring(B.Plain(a.spellId, "?")), tostring(B.Plain(a.duration, "?")),
				tostring(B.Plain(a.sourceUnit, "-")), tostring(B.Plain(a.isFromPlayerOrPlayerPet, "?")))
			print(line)
		end
		local errs = B.errorLog and #B.errorLog or 0
		B:Print("BitsjUI errors logged: " .. errs .. " (/bui errors)")
	elseif cmd == "npdebug" then
		B:GetModule("Nameplates"):ShowDebug()
	elseif cmd == "errors" or cmd == "error" then
		Config:Show("errors")
	elseif cmd == "install" then
		B.Installer:Show()
	elseif cmd == "version" or cmd == "whatsnew" or cmd == "updatetest" then
		B:GetModule("Update"):Slash(cmd)
	elseif cmd == "delete" and rest ~= "" then
		for _, name in ipairs(B:GetProfiles()) do
			if name:lower() == rest then
				if B:DeleteProfile(name) then B:Print("Deleted profile " .. name) else B:Print("Can't delete the active profile or Default.") end
				return
			end
		end
		B:Print("No profile named " .. rest)
	else
		Config:Toggle()
	end
end

SLASH_BITSJUIRL1 = "/rl"
SlashCmdList.BITSJUIRL = function() ReloadUI() end

B:RegisterCallback("LOGIN", function()
	Config:UpdateMinimapButton()
end)

-------------------------------------------------------------------------------
-- "BitsjUI" button in the Esc menu, right under AddOns
-------------------------------------------------------------------------------
local function AddGameMenuButton(menu)
	if not B.db.general.gameMenuButton then return end
	local after
	if menu.buttonPool then
		for b in menu.buttonPool:EnumerateActive() do
			local t = b:GetText()
			if t == ADDONS or t == HUD_EDIT_MODE_MENU then
				if not after or b.layoutIndex > after then after = b.layoutIndex end
			end
		end
	end
	local btn = menu:AddButton(B:TitleText(), function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		HideUIPanel(menu)
		Config:Show()
	end)
	if btn and after then
		btn.layoutIndex = after + 0.5
		btn.topPadding = nil
		if menu.MarkDirty then menu:MarkDirty() end
	end
end

B:RegisterCallback("LOGIN", function()
	if GameMenuFrame and GameMenuFrame.InitButtons and not Config.menuHooked then
		Config.menuHooked = true
		hooksecurefunc(GameMenuFrame, "InitButtons", function(self) B:Try(AddGameMenuButton, self) end)
	end
end)
