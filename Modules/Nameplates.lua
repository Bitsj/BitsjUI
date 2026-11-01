--[[
	BitsjUI - Nameplates
	Draws its own clean plate on top of each Blizzard nameplate:
	health bar with "2.0K (64.1%)", name under the bar, level, raid icon,
	your debuffs above the bar and a castbar under the name.
	The plate ignores the nameplate's own scale, so sizes are in normal UI
	units and follow the BitsjUI UI scale. Forbidden plates (friendly plates
	inside instances) are left to Blizzard, as the client requires.
]]
local _, B = ...
local M = B:NewModule("Nameplates")

local issecret = B.IsSecret
local active = {}   -- unit -> our plate

local function db() return B.db.nameplates end

local function SetCVarSafe(name, value)
	if C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name) == nil then return end
	pcall(SetCVar, name, tostring(value))
end

-- Blizzard applies plate opacity in the engine every frame, so the reliable
-- way to hide its plates is to let Blizzard fade them to 0 itself. The
-- player's own values are saved and restored when BitsjUI plates are off.
local ALPHA_CVARS = {
	"nameplateMinAlpha", "nameplateMaxAlpha", "nameplateSelectedAlpha",
	"nameplateNotSelectedAlpha", "nameplateOccludedAlphaMult",
}

function M:HideBlizzardPlates(hide)
	B.global.npAlphaBackup = B.global.npAlphaBackup or {}
	local backup = B.global.npAlphaBackup
	for _, name in ipairs(ALPHA_CVARS) do
		local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
		if cur ~= nil then
			if hide then
				if backup[name] == nil then backup[name] = cur end
				pcall(SetCVar, name, "0")
			elseif backup[name] ~= nil then
				pcall(SetCVar, name, backup[name])
				backup[name] = nil
			end
		end
	end
end

function M:ApplyCVars()
	local d = db()
	B:RunOOC("np_cvars", function()
		M:HideBlizzardPlates(d.enabled)
		SetCVarSafe("nameplateMaxDistance", d.maxDistance)
		SetCVarSafe("ShowClassColorInNameplate", d.classColors and 1 or 0)
		M:ApplyStacking(d.stacking)
	end)
end

-- Midnight removed the old overlap CVars and added a separate "Stack
-- Nameplates" option whose CVar name isn't documented. Ask the client for
-- every console variable with "nameplate" and "stack" in its name and switch
-- the on/off ones.
M.stackCVars = {}
function M:ApplyStacking(on)
	wipe(self.stackCVars)
	if not (C_Console and C_Console.GetAllCommands) then return end
	local ok, list = pcall(C_Console.GetAllCommands)
	if not ok or type(list) ~= "table" then return end
	for _, c in ipairs(list) do
		local name = type(c) == "table" and c.command
		if type(name) == "string" then
			local lower = name:lower()
			if lower:find("nameplate") and lower:find("stack") then
				local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
				if cur == "0" or cur == "1" then
					pcall(SetCVar, name, on and "1" or "0")
					self.stackCVars[#self.stackCVars + 1] = name
				end
			end
		end
	end
	-- older clients
	SetCVarSafe("nameplateMotion", on and 1 or 0)
end

local function UF() return B:GetModule("UnitFrames") end

-------------------------------------------------------------------------------
-- Pieces
-------------------------------------------------------------------------------
-- quest > caster > melee; anything else returns nil (keeps the reaction colour).
-- Casters are told apart by their mana bar (the method coloured-plate addons
-- use in Midnight); melee = other elites, so normal trash stays red.
function M.MobType(unit)
	if not db().colorByType or B.Plain(UnitIsPlayer(unit), true) then return end
	local quest = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if quest then
		local ok, v = pcall(quest, unit)
		if ok and B.Plain(v, false) == true then return "quest" end
	end
	local cl = B.Plain(UnitClassification(unit), "normal")
	local elite = cl == "elite" or cl == "rareelite" or cl == "worldboss"
	local ok, pt = pcall(UnitPowerType, unit)
	pt = ok and B.Plain(pt, nil)
	local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
	if pt == mana then
		local okMax, mx = pcall(UnitPowerMax, unit, mana)
		mx = okMax and B.Plain(mx, 1) or 1
		if mx and mx > 0 then return "caster" end
	end
	if elite then return "melee" end
end

-- aggro: UnitThreatSituation 3 = you tank securely, 2 = you tank but are
-- losing it, 1 = someone else tanks but you're close, 0 = someone else tanks
local tankCache, tankTime = false, 0
local IsTankRoleRaw
local function IsTankRole()
	local now = GetTime()
	if now - tankTime > 0.5 then tankCache, tankTime = IsTankRoleRaw(), now end
	return tankCache
end
function IsTankRoleRaw()
	local idx = GetSpecialization and GetSpecialization()
	local role = idx and GetSpecializationRole and GetSpecializationRole(idx)
	if role then return role == "TANK" end
	-- Classic: no specs. Group role, tank stance / form, or Righteous Fury
	if UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") == "TANK" then return true end
	local form = GetShapeshiftFormID and GetShapeshiftFormID()
	if form == 5 or form == 8 or form == 18 then return true end   -- bear, dire bear, defensive stance
	local _, class = UnitClass("player")
	if class == "PALADIN" then
		for i = 1, 40 do
			local a = B.GetAura("player", i, "HELPFUL")
			if not a then break end
			if a.spellId == 25780 or a.spellId == 407627 then return true end   -- Righteous Fury
		end
	end
	return false
end

local function UpdateThreat(np)
	local t = np.threat
	if not t then return end
	local d = db()
	local status
	if d.threat then
		local ok, s = pcall(UnitThreatSituation, "player", np.unit)
		status = ok and B.Plain(s, nil)
	end
	if type(status) ~= "number" then t:Hide(); return end
	local c
	if IsTankRole() then
		if status == 3 then c = d.threatHigh
		elseif status >= 1 then c = d.threatWarn
		else c = d.threatLow end
	else
		if status == 3 then c = d.threatLow
		elseif status >= 1 then c = d.threatWarn end
	end
	if not c then t:Hide(); return end
	t:SetColor(c.r, c.g, c.b, 1)
	t:Show()
end
M.UpdateThreat = UpdateThreat

local function Color(unit)
	local r, g, b = 0.85, 0.2, 0.2
	pcall(function()
		if B.Plain(UnitIsPlayer(unit), false) and db().classColors then
			local _, class = UnitClass(unit)
			if class and not issecret(class) then r, g, b = B:ClassColor(class); return end
		end
		if B.Plain(UnitIsTapDenied and UnitIsTapDenied(unit), false) then r, g, b = 0.55, 0.55, 0.55; return end
		local reaction = B.Plain(UnitReaction(unit, "player"), nil)
		local kind = reaction and reaction <= 4 and M.MobType(unit)
		if kind then
			local c = db()[kind .. "Color"]
			r, g, b = c.r, c.g, c.b
			return
		end
		if reaction then
			if reaction <= 3 then r, g, b = 0.85, 0.2, 0.2
			elseif reaction == 4 then r, g, b = 0.95, 0.8, 0.25
			else r, g, b = 0.3, 0.8, 0.3 end
		end
	end)
	return r, g, b
end

-------------------------------------------------------------------------------
-- Absorb shields: a light bar that starts where the health ends. Works with
-- Midnight's hidden numbers, the status bar takes them as they are.
-------------------------------------------------------------------------------
local function UpdateAbsorb(np)
	B:UpdateAbsorb(np.health, np.unit, db().absorbs)
end

local function UpdateHealth(np)
	local unit = np.unit
	local max, hp = UnitHealthMax(unit), UnitHealth(unit)
	np.health:SetMinMaxValues(0, max)
	np.health:SetValue(hp)
	UpdateAbsorb(np)
	local r, g, b = Color(unit)
	np.health:SetStatusBarColor(r, g, b)
	-- the missing part stays readable: a dim version of the colour, fully opaque
	np.health.bg:SetVertexColor(r * 0.22 + 0.04, g * 0.22 + 0.04, b * 0.22 + 0.04, 1)
	if db().nameAbove then np.name:SetTextColor(r, g, b) else np.name:SetTextColor(1, 1, 1) end
	UpdateThreat(np)

	local mode = db().healthText
	local fs = np.hpText
	if mode == "none" then fs:SetText(""); return end
	local Abbrev = UF().Abbrev
	local pct = UF().HealthPercent(unit)
	local hasPct = issecret(pct) or pct ~= nil
	local ok
	if mode == "both" and hasPct then
		ok = pcall(fs.SetFormattedText, fs, "%s (%.1f%%)", Abbrev(hp), pct)
	elseif mode == "percent" and hasPct then
		ok = pcall(fs.SetFormattedText, fs, "%.1f%%", pct)
	else
		ok = pcall(fs.SetFormattedText, fs, "%s", Abbrev(hp))
	end
	if not ok then fs:SetText("") end
end

local function UpdateName(np)
	local unit = np.unit
	if not pcall(np.name.SetText, np.name, UnitName(unit)) then np.name:SetText("") end
	if db().showLevel then
		local lvl = B.Plain(UnitLevel(unit), 0)
		local cl = B.Plain(UnitClassification(unit), "normal")
		local txt = (lvl and lvl > 0) and tostring(lvl) or "??"
		if cl == "elite" or cl == "rareelite" or cl == "worldboss" then txt = txt .. "+" end
		np.level:SetText(txt)
		local diff = GetCreatureDifficultyColor and lvl and lvl > 0 and GetCreatureDifficultyColor(lvl)
		if diff then np.level:SetTextColor(diff.r, diff.g, diff.b) else np.level:SetTextColor(1, 0.3, 0.3) end
	else
		np.level:SetText("")
	end
end

local function UpdateTarget(np)
	local d = db()
	local isTarget = np.forceTarget or B.Plain(UnitIsUnit(np.unit, "target"), false)
	local isMouse = not isTarget and B.Plain(UnitIsUnit(np.unit, "mouseover"), false)
	np:SetScale(isTarget and d.targetScale or 1)
	np:SetFrameLevel(isTarget and 20 or isMouse and 10 or 2)
	local hasTarget = UnitExists("target")
	np:SetAlpha((hasTarget and not isTarget and not isMouse) and d.nonTargetAlpha or 1)
	-- target: thick bright border, soft glow and arrows either side
	local c = d.targetColor
	B:SetBorderSize(np.health, isTarget and 2 or 1)
	if isTarget then np.health.bBorder:SetColor(c.r, c.g, c.b, 1)
	elseif isMouse then np.health.bBorder:SetColor(0.75, 0.75, 0.78, 1)
	else np.health.bBorder:SetColor(0, 0, 0, 1) end
	np.glow:SetVertexColor(c.r, c.g, c.b, 0.55)
	np.glow:SetShown(isTarget and d.targetGlow)
	np.arrowL:SetVertexColor(c.r, c.g, c.b, 1)
	np.arrowR:SetVertexColor(c.r, c.g, c.b, 1)
	np.arrowL:SetShown(isTarget and d.targetArrows)
	np.arrowR:SetShown(isTarget and d.targetArrows)
end

local function UpdateRaidIcon(np)
	local idx = B.Plain(GetRaidTargetIndex(np.unit), nil)
	if idx then
		SetRaidTargetIconTexture(np.raid, idx)
		np.raid:Show()
	else
		np.raid:Hide()
	end
end

local function DebuffFilter() return db().onlyMine and "HARMFUL|PLAYER" or "HARMFUL" end

-- Blizzard AuraContainers (12.1+): the client picks and draws the auras
local function CreateBoxes(np)
	if np.debuffBox ~= nil or not B:HasAuraContainers() then return end
	local d = db()
	np.debuffBox = B:CreateAuraBox(np, {
		{ key = "debuffs", filter = DebuffFilter(), max = d.debuffNum },
	}, d.debuffSize) or false
	np.buffBox = B:CreateAuraBox(np, {
		{ key = "dispel", filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", max = d.buffNum, glow = d.dispelGlow and d.glowColor or nil },
		{ key = "buffs", filter = "HELPFUL|!RAID_PLAYER_DISPELLABLE", max = d.buffNum },
	}, d.buffSize) or false
end

local function LayoutBoxes(np)
	local d = db()
	if np.debuffBox then
		np.debuffBox:ClearAllPoints()
		np.debuffBox:SetPoint("BOTTOMLEFT", np.health, "TOPLEFT", 0, d.nameAbove and (d.nameSize + 8) or 4)
		np.debuffBox:SetSize(d.width, d.debuffSize)
		pcall(np.debuffBox.SetAuraGroupFilterString, np.debuffBox, "debuffs", DebuffFilter())
		B:UpdateAuraBox(np.debuffBox, d.debuffSize, { debuffs = d.debuffs and d.debuffNum or 0 })
		np.debuffBox:SetShown(d.debuffs)
	end
	if np.buffBox then
		np.buffBox:ClearAllPoints()
		np.buffBox:SetPoint("LEFT", np.health, "RIGHT", 4, 0)
		np.buffBox:SetSize(d.buffSize * d.buffNum, d.buffSize)
		for _, g in ipairs(np.buffBox.bGroups) do
			if g.key == "dispel" then g.glow = d.dispelGlow and d.glowColor or nil end
		end
		local n = d.buffs and d.buffNum or 0
		B:UpdateAuraBox(np.buffBox, d.buffSize, { dispel = n, buffs = n })
		np.buffBox:SetShown(d.buffs)
	end
end

local function UpdateAuras(np)
	if np.debuffBox then return end   -- the client keeps AuraContainers up to date
	local d = db()
	local shown = 0
	if d.debuffs and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local filter = d.onlyMine and "HARMFUL|PLAYER" or "HARMFUL"
		for i = 1, 40 do
			if shown >= d.debuffNum then break end
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, np.unit, i, filter)
			if not ok or type(aura) ~= "table" then break end
			shown = shown + 1
			local btn = np.auras[shown]
			if not btn then
				btn = CreateFrame("Frame", nil, np)
				B:CreateBackdrop(btn, 1)
				btn.icon = btn:CreateTexture(nil, "ARTWORK")
				btn.icon:SetAllPoints()
				btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.25 + 0.67)
				btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
				btn.cd:SetAllPoints()
				btn.cd:SetDrawEdge(false)
				btn.cd:SetReverse(true)
				btn.count = btn:CreateFontString(nil, "OVERLAY")
				btn.count:SetPoint("BOTTOMRIGHT", 1, 0)
				np.auras[shown] = btn
			end
			local size = d.debuffSize
			btn:SetSize(size, math.floor(size * 0.75))
			btn.icon:SetTexCoord(0.08, 0.92, 0.18, 0.82)
			B:SetFont(btn.count, math.max(8, math.floor(size * 0.45)))
			local cdText = btn.cd.GetCountdownFontString and btn.cd:GetCountdownFontString()
			if cdText then B:SetFont(cdText, math.max(8, math.floor(size * 0.45))) end
			btn:ClearAllPoints()
			btn:SetPoint("BOTTOMLEFT", np.health, "TOPLEFT", (shown - 1) * (size + 2), 4)
			pcall(btn.icon.SetTexture, btn.icon, aura.icon)
			UF().ApplyAuraCount(btn.count, np.unit, aura)
			UF().ApplyAuraCooldown(btn.cd, np.unit, aura)
			btn:Show()
		end
	end
	for i = shown + 1, #np.auras do np.auras[i]:Hide() end

	-- enemy buffs right of the bar; ones you can purge / dispel glow
	np.sBuffs = np.sBuffs or {}
	local nb = 0
	if d.buffs and UnitCanAttack("player", np.unit) then
		local canPurge = M.CanPurge()
		for i = 1, 40 do
			if nb >= d.buffNum then break end
			local aura = B.GetAura(np.unit, i, "HELPFUL")
			if not aura then break end
			nb = nb + 1
			local btn = np.sBuffs[nb]
			if not btn then
				btn = B:CreateAuraIcon(np, d.buffSize)
				np.sBuffs[nb] = btn
			end
			btn:SetSize(d.buffSize, d.buffSize)
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", np.health, "RIGHT", 4 + (nb - 1) * (d.buffSize + 2), 0)
			local glow = d.dispelGlow and (aura.isStealable or (canPurge and aura.dispelName == "Magic"))
			B:SetAuraIcon(btn, aura, glow and d.glowColor or { r = 0, g = 0, b = 0 })
		end
	end
	for i = nb + 1, #np.sBuffs do np.sBuffs[i]:Hide() end
end

-- classes that can remove magic buffs from enemies (Purge, Dispel Magic, Tranq for enrage is not magic)
function M.CanPurge()
	local _, class = UnitClass("player")
	return class == "SHAMAN" or class == "PRIEST" or class == "WARLOCK" or class == "DEMONHUNTER" or class == "EVOKER"
end

-------------------------------------------------------------------------------
-- Interrupt indicator on enemy castbars
--   ready      -> green frame around the castbar, bright kick icon
--   on cooldown-> grey kick icon with the cooldown running down, and a green
--                 line on the castbar where your kick comes back (red icon
--                 if it won't be back before the cast ends)
-- Blizzard hides some timings in instances; then the line can't be placed,
-- but the frame still turns green the moment your kick is ready.
-------------------------------------------------------------------------------
local KICKS = {
	WARRIOR = { 6552 }, ROGUE = { 1766 }, DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 },
	PALADIN = { 96231 }, SHAMAN = { 57994 }, MAGE = { 2139 }, HUNTER = { 147362, 187707 },
	MONK = { 116705 }, DRUID = { 106839, 78675 }, PRIEST = { 15487 }, EVOKER = { 351338 },
	WARLOCK = { 119910, 19647, 132409 },
}
-- Classic / Forever: by name (spell ranks have different IDs)
local CLASSIC_KICKS = {
	WARRIOR = { "Pummel", "Shield Bash" }, ROGUE = { "Kick" }, MAGE = { "Counterspell" },
	SHAMAN = { "Wind Shear", "Earth Shock" }, PRIEST = { "Silence" }, DEATHKNIGHT = { "Mind Freeze" },
	PALADIN = { "Rebuke" }, HUNTER = { "Counter Shot" }, DRUID = { "Skull Bash" }, MONK = { "Spear Hand Strike" },
}
local kick            -- { id = spellID or name, icon = texture }
local kickReady, kickReadyAt
-- base cooldowns, used to guess when kick is back while Blizzard hides the
-- real number (talents can shorten it; the green frame always shows the truth)
local KICK_CD = {
	[6552] = 15, [1766] = 15, [47528] = 15, [183752] = 15, [96231] = 15, [57994] = 12, [2139] = 24,
	[147362] = 24, [187707] = 15, [116705] = 15, [106839] = 15, [78675] = 60, [15487] = 30,
	[351338] = 20, [119910] = 24, [19647] = 24, [132409] = 24,
	Pummel = 10, ["Shield Bash"] = 12, Kick = 10, Counterspell = 24, ["Earth Shock"] = 6, Silence = 45,
	["Wind Shear"] = 6, ["Mind Freeze"] = 10, Rebuke = 15, ["Counter Shot"] = 24, ["Skull Bash"] = 15, ["Spear Hand Strike"] = 15,
}

local function Known(id)
	for _, fn in ipairs({ _G.IsPlayerSpell, _G.IsSpellKnownOrOverridesKnown }) do
		local ok, r = pcall(fn, id)
		if ok and r then return true end
	end
	local ok, r = pcall(_G.IsSpellKnown, id, true)   -- pet spells (Spell Lock)
	return ok and r and true or false
end

function M:FindKick()
	kick = nil
	if not db().kickIndicator then return end
	local _, class = UnitClass("player")
	if B.classicContent then
		for _, name in ipairs(CLASSIC_KICKS[class] or {}) do
			local n, icon
			if C_Spell and C_Spell.GetSpellInfo then
				local ok, info = pcall(C_Spell.GetSpellInfo, name)
				if ok and type(info) == "table" then n, icon = info.name, info.iconID end
			elseif GetSpellInfo then
				n, _, icon = GetSpellInfo(name)
			end
			if n then kick = { id = name, icon = icon }; break end
		end
	end
	if not kick then
		for _, id in ipairs(KICKS[class] or {}) do
			if Known(id) then
				local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
				kick = { id = id, icon = icon }
				break
			end
		end
	end
	M.kick = kick
end

-- ready (bool), readyAt (GetTime() value, or nil when Blizzard hides it)
local function KickState()
	if not kick then return end
	local start, dur, active, onGCD
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, kick.id)
		if ok and type(info) == "table" then start, dur, active, onGCD = info.startTime, info.duration, info.isActive, info.isOnGCD end
	elseif GetSpellCooldown then
		local ok, s, d = pcall(GetSpellCooldown, kick.id)
		if ok then start, dur = s, d end
	end
	if start and dur and not issecret(start) and not issecret(dur) then
		if dur == 0 or dur <= 1.5 then return true end   -- off cooldown, or only the global cooldown
		local at = start + dur
		return at <= GetTime(), at
	end
	if type(active) == "boolean" then return (not active) or onGCD == true end
	return true
end

local function RefreshKick()
	if not kick then kickReady, kickReadyAt = nil, nil; return end
	local was = kickReady
	local ready, at = KickState()
	local now = GetTime()
	if ready then
		kick.estAt = nil
	elseif not at then
		-- just went on cooldown: start our own clock
		if was == true then kick.estAt = now + (KICK_CD[kick.id] or 15) end
		if kick.estAt and kick.estAt > now then at = kick.estAt end
	end
	kickReady, kickReadyAt = ready, at
end

-- show a frame / texture unless the cast can't be interrupted (flag may be hidden)
local function ShowIfInterruptible(obj, notInt)
	if issecret(notInt) then
		obj:Show()
		if not (obj.SetAlphaFromBoolean and pcall(obj.SetAlphaFromBoolean, obj, notInt, 0, 1)) then obj:SetAlpha(1) end
	else
		obj:SetAlpha(1)
		obj:SetShown(not notInt)
	end
end

-- line on the castbar where kick comes back. Readable cast times: plain
-- maths. Hidden cast times: a copy of the cast's own timer, frozen at the
-- moment kick is back, drives an invisible bar; the line sits on its edge.
local function PlaceTick(cb, readyAt)
	local holder, tick, probe = cb.tickHolder, cb.tick, cb.probe
	if cb.mode == "lua" then
		local inTime = readyAt < cb.endTime
		local frac = cb.channeling and (cb.endTime - readyAt) / cb.total or (readyAt - cb.startTime) / cb.total
		if inTime and frac > 0 and frac < 1 then
			tick:ClearAllPoints()
			tick:SetPoint("TOP", cb, "TOPLEFT", frac * cb:GetWidth(), 0)
			tick:SetPoint("BOTTOM", cb, "BOTTOMLEFT", frac * cb:GetWidth(), 0)
			tick:SetAlpha(1)
			tick:Show()
		else
			tick:Hide()
		end
		return inTime
	end
	local d = cb.castDur
	if not (d and d.Copy and C_DurationUtil and C_DurationUtil.CreateManualClock and probe.SetTimerDuration) then
		tick:Hide(); return true
	end
	if cb.probeAt ~= readyAt then
		cb.probeAt = readyAt
		local ok = pcall(function()
			local copy = d:Copy()
			cb.clock = cb.clock or C_DurationUtil.CreateManualClock()
			cb.clock:SetTime(readyAt)
			copy:SetClock(cb.clock)
			local dir = Enum and Enum.StatusBarTimerDirection
			probe:SetTimerDuration(copy, nil, cb.channeling and dir and dir.RemainingTime or dir and dir.ElapsedTime)
			cb.probeDur = copy
		end)
		if not ok then cb.probeDur = nil end
		tick:ClearAllPoints()
		tick:SetPoint("TOP", probe:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		tick:SetPoint("BOTTOM", probe:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	end
	if not cb.probeDur then tick:Hide(); return true end
	tick:Show()
	-- past the end of the cast: no line
	local okE, expired = pcall(cb.probeDur.HasExpired, cb.probeDur)
	if not okE then tick:SetAlpha(1); return true end
	if issecret(expired) then
		if not (tick.SetAlphaFromBoolean and pcall(tick.SetAlphaFromBoolean, tick, expired, 0, 1)) then tick:SetAlpha(1) end
		return true
	end
	tick:SetAlpha(expired and 0 or 1)
	return not expired
end

local function UpdateKick(np)
	local cb = np.cast
	local k, edge, holder = cb.kick, cb.edge, cb.tickHolder
	if not (kick and db().kickIndicator and cb:IsShown() and cb.attackable) then
		k:Hide(); edge:Hide(); k.edge:Hide(); holder:Hide(); k.state = nil
		return
	end
	local ready, readyAt = kickReady, kickReadyAt
	k.icon:SetTexture(kick.icon)
	ShowIfInterruptible(k, cb.notInt)
	local c = db().kickColor
	if ready then
		if k.state ~= "ready" then
			k.state = "ready"
			k.icon:SetDesaturated(false)
			k.icon:SetVertexColor(1, 1, 1)
			k.bar:Hide()
			k.text:SetText("")
			edge:SetColor(c.r, c.g, c.b, 1)
			k.edge:SetColor(c.r, c.g, c.b, 1)
		end
		ShowIfInterruptible(edge, cb.notInt)
		ShowIfInterruptible(k.edge, cb.notInt)
		holder:Hide()
		cb.probeAt = nil
		return
	end
	edge:Hide(); k.edge:Hide()
	k.icon:SetDesaturated(true)
	cb.tick:SetVertexColor(c.r, c.g, c.b, 1)
	if readyAt then
		k.state = "cd"
		local rem = math.max(0, readyAt - GetTime())
		k.bar:SetMinMaxValues(0, 1); k.bar:SetValue(1); k.bar:Show()
		k.text:SetText(rem >= 1 and string.format("%d", math.ceil(rem)) or string.format("%.1f", rem))
		ShowIfInterruptible(holder, cb.notInt)
		local inTime = PlaceTick(cb, readyAt)
		if inTime then k.icon:SetVertexColor(1, 1, 1) else k.icon:SetVertexColor(1, 0.35, 0.35) end
	else
		-- no number at all: let the cover run the cooldown down by itself
		holder:Hide()
		k.icon:SetVertexColor(1, 1, 1)
		k.text:SetText("")
		if k.state ~= "hidden" then
			k.state = "hidden"
			local ok = false
			if C_Spell and C_Spell.GetSpellCooldownDuration and k.bar.SetTimerDuration then
				local okd, dur = pcall(C_Spell.GetSpellCooldownDuration, kick.id, true)
				local dir = Enum and Enum.StatusBarTimerDirection
				if okd and dur then
					ok = dir and pcall(k.bar.SetTimerDuration, k.bar, dur, nil, dir.RemainingTime)
					if not ok then ok = pcall(k.bar.SetTimerDuration, k.bar, dur) end
				end
			end
			if not ok then k.bar:SetMinMaxValues(0, 1); k.bar:SetValue(1) end
			k.bar:Show()
		end
	end
end

-------------------------------------------------------------------------------
-- Castbar
-------------------------------------------------------------------------------
local function CastColor(cb, notInt)
	local cc = B.db.castbars
	local base = cb.channeling and cc.channelColor or cc.castColor
	local ni = cc.nonInterruptColor
	if not issecret(notInt) then
		local c = notInt and ni or base
		cb:SetStatusBarColor(c.r, c.g, c.b)
		return
	end
	cb:SetStatusBarColor(1, 1, 1)
	local tex = cb:GetStatusBarTexture()
	if not (tex and tex.SetVertexColorFromBoolean and CreateColor
		and pcall(tex.SetVertexColorFromBoolean, tex, notInt, CreateColor(ni.r, ni.g, ni.b, 1), CreateColor(base.r, base.g, base.b, 1))) then
		cb:SetStatusBarColor(base.r, base.g, base.b)
	end
end

local function CastStart(np, channel)
	local cb = np.cast
	if not db().castbar then cb:Hide(); return end
	local unit = np.unit
	local name, text, texture, startMS, endMS, notInt, _
	if channel then
		name, text, texture, startMS, endMS, _, notInt = UnitChannelInfo(unit)
	else
		name, text, texture, startMS, endMS, _, _, notInt = UnitCastingInfo(unit)
	end
	if not B.HasValue(name) then cb:Hide(); return end
	cb.channeling = channel
	cb.notInt = notInt
	cb.attackable = B.Plain(UnitCanAttack("player", unit), true)
	pcall(cb.icon.SetTexture, cb.icon, texture)
	if not pcall(cb.text.SetText, cb.text, text) then pcall(cb.text.SetText, cb.text, name) end
	CastColor(cb, notInt)
	cb.mode = nil
	if not issecret(startMS) and not issecret(endMS) and startMS and endMS then
		cb.mode = "lua"
		cb.castDur = nil
		cb.startTime, cb.endTime = startMS / 1000, endMS / 1000
		cb.total = math.max(0.001, cb.endTime - cb.startTime)
		cb:SetMinMaxValues(0, cb.total)
	else
		local fn = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
		local ok = false
		if fn and cb.SetTimerDuration then
			local okd, dur = pcall(fn, unit)
			cb.castDur = okd and dur or nil
			if okd and dur then
				local dir = Enum and Enum.StatusBarTimerDirection
				ok = dir and pcall(cb.SetTimerDuration, cb, dur, nil, channel and dir.RemainingTime or dir.ElapsedTime)
				if not ok then ok = pcall(cb.SetTimerDuration, cb, dur) end
			end
		end
		if not ok then cb:SetMinMaxValues(0, 1); cb:SetValue(1) end
	end
	cb:Show()
	cb.kick.state = nil
	cb.probeAt = nil
	B:Try(UpdateKick, np)
end

local function CastStop(np)
	np.cast.mode = nil
	np.cast:Hide()
	UpdateKick(np)
end

-------------------------------------------------------------------------------
-- Plate construction
-------------------------------------------------------------------------------
-- four thin lines around a box (used for the "kick ready" frame)
local function CreateEdge(parent)
	local e = CreateFrame("Frame", nil, parent)
	e.tex = {}
	for i = 1, 4 do e.tex[i] = e:CreateTexture(nil, "OVERLAY", nil, 7); e.tex[i]:SetTexture(B.white) end
	function e:SetColor(r, g, b, a) for i = 1, 4 do self.tex[i]:SetVertexColor(r, g, b, a or 1) end end
	function e:Place(left, right, w)
		local t = self.tex
		local o = w
		t[1]:ClearAllPoints(); t[1]:SetPoint("BOTTOMLEFT", left, "TOPLEFT", -o - w, o); t[1]:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT", o + w, o); t[1]:SetHeight(w)
		t[2]:ClearAllPoints(); t[2]:SetPoint("TOPLEFT", left, "BOTTOMLEFT", -o - w, -o); t[2]:SetPoint("TOPRIGHT", right, "BOTTOMRIGHT", o + w, -o); t[2]:SetHeight(w)
		t[3]:ClearAllPoints(); t[3]:SetPoint("TOPRIGHT", left, "TOPLEFT", -o, o); t[3]:SetPoint("BOTTOMRIGHT", left, "BOTTOMLEFT", -o, -o); t[3]:SetWidth(w)
		t[4]:ClearAllPoints(); t[4]:SetPoint("TOPLEFT", right, "TOPRIGHT", o, o); t[4]:SetPoint("BOTTOMLEFT", right, "BOTTOMRIGHT", o, -o); t[4]:SetWidth(w)
	end
	e:Hide()
	return e
end

local function CreatePlate(plate)
	-- parented to UIParent (so hiding Blizzard's plate doesn't hide ours),
	-- anchored to the plate so it follows it in the world
	local np = CreateFrame("Frame", nil, UIParent)
	np:SetFrameStrata("BACKGROUND")
	np:SetPoint("CENTER", plate, "CENTER", 0, 0)
	np:SetSize(1, 1)
	np:EnableMouse(false)

	local hb = B:CreateStatusBar(np)
	hb:SetPoint("CENTER", np, "CENTER", 0, 0)
	B:CreateBorder(hb, 0, 0, 0, 1, B:Pixel(hb))
	np.health = hb
	-- target glow (9-slice so the soft edge keeps its size) and arrows
	np.glow = np:CreateTexture(nil, "BACKGROUND", nil, -1)
	np.glow:SetTexture(B.mediaPath .. "Textures\\Glow")
	if np.glow.SetTextureSliceMargins then
		pcall(np.glow.SetTextureSliceMargins, np.glow, 16, 16, 16, 16)
		if Enum and Enum.UITextureSliceMode then pcall(np.glow.SetTextureSliceMode, np.glow, Enum.UITextureSliceMode.Stretched) end
	end
	np.glow:SetBlendMode("ADD")
	np.glow:Hide()
	np.arrowL = np:CreateTexture(nil, "OVERLAY")
	np.arrowL:SetTexture(B.mediaPath .. "Textures\\Arrow")
	np.arrowL:Hide()
	np.arrowR = np:CreateTexture(nil, "OVERLAY")
	np.arrowR:SetTexture(B.mediaPath .. "Textures\\Arrow")
	np.arrowR:SetTexCoord(1, 0, 0, 1)
	np.arrowR:Hide()
	-- aggro edge: a thick coloured frame just outside the black border
	local th = CreateFrame("Frame", nil, hb)
	th:SetFrameLevel(hb:GetFrameLevel() + 1)
	th.tex = {}
	for i = 1, 4 do th.tex[i] = th:CreateTexture(nil, "OVERLAY"); th.tex[i]:SetTexture(B.white) end
	function th:SetColor(r, g, b, a) for i = 1, 4 do self.tex[i]:SetVertexColor(r, g, b, a or 1) end end
	th:Hide()
	np.threat = th
	-- absorb shield: clipped to the health bar, starts where the health ends
	np.absorb = B:CreateAbsorb(hb)
	-- text above the shield
	local textLayer = CreateFrame("Frame", nil, hb)
	textLayer:SetAllPoints(hb)
	textLayer:SetFrameLevel(hb:GetFrameLevel() + 3)
	np.hpText = textLayer:CreateFontString(nil, "OVERLAY")
	np.hpText:SetPoint("CENTER", hb, "CENTER", 0, 0)
	np.name = np:CreateFontString(nil, "OVERLAY")
	np.name:SetPoint("TOP", hb, "BOTTOM", 0, -3)
	np.name:SetWordWrap(false)
	np.level = np:CreateFontString(nil, "OVERLAY")
	np.level:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 2)
	np.raid = np:CreateTexture(nil, "OVERLAY")
	np.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	np.raid:SetSize(20, 20)
	np.raid:SetPoint("RIGHT", hb, "LEFT", -4, 0)
	np.raid:Hide()
	np.auras = {}

	local cb = B:CreateStatusBar(np)
	cb:SetPoint("TOP", np.name, "BOTTOM", 0, -3)
	B:CreateBorder(cb, 0, 0, 0, 1, B:Pixel(cb))
	cb.icon = cb:CreateTexture(nil, "OVERLAY")
	B:SkinIcon(cb.icon, cb)
	cb.icon:SetPoint("RIGHT", cb, "LEFT", -2, 0)
	cb.text = cb:CreateFontString(nil, "OVERLAY")
	cb.text:SetPoint("CENTER")
	cb.text:SetWordWrap(false)
	-- interrupt indicator
	local k = CreateFrame("Frame", nil, cb)
	k:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	k.icon = k:CreateTexture(nil, "ARTWORK")
	k.icon:SetAllPoints()
	k.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	B:CreateBorder(k, 0, 0, 0, 1, B:Pixel(k))
	k.bar = CreateFrame("StatusBar", nil, k)   -- dark cover that shrinks as the cooldown runs out
	k.bar:SetAllPoints()
	k.bar:SetOrientation("VERTICAL")
	k.bar:SetStatusBarTexture(B.white)
	k.bar:SetStatusBarColor(0, 0, 0, 0.6)
	k.bar:Hide()
	k.text = k.bar:CreateFontString(nil, "OVERLAY")
	k.text:SetPoint("CENTER", k, "CENTER", 0, 0)
	k:Hide()
	cb.kick = k
	k.edge = CreateEdge(k)
	cb.edge = CreateEdge(cb)
	-- invisible bar that the "kick is back here" line rides on
	cb.probe = CreateFrame("StatusBar", nil, cb)
	cb.probe:SetAllPoints(cb)
	cb.probe:SetStatusBarTexture(B.white)
	cb.probe:SetStatusBarColor(0, 0, 0, 0)
	cb.tickHolder = CreateFrame("Frame", nil, cb)
	cb.tickHolder:SetAllPoints(cb)
	cb.tickHolder:SetFrameLevel(cb:GetFrameLevel() + 4)
	cb.tickHolder:Hide()
	cb.tick = cb.tickHolder:CreateTexture(nil, "OVERLAY", nil, 7)
	cb.tick:SetTexture(B.white)
	cb.tick:Hide()
	cb:Hide()
	cb:SetScript("OnUpdate", B.Safe(function(self)
		if self.mode ~= "lua" then return end
		local now = GetTime()
		local v = self.channeling and (self.endTime - now) or (now - self.startTime)
		self:SetValue(math.max(0, math.min(self.total, v)))
		if now > self.endTime + 0.1 then self:Hide() end
	end))
	np.cast = cb

	plate.bPlate = np
	return np
end

local function Layout(np)
	local d = db()
	np.health:SetSize(d.width, d.height)
	-- centre bar + name (+ castbar) on the Blizzard plate so stacking spacing fits
	local nameH = d.nameSize + 3
	local below = (d.nameAbove and 0 or nameH) + (d.castbar and (d.castHeight + 3) or 0)
	local above = d.nameAbove and nameH or 0
	np.health:ClearAllPoints()
	np.health:SetPoint("CENTER", np, "CENTER", 0, (below - above) / 2)
	np.name:ClearAllPoints()
	if d.nameAbove then
		np.name:SetPoint("BOTTOM", np.health, "TOP", 0, 3)
	else
		np.name:SetPoint("TOP", np.health, "BOTTOM", 0, -3)
	end
	np.level:ClearAllPoints()
	if d.nameAbove then
		np.level:SetPoint("LEFT", np.health, "RIGHT", 3, 0)
	else
		np.level:SetPoint("BOTTOMRIGHT", np.health, "TOPRIGHT", 0, 2)
	end
	-- aggro edge, 2px, outside the 1px black border
	local px = B:Pixel(np.health)
	local th, o, w = np.threat, px * 3, px * 2
	th:ClearAllPoints(); th:SetAllPoints(np.health)
	local t = th.tex
	t[1]:ClearAllPoints(); t[1]:SetPoint("BOTTOMLEFT", np.health, "TOPLEFT", -o - w, o); t[1]:SetPoint("BOTTOMRIGHT", np.health, "TOPRIGHT", o + w, o); t[1]:SetHeight(w)
	t[2]:ClearAllPoints(); t[2]:SetPoint("TOPLEFT", np.health, "BOTTOMLEFT", -o - w, -o); t[2]:SetPoint("TOPRIGHT", np.health, "BOTTOMRIGHT", o + w, -o); t[2]:SetHeight(w)
	t[3]:ClearAllPoints(); t[3]:SetPoint("TOPRIGHT", np.health, "TOPLEFT", -o, o); t[3]:SetPoint("BOTTOMRIGHT", np.health, "BOTTOMLEFT", -o, -o); t[3]:SetWidth(w)
	t[4]:ClearAllPoints(); t[4]:SetPoint("TOPLEFT", np.health, "TOPRIGHT", o, o); t[4]:SetPoint("BOTTOMLEFT", np.health, "BOTTOMRIGHT", o, -o); t[4]:SetWidth(w)
	np.health:SetStatusBarTexture(B:GetTexture())
	np.health.bg:SetTexture(B:GetTexture())
	B:SetFont(np.hpText, d.fontSize)
	B:SetFont(np.name, d.nameSize)
	-- target decorations
	np.glow:ClearAllPoints()
	np.glow:SetPoint("TOPLEFT", np.health, "TOPLEFT", -10, 10)
	np.glow:SetPoint("BOTTOMRIGHT", np.health, "BOTTOMRIGHT", 10, -10)
	local ah = d.height + 6
	np.arrowL:SetSize(ah * 0.8, ah)
	np.arrowL:ClearAllPoints()
	np.arrowL:SetPoint("RIGHT", np.health, "LEFT", -4, 0)
	np.arrowR:SetSize(ah * 0.8, ah)
	np.arrowR:ClearAllPoints()
	np.arrowR:SetPoint("LEFT", np.health, "RIGHT", d.showLevel and d.nameAbove and 22 or 4, 0)
	np.name:SetWidth(d.width + 40)
	B:SetFont(np.level, d.fontSize)
	-- with the kick icon on the right the bar is centred between the two icons
	local withKick = d.kickIndicator and kick
	local ks = d.kickSize or 18
	local left, right = d.castHeight + 2, withKick and (ks + 2) or 0
	np.cast:SetSize(d.width - left - right, d.castHeight)
	np.cast:ClearAllPoints()
	np.cast:SetPoint("TOP", d.nameAbove and np.health or np.name, "BOTTOM", (left - right) / 2, d.nameAbove and -4 or -3)
	local cb = np.cast
	cb.kick:SetSize(ks, ks)
	B:SetFont(cb.kick.text, math.max(8, math.floor(ks * 0.55)))
	cb.edge:Place(cb.icon, cb, px)
	cb.kick.edge:Place(cb.kick, cb.kick, px)
	cb.tick:SetWidth(math.max(px * 3, 2))
	np.absorb:SetWidth(d.width)

	np.cast:SetStatusBarTexture(B:GetTexture())
	np.cast.icon:SetSize(d.castHeight, d.castHeight)
	B:SetFont(np.cast.text, math.max(7, d.castHeight - 1))
	np.cast.text:SetWidth(d.width - 10)
end

-- Hide Blizzard's whole plate (its insides may be locked in Midnight, so we
-- fade the plate itself; clicks still work on an invisible plate). Blizzard
-- also changes plate alpha for range / target, so keep forcing it to 0.
local function SetHidden(f)
	f.bLock = true
	f:SetAlpha(0)
	f.bLock = false
end

local function HideBlizzard(plate)
	if not plate.bHooked then
		plate.bHooked = true
		hooksecurefunc(plate, "SetAlpha", function(self)
			if self.bLock or not self.bHide or not db().enabled then return end
			SetHidden(self)
		end)
	end
	plate.bHide = true
	SetHidden(plate)
	-- move Blizzard's plate content into a hidden container: invisible no
	-- matter what opacity the engine applies
	local uf = plate.UnitFrame
	if uf and not (uf.IsForbidden and uf:IsForbidden()) and uf:GetParent() ~= B.hiddenParent then
		uf.bOrigParent = uf.bOrigParent or uf:GetParent()
		if pcall(uf.SetParent, uf, B.hiddenParent) then M.reparented = (M.reparented or 0) + 1 end
	end
end

local function ShowBlizzard(plate)
	plate.bHide = nil
	local uf = plate.UnitFrame
	if uf and uf.bOrigParent and not (uf.IsForbidden and uf:IsForbidden()) then
		pcall(uf.SetParent, uf, uf.bOrigParent)
	end
	plate.bLock = true
	plate:SetAlpha(1)
	plate.bLock = false
end

local function OnAdded(unit)
	if not db().enabled then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local np = plate.bPlate or CreatePlate(plate)
	np.unit = unit
	np.plate = plate
	active[unit] = np
	-- core plate first, every step on its own: one failing part must never
	-- leave the unit without a plate
	B:Try(Layout, np)
	B:Try(UpdateHealth, np)
	B:Try(UpdateName, np)
	B:Try(UpdateTarget, np)
	B:Try(UpdateRaidIcon, np)
	B:Try(function()
		if B.HasValue((UnitChannelInfo(unit))) then CastStart(np, true)
		elseif B.HasValue((UnitCastingInfo(unit))) then CastStart(np, false)
		else CastStop(np) end
	end)
	np:Show()
	HideBlizzard(plate)
	-- auras last (Blizzard AuraContainers, 12.1+)
	B:Try(function()
		CreateBoxes(np)
		LayoutBoxes(np)
		B:SetAuraBoxUnit(np.debuffBox or nil, unit)
		B:SetAuraBoxUnit(np.buffBox or nil, unit)
	end)
	B:Try(UpdateAuras, np)
	-- once more after Blizzard's own handler for this event has run
	C_Timer.After(0, function()
		if active[unit] == np then HideBlizzard(plate) end
	end)
end


local function OnRemoved(unit)
	local np = active[unit]
	active[unit] = nil
	if np then
		np:Hide()
		np.unit = nil
		B:SetAuraBoxUnit(np.debuffBox or nil, nil)
		B:SetAuraBoxUnit(np.buffBox or nil, nil)
		if np.plate then ShowBlizzard(np.plate) end
	end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local castStart = { UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_DELAYED = false, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_EMPOWER_START = true, UNIT_SPELLCAST_EMPOWER_UPDATE = true }
local castStop = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
	UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }

local function OnEvent(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then return OnAdded(unit) end
	if event == "NAME_PLATE_UNIT_REMOVED" then return OnRemoved(unit) end
	if event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
		for _, np in pairs(active) do UpdateTarget(np) end
		return
	end
	if event == "QUEST_LOG_UPDATE" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		for _, np in pairs(active) do B:Try(UpdateHealth, np) end
		return
	end
	if event == "SPELL_UPDATE_COOLDOWN" then
		RefreshKick()
		for _, np in pairs(active) do if np.cast:IsShown() then B:Try(UpdateKick, np) end end
		return
	end
	if event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "UNIT_PET" then
		M:FindKick()
		RefreshKick()
		for _, np in pairs(active) do B:Try(Layout, np); B:Try(UpdateKick, np) end
		return
	end
	if event == "RAID_TARGET_UPDATE" then
		for _, np in pairs(active) do UpdateRaidIcon(np) end
		return
	end
	local np = type(unit) == "string" and active[unit]
	if not np then return end
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(np)
	elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then UpdateAbsorb(np)
	elseif event == "UNIT_AURA" then UpdateAuras(np)
	elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then UpdateName(np)
	elseif event == "UNIT_FACTION" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_POWER_UPDATE"
		or event == "UNIT_CLASSIFICATION_CHANGED" then UpdateHealth(np)
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" then UpdateThreat(np)
	elseif castStart[event] ~= nil then CastStart(np, castStart[event])
	elseif castStop[event] then CastStop(np)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then CastColor(np.cast, false); np.cast.notInt = false; np.cast.kick.state = nil; UpdateKick(np)
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then CastColor(np.cast, true); np.cast.notInt = true; np.cast.kick.state = nil; UpdateKick(np)
	end
end

local EVENTS = {
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "RAID_TARGET_UPDATE",
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_THREAT_LIST_UPDATE",
	"UNIT_THREAT_SITUATION_UPDATE", "UNIT_CLASSIFICATION_CHANGED", "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED",
	"PLAYER_SPECIALIZATION_CHANGED",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_ABSORB_AMOUNT_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "UNIT_PET",
}

function M:OnEnable()
	if not db().enabled then
		B:RunOOC("np_restore", function() M:HideBlizzardPlates(false) end)
		return
	end
	self:ApplyCVars()
	self:FindKick()
	RefreshKick()
	local f = CreateFrame("Frame")
	for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
	f:SetScript("OnEvent", B.Safe(OnEvent))
	self.eventFrame = f
	f.elapsed = 0
	f:SetScript("OnUpdate", function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		if kick then RefreshKick() end
		for _, np in pairs(active) do
			local plate = np.plate
			if plate and plate.bHide and plate:GetAlpha() ~= 0 then SetHidden(plate) end
			if kick and np.cast:IsShown() then B:Try(UpdateKick, np) end
		end
	end)
	-- plates that already exist (e.g. after /reload)
	for _, plate in ipairs(C_NamePlate.GetNamePlates(false) or {}) do
		local uf = plate.UnitFrame
		local unit = uf and (uf.unit or uf.displayedUnit)
		if unit and not issecret(unit) then B:Try(OnAdded, unit) end
	end
end

-- sample plate for the menu preview
local sample
function M:Preview(on)
	if on and db().enabled then
		if not sample then
			local holder = CreateFrame("Frame", nil, UIParent)
			holder:SetSize(1, 1)
			holder:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
			sample = CreatePlate(holder)
			sample.label = sample:CreateFontString(nil, "OVERLAY")
			sample.label:SetPoint("BOTTOM", sample.health, "TOP", 0, 26)
		end
		sample.unit = UnitExists("target") and "target" or "player"
		sample:SetFrameStrata("DIALOG")
		B:SetFont(sample.label, 11)
		sample.label:SetText(B:TitleText() .. " nameplate preview")
		Layout(sample)
		CreateBoxes(sample)
		LayoutBoxes(sample)
		B:SetAuraBoxUnit(sample.debuffBox or nil, sample.unit)
		B:SetAuraBoxUnit(sample.buffBox or nil, sample.unit)
		UpdateHealth(sample)
		UpdateName(sample)
		UpdateAuras(sample)
		-- shown as your target so the highlight can be tuned
		sample.forceTarget = true
		UpdateTarget(sample)
		sample:SetScale(1)
		sample.cast:Hide()
		sample:Show()
	elseif sample then
		sample:Hide()
	end
end
B:RegisterCallback("PREVIEW", function(on) B:Try(M.Preview, M, on) end)

-------------------------------------------------------------------------------
-- /bui npdebug: what does this client's nameplate look like?
-------------------------------------------------------------------------------
local function Info(f)
	if type(f) ~= "table" or not f.GetObjectType then return tostring(f) end
	local parts = {}
	local function add(label, fn)
		local ok, v = pcall(fn)
		parts[#parts + 1] = label .. "=" .. (ok and tostring(v) or "err")
	end
	add("type", function() return f:GetObjectType() end)
	add("name", function() return f:GetName() end)
	add("forbidden", function() return f.IsForbidden and f:IsForbidden() end)
	add("shown", function() return f:IsShown() end)
	add("alpha", function() return f:GetAlpha() end)
	add("parent", function() local p = f:GetParent(); return p and (p:GetName() or p:GetObjectType()) end)
	return table.concat(parts, "  ")
end

function M:DebugText()
	local out = {}
	local function line(...) out[#out + 1] = table.concat({ ... }, " ") end
	local v, build, _, iface = GetBuildInfo()
	line("client", tostring(v), tostring(build), tostring(iface))
	line("BitsjUI plates enabled:", tostring(db().enabled), " active:", tostring(next(active) ~= nil), " reparented:", tostring(M.reparented or 0))
	local unit = UnitExists("target") and "target" or nil
	if not unit then
		for u in pairs(active) do unit = u; break end
	end
	line("unit:", tostring(unit))
	if unit then
		local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
		local plateAny = C_NamePlate.GetNamePlateForUnit(unit, true)
		line("plate (normal):", Info(plate))
		line("plate (incl. forbidden):", Info(plateAny))
		local p = plate or plateAny
		if p then
			line("plate.UnitFrame:", Info(p.UnitFrame))
			local ok, kids = pcall(function() return { p:GetChildren() } end)
			if ok then for i, c in ipairs(kids) do line("  plate child " .. i .. ":", Info(c)) end end
			local uf = p.UnitFrame
			if type(uf) == "table" and not (uf.IsForbidden and uf:IsForbidden()) then
				for k, val in pairs(uf) do
					if type(val) == "table" and val.GetObjectType and type(k) == "string" then
						line("  UnitFrame." .. k .. ":", Info(val))
					end
				end
			end
		end
	end
	line("")
	line("nameplate console variables:")
	local ok, list = pcall(C_Console.GetAllCommands)
	if ok and type(list) == "table" then
		local names = {}
		for _, c in ipairs(list) do
			local n = type(c) == "table" and c.command
			if type(n) == "string" and n:lower():find("nameplate") then names[#names + 1] = n end
		end
		table.sort(names)
		for _, n in ipairs(names) do line("  " .. n .. " = " .. tostring(C_CVar.GetCVar(n))) end
	end
	return table.concat(out, "\n")
end

function M:ShowDebug()
	local W = B.Widgets
	if not self.debugFrame then
		local f = CreateFrame("Frame", "BitsjUINameplateDebug", UIParent)
		f:SetSize(760, 520)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		W.Fill(f, W.colors.bg)
		B:CreateBorder(f, 0, 0, 0, 1)
		local title = f:CreateFontString(nil, "OVERLAY")
		W.Font(title, 14)
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("BitsjUI nameplate debug  -  Ctrl+A, Ctrl+C and send it")
		f.box = W.EditBox(f, 440)
		f.box:SetPoint("TOPLEFT", 12, -36)
		f.box:SetPoint("TOPRIGHT", -12, -36)
		local close = W.Button(f, "Close", 100, 24, function() f:Hide() end)
		close:SetPoint("BOTTOMRIGHT", -12, 10)
		local refresh = W.Button(f, "Refresh", 100, 24, function() f.box.edit:SetText(M:DebugText()) end)
		refresh:SetPoint("RIGHT", close, "LEFT", -8, 0)
		tinsert(UISpecialFrames, "BitsjUINameplateDebug")
		self.debugFrame = f
	end
	local ok, text = pcall(self.DebugText, self)
	self.debugFrame.box.edit:SetText(ok and text or ("debug failed: " .. tostring(text)))
	self.debugFrame:Show()
end

function M:Update()
	if B.previewing then B:Try(self.Preview, self, true) end
	if not db().enabled then return end
	self:ApplyCVars()
	for unit in pairs(active) do B:Try(OnAdded, unit) end
end
