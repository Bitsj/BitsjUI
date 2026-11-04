--[[
	BitsjUI - Damage meter settings
	The damage meter has its own settings window (gear icon on the meter's
	title bar, or /bui meter): sections on the left, the window you are
	editing (1-3) on top, and every option for text, fonts, bars, the title
	bar and the update rate.
]]
local _, B = ...
local W = B.Widgets
local C = W.colors

local MO = {}
B.MeterOptions = MO

local WIDTH, HEIGHT, SIDE = 780, 600, 170
local CONTENT_W = WIDTH - SIDE - 60
local ICONS = B.mediaPath .. "Textures\\Meter\\"

local frame
local state = { section = "general", win = 1 }

local function DMM() return B:GetModule("DamageMeter") end
local function update()
	local m = DMM()
	if m and m.Update then B:Try(m.Update, m) end
end

-------------------------------------------------------------------------------
-- option helpers (same feel as /bui)
-------------------------------------------------------------------------------
local function wpath(key) return "meter.windows." .. state.win .. "." .. key end

local function Check(lay, label, path, tooltip, after)
	return lay:Add(W.Check(lay.content, label,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update(); if after then after() end end, tooltip))
end

local function Slider(lay, label, path, minV, maxV, step, fmt, tooltip)
	return lay:Add(W.Slider(lay.content, label, minV, maxV, step,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v) end, fmt, update, tooltip))
end

local function Dropdown(lay, label, path, options, tooltip, after)
	return lay:Add(W.Dropdown(lay.content, label, options,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update(); if after then after() end end, tooltip))
end

local function Color(lay, label, path)
	return lay:Add(W.Color(lay.content, label,
		function() return B:GetPath(path) end,
		function(v) B:SetPath(path, v); update() end))
end

local function FontOptions()
	local out = { { value = "", label = "Same as the rest of the UI" } }
	for _, name in ipairs(B:GetFontList()) do
		local file = B.media.fonts[name]
		out[#out + 1] = { value = name, label = name, font = file and not name:find("Custom") and file or nil }
	end
	return out
end

local function TextureOptions()
	local out = { { value = "", label = "Same as the rest of the UI" } }
	for _, name in ipairs(B:GetTextureList()) do out[#out + 1] = { value = name, label = name } end
	return out
end

local OUTLINES = {
	{ value = "default", label = "Same as the rest of the UI" },
	{ value = "NONE", label = "None" },
	{ value = "OUTLINE", label = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick outline" },
	{ value = "MONOCHROME,OUTLINE", label = "Pixel outline" },
}

-------------------------------------------------------------------------------
-- sections
-------------------------------------------------------------------------------
local SECTIONS = {}

SECTIONS[#SECTIONS + 1] = { key = "general", label = "General", global = true,
	desc = "Settings for every meter window.", build = function(lay, rebuild)
	Check(lay, "Enable the damage meter *", "meter.enabled", "Needs a /reload.")
	Check(lay, "Hide Blizzard's meter window", "meter.hideBlizzard")
	Check(lay, "Jump to the current fight when combat starts", "meter.autoCurrent")
	lay:Add(W.Dropdown(lay.content, "Preset", DMM().PRESETS,
		function() return B.db.meter.preset end,
		function(v) DMM():ApplyPreset(v); rebuild() end,
		"Sets the look of all windows. You can tweak everything afterwards."))

	lay:Header("Update rate")
	Slider(lay, "In combat (seconds)", "meter.updateInterval", 0.1, 2, 0.1, "%.1f", "How often the bars refresh during a fight. Lower = smoother, a little more work.")
	Slider(lay, "Out of combat (seconds)", "meter.updateIntervalOOC", 0.2, 5, 0.1, "%.1f")

	lay:Header("Numbers and font")
	Dropdown(lay, "Numbers", "meter.numberStyle", {
		{ value = "short", label = "Short (12.3K, 4.5M)" },
		{ value = "full", label = "Full (12,345)" },
	})
	Dropdown(lay, "Font", "fonts.meter", FontOptions, "The font of every meter window (also set under /bui > General > Font per section).",
		function() B:RefreshFonts() end)
	if B.isClassic then
		lay:Text("Reads the combat log, like Details: damage, healing, absorbs, interrupts, dispels, damage taken, deaths and damage per enemy. Pets and totems count for their owner.")
	else
		lay:Text("Built on Blizzard's built-in damage meter data. Numbers are hidden from addons in combat, so percentages and chat reports appear when the fight is over.")
	end
end }

SECTIONS[#SECTIONS + 1] = { key = "window", label = "Window", desc = "Size, background, what this window shows and when.", build = function(lay)
	local DM = DMM()
	Check(lay, "Show this window", wpath("enabled"))
	Dropdown(lay, "Display", wpath("meterType"), DM.TYPES)
	lay:Add(W.Dropdown(lay.content, "Fight", DM.SESSIONS,
		function() return B:GetPath(wpath("sessionType")) end,
		function(v) B:SetPath(wpath("sessionType"), v); B:SetPath(wpath("sessionID"), nil); update() end))
	Dropdown(lay, "Visibility", wpath("visibility"), {
		{ value = "always", label = "Always" },
		{ value = "combat", label = "In combat only" },
		{ value = "group", label = "In a group only" },
	})
	lay:Header("Size and background")
	Slider(lay, "Width", wpath("width"), 140, 900, 1)
	Slider(lay, "Height", wpath("height"), 60, 900, 1)
	Slider(lay, "Background", wpath("bgAlpha"), 0, 1, 0.05, "%.2f")
	lay:NewLine()
	Check(lay, "Fade out of combat", wpath("fadeOOC"))
	Slider(lay, "Opacity out of combat", wpath("fadeAlpha"), 0, 1, 0.05, "%.2f")
	lay:Text("Drag the title bar to move the window, the bottom-right corner to resize it, and scroll with the mouse wheel to see more players.")
end }

SECTIONS[#SECTIONS + 1] = { key = "bars", label = "Bars", desc = "The player bars.", build = function(lay)
	Check(lay, "Class colours", wpath("classColors"))
	Color(lay, "Bar colour (without class colours)", wpath("barColor"))
	Check(lay, "Spec / class icons", wpath("showIcons"))
	lay:NewLine()
	Slider(lay, "Bar height", wpath("barHeight"), 10, 40, 1)
	Slider(lay, "Spacing", wpath("barSpacing"), 0, 8, 1)
	Slider(lay, "Bar opacity", wpath("barAlpha"), 0.1, 1, 0.05, "%.2f")
	Slider(lay, "Bar background", wpath("barBgAlpha"), 0, 1, 0.05, "%.2f")
	Dropdown(lay, "Texture", wpath("texture"), TextureOptions)
end }

SECTIONS[#SECTIONS + 1] = { key = "text", label = "Text", desc = "Names and numbers on the bars.", build = function(lay)
	Slider(lay, "Text size", wpath("fontSize"), 8, 20, 1)
	Dropdown(lay, "Outline", wpath("textOutline"), OUTLINES)
	Check(lay, "Text shadow", wpath("textShadow"))
	Dropdown(lay, "Name colour", wpath("nameColor"), {
		{ value = "white", label = "White" },
		{ value = "class", label = "Class colour" },
	})
	lay:Header("Numbers")
	Dropdown(lay, "Number format", wpath("textFormat"), {
		{ value = "both", label = "Total (per second)" },
		{ value = "total", label = "Total only" },
		{ value = "persec", label = "Per second only" },
	})
	Check(lay, "Show percent", wpath("showPercent"))
	Check(lay, "Show rank (1. 2. 3.)", wpath("showRank"))
	Check(lay, "Always show me", wpath("alwaysShowMe"), "If you're below the visible rows, you're shown at the bottom.")
end }

SECTIONS[#SECTIONS + 1] = { key = "title", label = "Title bar", desc = "The bar on top with the window name and buttons.", build = function(lay)
	Check(lay, "Show title bar", wpath("showTitle"))
	lay:NewLine()
	Slider(lay, "Title text size", wpath("titleFontSize"), 8, 18, 1)
	Slider(lay, "Title bar height", wpath("titleHeight"), 16, 32, 1)
	lay:Header("Buttons")
	local legend = {
		{ "Prev", "Previous fight" }, { "Next", "Next fight (or scroll on the title)" },
		{ "Display", "Choose display: damage, healing, interrupts..." },
		{ "Segment", "Choose fight (current, overall, earlier fights)" },
		{ "Reset", "Reset all fights" }, { "Report", "Report to chat" }, { "Settings", "This settings window" },
	}
	for _, l in ipairs(legend) do
		local row = CreateFrame("Frame", nil, lay.content)
		row:SetSize(CONTENT_W, 22)
		local ic = row:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("LEFT", 2, 0)
		ic:SetTexture(ICONS .. l[1])
		ic:SetVertexColor(B:AccentColor())
		local t = row:CreateFontString(nil, "OVERLAY")
		W.Font(t, 13, C.text)
		t:SetPoint("LEFT", ic, "RIGHT", 10, 0)
		t:SetText(l[2])
		lay:Add(row, true)
		lay.y = lay.y + 6
	end
end }

-------------------------------------------------------------------------------
-- window
-------------------------------------------------------------------------------
local function SectionByKey(key)
	for _, s in ipairs(SECTIONS) do if s.key == key then return s end end
	return SECTIONS[1]
end

local function Build()
	if not frame then return end
	local section = SectionByKey(state.section)
	if frame.page then frame.page:Hide() end
	local content = CreateFrame("Frame", nil, frame.scroll)
	content:SetSize(CONTENT_W, 10)
	frame.scroll:SetScrollChild(content)
	frame.scroll:SetVerticalScroll(0)
	frame.page = content
	local lay = W.Layout(content, CONTENT_W)
	lay:PageTitle(section.label, section.desc)
	local ok, err = pcall(section.build, lay, Build)
	if not ok then B:Error(err) end
	content:SetHeight(lay:Height())
	-- window tabs only matter for per-window sections
	for i, tab in ipairs(frame.tabs) do
		tab:SetShown(not section.global)
		local on = i == state.win
		tab.bg:SetColorTexture(unpack(on and C.hover or C.element))
		tab.line:SetShown(on)
	end
	frame.tabLabel:SetShown(not section.global)
	for _, b in ipairs(frame.nav) do
		local on = b.key == state.section
		b.bar:SetShown(on)
		b.bg:SetShown(on)
		if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3]) end
	end
end

local function Create()
	frame = CreateFrame("Frame", "BitsjUIMeterOptions", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 0, 20)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:Hide()
	tinsert(UISpecialFrames, "BitsjUIMeterOptions")
	W.Fill(frame, C.bg)
	B:CreateBorder(frame, 0, 0, 0, 1)

	-- header
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(46)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	W.Fill(header, C.panel)
	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICONS .. "Display")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", 16, 0)
	icon:SetVertexColor(B:AccentColor())
	local title = header:CreateFontString(nil, "OVERLAY")
	W.Font(title, 19)
	title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	title:SetText("Damage meter")
	local sub = header:CreateFontString(nil, "OVERLAY")
	W.Font(sub, 12, C.sub)
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
	sub:SetText(B:TitleText())
	local line = header:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", -10, 0)
	close.text = close:CreateFontString(nil, "OVERLAY")
	W.Font(close.text, 18, C.sub)
	close.text:SetPoint("CENTER")
	close.text:SetText("x")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(B:AccentColor()) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3]) end)
	close:SetScript("OnClick", function() frame:Hide() end)
	local bui = W.Button(header, "BitsjUI menu", 120, 24, function()
		frame:Hide()
		if B.Config then B.Config:Show() end
	end, "Open the main BitsjUI menu.")
	bui:SetPoint("RIGHT", close, "LEFT", -10, 0)

	-- sections on the left
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", 0, -46)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDE)
	W.Fill(side, C.panel)
	frame.nav = {}
	for i, s in ipairs(SECTIONS) do
		local b = CreateFrame("Button", nil, side)
		b:SetSize(SIDE, 30)
		b:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 30)
		b.key = s.key
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 1, 1, 0.05)
		b.bar = b:CreateTexture(nil, "ARTWORK")
		b.bar:SetColorTexture(B:AccentColor())
		b.bar:SetPoint("TOPLEFT")
		b.bar:SetPoint("BOTTOMLEFT")
		b.bar:SetWidth(3)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.04)
		b.text = b:CreateFontString(nil, "OVERLAY")
		W.Font(b.text, 14, C.sub)
		b.text:SetPoint("LEFT", 20, 0)
		b.text:SetText(s.label)
		b:SetScript("OnClick", function() state.section = s.key; Build() end)
		frame.nav[i] = b
	end

	-- which window you're editing
	frame.tabLabel = frame:CreateFontString(nil, "OVERLAY")
	W.Font(frame.tabLabel, 12, C.sub)
	frame.tabLabel:SetPoint("TOPLEFT", SIDE + 28, -62)
	frame.tabLabel:SetText("Editing:")
	frame.tabs = {}
	for i = 1, 3 do
		local t = CreateFrame("Button", nil, frame)
		t:SetSize(90, 24)
		t:SetPoint("LEFT", frame.tabLabel, "RIGHT", 10 + (i - 1) * 96, 0)
		t.bg = t:CreateTexture(nil, "BACKGROUND")
		t.bg:SetAllPoints()
		t.line = t:CreateTexture(nil, "ARTWORK")
		t.line:SetColorTexture(B:AccentColor())
		t.line:SetPoint("BOTTOMLEFT")
		t.line:SetPoint("BOTTOMRIGHT")
		t.line:SetHeight(2)
		t.text = t:CreateFontString(nil, "OVERLAY")
		W.Font(t.text, 13, C.text)
		t.text:SetPoint("CENTER")
		t.text:SetText("Window " .. i)
		t:SetScript("OnClick", function() state.win = i; Build() end)
		frame.tabs[i] = t
	end

	-- content
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", SIDE + 28, -96)
	scroll:SetPoint("BOTTOMRIGHT", -32, 16)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local child = self:GetScrollChild()
		local maxScroll = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
		self:SetVerticalScroll(B.Clamp(self:GetVerticalScroll() - delta * 50, 0, maxScroll))
	end)
	frame.scroll = scroll
end

function MO:Show(win, section)
	if not frame then Create() end
	if win then state.win = win end
	if section then state.section = section end
	Build()
	frame:Show()
end

function MO:Toggle(win)
	if frame and frame:IsShown() then frame:Hide() else self:Show(win) end
end
