--[[
	BitsjUI - Movers (drag & drop)
	Every BitsjUI frame registers a mover. "/bui move" (or the button in the
	menu) shows all movers. Drag to move, arrow keys nudge 1px (Shift = grid),
	right-click resets a frame to its default position.
	Positions are stored relative to the nearest screen anchor so they survive
	resolution and scale changes.
]]
local _, B = ...

local Movers = {}
B.Movers = Movers
Movers.list = {}
Movers.unlocked = false

local function GetPos(name)
	return B.db.positions[name]
end

-- apply saved (or default) position to the real frame
function Movers:Apply(name)
	local m = self.list[name]
	if not m then return end
	-- a module re-laying itself out mid-drag must not yank it back
	if m.mover and m.mover.isMoving then return end
	local frame = m.frame
	local pos = GetPos(name) or m.default
	local s = frame:GetScale()
	if not s or s == 0 then s = 1 end
	local function apply()
		frame:ClearAllPoints()
		frame:SetPoint(pos[1], UIParent, pos[2], (pos[3] or 0) / s, (pos[4] or 0) / s)
	end
	if frame:IsProtected() and InCombatLockdown() then
		B:RunOOC("mover_" .. name, apply)
	else
		apply()
	end
	self:SyncMover(name)
end

function Movers:ApplyAll()
	for name in pairs(self.list) do self:Apply(name) end
end

-- compute a resolution independent anchor for a rect in UIParent space
local function NearestAnchor(left, bottom, width, height)
	local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
	local cx, cy = left + width / 2, bottom + height / 2
	local h, v
	if cx < pw / 3 then h = "LEFT" elseif cx > pw * 2 / 3 then h = "RIGHT" else h = "" end
	if cy < ph / 3 then v = "BOTTOM" elseif cy > ph * 2 / 3 then v = "TOP" else v = "" end
	local point = v .. h
	if point == "" then point = "CENTER" end

	local fx, fy, px, py
	if h == "LEFT" then fx, px = left, 0 elseif h == "RIGHT" then fx, px = left + width, pw else fx, px = cx, pw / 2 end
	if v == "BOTTOM" then fy, py = bottom, 0 elseif v == "TOP" then fy, py = bottom + height, ph else fy, py = cy, ph / 2 end
	return point, B.Round(fx - px, 1), B.Round(fy - py, 1)
end

-- store the location of the mover (or of the frame itself when it was
-- dragged directly, e.g. a meter window's title bar)
function Movers:SaveFrame(name)
	local m = self.list[name]
	if not m then return end
	self:SaveFromMover(name, m.frame)
end

-- where a region would land (UIParent units), grid snapping included
local function SnappedRect(region)
	local ms = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom = region:GetLeft(), region:GetBottom()
	if not left or not bottom then return end
	left, bottom = left * ms, bottom * ms
	local w, h = region:GetWidth() * ms, region:GetHeight() * ms
	local grid = B.db.movers.grid
	if B.db.movers.snap and not IsAltKeyDown() and grid and grid > 1 then
		-- snap the frame's center to the grid (grid is centered on screen)
		local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
		local cx = left + w / 2 - pw / 2
		local cy = bottom + h / 2 - ph / 2
		cx = math.floor(cx / grid + 0.5) * grid
		cy = math.floor(cy / grid + 0.5) * grid
		left = cx + pw / 2 - w / 2
		bottom = cy + ph / 2 - h / 2
	end
	return left, bottom, w, h
end

-- live: put the real frame where the mover is (snapped), every frame of the drag
function Movers:Follow(name)
	local m = self.list[name]
	if not m then return end
	local frame = m.frame
	if frame:IsProtected() and InCombatLockdown() then return end
	local left, bottom, w, h = SnappedRect(m.mover)
	if not left then return end
	local fs = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if fs == 0 then fs = 1 end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (left + w / 2) / fs, (bottom + h / 2) / fs)
end

function Movers:SaveFromMover(name, region)
	local m = self.list[name]
	local mover = region or m.mover
	local left, bottom, w, h = SnappedRect(mover)
	if not left then return end

	local point, x, y = NearestAnchor(left, bottom, w, h)
	B.db.positions[name] = { point, point, x, y }
	self:Apply(name)
	B:Fire("MOVER_MOVED", name)
end

function Movers:Nudge(name, dx, dy)
	local pos = GetPos(name) or B.CopyTable(self.list[name].default)
	pos[3] = (pos[3] or 0) + dx
	pos[4] = (pos[4] or 0) + dy
	B.db.positions[name] = pos
	self:Apply(name)
end

function Movers:Reset(name)
	B.db.positions[name] = nil
	self:Apply(name)
end

function Movers:ResetAll()
	wipe(B.db.positions)
	self:ApplyAll()
end

-- keep the mover box on top of the real frame
function Movers:SyncMover(name)
	local m = self.list[name]
	if not m or not m.mover then return end
	local frame, mover = m.frame, m.mover
	if mover.isMoving then return end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local w, h = frame:GetWidth() * s, frame:GetHeight() * s
	if w < 8 then w = 8 end
	if h < 8 then h = 8 end
	mover:SetSize(w, h)
	local cx, cy = frame:GetCenter()
	if cx then
		mover:ClearAllPoints()
		mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * s, cy * s)
	end
end

local function CreateMover(name, label)
	local r, g, b = B:AccentColor()
	local mover = CreateFrame("Button", "BitsjUIMover_" .. name, UIParent)
	mover:SetFrameStrata("DIALOG")
	mover:SetFrameLevel(100)
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	if mover.SetDontSavePosition then mover:SetDontSavePosition(true) end
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:RegisterForClicks("AnyUp")
	mover:Hide()

	local bg = mover:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(B.white)
	bg:SetVertexColor(r, g, b, 0.25)
	mover.bg = bg
	local border = B:CreateBorder(mover, r, g, b, 0.9)
	mover.border = border

	local text = mover:CreateFontString(nil, "OVERLAY")
	text:SetFont(B:GetFont(), 12, B:Flags("OUTLINE"))
	text:SetPoint("CENTER")
	text:SetText(label)
	text:SetTextColor(1, 1, 1)
	mover.text = text

	mover:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self:StartMoving()
		self.isMoving = true
		-- the real frame follows the mouse live (snapped to the grid)
		self:SetScript("OnUpdate", function() B:Try(Movers.Follow, Movers, name) end)
	end)
	mover:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:StopMovingOrSizing()
		-- StartMoving can leave the mover with its own saved layout; never keep that
		if self.SetUserPlaced then self:SetUserPlaced(false) end
		self.isMoving = false
		Movers:SaveFromMover(name)
	end)
	mover:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			Movers:Reset(name)
		end
	end)
	mover:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(r, g, b, 0.5)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(label, r, g, b)
		GameTooltip:AddLine("Drag to move", 1, 1, 1)
		GameTooltip:AddLine("Arrow keys: 1px  |  Shift+arrow: one grid step", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Hold Alt while dropping: no snapping", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: reset", 0.8, 0.8, 0.8)
		GameTooltip:Show()
		self:EnableKeyboard(true)
	end)
	mover:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(r, g, b, 0.25)
		GameTooltip:Hide()
		self:EnableKeyboard(false)
	end)
	mover:SetScript("OnKeyDown", function(self, key)
		local step = IsShiftKeyDown() and (B.db.movers.grid or 16) or 1
		if key == "UP" then Movers:Nudge(name, 0, step)
		elseif key == "DOWN" then Movers:Nudge(name, 0, -step)
		elseif key == "LEFT" then Movers:Nudge(name, -step, 0)
		elseif key == "RIGHT" then Movers:Nudge(name, step, 0)
		else
			self:SetPropagateKeyboardInput(true)
			return
		end
		self:SetPropagateKeyboardInput(false)
	end)
	return mover
end

--[[ Register a frame.
	name    unique key (saved in db.positions)
	label   text shown on the mover
	default { point, relPoint, x, y } relative to UIParent ]]
function B:RegisterMover(frame, name, label, default)
	local m = Movers.list[name] or {}
	m.frame, m.label, m.default = frame, label, default
	Movers.list[name] = m
	if not m.mover then m.mover = CreateMover(name, label) end
	Movers:Apply(name)
	if Movers.unlocked and (m.enabled == nil or m.enabled) then m.mover:Show() end
	return m
end

-- hide a mover for a disabled element
function B:SetMoverEnabled(name, enabled)
	local m = Movers.list[name]
	if not m then return end
	m.enabled = enabled
	if not enabled then m.mover:Hide() elseif Movers.unlocked then
		Movers:SyncMover(name); m.mover:Show()
	end
end

-------------------------------------------------------------------------------
-- Grid overlay
-------------------------------------------------------------------------------
local grid
local function DrawGrid()
	if not grid then
		grid = CreateFrame("Frame", "BitsjUIGrid", UIParent)
		grid:SetAllPoints(UIParent)
		grid:SetFrameStrata("BACKGROUND")
		grid.lines = {}
	end
	for _, l in ipairs(grid.lines) do l:Hide() end
	local size = B.db.movers.grid or 16
	if size < 4 then size = 4 end
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local p = B:Pixel(UIParent)
	local n = 0
	local function line(vertical, offset, center)
		n = n + 1
		local l = grid.lines[n]
		if not l then
			l = grid:CreateTexture(nil, "BACKGROUND")
			l:SetTexture(B.white)
			grid.lines[n] = l
		end
		l:ClearAllPoints()
		if vertical then
			l:SetPoint("TOP", grid, "TOP", offset, 0)
			l:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			l:SetWidth(p)
		else
			l:SetPoint("LEFT", grid, "LEFT", 0, offset)
			l:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			l:SetHeight(p)
		end
		if center then
			local r, g, b = B:AccentColor()
			l:SetVertexColor(r, g, b, 0.8)
		else
			l:SetVertexColor(0, 0, 0, 0.35)
		end
		l:Show()
	end
	local cols = math.floor(w / 2 / size)
	for i = -cols, cols do line(true, i * size, i == 0) end
	local rows = math.floor(h / 2 / size)
	for i = -rows, rows do line(false, i * size, i == 0) end
	grid:Show()
end

-------------------------------------------------------------------------------
-- Floating control bar shown while unlocked
-------------------------------------------------------------------------------
local control
local function CreateControl()
	control = CreateFrame("Frame", "BitsjUIMoverControl", UIParent)
	control:SetSize(360, 64)
	control:SetPoint("TOP", UIParent, "TOP", 0, -120)
	control:SetFrameStrata("FULLSCREEN_DIALOG")
	control:EnableMouse(true)
	control:SetMovable(true)
	control:RegisterForDrag("LeftButton")
	control:SetScript("OnDragStart", control.StartMoving)
	control:SetScript("OnDragStop", control.StopMovingOrSizing)
	B:CreateBackdrop(control, 0.95)

	local title = control:CreateFontString(nil, "OVERLAY")
	title:SetFont(B:GetFont(), 14, B:Flags(""))
	title:SetPoint("TOP", 0, -8)
	title:SetText(B:TitleText() .. "  -  Move mode")

	local function button(text, x, onClick)
		local bt = CreateFrame("Button", nil, control)
		bt:SetSize(104, 22)
		bt:SetPoint("BOTTOM", control, "BOTTOM", x, 10)
		local bg = bt:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(); bg:SetTexture(B.white); bg:SetVertexColor(0.14, 0.14, 0.16, 1)
		B:CreateBorder(bt)
		local fs = bt:CreateFontString(nil, "OVERLAY")
		fs:SetFont(B:GetFont(), 12, B:Flags(""))
		fs:SetPoint("CENTER")
		fs:SetText(text)
		bt.text = fs
		bt:SetScript("OnEnter", function() local r, g, b = B:AccentColor(); bg:SetVertexColor(r * 0.4, g * 0.4, b * 0.4, 1) end)
		bt:SetScript("OnLeave", function() bg:SetVertexColor(0.14, 0.14, 0.16, 1) end)
		bt:SetScript("OnClick", onClick)
		return bt
	end
	control.gridBtn = button("Grid", -112, function()
		B.db.movers.showGrid = not B.db.movers.showGrid
		if B.db.movers.showGrid then DrawGrid() elseif grid then grid:Hide() end
	end)
	control.snapBtn = button("Snap: on", 0, function(self)
		B.db.movers.snap = not B.db.movers.snap
		self.text:SetText(B.db.movers.snap and "Snap: on" or "Snap: off")
	end)
	button("Lock", 112, function() Movers:Lock() end)
end

function Movers:Unlock()
	if InCombatLockdown() then
		B:Print("Can't unlock frames in combat.")
		return
	end
	self.unlocked = true
	for name, m in pairs(self.list) do
		if m.enabled == nil or m.enabled then
			self:SyncMover(name)
			m.mover:Show()
		end
	end
	if not control then CreateControl() end
	control.snapBtn.text:SetText(B.db.movers.snap and "Snap: on" or "Snap: off")
	control:Show()
	if B.db.movers.showGrid then DrawGrid() end
	B:Fire("MOVERS_TOGGLED", true)
end

function Movers:Lock()
	self.unlocked = false
	for _, m in pairs(self.list) do m.mover:Hide() end
	if control then control:Hide() end
	if grid then grid:Hide() end
	B:Fire("MOVERS_TOGGLED", false)
end

function Movers:Toggle()
	if self.unlocked then self:Lock() else self:Unlock() end
end

-- movers hide automatically when combat starts
B:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if Movers.unlocked then
		Movers:Lock()
		B:Print("Move mode closed (combat).")
	end
end)

B:RegisterCallback("UPDATE_ALL", function()
	Movers:ApplyAll()
	if Movers.unlocked and B.db.movers.showGrid then DrawGrid() end
end)
B:RegisterCallback("UI_SCALE_APPLIED", function()
	if B.db then Movers:ApplyAll() end
end)
