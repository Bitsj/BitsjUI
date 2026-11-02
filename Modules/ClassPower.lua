--[[
	BitsjUI - Class resource bar
	Holy Power, combo points, chi, soul shards, arcane charges, essence and
	runes as a segmented bar. Each segment is a StatusBar with the range
	[i-1, i] fed the current value, so it fills correctly even when the
	client hides the number in combat.
]]
local _, B = ...
local M = B:NewModule("ClassPower")

-- fonts: this file uses the "unitframes" section font (/bui > General > Fonts)
local FONT_SECTION = "unitframes"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local issecret = B.IsSecret
local PT = Enum and Enum.PowerType or {}

local COLORS = {
	[PT.HolyPower or 9] = { 0.95, 0.85, 0.40 },
	[PT.ComboPoints or 4] = { 1.00, 0.85, 0.25 },
	[PT.Chi or 12] = { 0.45, 0.95, 0.80 },
	[PT.SoulShards or 7] = { 0.62, 0.45, 0.90 },
	[PT.ArcaneCharges or 16] = { 0.30, 0.60, 1.00 },
	[PT.Essence or 19] = { 0.30, 0.85, 0.85 },
	runes = { 0.80, 0.20, 0.25 },
}
local RUNE_COLORS = { [250] = { 0.85, 0.15, 0.20 }, [251] = { 0.35, 0.65, 1.00 }, [252] = { 0.40, 0.85, 0.30 } }

local function db() return B.db.classpower end

local function SpecID()
	local idx = GetSpecialization and GetSpecialization()
	if idx and GetSpecializationInfo then return (GetSpecializationInfo(idx)) end
end

-- which resource the player uses right now: powerType or "runes" (and display mod)
local function Resource()
	local _, class = UnitClass("player")
	-- Classic Era: only rogues and cat-form druids have a class resource (combo points)
	if B.classicContent then
		if class == "ROGUE" then return PT.ComboPoints or 4, 1 end
		if class == "DRUID" and GetShapeshiftFormID and GetShapeshiftFormID() == 1 then return PT.ComboPoints or 4, 1 end
		return nil
	end
	local spec = SpecID()
	if class == "PALADIN" then return PT.HolyPower or 9, 1
	elseif class == "ROGUE" then return PT.ComboPoints or 4, 1
	elseif class == "DRUID" then
		local form = GetShapeshiftFormID and GetShapeshiftFormID()
		if form == 1 then return PT.ComboPoints or 4, 1 end   -- cat form
	elseif class == "MONK" then
		if spec == 269 then return PT.Chi or 12, 1 end
	elseif class == "WARLOCK" then return PT.SoulShards or 7, 10   -- fragments
	elseif class == "MAGE" then
		if spec == 62 then return PT.ArcaneCharges or 16, 1 end
	elseif class == "EVOKER" then return PT.Essence or 19, 1
	elseif class == "DEATHKNIGHT" then return "runes", 1
	end
end

-------------------------------------------------------------------------------
local frame

local function Segment(i)
	local seg = frame.segments[i]
	if seg then return seg end
	seg = B:CreateStatusBar(frame)
	B:CreateBorder(seg, 0, 0, 0, 1, B:Pixel(seg))
	frame.segments[i] = seg
	return seg
end

-- the player frame's bar block when the resource bar is attached under it
local function PlayerBars()
	local d = db()
	if not d.attachToPlayer then return end
	local pf = _G.BitsjUI_player
	if pf and pf.bars and B.db.unitframes.enabled and B.db.unitframes.player.enabled then return pf.bars end
end

function M:Width()
	local bars = PlayerBars()
	if bars then return B.db.unitframes.player.width end
	return db().width
end

function M:Attach()
	local bars = PlayerBars()
	B:SetMoverEnabled("classpower", db().enabled and not bars)
	if not bars then return end
	-- tucked right under the player frame, clear of its border
	local gap = B:Pixel(frame) * ((B.db.unitframes.borderSize or 1) * 2) + (db().attachGap or 3)
	frame:ClearAllPoints()
	-- pinned on both sides so it can never be wider than the player frame
	frame:SetPoint("TOPLEFT", bars, "BOTTOMLEFT", 0, -gap)
	frame:SetPoint("TOPRIGHT", bars, "BOTTOMRIGHT", 0, -gap)
end

function M:Layout()
	if not frame then return end
	self:LayoutInner()
	self:Attach()
end

function M:LayoutInner()
	local d = db()
	local width = self:Width()
	local kind, mod = Resource()
	frame.kind, frame.mod = kind, mod
	local count = 0
	if kind == "runes" then
		count = 6
	elseif kind then
		count = B.Plain(UnitPowerMax("player", kind), 5) or 5
		if count > 10 then count = 5 end
		if count < 0 then count = 0 end   -- this client has no such resource
	end
	frame.count = count

	frame:SetSize(width, d.height + (d.showPowerBar and (d.powerHeight + 3) or 0))
	if count == 0 or not d.enabled then
		for _, s in ipairs(frame.segments) do s:Hide() end
		frame.power:SetShown(d.enabled and d.showPowerBar)
		frame:SetShown(d.enabled and d.showPowerBar)
		B:SetMoverEnabled("classpower", d.enabled)
		B.Movers:Apply("classpower")
		self:UpdateValues()
		return
	end

	local w = (width - (count - 1) * d.spacing) / count
	local color = COLORS[kind] or COLORS.runes
	if kind == "runes" then color = RUNE_COLORS[SpecID() or 0] or COLORS.runes end
	for i = 1, count do
		local seg = Segment(i)
		seg:ClearAllPoints()
		seg:SetSize(w, d.height)
		seg:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (w + d.spacing), 0)
		seg:SetStatusBarTexture(B:GetTexture())
		seg:SetStatusBarColor(color[1], color[2], color[3])
		seg.bg:SetVertexColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18, 0.9)
		if kind ~= "runes" then seg:SetMinMaxValues((i - 1) * mod, i * mod) else seg:SetMinMaxValues(0, 1) end
		seg:Show()
	end
	for i = count + 1, #frame.segments do frame.segments[i]:Hide() end

	frame.power:ClearAllPoints()
	frame.power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	frame.power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.power:SetHeight(d.powerHeight)
	frame.power:SetShown(d.showPowerBar)
	frame:Show()
	B:SetMoverEnabled("classpower", true)
	B.Movers:Apply("classpower")
	self:UpdateValues()
end

function M:UpdateValues()
	if not frame or not frame:IsShown() then return end
	local kind, mod = frame.kind, frame.mod
	local value
	if kind == "runes" then
		local now = GetTime()
		frame.runesPending = false
		for i = 1, 6 do
			local seg = frame.segments[i]
			local ok, start, duration, ready = pcall(GetRuneCooldown, i)
			if ok and not issecret(ready) and not issecret(start) and not issecret(duration) then
				if ready or not start or not duration or duration == 0 then
					seg:SetValue(1); seg:SetAlpha(1)
				else
					seg:SetValue(math.min(1, (now - start) / duration)); seg:SetAlpha(0.6)
					frame.runesPending = true
				end
			else
				seg:SetValue(1)
				if seg.SetAlphaFromBoolean and ok then pcall(seg.SetAlphaFromBoolean, seg, ready, 1, 0.4) end
			end
		end
	elseif kind then
		value = (mod > 1) and UnitPower("player", kind, true) or UnitPower("player", kind)
		-- Classic: combo points live on the target
		if B.classicContent and GetComboPoints and kind == (PT.ComboPoints or 4) then
			local ok, cp = pcall(GetComboPoints, "player", "target")
			if ok and type(cp) == "number" then value = cp end
		end
		for i = 1, frame.count do frame.segments[i]:SetValue(value) end
	end

	-- extra power bar
	if frame.power:IsShown() then
		frame.power:SetMinMaxValues(0, UnitPowerMax("player"))
		frame.power:SetValue(UnitPower("player"))
		local _, token = UnitPowerType("player")
		token = B.Plain(token, nil)
		local c = token and PowerBarColor and PowerBarColor[token]
		if c then frame.power:SetStatusBarColor(c.r, c.g, c.b) end
	end

	-- fade when idle out of combat
	local alpha = 1
	if db().fadeOOC and not InCombatLockdown() then
		local empty = (kind == "runes" and not frame.runesPending)
			or (kind ~= "runes" and not issecret(value) and (value or 0) == 0)
		if empty then alpha = 0.25 end
	end
	if B.Movers.unlocked or B.previewing then alpha = 1 end
	frame:SetAlpha(alpha)
end

function M:OnEnable()
	frame = CreateFrame("Frame", "BitsjUIClassPower", UIParent)
	frame:SetFrameStrata("LOW")
	frame.segments = {}
	frame.power = B:CreateStatusBar(frame)
	B:CreateBorder(frame.power, 0, 0, 0, 1, B:Pixel(frame.power))
	frame:SetSize(db().width, db().height)
	B:RegisterMover(frame, "classpower", "Class resource", { "BOTTOM", "BOTTOM", 0, 272 })

	local function relayout() M:Layout() end
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_SHAPESHIFT_FORM",
		"UNIT_MAXPOWER", "TRAIT_CONFIG_UPDATED" }) do
		B:RegisterEvent(e, relayout)
	end
	local function values() M:UpdateValues() end
	for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "RUNE_POWER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
		"PLAYER_TARGET_CHANGED", "UNIT_COMBO_POINTS" }) do
		B:RegisterEvent(e, values)
	end
	frame.elapsed = 0
	frame:SetScript("OnUpdate", B.Safe(function(self, el)
		if self.kind ~= "runes" or not self.runesPending then return end
		self.elapsed = self.elapsed + el
		if self.elapsed > 0.05 then self.elapsed = 0; M:UpdateValues() end
	end))
	B:RegisterCallback("MOVERS_TOGGLED", values)
	B:RegisterCallback("PREVIEW", values)
	-- follow the player frame when it is resized or moved
	local UF = B:GetModule("UnitFrames")
	if UF and UF.LayoutFrame then
		hooksecurefunc(UF, "LayoutFrame", function(_, key) if key == "player" then M:Layout() end end)
	end
	B:RegisterCallback("UPDATE_ALL", relayout)
	-- the mover system re-applies saved spots (login, layout reset, grid);
	-- while attached the player frame decides where the bar goes
	hooksecurefunc(B.Movers, "Apply", function(_, name) if name == "classpower" then M:Attach() end end)
	hooksecurefunc(B.Movers, "ApplyAll", function() M:Attach() end)
	self:Layout()
end

function M:Update()
	self:Layout()
end
