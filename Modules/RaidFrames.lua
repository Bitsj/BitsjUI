--[[
	BitsjUI - Party & raid frames
	Simple class-coloured tiles in the BitsjUI style: name top-left, status
	text, dark rounded border, white edge on your target, red edge when the
	unit has aggro, dimmed out of range, small debuffs (the ones Blizzard
	flags for raid frames) and your own HoTs.

	Built on Blizzard's SecureGroupHeaderTemplate, so clicking / targeting
	works in combat. Raid: one column per group with a "Group N" label.
	Party: one column including you.
	Health and range can be hidden numbers in combat; they only ever go into
	widget setters (SetValue, SetAlphaFromBoolean), never into comparisons.
]]
local _, B = ...
local M = B:NewModule("RaidFrames")

-- fonts: this file uses the "raidframes" section font (/bui > General > Fonts)
local FONT_SECTION = "raidframes"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local issecret = B.IsSecret
local function db() return B.db.raidframes end
-- party and raid each have their own look; b.kind says which a tile belongs to
local function K(b) return B.db.raidframes[(b and b.kind) or "raid"] end

local holderRaid, holderParty
local raidHeaders, partyHeader = {}, nil
local buttons = {}     -- every styled button
local byUnit = {}      -- unit -> { button = true }

-------------------------------------------------------------------------------
-- Updates
-------------------------------------------------------------------------------
local function ClassColor(unit)
	local _, class = UnitClass(unit)
	if class and not issecret(class) then return B:ClassColor(class) end
	return 0.45, 0.45, 0.5
end

local function UpdateHealth(b)
	local unit = b.unit
	if not unit then return end
	local d = K(b)
	pcall(b.health.SetMinMaxValues, b.health, 0, UnitHealthMax(unit))
	if not pcall(b.health.SetValue, b.health, UnitHealth(unit)) then b.health:SetValue(0) end
	B:UpdateAbsorb(b.health, unit, db().absorbs ~= false)

	local offline = not B.Plain(UnitIsConnected(unit), true)
	local dead = B.Plain(UnitIsDeadOrGhost(unit), false)
	local r, g, bl = ClassColor(unit)
	if offline or dead then r, g, bl = 0.35, 0.35, 0.38 end
	if d.colorMode == "dark" and not (offline or dead) then
		b.health:SetStatusBarColor(0.16, 0.16, 0.18)
		b.health.bg:SetVertexColor(r * 0.55, g * 0.55, bl * 0.55, 1)
	else
		b.health:SetStatusBarColor(r, g, bl)
		b.health.bg:SetVertexColor(r * 0.25, g * 0.25, bl * 0.25, 1)
	end
	if offline then b.status:SetText("Offline")
	elseif dead then b.status:SetText(B.Plain(UnitIsGhost(unit), false) and "Ghost" or "Dead")
	else b.status:SetText("") end
end

local function UpdateName(b)
	local unit = b.unit
	if not unit then return end
	local name = UnitName(unit)
	if not issecret(name) and type(name) == "string" then name = name:gsub("%-.+$", "") end
	if not pcall(b.name.SetText, b.name, name) then b.name:SetText("") end
	local d = K(b)
	if d.nameColor == "class" then
		b.name:SetTextColor(ClassColor(unit))
	else
		b.name:SetTextColor(1, 1, 1)
	end
end

local function UpdateRange(b)
	local unit = b.unit
	if not unit then return end
	local d = K(b)
	if B.Plain(UnitIsUnit(unit, "player"), false) then b:SetAlpha(1); return end
	local ok, inRange, checked = pcall(UnitInRange, unit)
	if not ok then b:SetAlpha(1); return end
	if issecret(inRange) then
		if b.SetAlphaFromBoolean then pcall(b.SetAlphaFromBoolean, b, inRange, 1, d.rangeAlpha) end
		return
	end
	if checked == false then b:SetAlpha(1) else b:SetAlpha(inRange and 1 or d.rangeAlpha) end
end

local function UpdateEdge(b)
	local unit = b.unit
	if not unit then return end
	if B.Plain(UnitIsUnit(unit, "target"), false) then
		b.bBorder:SetColor(1, 1, 1, 1)
		return
	end
	if K(b).aggro then
		local ok, s = pcall(UnitThreatSituation, unit)
		s = ok and B.Plain(s, nil)
		if type(s) == "number" and s >= 2 then b.bBorder:SetColor(0.95, 0.15, 0.15, 1); return end
	end
	b.bBorder:SetColor(0, 0, 0, 1)
end

local function UpdateIcons(b)
	local unit = b.unit
	if not unit then return end
	local idx = GetRaidTargetIndex and B.Plain(GetRaidTargetIndex(unit), nil)
	if idx then SetRaidTargetIconTexture(b.raid, idx); b.raid:Show() else b.raid:Hide() end
	local role = UnitGroupRolesAssigned and B.Plain(UnitGroupRolesAssigned(unit), "NONE")
	local roleAtlas = (role == "TANK" and "roleicon-tiny-tank") or (role == "HEALER" and "roleicon-tiny-healer") or nil
	if K(b).roleIcon and roleAtlas and B.HasAtlas(roleAtlas) then
		b.role:SetAtlas(roleAtlas)
		b.role:Show()
	else
		b.role:Hide()
	end
end

-- summon (pending / accepted / declined) and incoming resurrection, big in the middle
local SUMMON_ATLAS = {}
local function UpdateStatus(b)
	local unit = b.unit
	if not unit or not b.center then return end
	local atlas
	if K(b).summonIcon ~= false and C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
		local ok, has = pcall(C_IncomingSummon.HasIncomingSummon, unit)
		if ok and B.Plain(has, false) then
			local st = B.Plain(C_IncomingSummon.IncomingSummonStatus(unit), nil)
			local S = Enum and Enum.SummonStatus or {}
			if st == (S.Pending or 1) then atlas = "RaidFrame-Icon-SummonPending"
			elseif st == (S.Accepted or 2) then atlas = "RaidFrame-Icon-SummonAccepted"
			elseif st == (S.Declined or 3) then atlas = "RaidFrame-Icon-SummonDeclined" end
		end
	end
	if not atlas and UnitHasIncomingResurrection then
		local ok, res = pcall(UnitHasIncomingResurrection, unit)
		if ok and B.Plain(res, false) then atlas = "RaidFrame-Icon-Rez" end
	end
	if atlas then b.center:SetAtlas(atlas); b.center:Show() else b.center:Hide() end
end

-- Classic clients (no AuraContainer): scan the unit's auras ourselves.
-- Debuffs bottom right (dispellable ones get their type colour), your own
-- short buffs (HoTs, shields) bottom left.
local function ScanAuras(b)
	if not b.sDebuffs or not b.unit then return end
	local d = K(b)
	local n = 0
	if d.debuffs then
		for i = 1, 40 do
			if n >= 3 then break end
			local a = B.GetAura(b.unit, i, "HARMFUL")
			if not a then break end
			n = n + 1
			B:SetAuraIcon(b.sDebuffs[n], a)
		end
	end
	for i = n + 1, 3 do b.sDebuffs[i]:Hide() end
	n = 0
	if d.myBuffs then
		for i = 1, 40 do
			if n >= 3 then break end
			local a = B.GetAura(b.unit, i, "HELPFUL|PLAYER")
			if not a then break end
			local dur = B.Plain(a.duration, 0) or 0
			if dur > 0 and dur <= 60 then
				n = n + 1
				B:SetAuraIcon(b.sHots[n], a)
			end
		end
	end
	for i = n + 1, 3 do b.sHots[i]:Hide() end
end

local function LayoutScan(b)
	if not b.sDebuffs then return end
	local d = K(b)
	for i = 1, 3 do
		local db_, hb = b.sDebuffs[i], b.sHots[i]
		db_:SetSize(d.debuffSize, d.debuffSize)
		db_:ClearAllPoints()
		db_:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2 - (i - 1) * (d.debuffSize + 2), 2)
		hb:SetSize(d.buffSize, d.buffSize)
		hb:ClearAllPoints()
		hb:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2 + (i - 1) * (d.buffSize + 2), 2)
	end
end

local function UpdateAll(b)
	if not b.unit or not b:IsVisible() then return end
	B:Try(UpdateHealth, b)
	B:Try(UpdateName, b)
	B:Try(UpdateRange, b)
	B:Try(UpdateEdge, b)
	B:Try(UpdateIcons, b)
	B:Try(UpdateStatus, b)
	B:Try(ScanAuras, b)
end

-------------------------------------------------------------------------------
-- Button look
-------------------------------------------------------------------------------
local function LayoutButton(b)
	local d = K(b)
	local tex = B:GetTexture()
	b.health:SetStatusBarTexture(tex)
	b.health.bg:SetTexture(tex)
	SetFont(b.name, d.nameSize); b.name.bSize = d.nameSize
	SetFont(b.status, d.nameSize - 1); b.status.bSize = d.nameSize - 1
	b.name:ClearAllPoints()
	b.name:SetPoint("TOPLEFT", b, "TOPLEFT", d.roleIcon and 14 or 4, -3)
	b.name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)
	B:SetBorderSize(b, d.borderSize or 1)
	if b.debuffs then
		b.debuffs:SetSize(d.debuffSize * 3 + 4, d.debuffSize)
		B:UpdateAuraBox(b.debuffs, d.debuffSize, { debuffs = d.debuffs and 3 or 0 })
	end
	if b.hots then
		b.hots:SetSize(d.buffSize * 3 + 4, d.buffSize)
		B:UpdateAuraBox(b.hots, d.buffSize, { hots = d.myBuffs and 3 or 0 })
	end
	LayoutScan(b)
end

local function SetUnit(b, unit)
	if b.unit and byUnit[b.unit] then byUnit[b.unit][b] = nil end
	b.unit = unit
	if unit then
		byUnit[unit] = byUnit[unit] or {}
		byUnit[unit][b] = true
	end
	B:Fire("RAID_BUTTONS_CHANGED")
	if b.debuffs then B:SetAuraBoxUnit(b.debuffs, unit) end
	if b.hots then B:SetAuraBoxUnit(b.hots, unit) end
	UpdateAll(b)
end

-- every party / raid tile currently bound to a unit (for other addons, e.g. MiniAuras)
function M:GetUnitButtons()
	local out = {}
	for _, b in ipairs(buttons) do
		if b.unit then out[#out + 1] = b end
	end
	return out
end

local function StyleButton(b, kind)
	if b.bStyled then return end
	b.bStyled = true
	b.kind = kind
	buttons[#buttons + 1] = b

	local hp = B:CreateStatusBar(b)
	hp:SetAllPoints(b)
	b.health = hp
	B:CreateAbsorb(hp)
	B:CreateBorder(b, 0, 0, 0, 1, B:Pixel(b))

	local overlay = CreateFrame("Frame", nil, b)
	overlay:SetAllPoints(b)
	overlay:SetFrameLevel(hp:GetFrameLevel() + 3)
	b.name = CreateText(overlay, K(b).nameSize, "LEFT")
	b.status = CreateText(overlay, K(b).nameSize - 1, "CENTER")
	b.status:SetPoint("CENTER", b, "CENTER", 0, -4)
	b.status:SetTextColor(0.85, 0.85, 0.88)
	b.role = overlay:CreateTexture(nil, "OVERLAY")
	b.role:SetSize(10, 10)
	b.role:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.raid = overlay:CreateTexture(nil, "OVERLAY")
	b.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	b.raid:SetSize(14, 14)
	b.raid:SetPoint("CENTER", b, "TOP", 0, 0)
	b.raid:Hide()
	b.center = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	b.center:SetSize(22, 22)
	b.center:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.center:Hide()

	-- Blizzard-picked raid debuffs bottom right, your HoTs bottom left
	local d = K(b)
	b.debuffs = B:CreateAuraBox(overlay, { { key = "debuffs", filter = "HARMFUL|RAID_IN_COMBAT", max = 3 } }, d.debuffSize)
	if b.debuffs then
		b.debuffs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		B:SetAuraBoxFlow(b.debuffs, "BOTTOMRIGHT", "Left", "Up", 2)
	end
	b.hots = B:CreateAuraBox(overlay, { { key = "hots", filter = "HELPFUL|PLAYER|RAID_IN_COMBAT", max = 3 } }, d.buffSize)
	if b.hots then
		b.hots:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
		B:SetAuraBoxFlow(b.hots, "BOTTOMLEFT", "Right", "Up", 2)
	end
	if not b.debuffs then
		b.sDebuffs, b.sHots = {}, {}
		for i = 1, 3 do
			b.sDebuffs[i] = B:CreateAuraIcon(overlay, d.debuffSize)
			b.sHots[i] = B:CreateAuraIcon(overlay, d.buffSize)
			b.sDebuffs[i]:Hide(); b.sHots[i]:Hide()
		end
	end

	b:HookScript("OnAttributeChanged", function(self, name, value)
		if name == "unit" then SetUnit(self, value) end
	end)
	b:HookScript("OnShow", function(self) UpdateAll(self) end)
	-- unit tooltip on hover (the secure template has none of its own)
	b:HookScript("OnEnter", function(self)
		local unit = self:GetAttribute("unit")
		if not unit or not UnitExists(unit) then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(unit)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() GameTooltip:Hide() end)
	b:RegisterForClicks("AnyUp")
	LayoutButton(b)
	SetUnit(b, b:GetAttribute("unit"))
end

-------------------------------------------------------------------------------
-- Headers
-------------------------------------------------------------------------------
local CONFIG = [[
	self:SetWidth(%d)
	self:SetHeight(%d)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
	self:SetAttribute("toggleForVehicle", true)
]]

local function NewHeader(name, parent, kind)
	local h = CreateFrame("Frame", name, parent, "SecureGroupHeaderTemplate")
	h:SetAttribute("template", "SecureUnitButtonTemplate")
	h:SetAttribute("point", "TOP")
	h:SetAttribute("sortMethod", "INDEX")
	h:HookScript("OnAttributeChanged", function(_, key, value)
		if type(key) == "string" and key:match("^child%d+$") and type(value) == "table" then
			StyleButton(value, kind)
		end
	end)
	return h
end

-- size / spacing (out of combat only: the headers are protected)
function M:Arrange()
	if InCombatLockdown() then B:RunOOC("raidframes", function() M:Arrange() end); return end
	local P, R = db().party, db().raid
	local function size(h, c)
		h:SetAttribute("initialConfigFunction", string.format(CONFIG, c.width, c.height))
		h:SetAttribute("yOffset", -c.spacing)
		for i = 1, 40 do
			local child = h:GetAttribute("child" .. i)
			if not child then break end
			child:SetSize(c.width, c.height)
		end
	end
	size(partyHeader, P)
	for i = 1, 8 do
		local h = raidHeaders[i]
		size(h, R)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", holderRaid, "TOPLEFT", (i - 1) * (R.width + R.spacing), -(R.groupLabels and 16 or 0))
		SetFont(h.label, 12)
		h.label:SetTextColor(1, 0.82, 0.1)
	end
	partyHeader:ClearAllPoints()
	partyHeader:SetPoint("TOPLEFT", holderParty, "TOPLEFT", 0, 0)
	holderRaid:SetSize(8 * R.width + 7 * R.spacing, 5 * R.height + 4 * R.spacing + 16)
	holderParty:SetSize(P.width, 5 * P.height + 4 * P.spacing)
	for _, b in ipairs(buttons) do LayoutButton(b); UpdateAll(b) end
	self:UpdateLabels()
	self:RefreshPreview()
end

-- how many raid groups to show: by the raid instance's size when inside one
-- (Mythic 20 = groups 1-4, normal/heroic up to 30 = 1-6), otherwise by how
-- many people are in the raid (10 = 2 groups, 20 = 4, 25 = 5, 30 = 6, 40 = 8)
local function GroupsFor(n)
	if n <= 10 then return 2 elseif n <= 20 then return 4 elseif n <= 25 then return 5
	elseif n <= 30 then return 6 end
	return 8
end

function M:GroupCount()
	if db().raid.groups ~= "auto" then return 8 end
	local _, instanceType, _, _, maxPlayers = GetInstanceInfo()
	if instanceType == "raid" and maxPlayers and maxPlayers > 0 then return GroupsFor(maxPlayers) end
	return GroupsFor(GetNumGroupMembers() or 0)
end

function M:ApplyGroups()
	if not partyHeader then return end
	if InCombatLockdown() then B:RunOOC("raid_groups", function() M:ApplyGroups() end); return end
	local d = db()
	local n = self:GroupCount()
	for i = 1, 8 do
		local show = d.raid.show and i <= n
		RegisterStateDriver(raidHeaders[i], "visibility", show and "[group:raid] show; hide" or "hide")
	end
	RegisterStateDriver(partyHeader, "visibility", d.party.show and "[group:raid] hide; [group:party] show; hide" or "hide")
	C_Timer.After(0.1, function() M:UpdateLabels() end)
end

-- "Group N" only above groups that have someone in them
function M:UpdateLabels()
	if self.previewKind and self.previewKind ~= "party" then return end
	local show = db().raid.groupLabels
	for i = 1, 8 do
		local h = raidHeaders[i]
		local first = h and h:GetAttribute("child1")
		h.label:SetShown(show and h:IsVisible() and first and first:IsShown() and true or false)
	end
end

local function HideBlizzard()
	if not db().hideBlizzard then return end
	B:RunOOC("hide_compact", function()
		for _, name in ipairs({ "CompactPartyFrame", "PartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager",
			"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "PartyMemberBackground" }) do
			local f = _G[name]
			if f and not f.bHidden then
				f.bHidden = true
				pcall(f.SetParent, f, B.hiddenParent)
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Preview: fake tiles with the real look, for setting things up solo
-------------------------------------------------------------------------------
local FAKE = {
	{ "Bitsj", "PALADIN", 1, "TANK" }, { "Ryanwarlock", "WARLOCK", 0.82 }, { "Kiuni", "MAGE", 0.64 },
	{ "Habibiboom", "DRUID", 1, "HEALER" }, { "Shemkon", "SHAMAN", 0.91, "HEALER" }, { "Brimaz", "MONK", 0.47 },
	{ "Klix", "PALADIN", 1 }, { "Chaux", "PRIEST", 0, nil, "Dead" }, { "Blacknister", "SHAMAN", 0.73 },
	{ "Majkah", "DEMONHUNTER", 0.88 }, { "Brewswag", "MONK", 1, "TANK" }, { "Calestia", "WARLOCK", 0.35 },
	{ "Trollemgoo", "HUNTER", 0.95 }, { "Necroxo", "DEATHKNIGHT", 0.6 }, { "Moonwater", "DRUID", 1 },
	{ "Seemerollin", "EVOKER", 0.77, "HEALER" }, { "Owlgodtko", "ROGUE", 1 }, { "Thuglyf", "HUNTER", 0, nil, "Offline" },
	{ "Vertani", "MAGE", 0.52 }, { "Seji", "PRIEST", 0.99, "HEALER" },
}

if B.isClassic then
	-- classes Classic doesn't have
	local swap = { MONK = "ROGUE", DEMONHUNTER = "WARRIOR", DEATHKNIGHT = "WARRIOR", EVOKER = "SHAMAN" }
	for _, f in ipairs(FAKE) do f[2] = swap[f[2]] or f[2] end
end

local previewTiles = { party = {}, raid = {} }

local function PreviewTile(kind, i)
	local list = previewTiles[kind]
	if list[i] then return list[i] end
	local holder = kind == "party" and holderParty or holderRaid
	local b = CreateFrame("Frame", nil, holder)
	b.kind = kind
	b.health = B:CreateStatusBar(b)
	b.health:SetAllPoints(b)
	B:CreateBorder(b, 0, 0, 0, 1, B:Pixel(b))
	local overlay = CreateFrame("Frame", nil, b)
	overlay:SetAllPoints(b)
	overlay:SetFrameLevel(b.health:GetFrameLevel() + 3)
	b.name = CreateText(overlay, K(b).nameSize, "LEFT")
	b.status = CreateText(overlay, K(b).nameSize - 1, "CENTER")
	b.status:SetPoint("CENTER", b, "CENTER", 0, -4)
	b.status:SetTextColor(0.85, 0.85, 0.88)
	b.role = overlay:CreateTexture(nil, "OVERLAY")
	b.role:SetSize(10, 10)
	b.role:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.center = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	b.center:SetSize(22, 22)
	b.center:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.center:Hide()
	list[i] = b
	return b
end

local function FillPreview(b, data, i)
	local d = K(b)
	LayoutButton(b)
	local name, class, hp, role, status = data[1], data[2], data[3], data[4], data[5]
	local r, g, bl = B:ClassColor(class)
	if status then r, g, bl = 0.35, 0.35, 0.38 end
	b.health:SetMinMaxValues(0, 1)
	b.health:SetValue(status and 1 or hp)
	if d.colorMode == "dark" and not status then
		b.health:SetStatusBarColor(0.16, 0.16, 0.18)
		b.health.bg:SetVertexColor(r * 0.55, g * 0.55, bl * 0.55, 1)
	else
		b.health:SetStatusBarColor(r, g, bl)
		b.health.bg:SetVertexColor(r * 0.25, g * 0.25, bl * 0.25, 1)
	end
	b.name:SetText(name)
	if d.nameColor == "class" then b.name:SetTextColor(r, g, bl) else b.name:SetTextColor(1, 1, 1) end
	b.status:SetText(status or "")
	if d.roleIcon and (role == "TANK" or role == "HEALER") then
		b.role:SetAtlas(role == "TANK" and "roleicon-tiny-tank" or "roleicon-tiny-healer")
		b.role:Show()
	else
		b.role:Hide()
	end
	b.bBorder:SetColor(0, 0, 0, 1)
	if i == 3 then b.bBorder:SetColor(1, 1, 1, 1) end                       -- your target
	if i == 1 and d.aggro then b.bBorder:SetColor(0.95, 0.15, 0.15, 1) end -- has aggro
	b:SetAlpha(i == 6 and d.rangeAlpha or 1)                                -- out of range
	if i == 2 then b.center:SetAtlas("RaidFrame-Icon-SummonPending"); b.center:Show()       -- being summoned
	elseif i == 5 then b.center:SetAtlas("RaidFrame-Icon-SummonAccepted"); b.center:Show()
	else b.center:Hide() end
end

-- kind: nil (off), "party", "raid20", "raid40"
function M:SetPreview(kind)
	self.previewKind = kind
	self:RefreshPreview()
end

function M:RefreshPreview()
	if not holderParty then return end
	local P, R = db().party, db().raid
	local kind = self.previewKind
	-- unlocked movers show both, so you can place them
	if not kind and B.Movers.unlocked then kind = "both" end
	local partyN = (kind == "party" or kind == "both") and 5 or 0
	local raidN = (kind == "raid20" or kind == "both") and 20 or kind == "raid40" and 40 or 0

	for i = 1, math.max(partyN, #previewTiles.party) do
		if i <= partyN then
			local b = PreviewTile("party", i)
			b:SetSize(P.width, P.height)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", holderParty, "TOPLEFT", 0, -(i - 1) * (P.height + P.spacing))
			FillPreview(b, FAKE[i], i)
			b:Show()
		else
			previewTiles.party[i]:Hide()
		end
	end
	for i = 1, math.max(raidN, #previewTiles.raid) do
		if i <= raidN then
			local b = PreviewTile("raid", i)
			local group, slot = math.floor((i - 1) / 5), (i - 1) % 5
			b:SetSize(R.width, R.height)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", holderRaid, "TOPLEFT", group * (R.width + R.spacing),
				-(R.groupLabels and 16 or 0) - slot * (R.height + R.spacing))
			FillPreview(b, FAKE[(i - 1) % #FAKE + 1], i)
			b:Show()
		else
			previewTiles.raid[i]:Hide()
		end
	end
	-- group labels for the preview
	local groups = math.ceil(raidN / 5)
	for i = 1, 8 do
		local h = raidHeaders[i]
		if raidN > 0 then
			h.label:ClearAllPoints()
			h.label:SetPoint("BOTTOM", holderRaid, "TOPLEFT", (i - 1) * (R.width + R.spacing) + R.width / 2, -14)
			h.label:SetShown(R.groupLabels and i <= groups)
		else
			h.label:ClearAllPoints()
			h.label:SetPoint("BOTTOM", h, "TOP", 0, 3)
		end
	end
	if raidN == 0 then self:UpdateLabels() end
end

-------------------------------------------------------------------------------
function M:OnEnable()
	local d = db()
	if not d.enabled then return end

	holderRaid = CreateFrame("Frame", "BitsjUIRaidHolder", UIParent)
	holderParty = CreateFrame("Frame", "BitsjUIPartyHolder", UIParent)
	B:RegisterMover(holderRaid, "raid", "Raid frames", { "TOPLEFT", "TOPLEFT", 20, -240 })
	B:RegisterMover(holderParty, "party", "Party frames", { "TOPLEFT", "TOPLEFT", 20, -300 })

	for i = 1, 8 do
		local h = NewHeader("BitsjUIRaidGroup" .. i, holderRaid, "raid")
		h:SetAttribute("showRaid", true)
		h:SetAttribute("groupFilter", tostring(i))
		h.label = holderRaid:CreateFontString(nil, "OVERLAY")
		SetFont(h.label, 12)
		h.label:SetPoint("BOTTOM", h, "TOP", 0, 3)
		h.label:SetText("Group " .. i)
		raidHeaders[i] = h
	end
	partyHeader = NewHeader("BitsjUIParty", holderParty, "party")
	partyHeader:SetAttribute("showParty", true)
	partyHeader:SetAttribute("showPlayer", true)
	partyHeader:SetAttribute("showSolo", false)

	self:Arrange()
	self:ApplyGroups()
	HideBlizzard()

	-- events
	local f = CreateFrame("Frame")
	local unitEvents = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_FLAGS",
		"UNIT_THREAT_SITUATION_UPDATE", "INCOMING_SUMMON_CHANGED", "INCOMING_RESURRECT_CHANGED" }
	if not B:HasAuraContainers() then unitEvents[#unitEvents + 1] = "UNIT_AURA" end
	for _, e in ipairs(unitEvents) do pcall(f.RegisterEvent, f, e) end
	for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PLAYER_ROLES_ASSIGNED",
		"PLAYER_ENTERING_WORLD" }) do pcall(f.RegisterEvent, f, e) end
	f:SetScript("OnEvent", B.Safe(function(_, event, unit)
		if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_TARGET_CHANGED" then
			for _, b in ipairs(buttons) do if b.unit then UpdateEdge(b) end end
			return
		end
		if event == "INCOMING_SUMMON_CHANGED" or event == "INCOMING_RESURRECT_CHANGED" then
			if type(unit) == "string" and byUnit[unit] then
				for b in pairs(byUnit[unit]) do UpdateStatus(b) end
			else
				for _, b in ipairs(buttons) do if b.unit then UpdateStatus(b) end end
			end
			return
		end
		if event == "UNIT_AURA" and not (type(unit) == "string" and byUnit[unit]) then return end
		if type(unit) == "string" and byUnit[unit] then
			for b in pairs(byUnit[unit]) do
				if event == "UNIT_NAME_UPDATE" then UpdateName(b)
				elseif event == "UNIT_AURA" then ScanAuras(b)
				else UpdateHealth(b) end
			end
			return
		end
		for _, b in ipairs(buttons) do UpdateAll(b) end
		C_Timer.After(0.1, function() M:UpdateLabels() end)
	end))
	-- range is polled (no event for it)
	f.elapsed = 0
	f:SetScript("OnUpdate", function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 0.25 then return end
		self.elapsed = 0
		for _, b in ipairs(buttons) do
			if b.unit and b:IsVisible() then B:Try(UpdateRange, b) end
		end
	end)
	B:RegisterCallback("UPDATE_ALL", function() M:Arrange() end)
	B:RegisterCallback("MOVERS_TOGGLED", function() M:RefreshPreview() end)
	-- real group joined: drop the preview
	B:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		if M.previewKind and IsInGroup() then M:SetPreview(nil) end
		M:ApplyGroups()
	end)
	B:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:ApplyGroups() end)
	B:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() M:ApplyGroups() end)
end

function M:Update()
	if not partyHeader then return end
	self:Arrange()
	if InCombatLockdown() then return end
	self:ApplyGroups()
end
