--[[
	BitsjUI - Config widgets
	Small, flat widget set for the BitsjUI menu: buttons, checkboxes,
	sliders, dropdowns, colour swatches, edit boxes and a two-column layout.
]]
local _, B = ...
local W = {}
B.Widgets = W

W.colors = {
	bg = { 0.05, 0.05, 0.06, 0.97 },
	panel = { 0.075, 0.08, 0.09, 1 },
	element = { 0.12, 0.125, 0.14, 1 },
	hover = { 0.17, 0.175, 0.19, 1 },
	text = { 0.92, 0.92, 0.93 },
	sub = { 0.60, 0.62, 0.66 },
}
local C = W.colors

function W.Font(fs, size, color)
	fs:SetFont(B:GetFont(), size or 13, B:Flags(""))
	fs:SetShadowOffset(0, 0)
	local c = color or C.text
	fs:SetTextColor(c[1], c[2], c[3])
end

function W.Fill(frame, color, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

local function Accent(a)
	local r, g, b = B:AccentColor()
	return r, g, b, a or 1
end

-------------------------------------------------------------------------------
-- Tooltip helper
-------------------------------------------------------------------------------
local function AddTooltip(frame, title, text)
	if not text then return end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, Accent())
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

-------------------------------------------------------------------------------
-- Button
-------------------------------------------------------------------------------
function W.Button(parent, text, width, height, onClick, tooltip, template)
	local b = CreateFrame("Button", nil, parent, template)
	b:SetSize(width or 140, height or 26)
	b.bg = W.Fill(b, C.element)
	B:CreateBorder(b, 0, 0, 0, 1)
	b.text = b:CreateFontString(nil, "OVERLAY")
	W.Font(b.text, 13)
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b:SetScript("OnEnter", function(self)
		local r, g, bl = Accent()
		self.bg:SetColorTexture(r * 0.35, g * 0.35, bl * 0.35, 1)
	end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.element[1], C.element[2], C.element[3], 1) end)
	if template then
		-- secure buttons keep their own OnClick; run ours just before it
		if onClick then b:SetScript("PreClick", function(self, ...) onClick(self, ...) end) end
	else
		b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
	end
	AddTooltip(b, text, tooltip)
	return b
end

-- A button that runs onClick and then reloads the UI. Blizzard blocks
-- ReloadUI() from addon code, so the reload goes through a secure /reload
-- macro button. That secure button is never a child of our windows (a
-- protected child would stop the window from closing in combat): one shared
-- secure button floats over whichever reload button the mouse is on.
local overlay
local function Overlay()
	if overlay then return overlay end
	overlay = CreateFrame("Button", "BitsjUISecureReload", UIParent, "SecureActionButtonTemplate")
	overlay:SetFrameStrata("TOOLTIP")
	overlay:RegisterForClicks("AnyUp", "AnyDown")
	overlay:SetAttribute("type", "macro")
	overlay:SetAttribute("macrotext", "/reload")
	overlay:Hide()
	overlay:SetScript("PreClick", function(self, button, down)
		-- fires on key down or key up depending on a CVar: run once
		local useDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
		if (down and true or false) ~= (useDown and true or false) then return end
		local owner = self.owner
		if owner and owner.bOnReload then owner.bOnReload(owner, button, down) end
	end)
	overlay:SetScript("OnEnter", function(self)
		local owner = self.owner
		if owner then local f = owner:GetScript("OnEnter"); if f then f(owner) end end
	end)
	overlay:SetScript("OnLeave", function(self)
		local owner = self.owner
		if owner then local f = owner:GetScript("OnLeave"); if f then f(owner) end end
		if not InCombatLockdown() then self:Hide(); self:ClearAllPoints() end
	end)
	-- combat is about to lock everything: let go of it now
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:SetScript("OnEvent", function() overlay:Hide(); overlay:ClearAllPoints() end)
	return overlay
end

function W.ReloadButton(parent, text, width, height, onClick, tooltip)
	-- the plain button: in combat (no secure overlay) it does the work and asks for /reload
	local b = W.Button(parent, text, width, height, function(self, ...)
		if onClick then onClick(self, ...) end
		B:Print("Done. Type /reload to apply it.")
	end, tooltip)
	b.bOnReload = onClick
	b:HookScript("OnEnter", function(self)
		if InCombatLockdown() then return end
		local o = Overlay()
		if o.owner == self and o:IsShown() then return end
		o.owner = self
		o:ClearAllPoints()
		o:SetAllPoints(self)
		o:Show()
	end)
	return b
end

-------------------------------------------------------------------------------
-- Header / text
-------------------------------------------------------------------------------
function W.Header(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(30)
	f.text = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.text, 15)
	f.text:SetTextColor(Accent())
	f.text:SetPoint("BOTTOMLEFT", 0, 6)
	f.text:SetText(text)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.08)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	return f
end

function W.Text(parent, text, size, color)
	local f = CreateFrame("Frame", nil, parent)
	f.text = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.text, size or 12, color or C.sub)
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("TOPRIGHT")
	f.text:SetJustifyH("LEFT")
	f.text:SetWordWrap(true)
	f.text:SetText(text)
	f:SetHeight(18)
	f:SetScript("OnSizeChanged", function(self)
		self:SetHeight(math.max(16, self.text:GetStringHeight() + 4))
	end)
	return f
end

-------------------------------------------------------------------------------
-- Checkbox
-------------------------------------------------------------------------------
function W.Check(parent, label, get, set, tooltip)
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(24)
	local box = CreateFrame("Frame", nil, f)
	box:SetSize(18, 18)
	box:SetPoint("LEFT", 0, 0)
	box.bg = W.Fill(box, C.element)
	B:CreateBorder(box, 0, 0, 0, 1)
	local mark = box:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", 4, -4)
	mark:SetPoint("BOTTOMRIGHT", -4, 4)
	mark:SetColorTexture(Accent())
	f.mark = mark
	f.text = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.text, 13)
	f.text:SetPoint("LEFT", box, "RIGHT", 8, 0)
	f.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.text:SetJustifyH("LEFT")
	f.text:SetText(label)

	function f:Refresh() mark:SetShown(get() and true or false) end
	f:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
	end)
	f:SetScript("OnEnter", function() box.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1) end)
	f:SetScript("OnLeave", function() box.bg:SetColorTexture(C.element[1], C.element[2], C.element[3], 1) end)
	AddTooltip(f, label, tooltip)
	f:Refresh()
	return f
end

-------------------------------------------------------------------------------
-- Slider (value applied live, heavy refresh debounced)
-------------------------------------------------------------------------------
function W.Slider(parent, label, minV, maxV, step, get, set, fmt, onCommit, tooltip)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(44)
	f.label = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.label, 13)
	f.label:SetPoint("TOPLEFT", 0, -2)
	f.label:SetText(label)

	-- editable value box
	local eb = CreateFrame("EditBox", nil, f)
	eb:SetSize(54, 18)
	eb:SetPoint("TOPRIGHT", 0, 0)
	eb:SetAutoFocus(false)
	eb:SetJustifyH("RIGHT")
	eb:SetFont(B:GetFont(), 12, B:Flags(""))
	eb:SetTextColor(Accent())
	f.value = eb

	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(14)
	s:SetPoint("BOTTOMLEFT", 0, 6)
	s:SetPoint("BOTTOMRIGHT", 0, 6)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:EnableMouseWheel(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(C.element[1], C.element[2], C.element[3], 1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(6)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(Accent(0.7))
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetHeight(6)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 1, 1, 1)
	thumb:SetSize(8, 14)
	s:SetThumbTexture(thumb)
	f.slider = s

	local format = fmt or (step < 1 and "%.2f" or "%d")
	local function show(v)
		eb:SetText(string.format(format, v))
		local pct = (v - minV) / (maxV - minV)
		fill:SetWidth(math.max(1, (s:GetWidth() or 100) * pct))
	end

	-- live while dragging: apply at most ~25 times a second, plus once more
	-- when you stop so the final value always lands
	local timer, last = nil, 0
	local function commit()
		if not onCommit then return end
		local now = GetTime()
		if now - last >= 0.04 then
			last = now
			if timer then timer:Cancel(); timer = nil end
			onCommit()
		elseif not timer then
			timer = C_Timer.NewTimer(0.05, function() timer = nil; last = GetTime(); onCommit() end)
		end
	end

	s:SetScript("OnValueChanged", function(self, v, userInput)
		v = B.Round(v / step) * step
		v = B.Round(v, 4)
		show(v)
		if userInput then
			set(v)
			commit()
		end
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		local v = B.Clamp(self:GetValue() + delta * step, minV, maxV)
		self:SetValue(v)
		set(B.Round(v, 4))
		commit()
	end)
	s:SetScript("OnSizeChanged", function() show(s:GetValue()) end)
	eb:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = B.Clamp(v, minV, maxV)
			s:SetValue(v)
			set(B.Round(v, 4))
			commit()
		end
		self:ClearFocus()
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); show(s:GetValue()) end)

	function f:Refresh()
		local v = get() or minV
		s:SetValue(v)
		show(v)
	end
	AddTooltip(s, label, tooltip)
	f:Refresh()
	return f
end

-------------------------------------------------------------------------------
-- Dropdown (shared popup list)
-------------------------------------------------------------------------------
local list
local function CreateList()
	list = CreateFrame("Frame", "BitsjUIDropdownList", UIParent)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetClampedToScreen(true)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	W.Fill(list, C.panel)
	B:CreateBorder(list, 0, 0, 0, 1)
	list.buttons = {}
	list.offset = 0
	list:Hide()

	-- click outside closes
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:SetScript("OnClick", function() list:Hide() end)
	catcher:Hide()
	list.catcher = catcher
	list:SetScript("OnShow", function() catcher:Show() end)
	list:SetScript("OnHide", function() catcher:Hide() end)
	list:SetScript("OnMouseWheel", function(self, delta)
		local maxOffset = math.max(0, #self.options - self.visible)
		self.offset = B.Clamp(self.offset - delta, 0, maxOffset)
		self:Render()
	end)

	function list:Render()
		for i = 1, self.visible do
			local b = self.buttons[i]
			local opt = self.options[i + self.offset]
			if opt then
				b.text:SetText(opt.label)
				-- preview each font in itself; one still loading shows in the menu font
				W.Font(b.text, 13)
				if opt.font and B.FontWorks(opt.font) then pcall(b.text.SetFont, b.text, opt.font, 13, B:Flags("")) end
				local selected = opt.value == self.current
				if selected then b.text:SetTextColor(Accent()) else b.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end
				b.value = opt.value
				b:Show()
			else
				b:Hide()
			end
		end
	end
end

local ROW = 22
local MAX_ROWS = 12
local function OpenList(owner, options, current, onPick, width)
	if not list then CreateList() end
	if list:IsShown() and list.owner == owner then list:Hide(); return end
	list.owner = owner
	list.options = options
	list.current = current
	list.onPick = onPick
	list.visible = math.min(#options, MAX_ROWS)
	list.offset = 0
	for i, opt in ipairs(options) do
		if opt.value == current and i > MAX_ROWS then list.offset = math.min(i - 1, #options - MAX_ROWS) end
	end
	for i = 1, list.visible do
		if not list.buttons[i] then
			local b = CreateFrame("Button", nil, list)
			b:SetHeight(ROW)
			b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW)
			b:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			b.text = b:CreateFontString(nil, "OVERLAY")
			W.Font(b.text, 13)
			b.text:SetPoint("LEFT", 6, 0)
			b.text:SetPoint("RIGHT", -6, 0)
			b.text:SetJustifyH("LEFT")
			b:SetScript("OnClick", function(self)
				list:Hide()
				if list.onPick then list.onPick(self.value) end
			end)
			list.buttons[i] = b
		end
	end
	for i = list.visible + 1, #list.buttons do list.buttons[i]:Hide() end
	list:SetSize(width or owner:GetWidth(), list.visible * ROW + 8)
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	list:Render()
	list:Show()
end

W.OpenList = OpenList

-- options: array of { value = x, label = "..." } or a function returning one
function W.Dropdown(parent, label, options, get, set, tooltip)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(48)
	f.label = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.label, 13)
	f.label:SetPoint("TOPLEFT", 0, -2)
	f.label:SetText(label)

	local b = CreateFrame("Button", nil, f)
	b:SetHeight(24)
	b:SetPoint("BOTTOMLEFT")
	b:SetPoint("BOTTOMRIGHT")
	b.bg = W.Fill(b, C.element)
	B:CreateBorder(b, 0, 0, 0, 1)
	b.text = b:CreateFontString(nil, "OVERLAY")
	W.Font(b.text, 13)
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetPoint("RIGHT", -22, 0)
	b.text:SetJustifyH("LEFT")
	local arrow = b:CreateFontString(nil, "OVERLAY")
	W.Font(arrow, 12, C.sub)
	arrow:SetPoint("RIGHT", -8, 0)
	arrow:SetText("v")
	f.button = b

	local function getOptions()
		if type(options) == "function" then return options() end
		return options
	end
	function f:Refresh()
		local v = get()
		local text = tostring(v)
		for _, opt in ipairs(getOptions()) do
			if opt.value == v then text = opt.label; break end
		end
		b.text:SetText(text)
	end
	b:SetScript("OnClick", function(self)
		OpenList(self, getOptions(), get(), function(value)
			set(value)
			f:Refresh()
		end)
	end)
	b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1) end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.element[1], C.element[2], C.element[3], 1) end)
	AddTooltip(b, label, tooltip)
	f:Refresh()
	return f
end

-------------------------------------------------------------------------------
-- Colour swatch
-------------------------------------------------------------------------------
function W.Color(parent, label, get, set, hasAlpha)
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(24)
	local sw = CreateFrame("Frame", nil, f)
	sw:SetSize(30, 18)
	sw:SetPoint("LEFT")
	local checker = W.Fill(sw, { 0.3, 0.3, 0.3, 1 })
	local tex = sw:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	B:CreateBorder(sw, 0, 0, 0, 1)
	f.text = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.text, 13)
	f.text:SetPoint("LEFT", sw, "RIGHT", 8, 0)
	f.text:SetText(label)

	function f:Refresh()
		local c = get()
		tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
	end
	f:SetScript("OnClick", function()
		local c = get()
		local prev = { r = c.r, g = c.g, b = c.b, a = c.a }
		local function apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = hasAlpha and ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or c.a
			set({ r = r, g = g, b = b, a = a })
			f:Refresh()
		end
		local info = {
			r = c.r, g = c.g, b = c.b,
			opacity = c.a or 1,
			hasOpacity = hasAlpha,
			swatchFunc = apply,
			opacityFunc = apply,
			cancelFunc = function()
				set(prev)
				f:Refresh()
			end,
		}
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow(info)
		else
			ColorPickerFrame.func = apply
			ColorPickerFrame.opacityFunc = apply
			ColorPickerFrame.cancelFunc = info.cancelFunc
			ColorPickerFrame.hasOpacity = hasAlpha
			ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
			ShowUIPanel(ColorPickerFrame)
		end
	end)
	f:Refresh()
	return f
end

-------------------------------------------------------------------------------
-- Multi-line edit box (import / export)
-------------------------------------------------------------------------------
function W.EditBox(parent, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height or 120)
	W.Fill(f, C.element)
	B:CreateBorder(f, 0, 0, 0, 1)
	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", 6, -6)
	sf:SetPoint("BOTTOMRIGHT", -6, 6)
	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	eb:SetFont(B:GetFont(), 11, B:Flags(""))
	eb:SetTextColor(C.text[1], C.text[2], C.text[3])
	eb:SetWidth(400)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	sf:SetScrollChild(eb)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, eb:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(B.Clamp(self:GetVerticalScroll() - delta * 30, 0, maxScroll))
	end)
	sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(w) end)
	f:EnableMouse(true)
	f:SetScript("OnMouseDown", function() eb:SetFocus() end)
	f.edit = eb
	return f
end

function W.Input(parent, label, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(48)
	f.label = f:CreateFontString(nil, "OVERLAY")
	W.Font(f.label, 13)
	f.label:SetPoint("TOPLEFT", 0, -2)
	f.label:SetText(label)
	local box = CreateFrame("Frame", nil, f)
	box:SetHeight(24)
	box:SetPoint("BOTTOMLEFT")
	box:SetPoint("BOTTOMRIGHT")
	W.Fill(box, C.element)
	B:CreateBorder(box, 0, 0, 0, 1)
	local eb = CreateFrame("EditBox", nil, box)
	eb:SetPoint("TOPLEFT", 8, 0)
	eb:SetPoint("BOTTOMRIGHT", -8, 0)
	eb:SetAutoFocus(false)
	eb:SetFont(B:GetFont(), 13, B:Flags(""))
	eb:SetTextColor(C.text[1], C.text[2], C.text[3])
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	eb:SetScript("OnEnterPressed", eb.ClearFocus)
	f.edit = eb
	return f
end

-------------------------------------------------------------------------------
-- Two-column flow layout inside a scrolling page
-------------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function W.Layout(content, width)
	local l = setmetatable({}, Layout)
	l.content = content
	l.width = width
	l.colWidth = math.floor((width - 28) / 2)
	l.y = -6
	l.col = 1
	l.rowHeight = 0
	l.widgets = {}
	return l
end

function Layout:NewLine()
	if self.col == 2 then
		self.y = self.y - self.rowHeight - 12
		self.col = 1
		self.rowHeight = 0
	end
end

function Layout:Add(widget, full)
	widget:ClearAllPoints()
	if full then
		self:NewLine()
		widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y)
		widget:SetWidth(self.width)
		self.y = self.y - widget:GetHeight() - 12
	else
		local x = (self.col == 1) and 0 or (self.colWidth + 28)
		widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
		widget:SetWidth(self.colWidth)
		self.rowHeight = math.max(self.rowHeight, widget:GetHeight())
		if self.col == 1 then
			self.col = 2
		else
			self.col = 1
			self.y = self.y - self.rowHeight - 12
			self.rowHeight = 0
		end
	end
	self.widgets[#self.widgets + 1] = widget
	return widget
end

function Layout:Header(text)
	self:NewLine()
	if #self.widgets > 0 then self.y = self.y - 8 end
	return self:Add(W.Header(self.content, text), true)
end

function Layout:Text(text)
	local t = W.Text(self.content, text)
	self:Add(t, true)
	t.text:SetWidth(self.width)
	t:SetHeight(math.max(16, t.text:GetStringHeight() + 4))
	self.y = self.y - (t:GetHeight() - 18)
	return t
end

-- big page title, a one-line explanation and a thin accent line
function Layout:PageTitle(title, desc)
	local t = W.Text(self.content, title, 22, C.text)
	self:Add(t, true)
	t:SetHeight(28)
	self.y = self.y + 6
	if desc and desc ~= "" then
		local d = self:Text(desc)
		d.text:SetTextColor(C.sub[1], C.sub[2], C.sub[3])
	end
	local line = self.content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetAlpha(0.6)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, self.y + 4)
	line:SetWidth(self.width)
	self.y = self.y - 6
	return t
end

function Layout:Height()
	self:NewLine()
	return -self.y + 20
end

function Layout:RefreshAll()
	for _, w in ipairs(self.widgets) do
		if w.Refresh then w:Refresh() end
	end
end
