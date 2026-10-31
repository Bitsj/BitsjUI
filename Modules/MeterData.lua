--[[
	BitsjUI - Meter data from the combat log (Classic clients)
	Classic has no Blizzard damage meter, but its combat log is open to
	addons. This file reads it and answers the same questions the meter
	windows ask C_DamageMeter on retail (same function names, same table
	shapes), so DamageMeter.lua works unchanged on both.

	Tracked per fight and for "Overall": damage, healing (without overheal),
	absorbs, interrupts, dispels, damage taken, deaths and damage dealt to
	each enemy. Pets, totems and guardians count for their owner.
	A fight starts with the first hit while anyone in the group is in combat
	and ends when the whole group is out of combat; it is named after the
	enemy that took the most damage.
]]
local _, B = ...

local D = {}
B.MeterData = D

local MAX_FIGHTS = 30
local band = bit.band
local GROUP_MASK = 0x00000007          -- COMBATLOG_OBJECT_AFFILIATION_MINE / PARTY / RAID
local MINE = 0x00000001
local TYPE_PLAYER = 0x00000400
local TYPE_PET_OR_GUARDIAN = 0x00003000
local MELEE = 6603                      -- "Auto Attack"

local fights = {}        -- finished fights, oldest first
local current            -- fight in progress
local overall
local nextID = 1
local petOwner = {}      -- pet / totem GUID -> owner GUID
local lastHit = {}       -- player GUID -> { spell, name, amount } (for deaths)

-- spell names/icons for spells the log only gives by name (Classic Era logs
-- often carry spell ID 0); they get a stable negative key
D.names, D.icons = { [MELEE] = MELEE_ATTACK or "Melee" }, {}
local nameKeys, nextKey = {}, -1
local function SpellKey(id, name, school)
	if id and id > 0 then
		if name and not D.names[id] then D.names[id] = name end
		return id
	end
	if not name then return MELEE end
	local k = nameKeys[name]
	if not k then
		k = nextKey
		nextKey = nextKey - 1
		nameKeys[name] = k
		D.names[k] = name
		local tex
		if C_Spell and C_Spell.GetSpellTexture then tex = select(2, pcall(C_Spell.GetSpellTexture, name)) end
		if type(tex) ~= "number" and type(tex) ~= "string" and GetSpellTexture then tex = select(2, pcall(GetSpellTexture, name)) end
		D.icons[k] = (type(tex) == "number" or type(tex) == "string") and tex or 136243
	end
	return k
end

-------------------------------------------------------------------------------
-- Fight tables
-------------------------------------------------------------------------------
local TYPES = { 0, 2, 4, 5, 6, 7, 9, 10 }   -- stored kinds (1/3 are the per-second views of 0/2)

local function NewFight(name)
	local f = { id = nextID, name = name, start = GetTime(), kinds = {}, enemyDamage = {} }
	nextID = nextID + 1
	for _, k in ipairs(TYPES) do f.kinds[k] = {} end
	return f
end

local function Duration(f)
	if not f then return 0 end
	if f.stop then return math.max(1, f.stop - f.start) end
	if f.start then return math.max(1, GetTime() - f.start) end
	return math.max(1, f.time or 1)
end

local function PlayerInfo(guid, fallbackName)
	local class, name
	if GetPlayerInfoByGUID then
		local ok, _, c, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
		if ok then class, name = c, n end
	end
	return class, name or fallbackName
end

local function Source(fight, kind, guid, name, isPlayer)
	local list = fight.kinds[kind]
	local s = list[guid]
	if not s then
		local class, n = nil, name
		if isPlayer then class, n = PlayerInfo(guid, name) end
		s = { guid = guid, name = n or "?", class = class, total = 0, spells = {}, isPlayer = isPlayer }
		list[guid] = s
	end
	return s
end

local function Add(kind, guid, name, isPlayer, spell, amount, target)
	if not amount or amount <= 0 then return end
	for _, f in ipairs({ current, overall }) do
		if f then
			local s = Source(f, kind, guid, name, isPlayer)
			s.total = s.total + amount
			local sp = s.spells[spell]
			if not sp then
				sp = { amount = 0 }
				s.spells[spell] = sp
			end
			sp.amount = sp.amount + amount
			if target then sp.target = target end
		end
	end
end

-------------------------------------------------------------------------------
-- Who is who
-------------------------------------------------------------------------------
local function InGroup(flags) return flags and band(flags, GROUP_MASK) ~= 0 end
local function IsPlayerFlag(flags) return flags and band(flags, TYPE_PLAYER) ~= 0 end

-- the group member a hit belongs to (pets fold into their owner)
local function Owner(guid, name, flags)
	if not InGroup(flags) then return end
	if IsPlayerFlag(flags) then return guid, name, false end
	local owner = petOwner[guid]
	if not owner and band(flags, MINE) ~= 0 and band(flags, TYPE_PET_OR_GUARDIAN) ~= 0 then
		owner = UnitGUID("player")
	end
	if owner then
		local _, oname = PlayerInfo(owner)
		return owner, oname, true
	end
end

local function ScanPets()
	local function map(unit, pet)
		local o, p = UnitGUID(unit), UnitGUID(pet)
		if o and p then petOwner[p] = o end
	end
	map("player", "pet")
	for i = 1, 4 do map("party" .. i, "partypet" .. i) end
	for i = 1, 40 do map("raid" .. i, "raidpet" .. i) end
end

local function GroupInCombat()
	if UnitAffectingCombat("player") then return true end
	local prefix, n = "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
	if IsInRaid() then prefix, n = "raid", GetNumGroupMembers() end
	for i = 1, n do
		local u = prefix .. i
		if UnitAffectingCombat(u) and not UnitIsDeadOrGhost(u) then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Fight start / end
-------------------------------------------------------------------------------
local function StartFight()
	if current then return end
	current = NewFight()
	overall = overall or NewFight("Overall")
	overall.start = overall.start or GetTime()
	if B.Fire then B:Fire("METER_DATA") end
end

local function EndFight()
	if not current then return end
	current.stop = GetTime()
	-- name it after the enemy that took the most damage
	local best, bestAmount = nil, 0
	for _, e in pairs(current.kinds[10]) do
		if e.total > bestAmount then best, bestAmount = e.name, e.total end
	end
	current.name = best or ("Fight " .. current.id)
	if overall then overall.time = (overall.time or 0) + Duration(current) end
	-- keep only fights where something happened
	local any = next(current.kinds[0]) or next(current.kinds[2]) or next(current.kinds[7])
	if any then
		fights[#fights + 1] = current
		while #fights > MAX_FIGHTS do table.remove(fights, 1) end
	end
	current = nil
	if B.Fire then B:Fire("METER_DATA") end
end

-------------------------------------------------------------------------------
-- Combat log
-------------------------------------------------------------------------------
local DAMAGE = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true, SPELL_BUILDING_DAMAGE = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local function OnLog()
	local _, sub, _, sGUID, sName, sFlags, _, dGUID, dName, dFlags, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22 = CombatLogGetCurrentEventInfo()

	if sub == "SPELL_SUMMON" then
		if sGUID and dGUID then petOwner[dGUID] = petOwner[sGUID] or sGUID end
		return
	end

	-- damage --------------------------------------------------------------
	local spellID, spellName, amount, overkill
	if sub == "SWING_DAMAGE" then
		spellID, spellName, amount, overkill = MELEE, nil, a12, a13
	elseif DAMAGE[sub] then
		spellID, spellName, amount, overkill = a12, a13, a15, a16
	end
	if amount then
		local srcGroup, dstGroup = InGroup(sFlags), InGroup(dFlags)
		if (srcGroup and not dstGroup) or (dstGroup and not srcGroup) then StartFight() end
		if not current then return end
		local key = SpellKey(spellID, spellName)
		if srcGroup and not dstGroup then
			local owner, oname, isPet = Owner(sGUID, sName, sFlags)
			if owner then
				Add(0, owner, oname, true, key, amount, dName)
				if isPet then
					for _, f in ipairs({ current, overall }) do
						local s = f and f.kinds[0][owner]
						if s and s.spells[key] then s.spells[key].isPet = true; s.spells[key].petName = sName end
					end
				end
				-- the enemy's side: who hit it with what
				Add(10, dGUID, dName, false, key, amount, oname)
			end
		end
		if dstGroup and IsPlayerFlag(dFlags) then
			Add(7, dGUID, dName, true, key, amount, sName)
			lastHit[dGUID] = { key = key, name = sName, amount = amount }
		end
		return
	end

	if not current then return end

	-- healing -------------------------------------------------------------
	if HEAL[sub] then
		local effective = (a15 or 0) - (a16 or 0)
		local owner, oname = Owner(sGUID, sName, sFlags)
		if owner and effective > 0 then Add(2, owner, oname, true, SpellKey(a12, a13), effective, dName) end
		return
	end

	-- absorbs (shields) -------------------------------------------------------
	if sub == "SPELL_ABSORBED" then
		local caster, casterName, casterFlags, absorbID, absorbName, absorbed
		if type(a12) == "string" and a12:find("-", 1, true) then
			-- melee hit absorbed
			caster, casterName, casterFlags, absorbID, absorbName, absorbed = a12, a13, a14, a16, a17, a19
		else
			caster, casterName, casterFlags, absorbID, absorbName, absorbed = a15, a16, a17, a19, a20, a22
		end
		local owner, oname = Owner(caster, casterName, casterFlags)
		if owner then Add(4, owner, oname, true, SpellKey(absorbID, absorbName), absorbed, dName) end
		return
	end

	-- interrupts / dispels ------------------------------------------------
	if sub == "SPELL_INTERRUPT" or sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
		local owner, oname = Owner(sGUID, sName, sFlags)
		if owner then
			Add(sub == "SPELL_INTERRUPT" and 5 or 6, owner, oname, true, SpellKey(a15, a16), 1, dName)
		end
		return
	end

	-- deaths --------------------------------------------------------------
	if sub == "UNIT_DIED" and InGroup(dFlags) and IsPlayerFlag(dFlags) then
		local hit = lastHit[dGUID]
		Add(9, dGUID, dName, true, hit and hit.key or MELEE, 1, hit and hit.name)
		for _, f in ipairs({ current, overall }) do
			local s = f and f.kinds[9][dGUID]
			if s then s.deathTime = GetTime() - (f.start or GetTime()) end
		end
		lastHit[dGUID] = nil
	end
end

-------------------------------------------------------------------------------
-- C_DamageMeter-shaped answers
-------------------------------------------------------------------------------
local function KindOf(meterType)
	if meterType == 1 then return 0, true end
	if meterType == 3 then return 2, true end
	return meterType, false
end

local function FightFor(sessionType)
	if sessionType == 0 then return overall end
	return current or fights[#fights]
end

local function FightByID(id)
	if current and current.id == id then return current end
	for _, f in ipairs(fights) do if f.id == id then return f end end
end

local function Session(f, meterType)
	local out = { combatSources = {}, totalAmount = 0, maxAmount = 0 }
	if not f then return out end
	local kind, perSec = KindOf(meterType)
	local list = f.kinds[kind]
	if not list then return out end
	local dur = (f == overall) and math.max(1, (f.time or 0) + (current and Duration(current) or 0)) or Duration(f)
	out.durationSeconds = math.floor(dur)
	local me = UnitGUID("player")
	for guid, s in pairs(list) do
		out.combatSources[#out.combatSources + 1] = {
			sourceGUID = guid,
			name = s.name,
			classFilename = s.class,
			totalAmount = s.total,
			amountPerSecond = s.total / dur,
			isLocalPlayer = guid == me,
			deathTimeSeconds = s.deathTime or 0,
		}
		out.totalAmount = out.totalAmount + s.total
	end
	table.sort(out.combatSources, function(a, b)
		if perSec then return a.amountPerSecond > b.amountPerSecond end
		return a.totalAmount > b.totalAmount
	end)
	local top = out.combatSources[1]
	out.maxAmount = top and top.totalAmount or 0
	return out
end

local function SourceDetail(f, meterType, guid)
	local out = { combatSpells = {}, totalAmount = 0, maxAmount = 0 }
	local kind = KindOf(meterType)
	local s = f and f.kinds[kind] and f.kinds[kind][guid]
	if not s then return out end
	local dur = (f == overall) and math.max(1, (f.time or 0) + (current and Duration(current) or 0)) or Duration(f)
	for key, sp in pairs(s.spells) do
		out.combatSpells[#out.combatSpells + 1] = {
			spellID = key,
			totalAmount = sp.amount,
			amountPerSecond = sp.amount / dur,
			creatureName = sp.petName or "",
			combatSpellDetails = { isPet = sp.isPet or false, unitName = (kind ~= 0 and kind ~= 2) and sp.target or nil },
		}
		out.totalAmount = out.totalAmount + sp.amount
	end
	table.sort(out.combatSpells, function(a, b) return a.totalAmount > b.totalAmount end)
	out.maxAmount = out.combatSpells[1] and out.combatSpells[1].totalAmount or 0
	return out
end

function D.IsDamageMeterAvailable() return true, "" end
function D.GetCombatSessionFromType(sessionType, meterType) return Session(FightFor(sessionType), meterType) end
function D.GetCombatSessionFromID(id, meterType) return Session(FightByID(id), meterType) end
function D.GetCombatSessionSourceFromType(sessionType, meterType, guid) return SourceDetail(FightFor(sessionType), meterType, guid) end
function D.GetCombatSessionSourceFromID(id, meterType, guid) return SourceDetail(FightByID(id), meterType, guid) end

function D.GetAvailableCombatSessions()
	local out = {}
	for _, f in ipairs(fights) do
		out[#out + 1] = { sessionID = f.id, name = f.name, durationSeconds = math.floor(Duration(f)) }
	end
	return out
end

function D.ResetAllCombatSessions()
	wipe(fights)
	current, overall = nil, nil
	wipe(lastHit)
	if GroupInCombat() then StartFight() end
	if B.Fire then B:Fire("METER_DATA") end
end

-- meter kinds this source can answer (no "avoidable damage" on Classic)
D.SUPPORTED = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [9] = true, [10] = true }

-------------------------------------------------------------------------------
function D:Start()
	if self.started then return end
	self.started = true
	local f = CreateFrame("Frame")
	f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("UNIT_PET")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function(_, event)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			local ok, err = pcall(OnLog)
			if not ok then B:Error(err) end
		elseif event == "PLAYER_REGEN_DISABLED" then
			StartFight()
		else
			ScanPets()
		end
	end)
	-- the fight ends once nobody in the group is fighting any more
	local t = 0
	f:SetScript("OnUpdate", function(_, el)
		t = t + el
		if t < 1 then return end
		t = 0
		if current and not GroupInCombat() then EndFight() end
	end)
	ScanPets()
end
