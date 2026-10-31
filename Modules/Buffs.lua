--[[
	BitsjUI - Player buffs & debuffs
	A row of your buffs (and one of debuffs) next to the minimap, time left
	under each icon, right-click to cancel. Built on Blizzard's AuraContainer
	(12.1+), so the client keeps them correct in combat. Blizzard's own buff
	frame is hidden while this is on.
]]
local _, B = ...
local M = B:NewModule("Buffs")

local function db() return B.db.buffs end

local anchor, buffBox, debuffBox

-- a year: anything with a real timer passes, permanent (0) auras don't
local TIMED = 365 * 24 * 3600

-- permanent buffs that should still show while collapsed (spell IDs).
-- Paladin auras by default; more can be added in /bui -> Buffs.
function M.KeepSet()
	local set = {}
	for id in tostring(db().alwaysShow or ""):gmatch("%d+") do set[tonumber(id)] = true end
	return set
end

function M.OthersFilter()
	-- the "always show" ones live in their own group, so never twice
	local f = { excludeSpellIDs = M.KeepSet() }
	if db().collapsePassive then f.maxDuration = TIMED end
	return f
end

function M:Layout()
	local d = db()
	local step = d.size + d.spacing
	buffBox:ClearAllPoints()
	buffBox:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
	buffBox:SetSize(d.perRow * step, d.size)
	B:SetAuraBoxFlow(buffBox, "TOPRIGHT", "Left", "Down")
	-- active buffs (ones you can cancel: food, flasks, auras, procs...) always;
	-- the passive open-world ones (warband / zone / faction) only when expanded
	local n = d.enabled and d.maxBuffs or 0
	if d.collapse then
		B:SetAuraGroupCandidate(buffBox, "keep", { includeSpellIDs = M.KeepSet() })
		B:SetAuraGroupCandidate(buffBox, "buffs", M.OthersFilter())
	end
	B:UpdateAuraBox(buffBox, d.size, { buffs = n, keep = d.enabled and 8 or 0 })
	debuffBox:ClearAllPoints()
	debuffBox:SetPoint("TOPRIGHT", buffBox, "BOTTOMRIGHT", 0, -(d.fontSize + 10) * math.ceil(d.maxBuffs / d.perRow))
	debuffBox:SetSize(d.perRow * step, d.size)
	B:SetAuraBoxFlow(debuffBox, "TOPRIGHT", "Left", "Down")
	B:UpdateAuraBox(debuffBox, d.size, { debuffs = d.enabled and d.maxDebuffs or 0 })
	anchor:SetSize(d.perRow * step, d.size)
	buffBox:SetShown(d.enabled)
	debuffBox:SetShown(d.enabled)
	B:SetMoverEnabled("buffs", d.enabled)
	B.Movers:Apply("buffs")
end

local function HideBlizzard()
	if not db().hideBlizzard then return end
	B:RunOOC("hide_bufframe", function()
		for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
			local f = _G[name]
			if f and not f.bHidden then
				f.bHidden = true
				f:SetParent(B.hiddenParent)
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Classic clients: no AuraContainer, so Blizzard's SecureAuraHeaderTemplate
-- builds and orders the buttons (it works in combat), right-click cancels
-- through the secure "cancelaura" action. We only draw the looks.
-------------------------------------------------------------------------------
local headers = {}

local function StyleSecure(btn)
	if btn.bStyled then return end
	btn.bStyled = true
	local d = db()
	btn.edge = btn:CreateTexture(nil, "BACKGROUND")
	btn.edge:SetAllPoints()
	btn.edge:SetColorTexture(0, 0, 0, 1)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 1, -1)
	btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	B:SkinIcon(btn.icon, btn)
	btn.count = btn:CreateFontString(nil, "OVERLAY")
	B:SetFont(btn.count, math.max(8, math.floor(d.size * 0.40)))
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 1)
	btn.time = btn:CreateFontString(nil, "OVERLAY")
	B:SetFont(btn.time, d.fontSize)
	btn.time:SetPoint("TOP", btn, "BOTTOM", 0, -2)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		local slot = self:GetAttribute("target-slot")
		if slot then
			GameTooltip:SetInventoryItem("player", slot)
		else
			GameTooltip:SetUnitAura("player", self:GetID(), self:GetAttribute("filter"))
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function UpdateSecure(btn)
	if not btn.bStyled then StyleSecure(btn) end
	local slot = btn:GetAttribute("target-slot")
	if slot then
		-- weapon oil / poison / sharpening stone
		local hasMH, mhExp, mhCharges, _, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
		local mh = slot == GetInventorySlotInfo("MainHandSlot")
		btn.icon:SetTexture(GetInventoryItemTexture("player", slot))
		local charges = mh and mhCharges or ohCharges
		btn.count:SetText(charges and charges > 1 and charges or "")
		local left
		if mh then left = hasMH and mhExp else left = hasOH and ohExp end
		btn.bExpires = left and GetTime() + left / 1000 or nil
		btn.edge:SetColorTexture(0.6, 0.2, 0.9, 1)
		return
	end
	local index = btn:GetAttribute("index")
	local aura = index and B.GetAura("player", index, btn:GetAttribute("filter"))
	if not aura then btn.bExpires = nil; return end
	btn.icon:SetTexture(aura.icon)
	local n = aura.applications or 0
	btn.count:SetText(n > 1 and n or "")
	local exp = aura.expirationTime or 0
	btn.bExpires = (aura.duration or 0) > 0 and exp > 0 and exp or nil
	local c = btn:GetAttribute("filter") == "HARMFUL" and DebuffTypeColor and DebuffTypeColor[aura.dispelName or "none"]
	if c then btn.edge:SetColorTexture(c.r, c.g, c.b, 1) else btn.edge:SetColorTexture(0, 0, 0, 1) end
end

-- template OnLoad (Core/Templates.xml)
function BitsjUI_AuraButtonOnLoad(btn)
	StyleSecure(btn)
	if not InCombatLockdown() then btn:SetSize(db().size, db().size) end
	btn:HookScript("OnAttributeChanged", function(self, name)
		if name == "index" or name == "target-slot" or name == "filter" then UpdateSecure(self) end
	end)
end

local function EachButton(func)
	for _, h in ipairs(headers) do
		for i = 1, 40 do
			local b = h:GetAttribute("child" .. i)
			if not b then break end
			func(b)
		end
		for i = 1, 2 do
			local b = h:GetAttribute("tempEnchant" .. i)
			if b then func(b) end
		end
	end
end

local function Header(name, filter, weapons)
	local d = db()
	local h = CreateFrame("Frame", name, anchor, "SecureAuraHeaderTemplate")
	h:SetAttribute("unit", "player")
	h:SetAttribute("filter", filter)
	h:SetAttribute("template", "BitsjUIAuraTemplate")
	if weapons then
		h:SetAttribute("includeWeapons", 1)
		h:SetAttribute("weaponTemplate", "BitsjUIAuraTemplate")
	end
	h:SetAttribute("sortMethod", "TIME")
	h:SetAttribute("sortDirection", "-")
	h:SetAttribute("separateOwn", 0)
	headers[#headers + 1] = h
	return h
end

function M:LayoutSecure()
	local d = db()
	local step = d.size + d.spacing
	local rowH = d.size + d.fontSize + 10
	B:RunOOC("buffs_layout", function()
		for i, h in ipairs(headers) do
			h:SetAttribute("point", "TOPRIGHT")
			h:SetAttribute("xOffset", -step)
			h:SetAttribute("yOffset", 0)
			h:SetAttribute("wrapAfter", d.perRow)
			h:SetAttribute("wrapXOffset", 0)
			h:SetAttribute("wrapYOffset", -rowH)
			h:SetAttribute("maxWraps", math.max(1, math.ceil((i == 1 and d.maxBuffs or d.maxDebuffs) / d.perRow)))
			h:SetAttribute("minWidth", d.perRow * step)
			h:SetAttribute("minHeight", d.size)
			h:SetSize(d.perRow * step, d.size)
		end
		local buffs, debuffs = headers[1], headers[2]
		buffs:ClearAllPoints()
		buffs:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
		debuffs:ClearAllPoints()
		debuffs:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -rowH * math.ceil(d.maxBuffs / d.perRow) - 6)
		EachButton(function(b) b:SetSize(d.size, d.size) end)
		for _, h in ipairs(headers) do h:SetShown(d.enabled) end
	end)
	EachButton(function(b)
		if b.count then B:SetFont(b.count, math.max(8, math.floor(d.size * 0.40))) end
		if b.time then B:SetFont(b.time, d.fontSize) end
	end)
	anchor:SetSize(d.perRow * step, d.size)
	B:SetMoverEnabled("buffs", d.enabled)
	B.Movers:Apply("buffs")
end

function M:EnableSecure()
	local d = db()
	Header("BitsjUIBuffHeader", "HELPFUL", true)
	Header("BitsjUIDebuffHeader", "HARMFUL")
	-- countdown under each icon
	local t = 0
	anchor:SetScript("OnUpdate", function(_, elapsed)
		t = t + elapsed
		if t < 0.1 then return end
		t = 0
		local now = GetTime()
		EachButton(function(b)
			if b.time and b:IsShown() then b.time:SetText(b.bExpires and B.FormatTime(b.bExpires - now) or "") end
		end)
	end)
	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_AURA", "player")
	ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
	ev:SetScript("OnEvent", function() EachButton(function(b) if b:IsShown() then UpdateSecure(b) end end) end)
	self.secure = true
	self:LayoutSecure()
	for _, h in ipairs(headers) do h:Show() end
	HideBlizzard()
end

function M:OnEnable()
	if not db().enabled then return end
	if not B:HasAuraContainers() then
		local d = db()
		anchor = CreateFrame("Frame", "BitsjUIBuffs", UIParent)
		anchor:SetSize(d.perRow * (d.size + d.spacing), d.size)
		B:RegisterMover(anchor, "buffs", "Buffs", { "TOPRIGHT", "TOPRIGHT", -250, -10 })
		return self:EnableSecure()
	end
	local d = db()
	anchor = CreateFrame("Frame", "BitsjUIBuffs", UIParent)
	anchor:SetSize(d.perRow * (d.size + d.spacing), d.size)
	B:RegisterMover(anchor, "buffs", "Buffs", { "TOPRIGHT", "TOPRIGHT", -250, -10 })

	local style = { durationBelow = true, cancel = true, fontSize = d.fontSize }
	local groups
	if d.collapse then
		-- "keep": permanent buffs you always want (paladin auras...);
		-- "buffs": everything else, and only timed buffs while collapsed
		-- (Blizzard's maxDuration filter drops zone / warband / faction buffs)
		groups = {
			{ key = "keep", filter = "HELPFUL", max = 8, style = style,
				candidate = { includeSpellIDs = M.KeepSet() } },
			{ key = "buffs", filter = "HELPFUL", max = d.maxBuffs, style = style,
				candidate = M.OthersFilter() },
		}
	else
		groups = { { key = "buffs", filter = "HELPFUL", max = d.maxBuffs, style = style } }
	end
	buffBox = B:CreateAuraBox(anchor, groups, d.size)

	debuffBox = B:CreateAuraBox(anchor, { { key = "debuffs", filter = "HARMFUL", max = d.maxDebuffs, style = { durationBelow = true, fontSize = d.fontSize } } }, d.size)
	if not buffBox or not debuffBox then return end
	B:SetAuraBoxUnit(buffBox, "player")
	B:SetAuraBoxUnit(debuffBox, "player")
	self:Layout()
	HideBlizzard()
end

function M:Update()
	if self.secure then return self:LayoutSecure() end
	if not buffBox then return end
	self:Layout()
end
