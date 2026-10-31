--[[
	BitsjUI - Castbars
	Custom player / target / focus castbars with icon, spell name, timer,
	spark and latency zone. When the client hides cast timing (secret values),
	the bar falls back to the client-driven timer API, and finally to a
	static bar with the spell name, so it never errors.
]]
local _, B = ...
local M = B:NewModule("Castbars")
M.bars = {}

local issecret = B.IsSecret

local UNITS = {
	{ key = "player", unit = "player", label = "Castbar: player", default = { "BOTTOM", "BOTTOM", 13, 130 }, blizz = "PlayerCastingBarFrame" },
	{ key = "target", unit = "target", label = "Castbar: target", default = { "BOTTOM", "BOTTOM", 160, 244 } },
	{ key = "focus", unit = "focus", label = "Castbar: focus", default = { "BOTTOM", "BOTTOM", -420, 400 } },
}
M.UNITS = UNITS

local function cfg(key) return B.db.castbars[key] end
local function col(name) local c = B.db.castbars[name]; return c.r, c.g, c.b end

-------------------------------------------------------------------------------
local function SetBarColor(bar, notInterruptible)
	local tex = bar:GetStatusBarTexture()
	local cr, cg, cb
	if bar.channeling then cr, cg, cb = col("channelColor") else cr, cg, cb = col("castColor") end
	local nr, ng, nb = col("nonInterruptColor")

	if not issecret(notInterruptible) then
		if notInterruptible then bar:SetStatusBarColor(nr, ng, nb) else bar:SetStatusBarColor(cr, cg, cb) end
		bar.shield:SetShown(notInterruptible and true or false)
		return
	end
	-- secret boolean: let the client pick the colour
	bar:SetStatusBarColor(1, 1, 1)
	local done = false
	if tex and tex.SetVertexColorFromBoolean and CreateColor then
		done = pcall(tex.SetVertexColorFromBoolean, tex, notInterruptible, CreateColor(nr, ng, nb, 1), CreateColor(cr, cg, cb, 1))
	end
	if not done then bar:SetStatusBarColor(cr, cg, cb) end
	bar.shield:Show()
	if not (bar.shield.SetAlphaFromBoolean and pcall(bar.shield.SetAlphaFromBoolean, bar.shield, notInterruptible, 1, 0)) then
		bar.shield:Hide()
	end
end

local function StopBar(bar, failed, reason)
	bar.casting, bar.channeling = nil, nil
	bar.mode = nil
	if failed then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(col("failColor"))
		bar.text:SetText(reason or "Interrupted")
		bar.timer:SetText("")
		bar.spark:Hide()
		bar.fadeDelay = 0.6
	else
		bar.fadeDelay = 0.15
	end
	bar.fading = true
	bar.latency:Hide()
end

local function StartBar(bar, channel)
	local unit = bar.unit
	local name, text, texture, startMS, endMS, castID, notInt, _
	if channel then
		name, text, texture, startMS, endMS, _, notInt = UnitChannelInfo(unit)
	else
		name, text, texture, startMS, endMS, _, castID, notInt = UnitCastingInfo(unit)
	end
	if not B.HasValue(name) then
		bar:Hide()
		return
	end

	bar.casting = not channel
	bar.channeling = channel
	bar.castID = castID
	bar.fading = nil
	bar.fadeDelay = nil
	bar:SetAlpha(1)

	pcall(bar.icon.SetTexture, bar.icon, texture)
	if not pcall(bar.text.SetText, bar.text, text) then
		if not pcall(bar.text.SetText, bar.text, name) then bar.text:SetText("") end
	end
	SetBarColor(bar, notInt)

	local c = cfg(bar.key)
	bar.duration = nil
	if not issecret(startMS) and not issecret(endMS) and startMS and endMS then
		-- classic path: we know the timing
		bar.mode = "lua"
		bar.startTime = startMS / 1000
		bar.endTime = endMS / 1000
		bar.total = math.max(0.001, bar.endTime - bar.startTime)
		bar:SetMinMaxValues(0, bar.total)
		bar:SetValue(channel and bar.total or 0)
		bar.spark:SetShown(c.spark)
		-- latency (player casts only)
		if c.latency and bar.key == "player" and not channel then
			local _, _, _, world = GetNetStats()
			local lag = (world or 0) / 1000
			local w = bar:GetWidth() * math.min(1, lag / bar.total)
			if w > 1 then
				bar.latency:SetWidth(w)
				bar.latency:Show()
			else
				bar.latency:Hide()
			end
		else
			bar.latency:Hide()
		end
	else
		-- secret timing: let the client animate the bar
		bar.latency:Hide()
		bar.spark:Hide()
		local getDuration = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
		local ok = false
		if getDuration and bar.SetTimerDuration then
			local okd, dur = pcall(getDuration, unit)
			if okd and dur then
				local direction = Enum and Enum.StatusBarTimerDirection
				if direction then
					ok = pcall(bar.SetTimerDuration, bar, dur, nil, channel and direction.RemainingTime or direction.ElapsedTime)
				end
				if not ok then ok = pcall(bar.SetTimerDuration, bar, dur) end
				if ok then bar.duration = dur end
			end
		end
		if ok then
			bar.mode = "client"
		else
			bar.mode = "static"
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
		end
	end
	bar:Show()
end

local function OnUpdate(bar, elapsed)
	if bar.fading then
		bar.fadeDelay = (bar.fadeDelay or 0) - elapsed
		if bar.fadeDelay <= 0 then
			local a = bar:GetAlpha() - elapsed * 4
			if a <= 0 then
				bar.fading = nil
				bar:Hide()
				bar:SetAlpha(1)
			else
				bar:SetAlpha(a)
			end
		end
		return
	end
	local c = cfg(bar.key)
	if bar.mode == "lua" then
		local now = GetTime()
		local value
		if bar.channeling then
			value = bar.endTime - now
		else
			value = now - bar.startTime
		end
		if value < 0 then value = 0 end
		if value > bar.total then value = bar.total end
		bar:SetValue(value)
		if c.timer then
			bar.timer:SetFormattedText("%.1f", math.max(0, bar.endTime - now))
		else
			bar.timer:SetText("")
		end
		if c.spark then
			bar.spark:ClearAllPoints()
			bar.spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * (value / bar.total), 0)
		end
		if now > bar.endTime + 0.1 then
			StopBar(bar)
		end
	elseif bar.mode == "client" and c.timer and bar.duration and bar.duration.GetRemainingDuration then
		local ok, rem = pcall(bar.duration.GetRemainingDuration, bar.duration)
		if not (ok and pcall(bar.timer.SetFormattedText, bar.timer, "%.1f", rem)) then
			bar.timer:SetText("")
		end
	else
		bar.timer:SetText("")
	end
end

local function OnEvent(bar, event, unit, castGUID)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		bar.fading = nil
		if B.HasValue((UnitChannelInfo(bar.unit))) then
			StartBar(bar, true)
		elseif B.HasValue((UnitCastingInfo(bar.unit))) then
			StartBar(bar, false)
		else
			bar.casting, bar.channeling = nil, nil
			bar:Hide()
		end
		return
	end

	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
		StartBar(bar, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
		or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
		StartBar(bar, true)
	elseif event == "UNIT_SPELLCAST_STOP" then
		if bar.casting then StopBar(bar) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		if bar.channeling then StopBar(bar) end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if not (bar.casting or bar.channeling) then return end
		-- ignore failures of a queued spell while another cast is running
		if not issecret(castGUID) and not issecret(bar.castID) and bar.castID and castGUID and castGUID ~= bar.castID then
			return
		end
		StopBar(bar, true, event == "UNIT_SPELLCAST_INTERRUPTED" and "Interrupted" or "Failed")
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		SetBarColor(bar, false)
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		SetBarColor(bar, true)
	end
end

local castEvents = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function CreateCastbar(def)
	local bar = B:CreateStatusBar(UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar.unit, bar.key = def.unit, def.key
	bar:Hide()
	B:CreateBackdrop(bar, 0.9)

	-- icon sits to the left of the bar
	local iconFrame = CreateFrame("Frame", nil, bar)
	B:CreateBackdrop(iconFrame, 1)
	bar.iconFrame = iconFrame
	bar.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	bar.icon:SetAllPoints()
	B:SkinIcon(bar.icon)

	bar.text = B:CreateText(bar, B.db.castbars.fontSize, "LEFT")
	bar.text:SetPoint("LEFT", bar, "LEFT", 6, 0)
	bar.timer = B:CreateText(bar, B.db.castbars.fontSize, "RIGHT")
	bar.timer:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	bar.text:SetPoint("RIGHT", bar.timer, "LEFT", -6, 0)

	bar.spark = bar:CreateTexture(nil, "OVERLAY")
	bar.spark:SetTexture(B.white)
	bar.spark:SetVertexColor(1, 1, 1, 0.9)
	bar.spark:SetBlendMode("ADD")

	bar.latency = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.latency:SetTexture(B.white)
	bar.latency:SetVertexColor(0.9, 0.25, 0.25, 0.45)
	bar.latency:SetPoint("TOPRIGHT")
	bar.latency:SetPoint("BOTTOMRIGHT")
	bar.latency:Hide()

	bar.shield = bar:CreateTexture(nil, "OVERLAY")
	bar.shield:SetTexture(B.white)
	bar.shield:SetVertexColor(0.6, 0.6, 0.62, 0.9)
	bar.shield:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
	bar.shield:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
	bar.shield:SetHeight(2)
	bar.shield:Hide()

	for _, e in ipairs(castEvents) do
		pcall(bar.RegisterUnitEvent, bar, e, def.unit)
	end
	bar:RegisterEvent("PLAYER_ENTERING_WORLD")
	if def.key == "target" then bar:RegisterEvent("PLAYER_TARGET_CHANGED") end
	if def.key == "focus" then pcall(bar.RegisterEvent, bar, "PLAYER_FOCUS_CHANGED") end
	bar:SetScript("OnEvent", B.Safe(OnEvent))
	bar:SetScript("OnUpdate", B.Safe(OnUpdate))

	M.bars[def.key] = bar
	return bar
end

function M:LayoutBar(key)
	local bar = self.bars[key]
	if not bar then return end
	local c = cfg(key)
	bar:SetSize(c.width, c.height)
	bar.iconFrame:SetSize(c.height, c.height)
	bar.iconFrame:ClearAllPoints()
	bar.iconFrame:SetPoint("RIGHT", bar, "LEFT", -4, 0)
	bar.iconFrame:SetShown(c.icon)
	bar.spark:SetSize(2, c.height)
	local size = B.db.castbars.fontSize
	if c.height < 18 then size = size - 2 end
	B:SetFont(bar.text, size); bar.text.bSize = size
	B:SetFont(bar.timer, size); bar.timer.bSize = size
	if not c.enabled then
		bar:UnregisterAllEvents()
		bar:Hide()
	end
	B:SetMoverEnabled("cb_" .. key, c.enabled)
	B.Movers:Apply("cb_" .. key)
	self:Attach(key)
end

-- target / focus castbar tucked under its unit frame, icon + bar = frame width
function M:Attach(key)
	local bar = self.bars[key]
	local c = cfg(key)
	if not bar then return end
	local uf = B.db.unitframes
	local f = _G["BitsjUI_" .. key]
	local attached = c.attach and c.enabled and f and f.bars and uf.enabled and uf[key] and uf[key].enabled
	-- borders: as thick as the unit frame's when attached, so the edges line up
	local t = attached and (uf.borderSize or 1) or 1
	B:SetBorderSize(bar, t)
	B:SetBorderSize(bar.iconFrame, t)
	local px = B:Pixel(bar)
	local iconGap = px * t * 2 + px * 2          -- room for both borders + a hairline
	bar.iconFrame:ClearAllPoints()
	bar.iconFrame:SetPoint("RIGHT", bar, "LEFT", -iconGap, 0)
	if not attached then return end
	B:SetMoverEnabled("cb_" .. key, false)
	-- icon + gap + bar = exactly the unit frame's width
	local w = uf[key].width - (c.icon and (c.height + iconGap) or 0)
	bar:SetSize(math.max(20, w), c.height)
	local gap = px * t * 2 + px * 2
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", f.bars, "BOTTOMRIGHT", 0, -gap)
end

local function HideBlizzard(def)
	-- Mute and hide Blizzard's castbar. Never SetUnit(nil): Blizzard's target
	-- frame still calls UnitChannelInfo(bar.unit) when you change target.
	local f
	if def.key == "player" then
		f = _G.PlayerCastingBarFrame
	elseif def.key == "target" then
		f = _G.TargetFrameSpellBar or (_G.TargetFrame and _G.TargetFrame.spellbar)
	elseif def.key == "focus" then
		f = _G.FocusFrameSpellBar or (_G.FocusFrame and _G.FocusFrame.spellbar)
	end
	if f then
		if def.key == "player" then
			pcall(f.UnregisterAllEvents, f)
			f:SetAlpha(0)
			f:Hide()
		else
			-- Target / focus castbars must stay children of their unit frame:
			-- Blizzard calls GetParent():ShouldAnchorSpellBarToAuraContainer()
			-- on them. When BitsjUI replaces that unit frame the whole frame is
			-- already hidden; otherwise just keep the bar invisible.
			if not f.bAlphaHooked then
				f.bAlphaHooked = true
				hooksecurefunc(f, "SetAlpha", function(self, a)
					if self.bLockAlpha or a == 0 then return end
					self.bLockAlpha = true
					self:SetAlpha(0)
					self.bLockAlpha = nil
				end)
			end
			f:SetAlpha(0)
		end
	end
end

function M:OnEnable()
	if not B.db.castbars.enabled then return end
	for _, def in ipairs(UNITS) do
		local bar = CreateCastbar(def)
		B:RegisterMover(bar, "cb_" .. def.key, def.label, def.default)
		if cfg(def.key).enabled then HideBlizzard(def) end
		self:LayoutBar(def.key)
	end
	-- the mover system re-applies saved spots (login, layout reset); attached bars stay put
	hooksecurefunc(B.Movers, "Apply", function(_, name)
		local key = type(name) == "string" and name:match("^cb_(.+)$")
		if key and M.bars[key] then M:Attach(key) end
	end)
	hooksecurefunc(B.Movers, "ApplyAll", function() for key in pairs(M.bars) do M:Attach(key) end end)
		-- follow the unit frames when they are resized
	local UF = B:GetModule("UnitFrames")
	if UF and UF.LayoutFrame then
		hooksecurefunc(UF, "LayoutFrame", function(_, key)
			if M.bars[key] then M:LayoutBar(key) end
		end)
	end
end

function M:Update()
	if not B.db.castbars.enabled then return end
	for _, def in ipairs(UNITS) do self:LayoutBar(def.key) end
end

-- show test casts while the movers are visible
local function PreviewCasts()
	local unlocked = B.Movers.unlocked or B.previewing
	for key, bar in pairs(M.bars) do
		if unlocked and cfg(key).enabled then
			bar.mode = "lua"
			bar.casting = true
			bar.fading = nil
			bar.startTime = GetTime()
			bar.endTime = GetTime() + 3600
			bar.total = 3600
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0.6)
			bar.mode = "preview"
			bar.text:SetText("Preview")
			bar.timer:SetText("1.5")
			bar.icon:SetTexture(136243)
			bar:SetStatusBarColor(col("castColor"))
			bar:SetAlpha(1)
			bar:Show()
		elseif bar.mode == "preview" then
			bar.mode = nil
			bar.casting = nil
			bar:Hide()
		end
	end
end
B:RegisterCallback("MOVERS_TOGGLED", PreviewCasts)
B:RegisterCallback("PREVIEW", PreviewCasts)
B:RegisterCallback("UPDATE_ALL", PreviewCasts)
