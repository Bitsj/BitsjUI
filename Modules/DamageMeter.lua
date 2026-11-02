--[[
	BitsjUI - Damage meter
	Up to three meter windows built on Blizzard's C_DamageMeter data (Midnight
	no longer gives addons a combat log). Values are secret during combat, so
	bars and numbers go straight into widgets / AbbreviateNumbers, which accept
	them. Percentages and chat reports need plain numbers and appear after
	combat.
]]
local _, B = ...
local M = B:NewModule("DamageMeter")

-- fonts: this file uses the "meter" section font (/bui > General > Fonts)
local FONT_SECTION = "meter"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end
M.windows = {}
local bd   -- breakdown window (created on first use)

local issecret = B.IsSecret
local DM = _G.C_DamageMeter

M.TYPES = {
	{ value = 0, label = "Damage" },
	{ value = 1, label = "DPS" },
	{ value = 2, label = "Healing" },
	{ value = 3, label = "HPS" },
	{ value = 4, label = "Absorbs" },
	{ value = 5, label = "Interrupts" },
	{ value = 6, label = "Dispels" },
	{ value = 7, label = "Damage taken" },
	{ value = 8, label = "Avoidable damage taken" },
	{ value = 9, label = "Deaths" },
	{ value = 10, label = "Enemy damage taken" },
}
M.SESSIONS = {
	{ value = 1, label = "Current" },
	{ value = 0, label = "Overall" },
}
local PER_SECOND = { [1] = true, [3] = true }

local function TypeLabel(v)
	for _, t in ipairs(M.TYPES) do if t.value == v then return t.label end end
	return "?"
end

local function cfg(i) return B.db.meter.windows[i] end

-------------------------------------------------------------------------------
-- Formatting (secret safe)
-------------------------------------------------------------------------------
local function Short(v)
	if not issecret(v) and v == nil then return "" end
	if AbbreviateNumbers then
		local ok, r = pcall(AbbreviateNumbers, v)
		if ok and (issecret(r) or (type(r) == "string" and r ~= "")) then return r end
	end
	if issecret(v) then return v end
	if v >= 1e9 then return string.format("%.2fB", v / 1e9)
	elseif v >= 1e6 then return string.format("%.2fM", v / 1e6)
	elseif v >= 1e3 then return string.format("%.1fK", v / 1e3) end
	return string.format("%.0f", v)
end

local function Percent(part, total)
	if issecret(part) or issecret(total) or not part or not total or total <= 0 then return nil end
	return part / total * 100
end

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------
function M:Available()
	if not DM or not DM.GetCombatSessionFromType then return false end
	if DM.IsDamageMeterAvailable then
		local ok, available = pcall(DM.IsDamageMeterAvailable)
		if ok and available == false then return false end
	end
	return true
end

local function GetSession(c)
	if not DM then return nil end
	local ok, s
	if c.sessionID and DM.GetCombatSessionFromID then
		ok, s = pcall(DM.GetCombatSessionFromID, c.sessionID, c.meterType)
	else
		ok, s = pcall(DM.GetCombatSessionFromType, c.sessionType, c.meterType)
	end
	if ok and type(s) == "table" then return s end
end

local function SessionLabel(c)
	if c.sessionID then return c.sessionName or ("Fight " .. c.sessionID) end
	for _, s in ipairs(M.SESSIONS) do if s.value == c.sessionType then return s.label end end
	return ""
end

local function SessionOptions()
	local out = {}
	for _, s in ipairs(M.SESSIONS) do out[#out + 1] = { value = "type:" .. s.value, label = s.label } end
	if DM and DM.GetAvailableCombatSessions then
		local ok, list = pcall(DM.GetAvailableCombatSessions)
		if ok and type(list) == "table" then
			for i = #list, 1, -1 do
				local s = list[i]
				local name = B.Plain(s.name, nil)
				local dur = B.Plain(s.durationSeconds, nil)
				local id = B.Plain(s.sessionID, nil)
				if id then
					local label = (name or ("Fight " .. id))
					if dur then label = label .. string.format("  (%d:%02d)", math.floor(dur / 60), dur % 60) end
					out[#out + 1] = { value = "id:" .. id, label = label, name = name }
				end
			end
		end
	end
	return out
end

-- pick a segment by its menu value ("type:1", "id:12")
function M:SetSegment(win, value)
	local c = cfg(win.id)
	local kind, v = value:match("^(%a+):(%d+)$")
	if kind == "type" then
		c.sessionID, c.sessionName = nil, nil
		c.sessionType = tonumber(v)
	else
		c.sessionID = tonumber(v)
		for _, o in ipairs(SessionOptions()) do if o.value == value then c.sessionName = o.name or o.label end end
	end
	win.offset = 0
	self:Refresh(win)
	if bd and bd:IsShown() and bd.win == win then self:RefreshBreakdown() end
end

local function CurrentValue(c)
	if c.sessionID then return "id:" .. c.sessionID end
	return "type:" .. c.sessionType
end

-- step through Current, Overall, then older fights (and around)
function M:StepSegment(win, dir)
	local list = SessionOptions()
	if #list == 0 then return end
	local cur = CurrentValue(cfg(win.id))
	local idx = 1
	for i, o in ipairs(list) do if o.value == cur then idx = i end end
	idx = ((idx - 1 + dir) % #list) + 1
	self:SetSegment(win, list[idx].value)
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
local function CreateRow(win, i)
	local row = B:SoftBar(CreateFrame("StatusBar", nil, win.content))
	row:EnableMouse(true)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.left = row:CreateFontString(nil, "OVERLAY")
	row.right = row:CreateFontString(nil, "OVERLAY")
	row.left:SetJustifyH("LEFT")
	row.left:SetWordWrap(false)
	row.right:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", function(self) M:ShowTooltip(win, self) end)
	row:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.rank then M:OpenBreakdown(win, self.rank)
		elseif button == "RightButton" then M:StepSegment(win, 1) end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	win.rows[i] = row
	return row
end

local function StyleRow(win, row, i)
	local c = cfg(win.id)
	local tex = (c.texture ~= "" and c.texture) or nil
	row:SetStatusBarTexture(B:GetTexture(tex))
	row.bg:SetTexture(B:GetTexture(tex))
	row:SetHeight(c.barHeight)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * (c.barHeight + c.barSpacing))
	row:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, -(i - 1) * (c.barHeight + c.barSpacing))
	local font = GetFont()
	row.left:SetFont(font, c.fontSize, B:GetOutline())
	row.right:SetFont(font, c.fontSize, B:GetOutline())
	row.icon:SetSize(c.barHeight, c.barHeight)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetShown(c.showIcons)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", row, "LEFT", c.showIcons and (c.barHeight + 4) or 4, 0)
	row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
end

local function FillRow(win, row, src, rank, session)
	local c = cfg(win.id)
	local perSec = PER_SECOND[c.meterType]
	-- never use and/or on these values: they can be hidden in combat
	local value
	if perSec then value = src.amountPerSecond else value = src.totalAmount end
	row.src = src
	row.rank = rank

	-- bar length: relative to the top entry (the list is sorted by the client)
	local top = session.combatSources[1]
	local max = 1
	if top then
		if perSec then max = top.amountPerSecond else max = top.totalAmount end
	end
	pcall(row.SetMinMaxValues, row, 0, max)
	if not pcall(row.SetValue, row, value) then row:SetValue(0) end

	-- colours
	local class = B.Plain(src.classFilename, nil)
	local r, g, b = 0.5, 0.5, 0.55
	if c.classColors and class then r, g, b = B:ClassColor(class) end
	row:SetStatusBarColor(r, g, b, c.barAlpha)
	row.bg:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, c.barBgAlpha)

	-- icon: spec icon if known, else class icon
	if c.showIcons then
		local spec = B.Plain(src.specIconID, nil)
		if spec and spec ~= 0 then
			row.icon:SetTexture(spec)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		elseif class then
			B:ClassIcon(row.icon, class)
		else
			row.icon:SetTexture(nil)
		end
	end

	-- left: rank + name
	local name = src.name
	if not issecret(name) and type(name) == "string" then
		name = name:gsub("%-.+$", "")
	end
	local leftOK
	if c.showRank then
		leftOK = pcall(row.left.SetFormattedText, row.left, "%d. %s", rank, name)
	else
		leftOK = pcall(row.left.SetText, row.left, name)
	end
	if not leftOK then row.left:SetText(c.showRank and (rank .. ".") or "") end
	-- always white: the bar behind is already in the class colour
	row.left:SetTextColor(1, 1, 1)

	-- right: amount (per second) [percent]
	local total, persec = Short(src.totalAmount), Short(src.amountPerSecond)
	local pct = c.showPercent and Percent(src.totalAmount, session.totalAmount) or nil
	local fmt = c.textFormat
	local ok
	if c.meterType == 9 then
		ok = pcall(row.right.SetText, row.right, "")
	elseif fmt == "total" then
		ok = pct and pcall(row.right.SetFormattedText, row.right, "%s  %.1f%%", total, pct) or pcall(row.right.SetFormattedText, row.right, "%s", total)
	elseif fmt == "persec" then
		ok = pct and pcall(row.right.SetFormattedText, row.right, "%s  %.1f%%", persec, pct) or pcall(row.right.SetFormattedText, row.right, "%s", persec)
	else
		if perSec then total, persec = persec, total end
		ok = pct and pcall(row.right.SetFormattedText, row.right, "%s (%s)  %.1f%%", total, persec, pct)
			or pcall(row.right.SetFormattedText, row.right, "%s (%s)", total, persec)
	end
	if not ok then row.right:SetText("") end
	row:Show()
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
function M:Refresh(win)
	local c = cfg(win.id)
	if not c.enabled or not win:IsShown() then return end
	local rowsFit = math.max(1, math.floor((win.content:GetHeight() + c.barSpacing) / (c.barHeight + c.barSpacing)))

	win.title:SetFormattedText("%s  -  %s", TypeLabel(c.meterType), SessionLabel(c))

	if not self:Available() then
		for _, row in ipairs(win.rows) do row:Hide() end
		win.notice:SetText("Turn on Blizzard's damage meter\n(Options > Gameplay > Combat)")
		win.notice:Show()
		return
	end

	local session = GetSession(c)
	local sources = session and session.combatSources
	local count = (type(sources) == "table") and #sources or 0
	win.notice:SetShown(count == 0)
	win.notice:SetText("No data yet")

	-- find the local player for "always show me"
	local meIndex
	if c.alwaysShowMe and count > 0 then
		for i = 1, count do
			if B.Plain(sources[i].isLocalPlayer, false) then meIndex = i; break end
		end
	end

	win.offset = B.Clamp(win.offset or 0, 0, math.max(0, count - rowsFit))
	for i = 1, rowsFit do
		local row = win.rows[i] or CreateRow(win, i)
		StyleRow(win, row, i)
		local index = i + win.offset
		if i == rowsFit and meIndex and (meIndex > rowsFit + win.offset or meIndex <= win.offset) then
			index = meIndex
		end
		local src = sources and sources[index]
		if src then FillRow(win, row, src, index, session) else row:Hide() end
	end
	for i = rowsFit + 1, #win.rows do win.rows[i]:Hide() end
	win.lastSession = session
end

function M:ApplyVisibility(win)
	local c = cfg(win.id)
	local show = c.enabled and B.db.meter.enabled
	if show and c.visibility == "combat" then show = InCombatLockdown() or (UnitAffectingCombat and B.Plain(UnitAffectingCombat("player"), false)) end
	if show and c.visibility == "group" then show = IsInGroup() end
	if B.Movers.unlocked and c.enabled then show = true end
	win:SetShown(show and true or false)
	if c.fadeOOC and not InCombatLockdown() then win:SetAlpha(c.fadeAlpha) else win:SetAlpha(1) end
end

function M:Layout(win)
	local c = cfg(win.id)
	win:SetSize(c.width, c.height)
	local pr, pg, pb = B:PanelColor()
	win.bg:SetColorTexture(pr * 0.8, pg * 0.8, pb * 0.8, c.bgAlpha)
	local titleH = c.showTitle and 22 or 0
	win.titleBar:SetShown(c.showTitle)
	win.titleBar:SetHeight(math.max(1, titleH))
	win.content:ClearAllPoints()
	win.content:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -(titleH + 2))
	win.content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
	win.title:SetFont(GetFont(), 12, B:Flags(""))
	for _, b in ipairs(win.buttons) do b.text:SetFont(GetFont(), 12, B:Flags("")) end
	win.notice:SetFont(GetFont(), 12, B:Flags(""))
	B:SetMoverEnabled("meter" .. win.id, c.enabled)
	B.Movers:Apply("meter" .. win.id)
	self:ApplyVisibility(win)
	self:Refresh(win)
end

local function TitleButton(win, text, tooltip, onClick)
	local b = CreateFrame("Button", nil, win.titleBar)
	b:SetSize(20, 20)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFont(GetFont(), 12, B:Flags(""))
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b.text:SetTextColor(0.7, 0.72, 0.75)
	b:SetScript("OnEnter", function(self)
		self.text:SetTextColor(B:AccentColor())
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tooltip, 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.72, 0.75); GameTooltip:Hide() end)
	b:SetScript("OnClick", onClick)
	win.buttons[#win.buttons + 1] = b
	return b
end

local function CreateWindow(i)
	local win = CreateFrame("Frame", "BitsjUIMeter" .. i, UIParent)
	win.id = i
	win.rows, win.buttons = {}, {}
	win:SetFrameStrata("LOW")
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:SetResizable(true)
	if win.SetResizeBounds then win:SetResizeBounds(140, 60, 900, 900) end
	win:EnableMouseWheel(true)

	win.bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
	win.bg:SetAllPoints()
	B:CreateBorder(win, 0, 0, 0, 1)

	-- title bar (drag to move, buttons for mode / segment / reset / report)
	local tb = CreateFrame("Frame", nil, win)
	tb:SetPoint("TOPLEFT")
	tb:SetPoint("TOPRIGHT")
	tb:EnableMouse(true)
	tb:RegisterForDrag("LeftButton")
	tb:SetScript("OnDragStart", function() if not InCombatLockdown() then win:StartMoving() end end)
	tb:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		B.Movers:SaveFrame("meter" .. i)
	end)
	local tbg = tb:CreateTexture(nil, "BACKGROUND")
	tbg:SetAllPoints()
	local tr, tg, tb2 = B:PanelColor()
	tbg:SetColorTexture(tr + 0.03, tg + 0.035, tb2 + 0.045, 1)
	local line = tb:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	win.titleBar = tb

	win.title = tb:CreateFontString(nil, "OVERLAY")
	win.title:SetPoint("LEFT", 6, 0)
	win.title:SetJustifyH("LEFT")
	win.title:SetWordWrap(false)

	local report = TitleButton(win, "R", "Report to chat", function(self) M:OpenReport(win, self) end)
	report:SetPoint("RIGHT", tb, "RIGHT", -2, 0)
	local reset = TitleButton(win, "X", "Reset all fights", function() StaticPopup_Show("BITSJUI_METER_RESET") end)
	reset:SetPoint("RIGHT", report, "LEFT", 0, 0)
	local seg = TitleButton(win, "S", "Choose fight (segment)", function(self)
		B.Widgets.OpenList(self, SessionOptions(), CurrentValue(cfg(i)), function(value) M:SetSegment(win, value) end, 240)
	end)
	seg:SetPoint("RIGHT", reset, "LEFT", 0, 0)
	local mode = TitleButton(win, "M", "Choose display", function(self)
		B.Widgets.OpenList(self, M.TYPES, cfg(i).meterType, function(value)
			cfg(i).meterType = value
			win.offset = 0
			M:Refresh(win)
		end, 200)
	end)
	mode:SetPoint("RIGHT", seg, "LEFT", 0, 0)
	local nextSeg = TitleButton(win, ">", "Next fight (or scroll the mouse wheel over the title)", function() M:StepSegment(win, 1) end)
	nextSeg:SetPoint("RIGHT", mode, "LEFT", -2, 0)
	local prevSeg = TitleButton(win, "<", "Previous fight", function() M:StepSegment(win, -1) end)
	prevSeg:SetPoint("RIGHT", nextSeg, "LEFT", 0, 0)
	win.title:SetPoint("RIGHT", prevSeg, "LEFT", -4, 0)
	tb:EnableMouseWheel(true)
	tb:SetScript("OnMouseWheel", function(_, delta) M:StepSegment(win, delta > 0 and -1 or 1) end)

	win.content = CreateFrame("Frame", nil, win)
	win.notice = win.content:CreateFontString(nil, "OVERLAY")
	win.notice:SetPoint("CENTER")
	win.notice:SetTextColor(0.6, 0.62, 0.66)

	-- resize grip
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(12, 12)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetFrameLevel(win:GetFrameLevel() + 10)
	local gt = grip:CreateTexture(nil, "OVERLAY")
	gt:SetAllPoints()
	gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetScript("OnMouseDown", function() if not InCombatLockdown() then win:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function()
		win:StopMovingOrSizing()
		local c = cfg(i)
		c.width, c.height = B.Round(win:GetWidth()), B.Round(win:GetHeight())
		B.Movers:SaveFrame("meter" .. i)
		M:Layout(win)
	end)
	win:SetScript("OnSizeChanged", function() M:Refresh(win) end)

	win:SetScript("OnMouseWheel", function(self, delta)
		self.offset = (self.offset or 0) - delta
		M:Refresh(self)
	end)

	win.elapsed = 0
	win:SetScript("OnUpdate", B.Safe(function(self, el)
		self.elapsed = self.elapsed + el
		local interval = InCombatLockdown() and B.db.meter.updateInterval or 1
		if self.elapsed < interval then return end
		self.elapsed = 0
		M:Refresh(self)
	end))

	M.windows[i] = win
	return win
end

-------------------------------------------------------------------------------
-- Spell breakdown data
-- C_DamageMeter.GetCombatSessionSource* only accepts a *hidden* GUID from
-- Blizzard's own code, so in combat we hand it a GUID we can read ourselves:
-- yours (isLocalPlayer is never hidden), or the group member with that class.
-------------------------------------------------------------------------------
local function GroupGUIDForClass(class)
	if not class then return end
	local found
	local prefix, n = "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
	if IsInRaid and IsInRaid() then prefix, n = "raid", GetNumGroupMembers() end
	for i = 1, n do
		local unit = prefix .. i
		local _, c = UnitClass(unit)
		if c == class and not B.Plain(UnitIsUnit(unit, "player"), false) then
			if found then return nil end   -- two of that class: can't tell them apart
			found = UnitGUID(unit)
		end
	end
	if found and not issecret(found) then return found end
end

function M:GetSourceDetail(c, src)
	if not DM or not src then return end
	local guid
	if B.Plain(src.isLocalPlayer, false) then
		guid = UnitGUID("player")
	elseif not issecret(src.sourceGUID) then
		guid = src.sourceGUID
	else
		guid = GroupGUIDForClass(B.Plain(src.classFilename, nil))
	end
	local creature = src.sourceCreatureID
	if issecret(creature) then creature = nil end
	if not guid and not creature then return nil, "hidden" end
	local ok, detail
	if c.sessionID and DM.GetCombatSessionSourceFromID then
		ok, detail = pcall(DM.GetCombatSessionSourceFromID, c.sessionID, c.meterType, guid, creature)
	elseif DM.GetCombatSessionSourceFromType then
		ok, detail = pcall(DM.GetCombatSessionSourceFromType, c.sessionType, c.meterType, guid, creature)
	end
	if ok and type(detail) == "table" and type(detail.combatSpells) == "table" then return detail end
end

-- spell name / icon accept hidden spell IDs (C_Spell allows them from addons)
local function SpellName(id)
	local md = B.MeterData
	if DM == md and md and md.names[id] then return md.names[id] end
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, id)
		if ok and (issecret(name) or name) then return name end
	end
	return "?"
end
local function SpellIcon(id)
	local md = B.MeterData
	if DM == md and md and md.icons[id] then return md.icons[id] end
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, id)
		if ok then return tex end
	end
end

-------------------------------------------------------------------------------
-- Tooltip: every spell (trinkets, racials, pets...) with icon and amount
-------------------------------------------------------------------------------
local TIP_MAX = 25

function M:ShowTooltip(win, row)
	local src = row.src
	if not src then return end
	local c = cfg(win.id)
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if not pcall(GameTooltip.AddDoubleLine, GameTooltip, src.name, Short(src.totalAmount), 1, 1, 1, 1, 1, 1) then
		GameTooltip:AddLine("#" .. row.rank, 1, 1, 1)
	end
	local detail, why = self:GetSourceDetail(c, src)
	local spells = detail and detail.combatSpells
	if type(spells) == "table" and #spells > 0 then
		local total = detail.totalAmount
		for idx = 1, math.min(TIP_MAX, #spells) do
			local sp = spells[idx]
			local name = SpellName(sp.spellID)
			local d = sp.combatSpellDetails
			local pet = d and B.Plain(d.isPet, false)
			local pct = Percent(sp.totalAmount, total)
			local right
			if pct then right = string.format("%s  |cff9a9aa0%.1f%%|r", Short(sp.totalAmount), pct) end
			local ok
			if pet then
				ok = pcall(GameTooltip.AddDoubleLine, GameTooltip, name, right or Short(sp.totalAmount), 0.75, 0.85, 1, 1, 1, 1)
			else
				ok = pcall(GameTooltip.AddDoubleLine, GameTooltip, name, right or Short(sp.totalAmount), 1, 0.92, 0.75, 1, 1, 1)
			end
			if ok then pcall(GameTooltip.AddTexture, GameTooltip, SpellIcon(sp.spellID)) end
		end
		if #spells > TIP_MAX then
			GameTooltip:AddLine(string.format("+ %d more", #spells - TIP_MAX), 0.6, 0.6, 0.65)
		end
	elseif why == "hidden" then
		GameTooltip:AddLine("Spell list for this player shows after combat.", 0.6, 0.6, 0.65, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click: full breakdown", 0.55, 0.8, 1)
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Breakdown window (Details-style): every spell of one player, live
-------------------------------------------------------------------------------
local function BDRow(i)
	local r = bd.rows[i]
	if r then return r end
	r = B:SoftBar(CreateFrame("StatusBar", nil, bd.list))
	r:EnableMouse(true)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.icon = r:CreateTexture(nil, "OVERLAY")
	B:SkinIcon(r.icon, r)
	r.name = r:CreateFontString(nil, "OVERLAY")
	r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
	r.amount = r:CreateFontString(nil, "OVERLAY")
	r.amount:SetJustifyH("RIGHT")
	r.extra = r:CreateFontString(nil, "OVERLAY")
	r.extra:SetJustifyH("RIGHT")
	for _, fs in ipairs({ r.name, r.amount, r.extra }) do fs:SetFont(GetFont(), 12, B:Flags("")) end
	r:SetScript("OnEnter", function(self)
		if not self.spellID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
			pcall(GameTooltip.AddLine, GameTooltip, SpellName(self.spellID), 1, 1, 1)
		end
		if self.target then
			pcall(GameTooltip.AddDoubleLine, GameTooltip, self.isPet and "Pet" or "Target", self.target, 0.6, 0.6, 0.65, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	bd.rows[i] = r
	return r
end

local function CreateBreakdown()
	bd = CreateFrame("Frame", "BitsjUIMeterBreakdown", UIParent)
	bd:SetSize(360, 360)
	bd:SetFrameStrata("MEDIUM")
	bd:SetClampedToScreen(true)
	bd:SetMovable(true)
	bd:EnableMouse(true)
	bd:EnableMouseWheel(true)
	bd:RegisterForDrag("LeftButton")
	bd:SetScript("OnDragStart", bd.StartMoving)
	bd:SetScript("OnDragStop", bd.StopMovingOrSizing)
	bd.rows = {}
	B:CreateBackdrop(bd, 0.92)
	tinsert(UISpecialFrames, "BitsjUIMeterBreakdown")   -- Esc closes it

	local head = CreateFrame("Frame", nil, bd)
	head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(34)
	local hbg = head:CreateTexture(nil, "BACKGROUND")
	local hr, hg, hb = B:PanelColor()
	hbg:SetAllPoints(); hbg:SetColorTexture(hr + 0.03, hg + 0.035, hb + 0.045, 1)
	local line = head:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
	bd.head = head
	bd.icon = head:CreateTexture(nil, "OVERLAY")
	bd.icon:SetSize(24, 24); bd.icon:SetPoint("LEFT", 6, 0)
	bd.title = head:CreateFontString(nil, "OVERLAY")
	bd.title:SetFont(GetFont(), 14, B:Flags(""))
	bd.title:SetPoint("TOPLEFT", bd.icon, "TOPRIGHT", 6, 0)
	bd.title:SetJustifyH("LEFT"); bd.title:SetWordWrap(false)
	bd.sub = head:CreateFontString(nil, "OVERLAY")
	bd.sub:SetFont(GetFont(), 11, B:Flags(""))
	bd.sub:SetPoint("BOTTOMLEFT", bd.icon, "BOTTOMRIGHT", 6, 0)
	bd.sub:SetJustifyH("LEFT"); bd.sub:SetTextColor(0.62, 0.64, 0.68)

	local function Btn(text, tip, onClick)
		local b = CreateFrame("Button", nil, head)
		b:SetSize(20, 20)
		b.text = b:CreateFontString(nil, "OVERLAY")
		b.text:SetFont(GetFont(), 13, B:Flags(""))
		b.text:SetPoint("CENTER"); b.text:SetText(text); b.text:SetTextColor(0.7, 0.72, 0.75)
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function(self)
			self.text:SetTextColor(B:AccentColor())
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip, 1, 1, 1); GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.72, 0.75); GameTooltip:Hide() end)
		return b
	end
	bd.close = Btn("X", "Close", function() bd:Hide() end)
	bd.close:SetPoint("RIGHT", -4, 0)
	bd.nextB = Btn(">", "Next player", function() M:BreakdownStep(1) end)
	bd.nextB:SetPoint("RIGHT", bd.close, "LEFT", -2, 0)
	bd.prevB = Btn("<", "Previous player", function() M:BreakdownStep(-1) end)
	bd.prevB:SetPoint("RIGHT", bd.nextB, "LEFT", 0, 0)
	bd.title:SetPoint("RIGHT", bd.prevB, "LEFT", -6, 0)

	bd.list = CreateFrame("Frame", nil, bd)
	bd.list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -4)
	bd.list:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -4, 18)
	bd.notice = bd.list:CreateFontString(nil, "OVERLAY")
	bd.notice:SetFont(GetFont(), 12, B:Flags(""))
	bd.notice:SetPoint("CENTER"); bd.notice:SetTextColor(0.6, 0.62, 0.66)
	bd.foot = bd:CreateFontString(nil, "OVERLAY")
	bd.foot:SetFont(GetFont(), 10, B:Flags(""))
	bd.foot:SetPoint("BOTTOMLEFT", 6, 4); bd.foot:SetTextColor(0.5, 0.52, 0.56)

	bd:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, (self.offset or 0) - delta * 2)
		M:RefreshBreakdown()
	end)
	bd.elapsed = 0
	bd:SetScript("OnUpdate", B.Safe(function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < (InCombatLockdown() and B.db.meter.updateInterval or 1) then return end
		self.elapsed = 0
		M:RefreshBreakdown()
	end))
	bd:Hide()
end

-- open for the player at <rank> in window <win>
function M:OpenBreakdown(win, rank)
	if not bd then CreateBreakdown() end
	bd.win, bd.rank, bd.offset = win, rank, 0
	if not bd.placed then
		bd.placed = true
		bd:ClearAllPoints()
		bd:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", -8, 0)
	end
	bd:Show()
	self:RefreshBreakdown()
end

function M:BreakdownStep(dir)
	if not bd or not bd.win then return end
	local session = GetSession(cfg(bd.win.id))
	local n = session and type(session.combatSources) == "table" and #session.combatSources or 0
	if n == 0 then return end
	bd.rank = ((bd.rank - 1 + dir) % n) + 1
	bd.offset = 0
	self:RefreshBreakdown()
end

function M:RefreshBreakdown()
	if not bd or not bd:IsShown() or not bd.win then return end
	local c = cfg(bd.win.id)
	local font, outline = GetFont(), B:GetOutline()
	bd.title:SetFont(font, 14, outline)
	bd.sub:SetFont(font, 11, B:Flags(""))
	bd.foot:SetFont(font, 10, B:Flags(""))
	bd.notice:SetFont(font, 12, B:Flags(""))
	for _, b in ipairs({ bd.close, bd.prevB, bd.nextB }) do b.text:SetFont(font, 13, B:Flags("")) end

	local session = GetSession(c)
	local src = session and type(session.combatSources) == "table" and session.combatSources[bd.rank]
	if not src then
		bd.title:SetText("No data"); bd.sub:SetText(""); bd.icon:SetTexture(nil)
		for _, r in ipairs(bd.rows) do r:Hide() end
		return
	end
	-- header
	if not pcall(bd.title.SetFormattedText, bd.title, "%d. %s", bd.rank, src.name) then bd.title:SetText("#" .. bd.rank) end
	local class = B.Plain(src.classFilename, nil)
	local cr, cg, cb = 0.8, 0.8, 0.85
	if class then cr, cg, cb = B:ClassColor(class) end
	bd.title:SetTextColor(cr, cg, cb)
	local spec = B.Plain(src.specIconID, nil)
	if spec and spec ~= 0 then bd.icon:SetTexture(spec); bd.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	elseif class then B:ClassIcon(bd.icon, class) else bd.icon:SetTexture(nil) end
	if not pcall(bd.sub.SetFormattedText, bd.sub, "%s  -  %s total  (%s/s)", TypeLabel(c.meterType), Short(src.totalAmount), Short(src.amountPerSecond)) then
		bd.sub:SetText(TypeLabel(c.meterType))
	end
	bd.foot:SetText(SessionLabel(c) .. "   -   mouse wheel scrolls, Esc closes")

	local detail, why = self:GetSourceDetail(c, src)
	local spells = detail and detail.combatSpells
	local n = type(spells) == "table" and #spells or 0
	bd.notice:SetShown(n == 0)
	bd.notice:SetText(why == "hidden" and "This player's spells show after combat." or "No spells yet")

	local h, sp = 18, 1
	local fit = math.max(1, math.floor((bd.list:GetHeight() + sp) / (h + sp)))
	bd.offset = math.max(0, math.min(bd.offset or 0, math.max(0, n - fit)))
	local max = detail and detail.maxAmount
	local tex = B:GetTexture((c.texture ~= "" and c.texture) or nil)
	for i = 1, fit do
		local r = BDRow(i)
		local spell = spells and spells[i + bd.offset]
		if spell then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", bd.list, "TOPLEFT", 0, -(i - 1) * (h + sp))
			r:SetPoint("TOPRIGHT", bd.list, "TOPRIGHT", 0, -(i - 1) * (h + sp))
			r:SetHeight(h)
			r:SetStatusBarTexture(tex); r.bg:SetTexture(tex)
			r:SetStatusBarColor(cr, cg, cb, 0.75)
			r.bg:SetVertexColor(cr * 0.2, cg * 0.2, cb * 0.2, 0.6)
			pcall(r.SetMinMaxValues, r, 0, max)
			if not pcall(r.SetValue, r, spell.totalAmount) then r:SetValue(0) end
			r.icon:SetSize(h, h); r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT")
			pcall(r.icon.SetTexture, r.icon, SpellIcon(spell.spellID))
			for _, fs in ipairs({ r.name, r.amount, r.extra }) do fs:SetFont(font, 12, outline) end
			r.extra:ClearAllPoints(); r.extra:SetPoint("RIGHT", -4, 0); r.extra:SetWidth(46)
			r.amount:ClearAllPoints(); r.amount:SetPoint("RIGHT", r.extra, "LEFT", -4, 0)
			r.name:ClearAllPoints(); r.name:SetPoint("LEFT", h + 4, 0); r.name:SetPoint("RIGHT", r.amount, "LEFT", -6, 0)
			local d = spell.combatSpellDetails
			r.isPet = d and B.Plain(d.isPet, false)
			r.target = d and d.unitName
			r.spellID = spell.spellID
			local name = SpellName(spell.spellID)
			local ok
			if r.isPet then
				ok = pcall(r.name.SetFormattedText, r.name, "%s |cff8fb4ff(%s)|r", name, d.unitName)
			end
			if not ok and not pcall(r.name.SetText, r.name, name) then r.name:SetText("?") end
			if not pcall(r.amount.SetFormattedText, r.amount, "%s (%s)", Short(spell.totalAmount), Short(spell.amountPerSecond)) then
				r.amount:SetText("")
			end
			local pct = Percent(spell.totalAmount, detail.totalAmount)
			r.extra:SetText(pct and string.format("%.1f%%", pct) or "")
			r:Show()
		else
			r:Hide()
		end
	end
	for i = fit + 1, #bd.rows do bd.rows[i]:Hide() end
end

-------------------------------------------------------------------------------
-- Report to chat (only possible when values are not secret, i.e. after combat)
-------------------------------------------------------------------------------
local CHANNELS = {
	{ value = "SAY", label = "Say" }, { value = "PARTY", label = "Party" }, { value = "RAID", label = "Raid" },
	{ value = "INSTANCE_CHAT", label = "Instance" }, { value = "GUILD", label = "Guild" },
}

function M:OpenReport(win, anchor)
	B.Widgets.OpenList(anchor, CHANNELS, nil, function(channel) M:Report(win, channel, 5) end, 140)
end

function M:Report(win, channel, lines)
	local c = cfg(win.id)
	local session = GetSession(c)
	local sources = session and session.combatSources
	if type(sources) ~= "table" or #sources == 0 then B:Print("No data to report."); return end
	if issecret(sources[1].totalAmount) then B:Print("You can report after combat (numbers are hidden in combat)."); return end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	send(string.format("BitsjUI: %s - %s", TypeLabel(c.meterType), SessionLabel(c)), channel)
	for i = 1, math.min(lines, #sources) do
		local s = sources[i]
		local name = B.Plain(s.name, "?")
		send(string.format("%d. %s  %s (%s)", i, name, Short(s.totalAmount), Short(s.amountPerSecond)), channel)
	end
end

StaticPopupDialogs["BITSJUI_METER_RESET"] = {
	text = "Reset all fights in the damage meter?",
	button1 = YES, button2 = NO,
	OnAccept = function()
		if DM and DM.ResetAllCombatSessions then pcall(DM.ResetAllCombatSessions) end
		for _, win in pairs(M.windows) do win.offset = 0; M:Refresh(win) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-------------------------------------------------------------------------------
-- Presets
-------------------------------------------------------------------------------
M.PRESETS = {
	{ value = "dark", label = "BitsjUI dark" },
	{ value = "classic", label = "Classic" },
	{ value = "minimal", label = "Minimal" },
}

function M:ApplyPreset(key)
	for i = 1, 3 do
		local c = cfg(i)
		if key == "dark" then
			c.bgAlpha, c.barAlpha, c.barBgAlpha = 0.85, 0.9, 0.35
			c.barHeight, c.barSpacing, c.fontSize = 20, 1, 12
			c.showTitle, c.showIcons, c.classColors, c.texture = true, true, true, ""
		elseif key == "classic" then
			c.bgAlpha, c.barAlpha, c.barBgAlpha = 0.6, 1, 0.2
			c.barHeight, c.barSpacing, c.fontSize = 16, 1, 11
			c.showTitle, c.showIcons, c.classColors, c.texture = true, true, true, "Blizzard"
		elseif key == "minimal" then
			c.bgAlpha, c.barAlpha, c.barBgAlpha = 0, 0.8, 0
			c.barHeight, c.barSpacing, c.fontSize = 16, 2, 11
			c.showTitle, c.showIcons, c.classColors, c.texture = false, false, true, "Flat"
		end
	end
	B.db.meter.preset = key
	self:Update()
end

-------------------------------------------------------------------------------
local function HideBlizzardMeter()
	if not B.db.meter.hideBlizzard then return end
	for _, name in ipairs({ "DamageMeter", "DamageMeterFrame" }) do
		local f = _G[name]
		if type(f) == "table" and f.SetAlpha and not f.bHidden then
			f.bHidden = true
			f:SetAlpha(0)
			pcall(f.EnableMouse, f, false)
		end
	end
end

local DEFAULTS = {
	[1] = { "BOTTOMRIGHT", "BOTTOMRIGHT", -8, 8 },
	[2] = { "BOTTOMRIGHT", "BOTTOMRIGHT", -296, 8 },
	[3] = { "BOTTOMRIGHT", "BOTTOMRIGHT", -8, 216 },
}

function M:OnEnable()
	if not B.db.meter.enabled then return end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_DamageMeter") end
	DM = _G.C_DamageMeter
	-- no Blizzard meter on this client (Classic): read the combat log ourselves
	if not self:Available() and B.MeterData and CombatLogGetCurrentEventInfo then
		DM = B.MeterData
		B.MeterData:Start()
		local keep = {}
		for _, t in ipairs(M.TYPES) do if DM.SUPPORTED[t.value] then keep[#keep + 1] = t end end
		M.TYPES = keep
		B:RegisterCallback("METER_DATA", function()
			for _, win in pairs(M.windows) do win.elapsed = math.max(win.elapsed or 0, 10) end
		end)
	end
	for i = 1, 3 do
		local win = CreateWindow(i)
		B:RegisterMover(win, "meter" .. i, "Damage meter " .. i, DEFAULTS[i])
		self:Layout(win)
	end
	HideBlizzardMeter()

	local function refreshAll()
		for _, win in pairs(M.windows) do M:ApplyVisibility(win); M:Refresh(win) end
	end
	-- like Details: a new fight jumps old-fight windows back to "Current"
	B:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if not B.db.meter.autoCurrent then return end
		for i, win in pairs(M.windows) do
			if cfg(i).sessionID then M:SetSegment(win, "type:1") end
		end
	end)
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		B:RegisterEvent(e, function() C_Timer.After(0.5, refreshAll) end)
	end
	-- Blizzard meter events (names may not exist on every build)
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function()
		for _, win in pairs(M.windows) do win.elapsed = math.max(win.elapsed, 10) end
	end)
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_DamageMeter" and DM ~= B.MeterData then DM = _G.C_DamageMeter; HideBlizzardMeter() end
	end)
	B:RegisterCallback("MOVERS_TOGGLED", refreshAll)
end

function M:Update()
	if not B.db.meter.enabled then return end
	HideBlizzardMeter()
	for _, win in pairs(self.windows) do self:Layout(win) end
end
