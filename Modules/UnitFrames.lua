--[[
	BitsjUI - Unit frames
	Portrait style: round portrait, health + power bars with "current / max"
	text, name above the bars, level badge on the target.
	Health and power go straight into StatusBars (they accept Midnight's
	hidden combat values) and all text goes through secret-safe formatting.
]]
local _, B = ...
local M = B:NewModule("UnitFrames")
M.frames = {}

local issecret = B.IsSecret
local MEDIA = B.mediaPath .. "Textures\\"

local UNITS = {
	{ key = "player", unit = "player", label = "Player", default = { "BOTTOM", "BOTTOM", -180, 302 }, blizz = "PlayerFrame" },
	{ key = "target", unit = "target", label = "Target", default = { "BOTTOM", "BOTTOM", 180, 302 }, blizz = "TargetFrame", mirrored = true },
	{ key = "targettarget", unit = "targettarget", label = "Target of target", default = { "BOTTOM", "BOTTOM", 345, 306 }, blizz = "TargetFrameToT", nameBelow = true },
	{ key = "focus", unit = "focus", label = "Focus", default = { "BOTTOM", "BOTTOM", -420, 420 }, blizz = "FocusFrame" },
	{ key = "pet", unit = "pet", label = "Pet", default = { "BOTTOM", "BOTTOM", -345, 306 }, blizz = "PetFrame", nameBelow = true },
}
M.UNITS = UNITS

local function cfg(key) return B.db.unitframes[key] end

-------------------------------------------------------------------------------
-- Secret-safe text helpers
-------------------------------------------------------------------------------
-- returns something SetFormattedText("%s") can show: a short string, or the
-- raw (possibly hidden) number when the client won't let us shorten it
local function Abbrev(v)
	if not issecret(v) and v == nil then return "" end
	if AbbreviateNumbers then
		local ok, r = pcall(AbbreviateNumbers, v)
		if ok then
			if issecret(r) then return r end
			if type(r) == "string" and r ~= "" then return r end
		end
	end
	if issecret(v) then return v end
	if v >= 1e9 then return string.format("%.2fB", v / 1e9)
	elseif v >= 1e6 then return string.format("%.1fM", v / 1e6)
	elseif v >= 1e4 then return string.format("%.0fK", v / 1e3)
	elseif v >= 1e3 then return string.format("%.1fK", v / 1e3) end
	return tostring(math.floor(v))
end
M.Abbrev = Abbrev

local function Percent(func, unit, ...)
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if func then
		local ok, v = pcall(func, unit, ...)
		if ok and B.HasValue(v) then
			if curve or issecret(v) then return v end
			return v * 100
		end
	end
end

local function HealthPercent(unit)
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local v = Percent(UnitHealthPercent, unit, true, curve)
	if issecret(v) or v ~= nil then return v end
	local hp, max = UnitHealth(unit), UnitHealthMax(unit)
	if not issecret(hp) and not issecret(max) and max and max > 0 then return hp / max * 100 end
end
M.HealthPercent = HealthPercent

local function SafeFormat(fs, fmt, ...)
	return pcall(fs.SetFormattedText, fs, fmt, ...)
end

local function FormatValues(fs, mode, cur, max, pct)
	if mode == "none" then fs:SetText(""); return end
	local ok
	if mode == "curmax" then
		ok = SafeFormat(fs, "%s / %s", Abbrev(cur), Abbrev(max))
	elseif mode == "curmaxpct" then
		ok = (issecret(pct) or pct ~= nil) and SafeFormat(fs, "%s / %s  (%.0f%%)", Abbrev(cur), Abbrev(max), pct)
	elseif mode == "both" then
		ok = (issecret(pct) or pct ~= nil) and SafeFormat(fs, "%s  ||  %.0f%%", Abbrev(cur), pct)
	elseif mode == "percent" then
		ok = (issecret(pct) or pct ~= nil) and SafeFormat(fs, "%.0f%%", pct)
	else -- current
		ok = SafeFormat(fs, "%s", Abbrev(cur))
	end
	if not ok and not SafeFormat(fs, "%s", Abbrev(cur)) then fs:SetText("") end
end

-------------------------------------------------------------------------------
-- Colours
-------------------------------------------------------------------------------
local function UnitColor(unit)
	local r, g, b = 0.3, 0.8, 0.3
	pcall(function()
		if B.Plain(UnitIsPlayer(unit), false) then
			local _, class = UnitClass(unit)
			if class and not issecret(class) then r, g, b = B:ClassColor(class); return end
		end
		if B.Plain(UnitIsTapDenied and UnitIsTapDenied(unit), false) then r, g, b = 0.55, 0.55, 0.55; return end
		local reaction = B.Plain(UnitReaction(unit, "player"), nil)
		local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if c then r, g, b = c.r, c.g, c.b end
	end)
	return r, g, b
end
M.UnitColor = UnitColor

local function PowerColor(unit)
	local r, g, b = 0.3, 0.5, 1
	pcall(function()
		local _, token = UnitPowerType(unit)
		token = B.Plain(token, nil)
		local c = token and PowerBarColor and PowerBarColor[token]
		if c then r, g, b = c.r, c.g, c.b end
	end)
	return r, g, b
end

-------------------------------------------------------------------------------
-- Updates
-------------------------------------------------------------------------------
local function UpdateHealth(f)
	local unit = f.unit
	if not UnitExists(unit) then return end
	local db = B.db.unitframes
	local c = cfg(f.key)

	local max, hp = UnitHealthMax(unit), UnitHealth(unit)
	f.health:SetMinMaxValues(0, max)
	f.health:SetValue(hp)
	B:UpdateAbsorb(f.health, unit, db.absorbs ~= false)

	local r, g, b
	if db.healthColor == "dark" then
		local d = db.darkHealth; r, g, b = d.r, d.g, d.b
	elseif db.healthColor == "custom" then
		local d = db.customHealth; r, g, b = d.r, d.g, d.b
	else
		r, g, b = UnitColor(unit)
	end
	f.health:SetStatusBarColor(r, g, b)
	local m = db.bgMultiplier
	if db.healthColor == "dark" then
		local cr, cg, cb = UnitColor(unit)
		f.health.bg:SetVertexColor(cr * 0.35, cg * 0.35, cb * 0.35, 1)
	else
		f.health.bg:SetVertexColor(r * m, g * m, b * m, 1)
	end

	local fs = f.healthText
	local split = c.healthText == "split"
	if f.healthPct then f.healthPct:SetText("") end
	if not B.Plain(UnitIsConnected(unit), true) then fs:SetText("Offline"); return end
	if B.Plain(UnitIsDeadOrGhost(unit), false) then
		fs:SetText(B.Plain(UnitIsGhost(unit), false) and "Ghost" or "Dead")
		return
	end
	if split then
		-- value on the left, percent on the right
		local pct = HealthPercent(unit)
		FormatValues(fs, "current", hp, max, pct)
		if f.healthPct then FormatValues(f.healthPct, "percent", hp, max, pct) end
	else
		FormatValues(fs, c.healthText, hp, max, HealthPercent(unit))
	end
end

local function UpdatePower(f)
	if not f.power:IsShown() then return end
	local unit = f.unit
	if not UnitExists(unit) then return end
	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	f.power:SetMinMaxValues(0, max)
	f.power:SetValue(cur)
	local r, g, b = PowerColor(unit)
	f.power:SetStatusBarColor(r, g, b)
	f.power.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)
	local mode = cfg(f.key).powerText
	local pct
	if mode == "percent" then pct = Percent(UnitPowerPercent, unit, nil, CurveConstants and CurveConstants.ScaleTo100) end
	FormatValues(f.powerText, mode, cur, max, pct)
end

local classification = { worldboss = "B", rareelite = "R+", elite = "+", rare = "R" }

local function UpdateName(f)
	local unit = f.unit
	if not UnitExists(unit) then return end
	local c = cfg(f.key)
	local db = B.db.unitframes
	if c.showName then
		local name = UnitName(unit)
		if not pcall(f.nameText.SetText, f.nameText, name) then f.nameText:SetText("") end
		if db.nameColor == "class" then
			f.nameText:SetTextColor(UnitColor(unit))
		elseif db.nameColor == "white" then
			f.nameText:SetTextColor(1, 1, 1)
		else
			f.nameText:SetTextColor(1, 0.82, 0.1)
		end
	else
		f.nameText:SetText("")
	end

	-- clean style: plain level number above the outer corner
	local clean = db.style == "clean"
	if f.levelText then
		if clean and c.showLevel then
			local lvl = B.Plain(UnitLevel(unit), 0)
			local cl = B.Plain(UnitClassification(unit), "normal")
			f.levelText:SetText(((lvl and lvl > 0) and tostring(lvl) or "??") .. (classification[cl] or ""))
			local diff = GetCreatureDifficultyColor and lvl and lvl > 0 and GetCreatureDifficultyColor(lvl)
			if f.key == "player" or not diff then
				f.levelText:SetTextColor(1, 0.82, 0)
			else
				f.levelText:SetTextColor(diff.r, diff.g, diff.b)
			end
		else
			f.levelText:SetText("")
		end
	end
	if f.badge and clean then f.badge:Hide() end
	if f.badge and not clean then
		if c.showLevel then
			local lvl = B.Plain(UnitLevel(unit), 0)
			local cl = B.Plain(UnitClassification(unit), "normal")
			f.badge.text:SetText(((lvl and lvl > 0) and tostring(lvl) or "??") .. (classification[cl] or ""))
			local diff = GetCreatureDifficultyColor and lvl and lvl > 0 and GetCreatureDifficultyColor(lvl)
			if diff then f.badge.text:SetTextColor(diff.r, diff.g, diff.b) else f.badge.text:SetTextColor(1, 0.3, 0.3) end
			f.badge:Show()
		else
			f.badge:Hide()
		end
	end
end

local function UpdatePortrait(f)
	if not f.portrait or not f.portraitFrame:IsShown() then return end
	local unit = f.unit
	if not UnitExists(unit) then return end
	local style = B.db.unitframes.portraitStyle
	if style == "class" and B.Plain(UnitIsPlayer(unit), false) then
		local _, class = UnitClass(unit)
		if class and not issecret(class) then
			f.portrait:SetTexCoord(0, 1, 0, 1)
			B:ClassIcon(f.portrait, class)
			return
		end
	end
	f.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	SetPortraitTexture(f.portrait, unit)
end

local function UpdateIcons(f)
	local unit = f.unit
	local inCombat = B.Plain(UnitAffectingCombat("player"), false)
	if f.combat then f.combat:SetShown(inCombat and true or false) end
	if f.resting then f.resting:SetShown(IsResting() and not inCombat) end
	if f.leader then
		f.leader:SetShown(UnitExists(unit) and B.Plain(UnitIsGroupLeader(unit), false) or false)
	end
	if f.raidIcon then
		local idx = UnitExists(unit) and B.Plain(GetRaidTargetIndex(unit), nil)
		if idx then
			SetRaidTargetIconTexture(f.raidIcon, idx)
			f.raidIcon:Show()
		else
			f.raidIcon:Hide()
		end
	end
end

-------------------------------------------------------------------------------
-- Target auras
-------------------------------------------------------------------------------
local function AuraButton(f, i)
	f.auras = f.auras or {}
	local btn = f.auras[i]
	if btn then return btn end
	btn = CreateFrame("Button", nil, f)
	btn:EnableMouse(true)
	B:CreateBackdrop(btn, 1)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	B:SkinIcon(btn.icon, btn)
	btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	btn.cd:SetAllPoints()
	btn.cd:SetDrawEdge(false)
	btn.cd:SetReverse(true)
	btn.count = btn:CreateFontString(nil, "OVERLAY")
	B:SetFont(btn.count, 11)
	btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		local ok = false
		if self.auraID then
			local fn = self.isDebuff and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
			if fn then ok = pcall(fn, GameTooltip, f.unit, self.auraID, self.filter) end
		end
		if not ok and self.index then pcall(GameTooltip.SetUnitAura, GameTooltip, f.unit, self.index, self.filter) end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	f.auras[i] = btn
	return btn
end

-- shared with nameplates and timers
function M.ApplyAuraCooldown(cd, unit, aura)
	local id = aura.auraInstanceID
	if C_UnitAuras.GetAuraDuration and cd.SetCooldownFromDurationObject and id then
		local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, id)
		if ok and dur and pcall(cd.SetCooldownFromDurationObject, cd, dur) then return true end
	end
	local ok = pcall(function()
		if aura.duration and aura.duration > 0 then
			cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
		else
			cd:Clear()
		end
	end)
	if not ok then cd:Clear() end
	return ok
end

function M.ApplyAuraCount(fs, unit, aura)
	local id = aura.auraInstanceID
	if C_UnitAuras.GetAuraApplicationDisplayCount and id then
		local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
		if ok and pcall(fs.SetText, fs, txt) then return end
	end
	local n = B.Plain(aura.applications, 0)
	fs:SetText(n > 1 and n or "")
end

local function AuraFilter(a)
	local filter = a.buffs and "HELPFUL" or "HARMFUL"
	if a.onlyPlayer then filter = filter .. "|PLAYER" end
	return filter
end

-- 12.1+: let the client handle target auras through an AuraContainer
local function LayoutAuraBox(f)
	local a = cfg(f.key).auras
	if not a or not B:HasAuraContainers() then return end
	if not f.auraBox then
		f.auraBox = B:CreateAuraBox(f, { { key = "auras", filter = AuraFilter(a), max = a.num } }, a.size)
		if not f.auraBox then return end
		B:SetAuraBoxUnit(f.auraBox, f.unit)
	end
	f.auraBox:ClearAllPoints()
	f.auraBox:SetSize(a.num * (a.size + a.spacing), a.size)
	if B.db.unitframes.style == "clean" then
		f.auraBox:SetPoint("BOTTOMLEFT", f.bars, "TOPLEFT", 0, 18)
		pcall(f.auraBox.SetFlowLayoutAnchorPoint, f.auraBox, "BOTTOMLEFT")
	else
		f.auraBox:SetPoint("TOPLEFT", f.bars, "BOTTOMLEFT", 0, -5)
	end
	pcall(f.auraBox.SetAuraGroupFilterString, f.auraBox, "auras", AuraFilter(a))
	B:UpdateAuraBox(f.auraBox, a.size, { auras = a.enabled and a.num or 0 })
	f.auraBox:SetShown(a.enabled)
end
M.LayoutAuraBox = LayoutAuraBox

local function UpdateAuras(f)
	local a = cfg(f.key).auras
	if not a then return end
	if f.auraBox then return end
	local shown = 0
	if a.enabled and UnitExists(f.unit) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local isDebuff = not a.buffs
		local filter = isDebuff and "HARMFUL" or "HELPFUL"
		if a.onlyPlayer then filter = filter .. "|PLAYER" end
		local mirrored = f.def.mirrored
		for i = 1, 40 do
			if shown >= a.num then break end
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, f.unit, i, filter)
			if not ok or type(aura) ~= "table" then break end
			shown = shown + 1
			local btn = AuraButton(f, shown)
			btn:SetSize(a.size, a.size)
			btn:ClearAllPoints()
			local x = (shown - 1) * (a.size + a.spacing)
			if mirrored then
				btn:SetPoint("TOPRIGHT", f.bars, "BOTTOMRIGHT", -x, -5)
			else
				btn:SetPoint("TOPLEFT", f.bars, "BOTTOMLEFT", x, -5)
			end
			btn.index, btn.filter, btn.isDebuff = i, filter, isDebuff
			btn.auraID = aura.auraInstanceID
			pcall(btn.icon.SetTexture, btn.icon, aura.icon)
			M.ApplyAuraCount(btn.count, f.unit, aura)
			M.ApplyAuraCooldown(btn.cd, f.unit, aura)
			btn:Show()
		end
	end
	if f.auras then
		for i = shown + 1, #f.auras do f.auras[i]:Hide() end
	end
end

-------------------------------------------------------------------------------
-- Hunter pet happiness (Classic): small face tile beside the pet frame,
-- edge in green / yellow / red, tooltip with damage and loyalty
-------------------------------------------------------------------------------
local HAPPY = {
	[1] = { 0.375, 0.5625, 1.00, 0.30, 0.30 },   -- unhappy
	[2] = { 0.1875, 0.375, 1.00, 0.82, 0.25 },   -- content
	[3] = { 0, 0.1875, 0.37, 0.88, 0.45 },       -- happy
}

local function UpdateHappiness(f)
	local h = f.happy
	if not h then return end
	local happiness, damage, loyalty
	if GetPetHappiness then happiness, damage, loyalty = GetPetHappiness() end
	local isHunterPet = HasPetUI and select(2, HasPetUI())
	local info = happiness and HAPPY[happiness]
	if not info or not isHunterPet or cfg("pet").happiness == false then h:Hide(); return end
	-- crop the face out of Blizzard's sheet (each face has a transparent margin)
	local l, r = info[1], info[2]
	local w = r - l
	h.icon:SetTexCoord(l + w * 0.12, r - w * 0.12, 0.359375 * 0.1, 0.359375 * 0.9)
	h.bBorder:SetColor(info[3], info[4], info[5], 1)
	h.happiness, h.damage, h.loyalty = happiness, damage, loyalty
	h:Show()
end

local function CreateHappiness(f)
	local h = CreateFrame("Frame", nil, f.overlay)
	B:CreateBackdrop(h, 1)
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetPoint("TOPLEFT", 2, -2)
	h.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	h.icon:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	h:EnableMouse(true)
	h:SetScript("OnEnter", function(self)
		if not self.happiness then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		local c = HAPPY[self.happiness]
		GameTooltip:AddLine(_G["PET_HAPPINESS" .. self.happiness] or "", c[3], c[4], c[5])
		if PET_DAMAGE_PERCENTAGE and self.damage then
			GameTooltip:AddLine(string.format(PET_DAMAGE_PERCENTAGE, self.damage), 1, 1, 1)
		end
		if self.loyalty and self.loyalty < 0 and LOSING_LOYALTY then
			GameTooltip:AddLine(LOSING_LOYALTY, 1, 0.4, 0.4)
		elseif self.loyalty and self.loyalty > 0 and GAINING_LOYALTY then
			GameTooltip:AddLine(GAINING_LOYALTY, 0.4, 1, 0.5)
		end
		GameTooltip:Show()
	end)
	h:SetScript("OnLeave", GameTooltip_Hide)
	h:Hide()
	f.happy = h
end

local function UpdateAll(f)
	if not UnitExists(f.unit) then return end
	if f.happy then UpdateHappiness(f) end
	UpdateName(f)
	UpdateHealth(f)
	UpdatePower(f)
	UpdatePortrait(f)
	UpdateIcons(f)
	if f.key == "target" then UpdateAuras(f) end
end
M.UpdateFrame = UpdateAll

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------
local unitEvents = {
	UNIT_HEALTH = UpdateHealth, UNIT_MAXHEALTH = UpdateHealth, UNIT_ABSORB_AMOUNT_CHANGED = UpdateHealth, UNIT_CONNECTION = UpdateHealth, UNIT_FACTION = UpdateAll,
	UNIT_POWER_UPDATE = UpdatePower, UNIT_POWER_FREQUENT = UpdatePower, UNIT_MAXPOWER = UpdatePower, UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_NAME_UPDATE = UpdateName, UNIT_LEVEL = UpdateName, UNIT_CLASSIFICATION_CHANGED = UpdateName,
	UNIT_PORTRAIT_UPDATE = UpdatePortrait, UNIT_MODEL_CHANGED = UpdatePortrait,
	UNIT_AURA = function(f) if f.key == "target" then UpdateAuras(f) end end,
	UNIT_HAPPINESS = UpdateHappiness,
}

local function OnEvent(f, event, arg1)
	local handler = unitEvents[event]
	if handler then return handler(f) end
	if event == "UNIT_PET" then
		if arg1 == "player" then UpdateAll(f) end
	elseif event == "PET_UI_UPDATE" then
		UpdateHappiness(f)
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING"
		or event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
		UpdateIcons(f)
	else
		UpdateAll(f)
	end
end

local function CreateUnitFrame(def)
	local unit, key = def.unit, def.key
	local f = CreateFrame("Button", "BitsjUI_" .. key, UIParent, "SecureUnitButtonTemplate")
	f.unit, f.key, f.def = unit, key, def
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	if unit == "player" then f:SetAttribute("toggleForVehicle", true) end
	f:RegisterForClicks("AnyUp")
	f:SetFrameStrata("LOW")

	-- bar block
	local bars = CreateFrame("Frame", nil, f)
	B:CreateBackdrop(bars, 0.9)
	f.bars = bars
	f.health = B:CreateStatusBar(bars)
	B:CreateAbsorb(f.health)
	f.power = B:CreateStatusBar(bars)

	-- portrait
	local pf = CreateFrame("Frame", nil, f)
	pf:SetFrameLevel(bars:GetFrameLevel() + 3)
	f.portraitFrame = pf
	local bg = pf:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", pf, "TOPLEFT", 2, -2)
	bg:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -2, 2)
	bg:SetColorTexture(0.03, 0.03, 0.04, 1)
	f.portrait = pf:CreateTexture(nil, "ARTWORK")
	f.portrait:SetPoint("TOPLEFT", pf, "TOPLEFT", 2, -2)
	f.portrait:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -2, 2)
	local mask = pf:CreateMaskTexture()
	mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(f.portrait)
	f.portrait:AddMaskTexture(mask)
	bg:AddMaskTexture(mask)
	local ring = pf:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(MEDIA .. "PortraitRing")
	ring:SetPoint("TOPLEFT", pf, "TOPLEFT", -3, 3)
	ring:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 3, -3)
	f.ring = ring

	-- texts sit above everything
	local overlay = CreateFrame("Frame", nil, f)
	overlay:SetAllPoints(f)
	overlay:SetFrameLevel(pf:GetFrameLevel() + 5)
	f.overlay = overlay

	local db = B.db.unitframes
	f.nameText = B:CreateText(overlay, db.nameSize, "LEFT")
	f.healthText = B:CreateText(overlay, db.fontSize, "CENTER")
	f.healthPct = B:CreateText(overlay, db.fontSize, "RIGHT")
	f.powerText = B:CreateText(overlay, db.smallFontSize, "CENTER")
	f.levelText = B:CreateText(overlay, db.nameSize, "RIGHT")

	if key == "target" or key == "focus" then
		local badge = CreateFrame("Frame", nil, overlay)
		badge:SetSize(22, 22)
		local t = badge:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		t:SetTexture(MEDIA .. "Badge")
		badge.text = B:CreateText(badge, 10, "CENTER")
		badge.text:SetPoint("CENTER", 0, 0)
		f.badge = badge
	end

	f.raidIcon = overlay:CreateTexture(nil, "OVERLAY")
	f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.raidIcon:SetSize(18, 18)
	f.raidIcon:Hide()

	if key == "player" or key == "target" or key == "focus" then
		f.leader = overlay:CreateTexture(nil, "OVERLAY")
		f.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
		f.leader:SetSize(14, 14)
		f.leader:Hide()
	end
	if key == "player" then
		f.combat = overlay:CreateTexture(nil, "OVERLAY")
		f.combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
		f.combat:SetTexCoord(0.5, 1, 0, 0.49)
		f.combat:SetSize(20, 20)
		f.combat:Hide()
		f.resting = overlay:CreateTexture(nil, "OVERLAY")
		f.resting:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
		f.resting:SetTexCoord(0, 0.5, 0, 0.421875)
		f.resting:SetSize(18, 18)
		f.resting:Hide()
	end

	f:SetScript("OnEnter", function(self)
		if not UnitExists(self.unit) then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	f:SetScript("OnShow", B.Safe(UpdateAll))
	f:SetScript("OnEvent", B.Safe(OnEvent))

	for event in pairs(unitEvents) do
		pcall(f.RegisterUnitEvent, f, event, unit)
	end
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("RAID_TARGET_UPDATE")
	f:RegisterEvent("PARTY_LEADER_CHANGED")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	if key == "player" then
		f:RegisterEvent("PLAYER_REGEN_DISABLED")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("PLAYER_UPDATE_RESTING")
	elseif key == "target" or key == "targettarget" then
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
	elseif key == "focus" then
		pcall(f.RegisterEvent, f, "PLAYER_FOCUS_CHANGED")
	elseif key == "pet" then
		f:RegisterEvent("UNIT_PET")
		if GetPetHappiness then
			CreateHappiness(f)
			pcall(f.RegisterEvent, f, "PET_UI_UPDATE")
		end
	end

	if key == "targettarget" then
		f.elapsed = 0
		f:SetScript("OnUpdate", B.Safe(function(self, el)
			self.elapsed = self.elapsed + el
			if self.elapsed > 0.2 then self.elapsed = 0; UpdateAll(self) end
		end))
	end

	M.frames[key] = f
	return f
end

-- size / layout of an existing frame
function M:LayoutFrame(key)
	local f = self.frames[key]
	if not f then return end
	local c = cfg(key)
	local db = B.db.unitframes
	if InCombatLockdown() then
		B:RunOOC("uf_" .. key, function() M:LayoutFrame(key) end)
		return
	end

	local mirrored = f.def.mirrored
	local clean = db.style == "clean"
	local showPortrait = not clean and db.portraitStyle ~= "none" and (c.portraitSize or 0) > 0
	local p = B:Pixel(f)
	local ph = c.powerHeight or 0
	local barsH = c.healthHeight + (ph > 0 and (ph + p) or 0)
	local ps = showPortrait and c.portraitSize or 0
	local gap = showPortrait and -6 or 0   -- portrait overlaps the bar block slightly

	f:SetSize(c.width + ps + gap, math.max(barsH, ps))

	-- portrait
	f.portraitFrame:ClearAllPoints()
	f.portraitFrame:SetSize(math.max(1, ps), math.max(1, ps))
	f.portraitFrame:SetPoint(mirrored and "RIGHT" or "LEFT", f, mirrored and "RIGHT" or "LEFT", 0, 0)
	f.portraitFrame:SetShown(showPortrait)

	-- bar block, vertically centered on the portrait
	f.bars:ClearAllPoints()
	f.bars:SetSize(c.width, barsH)
	if showPortrait then
		f.bars:SetPoint(mirrored and "RIGHT" or "LEFT", f.portraitFrame, mirrored and "LEFT" or "RIGHT", mirrored and -gap or gap, 0)
	else
		f.bars:SetPoint("CENTER", f, "CENTER", 0, 0)
	end
	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", f.bars, "TOPLEFT", 0, 0)
	f.health:SetPoint("TOPRIGHT", f.bars, "TOPRIGHT", 0, 0)
	f.health:SetHeight(c.healthHeight)
	if ph > 0 then
		f.power:ClearAllPoints()
		f.power:SetPoint("BOTTOMLEFT", f.bars, "BOTTOMLEFT", 0, 0)
		f.power:SetPoint("BOTTOMRIGHT", f.bars, "BOTTOMRIGHT", 0, 0)
		f.power:SetHeight(ph)
		f.power:Show()
	else
		f.power:Hide()
	end
	-- the portrait covers the inner end of the bars; keep text clear of it
	local inset = showPortrait and 8 or 0

	-- fonts
	B:SetFont(f.nameText, db.nameSize); f.nameText.bSize = db.nameSize
	local hs = math.min(db.fontSize, math.max(8, c.healthHeight - 4))
	B:SetFont(f.healthText, hs); f.healthText.bSize = hs
	B:SetFont(f.healthPct, hs); f.healthPct.bSize = hs
	local ps2 = math.min(db.smallFontSize, math.max(7, ph))
	B:SetFont(f.powerText, ps2); f.powerText.bSize = ps2

	-- texts
	f.healthText:ClearAllPoints()
	f.healthPct:ClearAllPoints()
	if c.healthText == "split" then
		local l = (not mirrored) and inset or 0
		local r = mirrored and inset or 0
		f.healthText:SetPoint("LEFT", f.health, "LEFT", 5 + l, 0)
		f.healthText:SetJustifyH("LEFT")
		f.healthPct:SetPoint("RIGHT", f.health, "RIGHT", -5 - r, 0)
		f.healthPct:Show()
	else
		f.healthText:SetPoint("CENTER", f.health, "CENTER", mirrored and -inset / 2 or inset / 2, 0)
		f.healthText:SetJustifyH("CENTER")
		f.healthPct:Hide()
	end
	-- bolder border around the bar block
	B:SetBorderSize(f.bars, db.borderSize or 1)
	if f.portraitFrame.bBorder then B:SetBorderSize(f.portraitFrame, db.borderSize or 1) end
	f.powerText:ClearAllPoints()
	f.powerText:SetPoint("CENTER", f.power, "CENTER", mirrored and -inset / 2 or inset / 2, 0)
	f.nameText:ClearAllPoints()
	if f.def.nameBelow then
		f.nameText:SetPoint("TOP", f.bars, "BOTTOM", 0, -3)
		f.nameText:SetJustifyH("CENTER")
		f.nameText:SetWidth(c.width + ps)
	elseif clean then
		-- clean: name on the outer top corner, level on the inner top corner
		f.nameText:SetPoint(mirrored and "BOTTOMRIGHT" or "BOTTOMLEFT", f.bars, mirrored and "TOPRIGHT" or "TOPLEFT", 0, 3)
		f.nameText:SetJustifyH(mirrored and "RIGHT" or "LEFT")
		f.nameText:SetWidth(c.width - 30)
	else
		local x = mirrored and -inset or inset
		f.nameText:SetPoint(mirrored and "BOTTOMRIGHT" or "BOTTOMLEFT", f.bars, mirrored and "TOPRIGHT" or "TOPLEFT", x, 3)
		f.nameText:SetJustifyH(mirrored and "RIGHT" or "LEFT")
		f.nameText:SetWidth(c.width - inset)
	end
	B:SetFont(f.levelText, db.nameSize); f.levelText.bSize = db.nameSize
	f.levelText:ClearAllPoints()
	f.levelText:SetPoint(mirrored and "BOTTOMLEFT" or "BOTTOMRIGHT", f.bars, mirrored and "TOPLEFT" or "TOPRIGHT", 0, 3)
	f.levelText:SetJustifyH(mirrored and "LEFT" or "RIGHT")
	f.levelText:SetShown(clean)

	-- portrait decorations
	local anchor = showPortrait and f.portraitFrame or f.bars
	if f.badge then
		f.badge:ClearAllPoints()
		f.badge:SetPoint("CENTER", anchor, mirrored and "BOTTOMRIGHT" or "BOTTOMLEFT", mirrored and -4 or 4, 4)
	end
	f.raidIcon:ClearAllPoints()
	f.raidIcon:SetPoint("CENTER", anchor, "TOP", 0, 0)
	if f.happy then
		-- square tile on the outer side of the bars, same height and border as the frame
		local size = math.max(18, barsH)
		f.happy:ClearAllPoints()
		f.happy:SetSize(size, size)
		f.happy:SetPoint(mirrored and "LEFT" or "RIGHT", f.bars, mirrored and "RIGHT" or "LEFT", mirrored and 4 or -4, 0)
		B:SetBorderSize(f.happy, math.max(1, (db.borderSize or 2) - 1))
		UpdateHappiness(f)
	end
	if f.leader then
		f.leader:ClearAllPoints()
		f.leader:SetPoint("CENTER", anchor, mirrored and "TOPRIGHT" or "TOPLEFT", mirrored and -4 or 4, -4)
	end
	if f.combat then
		f.combat:ClearAllPoints()
		f.combat:SetPoint("CENTER", anchor, "BOTTOMRIGHT", -4, 4)
		f.resting:ClearAllPoints()
		f.resting:SetPoint("CENTER", anchor, "TOPLEFT", 4, -4)
	end

	if c.enabled then
		if key == "player" then f:Show()
		elseif M.preview then M:PreviewFrame(f, true)
		else RegisterUnitWatch(f) end
	else
		UnregisterUnitWatch(f)
		f:Hide()
	end
	B:SetMoverEnabled("uf_" .. key, c.enabled and not (M.cdmFitted and M.CDM_FOLLOW[key]))
	B.Movers:Apply("uf_" .. key)
	if key == "target" then B:Try(LayoutAuraBox, f) end
	B:Try(UpdateAll, f)
end

-------------------------------------------------------------------------------
-- Blizzard frames
-------------------------------------------------------------------------------
local function HideBlizzard(def)
	local frame = _G[def.blizz]
	if not frame or frame.bHidden then return end
	B:RunOOC("hideblizz_" .. def.key, function()
		frame.bHidden = true
		-- keep Blizzard's frame running (its events set up the castbar unit
		-- etc.; muting it caused UnitChannelInfo errors on target change),
		-- just park it in a hidden container
		frame:SetParent(B.hiddenParent)
	end)
end

-------------------------------------------------------------------------------
-- Preview: show your own character in the frames that need a unit
-------------------------------------------------------------------------------
function M:PreviewFrame(f, on)
	if f.key == "player" or InCombatLockdown() then return end
	if on and cfg(f.key).enabled then
		UnregisterUnitWatch(f)
		f.unit = "player"
		f:SetAttribute("unit", "player")
		if f.auraBox then B:SetAuraBoxUnit(f.auraBox, "player") end
		f:Show()
		B:Try(UpdateAll, f)
	else
		f.unit = f.def.unit
		f:SetAttribute("unit", f.def.unit)
		if f.auraBox then B:SetAuraBoxUnit(f.auraBox, f.def.unit) end
		if cfg(f.key).enabled then RegisterUnitWatch(f) else f:Hide() end
		if UnitExists(f.unit) then B:Try(UpdateAll, f) end
	end
end

B:RegisterCallback("PREVIEW", function(on)
	M.preview = on
	for _, f in pairs(M.frames) do M:PreviewFrame(f, on) end
end)

-------------------------------------------------------------------------------
-- Fit around the Cooldown Manager: the player frame sits left of Blizzard's
-- Essential cooldowns, the target frame right of them, both centred on the
-- same line; pet and target-of-target sit beside them. When the Cooldown
-- Manager grows or shrinks (more / fewer spells) the frames move with it.
-- Place the Cooldown Manager itself with Blizzard's Edit Mode.
-------------------------------------------------------------------------------
M.CDM_FOLLOW = { player = true, target = true, pet = true, targettarget = true }

local function CDMBounds()
	if not B.db.unitframes.fitCDM then return end
	local v = _G.EssentialCooldownViewer
	if not v or not v.GetLeft then return end
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("cooldownViewerEnabled") == "0" then return end
	local l, r, b, t = v:GetLeft(), v:GetRight(), v:GetBottom(), v:GetTop()
	if not (l and r and b and t) or r - l < 10 then return end
	local s = v:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * s, r * s, (b + t) / 2 * s
end

-- put a frame's `point` at UIParent coordinates x, y (frames can have their own scale)
local function PlaceAt(f, point, x, y)
	local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
	f:ClearAllPoints()
	f:SetPoint(point, UIParent, "BOTTOMLEFT", x * k, y * k)
end

function M:FitCDM()
	local l, r, cy = CDMBounds()
	local was = self.cdmFitted
	self.cdmFitted = l ~= nil
	if was ~= self.cdmFitted then
		for key in pairs(self.CDM_FOLLOW) do
			if self.frames[key] then B:SetMoverEnabled("uf_" .. key, cfg(key).enabled and not self.cdmFitted) end
		end
		-- back to the saved spots
		if was and not self.cdmFitted then
			for key in pairs(self.CDM_FOLLOW) do B.Movers:Apply("uf_" .. key) end
		end
	end
	if not l then return end
	if InCombatLockdown() then
		B:RunOOC("uf_fitcdm", function() M:FitCDM() end)
		return
	end
	local gap = B.db.unitframes.cdmGap or 12
	local p, t = self.frames.player, self.frames.target
	if p then PlaceAt(p, "RIGHT", l - gap, cy) end
	if t then PlaceAt(t, "LEFT", r + gap, cy) end
	local pet, tot = self.frames.pet, self.frames.targettarget
	if pet and p then pet:ClearAllPoints(); pet:SetPoint("RIGHT", p, "LEFT", -gap, 0) end
	if tot and t then tot:ClearAllPoints(); tot:SetPoint("LEFT", t, "RIGHT", gap, 0) end
end

-- run once per frame at most (size and position changes come in bursts)
function M:QueueFitCDM()
	if self.fitQueued then return end
	self.fitQueued = true
	C_Timer.After(0, function()
		M.fitQueued = false
		B:Try(M.FitCDM, M)
	end)
end

function M:HookCDM()
	local v = _G.EssentialCooldownViewer
	if not v or v.bFitHooked then return end
	v.bFitHooked = true
	v:HookScript("OnSizeChanged", function() M:QueueFitCDM() end)
	v:HookScript("OnShow", function() M:QueueFitCDM() end)
	hooksecurefunc(v, "SetPoint", function() M:QueueFitCDM() end)
	if v.SetScale then hooksecurefunc(v, "SetScale", function() M:QueueFitCDM() end) end
	self:QueueFitCDM()
end

function M:OnEnable()
	if not B.db.unitframes.enabled then return end
	for _, def in ipairs(UNITS) do
		local f = CreateUnitFrame(def)
		B:RegisterMover(f, "uf_" .. def.key, def.label, def.default)
		if cfg(def.key).enabled then HideBlizzard(def) end
		self:LayoutFrame(def.key)
	end
	-- the mover system re-applies saved spots; while fitted the Cooldown Manager decides
	hooksecurefunc(B.Movers, "Apply", function(_, name)
		local key = type(name) == "string" and name:match("^uf_(.+)$")
		if key and M.CDM_FOLLOW[key] and M.cdmFitted then M:QueueFitCDM() end
	end)
	hooksecurefunc(B.Movers, "ApplyAll", function() M:QueueFitCDM() end)
	self:HookCDM()
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_CooldownViewer" then M:HookCDM() end
	end)
	B:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() M:HookCDM(); M:QueueFitCDM() end) end)
	B:RegisterEvent("CVAR_UPDATE", function() M:QueueFitCDM() end)
end

function M:Update()
	if not B.db.unitframes.enabled then return end
	for _, def in ipairs(UNITS) do
		if self.frames[def.key] then
			if cfg(def.key).enabled then HideBlizzard(def) end
			self:LayoutFrame(def.key)
		end
	end
	self:QueueFitCDM()
end
