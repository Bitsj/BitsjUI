--[[
	BitsjUI - Defensive cooldowns
	A row of icons right above the player frame (over your name) that pops up
	while a defensive is active on you: your own (Divine Shield, Ice Block,
	Barkskin, Shield Wall...) and ones cast on you by others (Pain
	Suppression, Blessing of Protection, Ironbark...). Every class, retail and
	Classic. Icons show the time left as a sweep plus a countdown, and fade in.

	Retail: Blizzard's AuraContainer with a spell-ID allow list (aura data is
	hidden from addons in combat, the container still works).
	Classic: the player's buffs are scanned on UNIT_AURA.
	Extra spells can be added in /bui -> Defensives (spell IDs).
]]
local _, B = ...
local M = B:NewModule("Defensives")

-- fonts: this file uses the "auras" section font (/bui > General > Fonts)
local FONT_SECTION = "auras"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local function db() return B.db.defensives end

-- [spellID] = true. Buff IDs as they appear on the player.
local DEFENSIVES = {
	-- Death Knight
	48792, 48707, 49039, 55233, 81256, 145629, 194679, 219809,
	-- Demon Hunter
	212800, 196555, 187827, 209426, 203819,
	-- Druid
	22812, 61336, 22842, 102558, 200851,
	-- Evoker
	363916, 374348, 374227, 357170,
	-- Hunter
	186265, 264735, 281195, 19263, 388035,
	-- Mage
	45438, 11958, 342246, 110909, 113862, 235313, 11426, 235450, 414658,
	-- Monk
	120954, 122783, 122278, 115176, 125174, 322507, 115203,
	-- Paladin
	642, 1020, 498, 5573, 403876, 184662, 31850, 86659, 212641, 205191, 204018,
	-- Priest
	47585, 19236, 27827, 20711,
	-- Rogue
	31224, 5277, 26669, 1966, 45182, 185311,
	-- Shaman
	108271, 409293, 30823, 210918,
	-- Warlock
	104773, 108416, 212295,
	-- Warrior
	871, 118038, 12975, 12976, 184364, 23920, 97463, 20230, 386208, 392966,
	-- Racials
	65116, 20594, 58984, 312411,
	-- Externals (cast on you by others)
	33206, 47788, 102342, 1022, 5599, 10278, 6940, 116849, 196718, 81782,
}
local SET = {}
for _, id in ipairs(DEFENSIVES) do SET[id] = true end

function M.SpellSet()
	local set = {}
	for id in pairs(SET) do set[id] = true end
	for id in tostring(db().extra or ""):gmatch("%d+") do set[tonumber(id)] = true end
	for id in tostring(db().ignore or ""):gmatch("%d+") do set[tonumber(id)] = nil end
	return set
end

local holder, box
local icons = {}       -- Classic path
M.icons = icons

-------------------------------------------------------------------------------
-- Position: just above the player frame's name line
-------------------------------------------------------------------------------
local function PlayerBars()
	if not db().attach then return end
	local pf = _G.BitsjUI_player
	if pf and pf.bars and B.db.unitframes.enabled and B.db.unitframes.player.enabled then return pf.bars end
end

function M:Width()
	if PlayerBars() then return B.db.unitframes.player.width end
	return db().max * (db().size + db().spacing)
end

function M:Attach()
	if not holder then return end
	local bars = PlayerBars()
	B:SetMoverEnabled("defensives", db().enabled and not bars)
	if not bars then
		if M.attached then M.attached = false; B.Movers:Apply("defensives") end
		return
	end
	M.attached = true
	local uf = B.db.unitframes
	-- clear of the name / level line above the bars and the frame border
	local y = 3 + (uf.player.showName ~= false and (uf.nameSize or 12) + 4 or 0) + B:Pixel(holder) * (uf.borderSize or 2) + db().gap
	holder:ClearAllPoints()
	holder:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", 0, y)
	holder:SetPoint("BOTTOMRIGHT", bars, "TOPRIGHT", 0, y)
end

-------------------------------------------------------------------------------
-- Classic: our own icons
-------------------------------------------------------------------------------
local function Icon(i)
	local btn = icons[i]
	if btn then return btn end
	btn = B:CreateAuraIcon(holder, db().size)
	-- soft pop-in: fade from 0 and grow slightly
	local ag = btn:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.18); a:SetSmoothing("OUT")
	local s = ag:CreateAnimation("Scale")
	if s.SetScaleFrom then s:SetScaleFrom(0.7, 0.7); s:SetScaleTo(1, 1) else s:SetFromScale(0.7, 0.7); s:SetToScale(1, 1) end
	s:SetDuration(0.18); s:SetSmoothing("OUT")
	btn.pop = ag
	icons[i] = btn
	return btn
end

local function Scan()
	if box then return end
	local d = db()
	local set = M.set or M.SpellSet()
	local n = 0
	if d.enabled then
		for i = 1, 40 do
			if n >= d.max then break end
			local a = B.GetAura("player", i, "HELPFUL")
			if not a then break end
			local id = B.Plain(a.spellId, nil)
			if id and set[id] then
				n = n + 1
				local btn = Icon(n)
				local isNew = btn.bSpell ~= id or not btn:IsShown()
				btn.bSpell = id
				btn:SetSize(d.size, d.size)
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (n - 1) * (d.size + d.spacing), 0)
				B:SetAuraIcon(btn, a)
				if isNew and btn.pop then btn.pop:Stop(); btn.pop:Play() end
			end
		end
	end
	for i = n + 1, #icons do icons[i]:Hide(); icons[i].bSpell = nil end
end

-------------------------------------------------------------------------------
function M:Layout()
	if not holder then return end
	local d = db()
	M.set = M.SpellSet()
	holder:SetSize(self:Width(), d.size)
	if box then
		box:ClearAllPoints()
		box:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
		box:SetSize(self:Width(), d.size)
		B:SetAuraBoxFlow(box, "BOTTOMLEFT", "Right", "Up", d.spacing)
		B:SetAuraGroupCandidate(box, "def", { includeSpellIDs = M.set })
		B:UpdateAuraBox(box, d.size, { def = d.enabled and d.max or 0 })
		box:SetShown(d.enabled)
	else
		for _, btn in ipairs(icons) do
			btn:SetSize(d.size, d.size)
			local cdText = btn.cd.GetCountdownFontString and btn.cd:GetCountdownFontString()
			if cdText then SetFont(cdText, math.max(8, math.floor(d.size * 0.42))) end
			SetFont(btn.count, math.max(8, math.floor(d.size * 0.40)))
		end
		Scan()
	end
	self:Attach()
	self:Preview()
end

-- sample icons while moving frames / with the menu open
function M:Preview()
	if not holder then return end
	local on = (B.Movers.unlocked or B.previewing) and db().enabled
	if not holder.samples then
		holder.samples = {}
		for i, tex in ipairs({ 135896, 135936, 136120 }) do   -- Shield Wall, Divine Shield, Barkskin style icons
			local s = B:CreateAuraIcon(holder, db().size)
			s.icon:SetTexture(tex)
			s:Hide()
			holder.samples[i] = s
		end
	end
	local d = db()
	for i, s in ipairs(holder.samples) do
		s:SetSize(d.size, d.size)
		s:ClearAllPoints()
		s:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (i - 1) * (d.size + d.spacing), 0)
		s:SetShown(on)
	end
end

function M:OnEnable()
	if not db().enabled then return end
	holder = CreateFrame("Frame", "BitsjUIDefensives", UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:SetSize(self:Width(), db().size)
	B:RegisterMover(holder, "defensives", "Defensives", { "BOTTOM", "BOTTOM", -180, 360 })
	M.set = M.SpellSet()

	if B:HasAuraContainers() then
		box = B:CreateAuraBox(holder, { { key = "def", filter = "HELPFUL", max = db().max, candidate = { includeSpellIDs = M.set } } }, db().size)
		if box then B:SetAuraBoxUnit(box, "player") end
	end
	if not box then
		local ev = CreateFrame("Frame")
		ev:RegisterUnitEvent("UNIT_AURA", "player")
		ev:RegisterEvent("PLAYER_ENTERING_WORLD")
		ev:SetScript("OnEvent", B.Safe(Scan))
	end

	-- follow the player frame when it moves or changes size
	local UF = B:GetModule("UnitFrames")
	if UF and UF.LayoutFrame then
		hooksecurefunc(UF, "LayoutFrame", function(_, key) if key == "player" then M:Layout() end end)
	end
	hooksecurefunc(B.Movers, "Apply", function(_, name) if name == "defensives" or name == "uf_player" then M:Attach() end end)
	hooksecurefunc(B.Movers, "ApplyAll", function() M:Attach() end)
	B:RegisterCallback("MOVERS_TOGGLED", function() M:Preview() end)
	B:RegisterCallback("PREVIEW", function() M:Preview() end)
	self:Layout()
end

function M:Update()
	if holder then self:Layout() end
end
