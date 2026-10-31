--[[
	BitsjUI - Swing timer (Classic clients)
	Thin bars right above the player castbar showing when your next white
	hit lands: main hand, off hand (when dual wielding) and ranged (Auto
	Shot, wands, thrown). Each bar only appears while it is running or while
	you are auto-attacking, and they stack upwards in that order.

	How the timing is found:
	  - melee: your own swings in the combat log (hits and misses, main or
	    off hand), plus "next melee" abilities (Heroic Strike, Cleave, Maul,
	    Raptor Strike) which replace a swing
	  - parrying an attack speeds up your current swing, like the game does
	  - ranged: UNIT_SPELLCAST_SUCCEEDED for Auto Shot / Shoot / Throw
	  - haste changes (UNIT_ATTACKSPEED) stretch the bar that is running
	Retail no longer gives addons the combat log, so this is Classic only.
]]
local _, B = ...
local M = B:NewModule("Swing")

local function db() return B.db.swing end

local frame          -- holder above the castbar
local bars = {}      -- mh, oh, ranged
M.bars = bars
local ORDER = { "mh", "oh", "ranged" }
local LABEL = { mh = "Main hand", oh = "Off hand", ranged = "Ranged" }
local playerGUID
local attacking, autoRepeat = false, false

-- spells that fire the ranged timer (Auto Shot, wand Shoot, bow/gun/crossbow Shoot, Throw)
local RANGED_IDS = { [75] = true, [5019] = true, [3018] = true, [2764] = true, [7918] = true, [7919] = true, [2480] = true }
-- "next melee" abilities that replace a main hand swing
local NEXT_MELEE_IDS = { 78, 845, 6807, 2973 }   -- Heroic Strike, Cleave, Maul, Raptor Strike
local nextMeleeNames

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok and n then return n end
	end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function NextMeleeNames()
	if nextMeleeNames then return nextMeleeNames end
	nextMeleeNames = {}
	for _, id in ipairs(NEXT_MELEE_IDS) do
		local n = SpellName(id)
		if n then nextMeleeNames[n] = true end
	end
	return nextMeleeNames
end

-------------------------------------------------------------------------------
-- Bars
-------------------------------------------------------------------------------
local function ColorFor(key)
	local d = db()
	local c = (key == "mh" and d.meleeColor) or (key == "oh" and d.offColor) or d.rangedColor
	return c.r, c.g, c.b
end

local function CreateBar(key)
	local sb = B:CreateStatusBar(frame)
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(0)
	B:CreateBorder(sb, 0, 0, 0, 1, B:Pixel(sb))
	sb.label = B:CreateText(sb, db().fontSize, "LEFT")
	sb.label:SetPoint("LEFT", sb, "LEFT", 4, 0)
	sb.time = B:CreateText(sb, db().fontSize, "RIGHT")
	sb.time:SetPoint("RIGHT", sb, "RIGHT", -4, 0)
	sb.spark = sb:CreateTexture(nil, "OVERLAY")
	sb.spark:SetColorTexture(1, 1, 1, 0.9)
	sb.spark:SetWidth(2)
	-- rides on the fill's edge, so it needs no repositioning while the bar moves
	sb.spark:SetPoint("TOP", sb:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
	sb.spark:SetPoint("BOTTOM", sb:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	sb.key = key
	sb:Hide()
	bars[key] = sb
	return sb
end

-- show the bars that are in use, stacked upwards from the castbar
function M:Stack()
	local d = db()
	local y = 0
	for _, key in ipairs(ORDER) do
		local sb = bars[key]
		if sb and sb:IsShown() then
			sb:ClearAllPoints()
			sb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, y)
			sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, y)
			y = y + d.height + d.spacing
		end
	end
end

local function Wanted(key)
	local d = db()
	if not d.enabled then return false end
	if key == "ranged" then return d.ranged end
	if not M.hasLog then return false end   -- melee swings are only visible in the combat log
	if key == "oh" then return d.melee and d.offhand end
	return d.melee
end

local function SetActive(sb, on)
	if sb:IsShown() ~= on then
		sb:SetShown(on)
		M:Stack()
	end
end

-- start (or restart) a timer
local function Start(key, duration)
	local sb = bars[key]
	if not sb or not Wanted(key) or not duration or duration <= 0 then return end
	sb.start, sb.duration = GetTime(), duration
	sb.idleSince = nil
	SetActive(sb, true)
end

local function Speeds()
	local mh, oh = UnitAttackSpeed("player")
	local ranged = UnitRangedDamage and UnitRangedDamage("player")
	return mh, oh, ranged
end

-------------------------------------------------------------------------------
-- Ticking
-------------------------------------------------------------------------------
local function Tick()
	local now = GetTime()
	local d = db()
	for _, key in ipairs(ORDER) do
		local sb = bars[key]
		if sb and sb:IsShown() and not sb.sample then
			local left = 0
			if sb.start then left = math.max(0, sb.start + sb.duration - now) end
			local frac = (sb.duration and sb.duration > 0) and (1 - left / sb.duration) or 1
			sb:SetValue(frac)
			sb.spark:SetShown(left > 0)
			-- the number only needs a tenth of a second; the bar moves every frame
			local txt = (d.showText and left > 0) and string.format("%.1f", left) or ""
			if txt ~= sb.lastText then sb.lastText = txt; sb.time:SetText(txt) end
			-- swing done: keep a full bar while still attacking, fade out otherwise
			if left <= 0 then
				local still = (key == "ranged" and autoRepeat) or (key ~= "ranged" and attacking)
				if still then
					sb.idleSince = nil
				else
					sb.idleSince = sb.idleSince or now
					if now - sb.idleSince > 0.6 then
						sb.start = nil
						SetActive(sb, false)
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local function OnLog()
	local _, sub, _, sGUID, _, _, _, dGUID, _, _, _, a12, a13, _, _, _, _, _, _, _, a21 = CombatLogGetCurrentEventInfo()
	local mh, oh = Speeds()
	if sGUID == playerGUID then
		if sub == "SWING_DAMAGE" then
			if a21 then Start("oh", oh) else Start("mh", mh) end
		elseif sub == "SWING_MISSED" then
			if a13 then Start("oh", oh) else Start("mh", mh) end
		elseif (sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED") and a13 and NextMeleeNames()[a13] then
			Start("mh", mh)
		end
	elseif dGUID == playerGUID and sub == "SWING_MISSED" and a12 == "PARRY" then
		-- parry haste: 40 % of the swing off what is left, never below 20 % remaining
		local sb = bars.mh
		if sb and sb.start and sb.duration then
			local left = sb.start + sb.duration - GetTime()
			local minLeft = sb.duration * 0.2
			if left > minLeft then
				local newLeft = math.max(minLeft, left - sb.duration * 0.4)
				sb.start = sb.start - (left - newLeft)
			end
		end
	end
end

-- keep the same progress when attack speed changes mid swing
local function Rescale()
	local mh, oh, ranged = Speeds()
	local now = GetTime()
	for key, speed in pairs({ mh = mh, oh = oh, ranged = ranged }) do
		local sb = bars[key]
		if sb and sb.start and sb.duration and speed and speed > 0 and math.abs(speed - sb.duration) > 0.01 then
			local frac = math.min(1, (now - sb.start) / sb.duration)
			sb.duration = speed
			sb.start = now - frac * speed
		end
	end
end

local function OnEvent(_, event, unit, _, spellID)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnLog()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" and not B.IsSecret(spellID) and RANGED_IDS[spellID] then
			local _, _, ranged = Speeds()
			Start("ranged", ranged)
		end
	elseif event == "UNIT_ATTACKSPEED" or event == "UNIT_RANGEDDAMAGE" then
		Rescale()
	elseif event == "PLAYER_ENTER_COMBAT" then
		attacking = true
		local sb = bars.mh
		if sb and not sb.start and Wanted("mh") then sb.start, sb.duration = nil, Speeds(); SetActive(sb, true) end
	elseif event == "PLAYER_LEAVE_COMBAT" then
		attacking = false
	elseif event == "START_AUTOREPEAT_SPELL" then
		autoRepeat = true
		local sb = bars.ranged
		if sb and not sb.start and Wanted("ranged") then sb.duration = select(3, Speeds()); SetActive(sb, true) end
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		autoRepeat = false
	elseif event == "PLAYER_ENTERING_WORLD" then
		playerGUID = UnitGUID("player")
	end
end

-------------------------------------------------------------------------------
-- Layout: right above the player castbar, same width
-------------------------------------------------------------------------------
local function Castbar()
	if not db().attachToCastbar then return end
	local CB = B:GetModule("Castbars")
	local bar = CB and CB.bars and CB.bars.player
	if bar and B.db.castbars.enabled and B.db.castbars.player.enabled then return bar end
end

function M:Attach()
	if not frame then return end
	local cb = Castbar()
	B:SetMoverEnabled("swing", db().enabled and not cb)
	if not cb then
		if M.attached then M.attached = false; B.Movers:Apply("swing") end
		return
	end
	M.attached = true
	local gap = B:Pixel(frame) * 2 + db().gap   -- clear of both 1px borders
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", cb, "TOPLEFT", 0, gap)
	frame:SetPoint("BOTTOMRIGHT", cb, "TOPRIGHT", 0, gap)
end

function M:Layout()
	if not frame then return end
	local d = db()
	local cb = Castbar()
	frame:SetSize(cb and B.db.castbars.player.width or d.width, d.height * 3 + d.spacing * 2)
	for _, key in ipairs(ORDER) do
		local sb = bars[key]
		sb:SetHeight(d.height)
		sb:SetStatusBarTexture(B:GetTexture())
		sb.spark:ClearAllPoints()
		sb.spark:SetPoint("TOP", sb:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		sb.spark:SetPoint("BOTTOM", sb:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
		local r, g, b = ColorFor(key)
		sb:SetStatusBarColor(r, g, b)
		sb.bg:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, 0.9)
		B:SetFont(sb.label, d.fontSize)
		B:SetFont(sb.time, d.fontSize)
		sb.label:SetText(d.showText and LABEL[key] or "")
		if not Wanted(key) then sb.start = nil; sb:Hide() end
	end
	self:Attach()
	self:Preview()
	self:Stack()
end

-- sample bars while moving frames or with the menu open
function M:Preview()
	local on = (B.Movers.unlocked or B.previewing) and db().enabled
	local samples = { mh = 0.65, oh = 0.3, ranged = 0.85 }
	for _, key in ipairs(ORDER) do
		local sb = bars[key]
		if on and Wanted(key) and not sb.start then
			sb.sample = true
			sb:SetValue(samples[key])
			sb.spark:Hide()
			sb.time:SetText(db().showText and "1.2" or "")
			sb:Show()
		elseif sb.sample then
			sb.sample = nil
			if not sb.start then sb:Hide() end
		end
	end
	self:Stack()
end

function M:OnEnable()
	if not db().enabled then return end
	-- needs classic game rules; melee also needs the combat log, which the
	-- modern engine (retail, Forever) hides from addons -> ranged only there
	if not B.classicContent then return end
	M.hasLog = CombatLogGetCurrentEventInfo ~= nil
	frame = CreateFrame("Frame", "BitsjUISwing", UIParent)
	frame:SetSize(db().width, db().height)
	for _, key in ipairs(ORDER) do CreateBar(key) end
	B:RegisterMover(frame, "swing", "Swing timer", { "BOTTOM", "BOTTOM", 0, 190 })
	playerGUID = UnitGUID("player")

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ M.hasLog and "COMBAT_LOG_EVENT_UNFILTERED" or "PLAYER_ENTERING_WORLD", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
		"START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTERING_WORLD" }) do
		pcall(ev.RegisterEvent, ev, e)
	end
	for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_ATTACKSPEED", "UNIT_RANGEDDAMAGE" }) do
		pcall(ev.RegisterUnitEvent, ev, e, "player")
	end
	ev:SetScript("OnEvent", B.Safe(OnEvent))
	-- every frame: a swing bar has to move smoothly to be readable
	frame:SetScript("OnUpdate", function()
		local ok, err = pcall(Tick)
		if not ok then frame:SetScript("OnUpdate", nil); B:Error(err) end   -- never spam an error every frame
	end)

	-- follow the castbar when it moves or changes size
	local CB = B:GetModule("Castbars")
	if CB and CB.LayoutBar then
		hooksecurefunc(CB, "LayoutBar", function(_, key) if key == "player" then M:Layout() end end)
	end
	hooksecurefunc(B.Movers, "Apply", function(_, name) if name == "swing" or name == "cb_player" then M:Attach() end end)
	hooksecurefunc(B.Movers, "ApplyAll", function() M:Attach() end)
	B:RegisterCallback("MOVERS_TOGGLED", function() M:Preview() end)
	B:RegisterCallback("PREVIEW", function() M:Preview() end)
	self:Layout()
end

function M:Update()
	if frame then self:Layout() end
end
