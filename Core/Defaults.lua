--[[
	BitsjUI - Defaults
	Tuned for 2560x1440 (27") at UI scale 0.62 (UIParent ~2202 x 1239 units).
	The default layout follows the "classic clean" style: portrait unit frames
	high on the left, spell timers and a tight 3x12 action bar block at the
	bottom centre, square minimap top right.
]]
local _, B = ...

B.globalDefaults = {
	installed = false,
	installVersion = 0,
}

local function bar(enabled, buttons, perRow, size, spacing, mouseover)
	return {
		enabled = enabled, buttons = buttons, perRow = perRow, size = size, spacing = spacing,
		alpha = 1, mouseover = mouseover or false, mouseoverAlpha = 0,
	}
end

local function color(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end

local function unit(t)
	t.enabled = true
	return t
end

B.defaults = {
	general = {
		uiScale = 0.62,
		updateNotify = true,         -- tell me when someone in guild / group has a newer BitsjUI
		whatsNew = true,             -- "What's new" window after updating
		font = "Barlow",
		fontOutline = "OUTLINE",
		fontShadow = false,
		sharpText = true,            -- vector ("Slug") text rendering: sharper at any UI scale
		replaceGameFonts = true,
		texture = "Bitsj Gloss",
		accent = color(0.31, 0.82, 0.71),   -- used when the theme is "custom"
		colorBrightness = 0.85,      -- bar colours: 1 = Blizzard's full colours
		colorSaturation = 0.85,      -- bar colours: lower = calmer, greyer
		themeMode = "class",         -- class | faction | custom: colour of highlights, lines, menu
		themeTint = 0.07,            -- how much panels take on that colour (0 = plain dark)
		themeBorders = false,        -- borders in a deep shade of the theme colour instead of black
		welcome = true,              -- greeting in chat at login
		gameMenuButton = true,       -- BitsjUI button in the Esc menu
		factionCrest = true,         -- faction emblem on the minimap bar
		backdrop = color(0.05, 0.05, 0.06, 0.85),
		border = color(0, 0, 0, 1),
		borderStyle = "rounded",     -- rounded | sharp
		iconZoom = 0.08,             -- how much of the icon's own border is cropped
		iconShadow = 0.55,           -- inner shadow strength (0 = off)
		iconGloss = 0.6,             -- soft top sheen (0 = off)
		cornerRadius = 5,            -- in screen pixels
		hideBagsBar = true,
		microMenuMouseover = true,
		hideTalkingHead = false,
		hideErrors = false,
		minimapButton = { show = true, angle = 220 },
		previewInMenu = true,
	},

	movers = { grid = 16, snap = true, showGrid = true },

	-- saved frame positions: [moverName] = { point, relPoint, x, y }
	positions = {},

	actionbars = {
		enabled = true,
		range = true,
		abbreviate = true,
		showHotkey = true,
		showMacro = false,
		showCount = true,
		hotkeySize = 11,
		countSize = 11,
		macroSize = 9,
		emptyButtons = true,
		pressAnim = true,
		pressStyle = "both",          -- flash | pop | both
		pressAccent = false,
		hideCastAnim = true,
		bitsjCooldowns = true,
		showGCD = true,
		desaturateCD = true,
		borderSize = 2,               -- button border thickness in pixels (rounded with the theme)
		bars = {
			-- bars 1-3 stacked in the middle (1 at the bottom), 4+5 on the right on mouseover
			[1] = bar(true, 12, 12, 36, 4),
			[2] = bar(true, 12, 12, 36, 4),
			[3] = bar(true, 12, 12, 36, 4),
			[4] = bar(true, 12, 1, 32, 4, true),
			[5] = bar(true, 12, 1, 32, 4, true),
			[6] = bar(false, 12, 12, 32, 2),
			[7] = bar(false, 12, 12, 32, 2),
			[8] = bar(false, 12, 12, 32, 2),
			pet = bar(true, 10, 10, 26, 2),
			stance = bar(true, 10, 10, 28, 2),
		},
	},

	unitframes = {
		enabled = true,
		style = "clean",             -- clean (slim bars) | portrait
		healthColor = "class",       -- class | dark | custom
		customHealth = color(0.25, 0.75, 0.35),
		darkHealth = color(0.16, 0.16, 0.18),
		bgMultiplier = 0.25,
		borderSize = 3,              -- frame border thickness in pixels
		fontSize = 13,
		smallFontSize = 11,
		nameSize = 12,
		nameColor = "gold",          -- gold | class | white
		portraitStyle = "3d",        -- 3d (2D portrait art) | class (class icon) | none
		player = unit({ width = 200, healthHeight = 26, powerHeight = 7, portraitSize = 64,
			healthText = "split", powerText = "none", showName = true, showLevel = true }),
		target = unit({ width = 200, healthHeight = 26, powerHeight = 7, portraitSize = 64,
			healthText = "split", powerText = "none", showName = true, showLevel = true,
			auras = { enabled = true, onlyPlayer = false, size = 20, num = 16, spacing = 2, buffs = false } }),
		targettarget = unit({ width = 90, healthHeight = 14, powerHeight = 0, portraitSize = 32,
			healthText = "none", powerText = "none", showName = true, showLevel = false }),
		focus = unit({ width = 130, healthHeight = 18, powerHeight = 5, portraitSize = 44,
			healthText = "percent", powerText = "none", showName = true, showLevel = true }),
		pet = unit({ width = 90, healthHeight = 12, powerHeight = 4, portraitSize = 32,
			healthText = "none", powerText = "none", showName = true, showLevel = false, happiness = true }),
	},

	classpower = {
		enabled = true,
		width = 150, height = 8, spacing = 2,
		attachToPlayer = true,       -- sit under the player frame and match its width
		attachGap = 3,
		fadeOOC = true,              -- fade out when empty and out of combat
		showPowerBar = false,        -- extra mana/energy bar under the resource
		powerHeight = 8,
	},

	buffs = {
		enabled = true,
		hideBlizzard = true,
		size = 30, spacing = 4, perRow = 12,
		maxBuffs = 24, maxDebuffs = 12,
		fontSize = 11,
		collapse = true,             -- split active / passive buffs with a toggle
		collapsePassive = true,      -- permanent buffs hidden
		alwaysShow = "465, 317920, 32223",  -- spell IDs kept while collapsed (Devotion, Concentration, Crusader Aura)
	},

	timers = {
		enabled = true,
		width = 180, height = 16, spacing = 2, groupGap = 6,
		fontSize = 11,
		playerBuffs = false,         -- long buffs (Enlisted, flasks...) can't be filtered in 12.x
		targetDebuffs = true,
		maxBars = 10,
		growUp = true,
		attachToPlayer = true,       -- under the player frame, same width, growing down
		attachGap = 6,
		buffColor = color(0.92, 0.50, 0.22),
		debuffColor = color(0.62, 0.32, 0.86),
		iconSize = 34, buffNum = 5, debuffNum = 6,
	},

	castbars = {
		enabled = true,
		castColor = color(0.31, 0.82, 0.71),
		channelColor = color(0.35, 0.60, 0.95),
		nonInterruptColor = color(0.60, 0.60, 0.62),
		failColor = color(0.85, 0.22, 0.22),
		fontSize = 12,
		player = { enabled = true, width = 450, height = 22, icon = true, timer = true, latency = true, spark = true },
		target = { enabled = true, width = 200, height = 18, icon = true, timer = true, latency = false, spark = true, attach = true },
		focus = { enabled = true, width = 140, height = 14, icon = true, timer = true, latency = false, spark = true, attach = false },
	},

	swing = {
		enabled = true,
		attachToCastbar = true,      -- right above the player castbar, same width
		width = 300, height = 12, spacing = 3, gap = 4,
		fontSize = 10, showText = true,
		melee = true, offhand = true, ranged = true,
		meleeColor = color(0.90, 0.72, 0.35),
		offColor = color(0.72, 0.52, 0.30),
		rangedColor = color(0.45, 0.80, 0.40),
	},

	nameplates = {
		enabled = true,
		width = 170, height = 16,
		fontSize = 10, nameSize = 13,
		healthText = "none",         -- both | value | percent | none
		nameAbove = true,            -- name above the bar, coloured like the bar
		-- mob type colours (other hostile NPCs keep the plain red)
		colorByType = true,
		questColor = color(0.95, 0.80, 0.20),
		casterColor = color(0.35, 0.55, 1.00),
		meleeColor = color(0.95, 0.50, 0.15),
		-- aggro indicator
		threat = true,
		threatHigh = color(0.20, 0.90, 0.30),   -- tank: you hold aggro / dps: (shown red)
		threatWarn = color(1.00, 0.60, 0.10),   -- about to change hands
		threatLow = color(0.95, 0.15, 0.15),    -- tank: you have no aggro / dps: you HAVE aggro
		showLevel = true,
		classColors = true,
		stacking = true,
		maxDistance = 41,
		targetScale = 1.2,
		nonTargetAlpha = 0.55,
		targetGlow = true, targetArrows = true,
		targetColor = color(1, 1, 1),
		castbar = true, castHeight = 10,
		debuffs = true, debuffSize = 22, debuffNum = 6, onlyMine = true,
		buffs = true, buffSize = 20, buffNum = 4,
		dispelGlow = true, glowColor = color(0.25, 0.85, 1.0),
	},

	raidframes = {
		enabled = true,
		hideBlizzard = true,
		party = {
			show = true,
			summonIcon = true,
			width = 120, height = 46, spacing = 4,
			borderSize = 1,
			colorMode = "class",      -- class | dark
			nameColor = "white",      -- white | class
			nameSize = 12,
			roleIcon = true, aggro = true,
			rangeAlpha = 0.4,
			debuffs = true, debuffSize = 18,
			myBuffs = true, buffSize = 15,
		},
		raid = {
			show = true,
			summonIcon = true,
			width = 92, height = 46, spacing = 4,
			borderSize = 1,
			colorMode = "class",
			nameColor = "white",
			nameSize = 11,
			groupLabels = true,
			groups = "auto",          -- auto (by raid size) | all
			roleIcon = true, aggro = true,
			rangeAlpha = 0.4,
			debuffs = true, debuffSize = 16,
			myBuffs = true, buffSize = 14,
		},
	},

	character = {
		enabled = true,
		showIlvl = true, showTrack = true, showEnchants = true, missingEnchants = true, showAverage = true,
		ilvlSize = 12, enchantSize = 10,
		betterStats = true,          -- exact % with ratings, flat headers
		extraStats = true,           -- Mythic+ rating, movement speed, durability under the stats
	},

	quests = {
		enabled = true,
		headerSize = 14, lineSize = 12, outline = true,
		sortByDistance = true,       -- closest tracked quest on top, re-sorted while moving
	},

	friends = {
		enabled = true,
		classColors = true, classIcons = true, factionTint = true,
	},

	bags = {
		enabled = true,
		alpha = 0.92,                -- panel opacity
		qualityBorders = true,       -- item border in its quality colour (uncommon and up)
		countSize = 12,
	},

	qol = {
		enabled = true,
		autoRepair = true, guildRepair = true, sellJunk = true,
		fastLoot = true, autoDelete = true,
		skipCinematics = false, ahCurrentExpansion = true,
		autoKeystone = true, quickSignup = true, announceReset = false,
		openContainers = false, hideScreenshotText = true,
		fpsText = true, fpsSize = 12,
		durabilityWarning = true, durabilityPercent = 25,
	},

	minimap = {
		enabled = true,
		square = true,
		mouseZoom = true,
		hideZoomButtons = true,
		zoneText = "header",         -- header | hover | hide
		clock = "header",            -- header | below | off
		coords = false,
		border = true,
		buttons = "hover",           -- hover | show | hide: tracking, calendar, addon buttons...
	},

	chat = { enabled = true, fontSize = 14, hideButtons = true, styleEditBox = true, styleTabs = true, shadow = true,
		panel = true, panelAlpha = 0.75, borderSize = 2, tabFontSize = 13 },

	cdm = {
		enabled = true, zoom = true, border = true, hideOverlay = true, swipeAlpha = 0.75,
		countdownSize = 16, countSize = 13, barFontSize = 12, styleBars = true,
	},

	meter = {
		enabled = true,
		updateInterval = 0.5,
		autoCurrent = true,           -- new fight: windows showing an old fight jump back to Current
		hideBlizzard = true,
		preset = "dark",
		windows = {},
	},

	tooltip = { enabled = true, cursor = false, classBorder = true, healthBar = true, hideInCombat = false },
}

local function meterWindow(enabled, meterType)
	return {
		enabled = enabled, meterType = meterType, sessionType = 1,
		width = 280, height = 200, barHeight = 20, barSpacing = 1, fontSize = 12,
		showTitle = true, showRank = true, showIcons = true, classColors = true,
		textFormat = "both", showPercent = true, alwaysShowMe = true,
		visibility = "always", fadeOOC = false, fadeAlpha = 0.5,
		bgAlpha = 0.85, barAlpha = 0.9, barBgAlpha = 0.35, texture = "",
	}
end
B.defaults.meter.windows[1] = meterWindow(true, 0)
B.defaults.meter.windows[2] = meterWindow(false, 2)
B.defaults.meter.windows[3] = meterWindow(false, 7)
