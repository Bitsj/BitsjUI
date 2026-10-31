--[[
	BitsjUI - Spell timers
	Timer bars for your own short buffs and your debuffs on the target:
	icon, spell name, time left, draining bar. In combat the client hides
	aura timing from addons, so the bar is driven by the client's own
	duration objects (it keeps animating) and the text is filled in with
	secret-aware formatting.
	Long buffs (food, flasks...) are filtered out when they are first seen
	with readable timing, normally out of combat.
]]
local _, B = ...
local M = B:NewModule("Timers")

local issecret = B.IsSecret
local function db() return B.db.timers end

local anchor
local pool = {}

-------------------------------------------------------------------------------
-- Attached under the player frame (below the class resource bar when that
-- one is attached too), same width, growing downwards
-------------------------------------------------------------------------------
local function PlayerAnchor()
	if not db().attachToPlayer then return end
	local pf = _G.BitsjUI_player
	if not (pf and pf.bars and B.db.unitframes.enabled and B.db.unitframes.player.enabled) then return end
	local cp = _G.BitsjUIClassPower
	if cp and cp:IsShown() and B.db.classpower.enabled and B.db.classpower.attachToPlayer then return cp end
	return pf.bars
end

function M:Width()
	if PlayerAnchor() then return B.db.unitframes.player.width end
	return db().width
end

local function GrowUp()
	if PlayerAnchor() then return false end
	return db().growUp
end

function M:Attach()
	if not anchor then return end
	local a = PlayerAnchor()
	B:SetMoverEnabled("timers", db().enabled and not a)
	if not a then
		-- just detached: back to the saved / default spot
		if M.attached then M.attached = false; B.Movers:Apply("timers") end
		return
	end
	M.attached = true
	local gap = B:Pixel(anchor) * ((B.db.unitframes.borderSize or 1) * 2) + (db().attachGap or 6)
	anchor:ClearAllPoints()
	anchor:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -gap)
	anchor:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT", 0, -gap)
end
local used = 0
local longCache = {}   -- auraInstanceID -> true when too long to show

local function GetBar(i)
	local bar = pool[i]
	if bar then return bar end
	bar = CreateFrame("Frame", nil, anchor)
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	B:SkinIcon(bar.icon, bar)
	bar.iconBorder = CreateFrame("Frame", nil, bar)
	bar.iconBorder:SetAllPoints(bar.icon)
	B:CreateBorder(bar.iconBorder, 0, 0, 0, 1)
	bar.count = bar.iconBorder:CreateFontString(nil, "OVERLAY")
	bar.count:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", -1, 1)

	bar.sb = B:CreateStatusBar(bar)
	B:CreateBorder(bar.sb, 0, 0, 0, 1, B:Pixel(bar.sb))
	bar.name = bar.sb:CreateFontString(nil, "OVERLAY")
	bar.name:SetPoint("CENTER", bar.sb, "CENTER", -8, 0)
	bar.name:SetWordWrap(false)
	bar.time = bar.sb:CreateFontString(nil, "OVERLAY")
	bar.time:SetPoint("RIGHT", bar.sb, "RIGHT", -4, 0)

	bar.elapsed = 0
	bar:SetScript("OnUpdate", B.Safe(function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		if self.mode == "lua" then
			local left = self.expires - GetTime()
			if left < 0 then left = 0 end
			self.sb:SetValue(left)
			self.time:SetFormattedText(left >= 10 and "%.0f" or "%.1f", left)
		elseif self.mode == "client" and self.dur and self.dur.GetRemainingDuration then
			local ok, rem = pcall(self.dur.GetRemainingDuration, self.dur)
			if not (ok and pcall(self.time.SetFormattedText, self.time, "%.1f", rem)) then self.time:SetText("") end
		end
	end))
	pool[i] = bar
	return bar
end

local function StyleBar(bar)
	local d = db()
	bar:SetSize(M:Width(), d.height)
	bar.icon:ClearAllPoints()
	bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.icon:SetSize(d.height, d.height)
	bar.sb:ClearAllPoints()
	bar.sb:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 3, 0)
	bar.sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	bar.sb:SetStatusBarTexture(B:GetTexture())
	bar.sb.bg:SetTexture(B:GetTexture())
	B:SetFont(bar.name, d.fontSize)
	B:SetFont(bar.time, d.fontSize - 2)
	B:SetFont(bar.count, d.fontSize - 2)
	bar.name:SetWidth(M:Width() - d.height - 50)
end

-- returns "skip", "client", or "lua" (+ values) for an aura
local function Timing(unit, aura)
	local id = aura.auraInstanceID
	if not issecret(id) and id and longCache[id] then return "skip" end
	local duration, expires = aura.duration, aura.expirationTime
	if not issecret(duration) and not issecret(expires) then
		if not duration or duration <= 0 then return "skip" end
		local maxD = 60
		if duration > maxD then
			if id and not issecret(id) then longCache[id] = true end
			return "skip"
		end
		return "lua", duration, expires
	end
	-- hidden timing: ask the client for a duration object
	if C_UnitAuras.GetAuraDuration and id then
		local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, id)
		if ok and dur then return "client", dur end
	end
	return "skip"
end

local function AddAuras(unit, filter, color)
	local d = db()
	if not UnitExists(unit) or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end
	for i = 1, 40 do
		if used >= d.maxBars then return end
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok or type(aura) ~= "table" then return end
		local mode, a, b = Timing(unit, aura)
		if mode ~= "skip" then
			used = used + 1
			local bar = GetBar(used)
			StyleBar(bar)
			bar.group = filter
			pcall(bar.icon.SetTexture, bar.icon, aura.icon)
			if not pcall(bar.name.SetText, bar.name, aura.name) then bar.name:SetText("") end
			B:GetModule("UnitFrames").ApplyAuraCount(bar.count, unit, aura)
			bar.sb:SetStatusBarColor(color.r, color.g, color.b)
			bar.sb.bg:SetVertexColor(color.r * 0.2, color.g * 0.2, color.b * 0.2, 0.85)
			bar.mode, bar.dur = mode, nil
			if mode == "lua" then
				bar.expires = b
				bar.sb:SetMinMaxValues(0, a)
				bar.sb:SetValue(math.max(0, b - GetTime()))
			else
				bar.dur = a
				local dir = Enum and Enum.StatusBarTimerDirection
				local set = bar.sb.SetTimerDuration and ((dir and pcall(bar.sb.SetTimerDuration, bar.sb, a, nil, dir.RemainingTime))
					or pcall(bar.sb.SetTimerDuration, bar.sb, a))
				if not set then bar.sb:SetMinMaxValues(0, 1); bar.sb:SetValue(1) end
			end
			bar:Show()
		end
	end
end

-- 12.1+: aura scanning is unreliable for addons, so the timers use
-- Blizzard AuraContainers (the client picks, draws and counts down the auras)
function M:LayoutBoxes()
	local d = db()
	local rowH = d.height + d.spacing
	local w = self:Width()
	local b, t = self.buffBox, self.debuffBox
	-- debuffs on target first (closest to the anchor), your buffs after a gap
	t:ClearAllPoints()
	t:SetSize(w, d.debuffNum * rowH)
	b:ClearAllPoints()
	b:SetSize(w, d.buffNum * rowH)
	if GrowUp() then
		t:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
		B:SetAuraBoxFlow(t, "BOTTOMLEFT", "Right", "Up", d.spacing)
		b:SetPoint("BOTTOM", t, "TOP", 0, d.groupGap)
		B:SetAuraBoxFlow(b, "BOTTOMLEFT", "Right", "Up", d.spacing)
	else
		t:SetPoint("TOP", anchor, "TOP", 0, 0)
		B:SetAuraBoxFlow(t, "TOPLEFT", "Right", "Down", d.spacing)
		b:SetPoint("TOP", t, "BOTTOM", 0, -d.groupGap)
		B:SetAuraBoxFlow(b, "TOPLEFT", "Right", "Down", d.spacing)
	end
	B:UpdateAuraBox(t, d.height, { debuffs = (d.enabled and d.targetDebuffs) and d.debuffNum or 0 })
	B:UpdateAuraBox(b, d.height, { buffs = (d.enabled and d.playerBuffs) and d.buffNum or 0 })
	b:SetShown(d.enabled and d.playerBuffs)
	t:SetShown(d.enabled and d.targetDebuffs)
	anchor:SetSize(w, d.height)
	self:Attach()
end

function M:Refresh()
	if not anchor then return end
	if self.buffBox then return self:LayoutBoxes() end
	local d = db()
	used = 0
	if d.enabled then
		if d.playerBuffs then AddAuras("player", "HELPFUL|PLAYER", d.buffColor) end
		local firstDebuff = used + 1
		if d.targetDebuffs then AddAuras("target", "HARMFUL|PLAYER", d.debuffColor) end
		-- stack bars, with a gap between buffs and debuffs
		local y = 0
		for i = 1, used do
			local bar = pool[i]
			if i == firstDebuff and i > 1 then y = y + d.groupGap end
			bar:ClearAllPoints()
			if GrowUp() then
				bar:SetPoint("BOTTOM", anchor, "BOTTOM", 0, y)
			else
				bar:SetPoint("TOP", anchor, "TOP", 0, -y)
			end
			y = y + d.height + d.spacing
		end
	end
	for i = used + 1, #pool do pool[i]:Hide(); pool[i].mode = nil end

	-- preview while moving
	if (B.Movers.unlocked or B.previewing) and used == 0 and d.enabled then
		local samples = {
			{ 136243, "Sample buff", "12.0", 0.7, d.buffColor },
			{ 132307, "Another buff", "4.2", 0.3, d.buffColor },
			{ 136207, "Your debuff", "8.5", 0.55, d.debuffColor },
		}
		local y = 0
		for i, smp in ipairs(samples) do
			local bar = GetBar(i)
			StyleBar(bar)
			bar.icon:SetTexture(smp[1])
			bar.name:SetText(smp[2])
			bar.time:SetText(smp[3])
			bar.count:SetText("")
			bar.mode = nil
			bar.sb:SetMinMaxValues(0, 1); bar.sb:SetValue(smp[4])
			bar.sb:SetStatusBarColor(smp[5].r, smp[5].g, smp[5].b)
			bar.sb.bg:SetVertexColor(smp[5].r * 0.2, smp[5].g * 0.2, smp[5].b * 0.2, 0.85)
			if i == 3 then y = y + d.groupGap end
			bar:ClearAllPoints()
			if GrowUp() then bar:SetPoint("BOTTOM", anchor, "BOTTOM", 0, y) else bar:SetPoint("TOP", anchor, "TOP", 0, -y) end
			y = y + d.height + d.spacing
			bar:Show()
		end
	end
end

function M:OnEnable()
	anchor = CreateFrame("Frame", "BitsjUITimers", UIParent)
	anchor:SetFrameStrata("LOW")
	anchor:SetSize(self:Width(), db().height)
	B:RegisterMover(anchor, "timers", "Spell timers", { "BOTTOM", "BOTTOM", -420, 302 })
	B:SetMoverEnabled("timers", db().enabled)
	-- follow the player frame / resource bar; while attached they decide where the timers go
	local UF = B:GetModule("UnitFrames")
	if UF and UF.LayoutFrame then
		hooksecurefunc(UF, "LayoutFrame", function(_, key) if key == "player" then M:Update() end end)
	end
	local CP = B:GetModule("ClassPower")
	if CP and CP.Layout then hooksecurefunc(CP, "Layout", function() M:Attach() end) end
	hooksecurefunc(B.Movers, "Apply", function(_, name) if name == "timers" or name == "classpower" or name == "uf_player" then M:Attach() end end)
	hooksecurefunc(B.Movers, "ApplyAll", function() M:Attach() end)

	if B:HasAuraContainers() then
		local d = db()
		local function style(color)
			return { bar = true, width = self:Width(), height = d.height, color = color, fontSize = d.fontSize }
		end
		self.buffBox = B:CreateAuraBox(anchor, { { key = "buffs", filter = "HELPFUL|PLAYER", max = d.buffNum, style = style(d.buffColor) } }, d.height)
		self.debuffBox = B:CreateAuraBox(anchor, { { key = "debuffs", filter = "HARMFUL|PLAYER", max = d.debuffNum, style = style(d.debuffColor) } }, d.height)
		if self.buffBox and self.debuffBox then
			B:SetAuraBoxUnit(self.buffBox, "player")
			B:SetAuraBoxUnit(self.debuffBox, "target")
			self:LayoutBoxes()
			return
		end
		self.buffBox, self.debuffBox = nil, nil
	end

	local f = CreateFrame("Frame")
	pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player", "target")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", B.Safe(function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then wipe(longCache) end
		M:Refresh()
	end))
	B:RegisterCallback("MOVERS_TOGGLED", function() M:Refresh() end)
	B:RegisterCallback("PREVIEW", function() M:Refresh() end)
	self:Refresh()
	self:Attach()
end

function M:Update()
	if not anchor then return end
	if self.buffBox then return self:LayoutBoxes() end
	anchor:SetSize(self:Width(), db().height)
	self:Attach()
	self:Refresh()
end
