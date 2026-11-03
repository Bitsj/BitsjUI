--[[
	BitsjUI - Aura boxes
	Since 12.1 the client no longer lets addons scan auras reliably (aura data
	is hidden in combat). Working addons use Blizzard's AuraContainer instead:
	the client picks, draws and updates the auras for a unit + filter, and the
	addon only styles the buttons. That is what this file wraps.

	Blizzard API used (12.1+):
	  CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	  container:SetUnit(unit) / :SetEnabled(bool) / :UpdateAllAuras()
	  container:AddAuraGroup(key, filterString, { maxFrameCount, initializeFrame })
	  container:SetAuraGroupMaxFrameCount(key, n) / :SetAuraGroupFilterString(key, f)
	  container:GetAuraGroupFrameCount(key) / :GetAuraGroupFrame(key, i)
]]
local _, B = ...

function B:HasAuraContainers()
	if self.auraContainerOK ~= nil then return self.auraContainerOK end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	self.auraContainerOK = ok and type(c) == "table" and c.AddAuraGroup ~= nil and c.SetUnit ~= nil
	if ok and type(c) == "table" and c.Hide then c:Hide() end
	return self.auraContainerOK
end

-------------------------------------------------------------------------------
-- Button styling (only our own additions + safe cosmetic calls)
-------------------------------------------------------------------------------
local function Glow(frame, color)
	if frame.bGlow then
		frame.bGlow:SetShown(color ~= nil)
		if color then
			for _, t in ipairs(frame.bGlow.edges) do t:SetColorTexture(color.r, color.g, color.b, 1) end
		end
		return
	end
	if not color then return end
	local g = CreateFrame("Frame", nil, frame)
	g:SetFrameLevel(frame:GetFrameLevel() + 6)
	g:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
	g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
	g.edges = {}
	local p = 2
	local function edge(a1, a2, w, h)
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(color.r, color.g, color.b, 1)
		t:SetPoint(a1, g, a1)
		t:SetPoint(a2, g, a2)
		if w then t:SetWidth(w) else t:SetHeight(h) end
		g.edges[#g.edges + 1] = t
	end
	edge("TOPLEFT", "TOPRIGHT", nil, p)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, p)
	edge("TOPLEFT", "BOTTOMLEFT", p, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", p, nil)
	-- soft pulse
	local ag = g:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.6)
	a:SetSmoothing("IN_OUT")
	ag:SetLooping("BOUNCE")
	ag:Play()
	frame.bGlow = g
end

-- Aura buttons become forbidden for addon code once Blizzard has set them up,
-- so they can only be styled inside the group's initializeFrame callback.
-- Never touch them afterwards.
local function Forbidden(f)
	return type(f) ~= "table" or (f.IsForbidden and f:IsForbidden())
end

-- Blizzard's CustomAuraButton is an empty shell: we create the visual parts
-- and hand them over (SetIcon, SetDurationCooldown, ...). The client then
-- fills them in itself, also in combat.
-- hand a region to the button; failures are logged with the client's own
-- message (see /bui errors) instead of being swallowed
local function Give(frame, method, region, options)
	local fn = frame[method]
	if not fn then
		B:Error("AuraButton has no method " .. method)
		return false
	end
	local ok, err = pcall(fn, frame, region, options)
	if ok then return true end
	local ok2, err2 = pcall(fn, frame, region, {})
	if ok2 then return true end
	B:Error("AuraButton:" .. method .. " failed: " .. tostring(err) .. "  |  with {}: " .. tostring(err2))
	return false
end

local function BuildIcon(frame, size, glowColor, style)
	frame:SetSize(size, size)
	-- dispel-type coloured edge behind the icon (Blizzard colours it)
	local edge = frame:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0, 0, 0, 1)
	Give(frame, "AddDispelTypeTexture", edge)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	B:SkinIcon(icon, frame)
	Give(frame, "SetIcon", icon)
	local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.6) end
	Give(frame, "SetDurationCooldown", cd)
	local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
	if cdText then B:SetFont(cdText, math.max(8, math.floor(size * 0.42))) end
	local count = frame:CreateFontString(nil, "OVERLAY")
	B:SetFont(count, math.max(8, math.floor(size * 0.40)))
	count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, 1)
	count:SetParent(cd)   -- above the swipe
	Give(frame, "SetApplicationCount", count)
	-- time left under the icon (player buffs)
	if style and style.durationBelow then
		local dur = frame:CreateFontString(nil, "OVERLAY")
		B:SetFont(dur, style.fontSize or 11)
		dur:SetPoint("TOP", frame, "BOTTOM", 0, -2)
		Give(frame, "SetDurationText", dur)
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
	end
	-- right-click cancels (your own buffs)
	if style and style.cancel and frame.SetCancelAuraButtons then
		local ok, err = pcall(frame.SetCancelAuraButtons, frame, "RightButtonUp")
		if not ok then B:Error("AuraButton:SetCancelAuraButtons failed: " .. tostring(err)) end
	end
	Glow(frame, glowColor)
end

-- timer bar: icon | name ............ time, draining bar
local function BuildBar(frame, opts)
	local w, h, c = opts.width, opts.height, opts.color
	frame:SetSize(w, h)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(h, h)
	icon:SetPoint("LEFT")
	B:SkinIcon(icon, frame)
	Give(frame, "SetIcon", icon)
	local iconBorder = CreateFrame("Frame", nil, frame)
	iconBorder:SetAllPoints(icon)
	B:CreateBorder(iconBorder, 0, 0, 0, 1)

	local sb = CreateFrame("StatusBar", nil, frame)
	sb:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, 0)
	sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	sb:SetStatusBarTexture(B:GetTexture())
	sb:SetStatusBarColor(c.r, c.g, c.b)
	local bg = sb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(B:GetTexture())
	bg:SetVertexColor(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.85)
	B:CreateBorder(sb, 0, 0, 0, 1)
	Give(frame, "SetDurationBar", sb)

	local name = sb:CreateFontString(nil, "OVERLAY")
	B:SetFont(name, opts.fontSize)
	name:SetPoint("LEFT", sb, "LEFT", 6, 0)
	name:SetPoint("RIGHT", sb, "RIGHT", -40, 0)
	name:SetJustifyH("CENTER")
	name:SetWordWrap(false)
	Give(frame, "SetSpellName", name)

	local time = sb:CreateFontString(nil, "OVERLAY")
	B:SetFont(time, math.max(8, opts.fontSize - 2))
	time:SetPoint("RIGHT", sb, "RIGHT", -4, 0)
	Give(frame, "SetDurationText", time)

	local count = sb:CreateFontString(nil, "OVERLAY")
	B:SetFont(count, math.max(8, opts.fontSize - 2))
	count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	Give(frame, "SetApplicationCount", count)
end

-- style = nil (icon) or { bar = true, width, height, color, fontSize }
function B:StyleAuraFrame(frame, size, glowColor, style)
	if Forbidden(frame) or frame.bStyled then return end
	frame.bStyled = true
	local ok, err
	if style and style.bar then
		ok, err = pcall(BuildBar, frame, style)
	else
		ok, err = pcall(BuildIcon, frame, size, glowColor, style)
	end
	if not ok then B:Error(err) end
end

-------------------------------------------------------------------------------
-- Aura box: one container with one or more groups
-- groups = { { key = "debuffs", filter = "HARMFUL|PLAYER", max = 6, glow = color|nil }, ... }
-------------------------------------------------------------------------------
function B:CreateAuraBox(parent, groups, size)
	if not self:HasAuraContainers() then return nil end
	local ok, box = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or type(box) ~= "table" then return nil end
	box.bSize = size
	box.bGroups = groups
	for _, g in ipairs(groups) do
		local group = g
		local okg = pcall(box.AddAuraGroup, box, group.key, group.filter, {
			maxFrameCount = group.max,
			candidateFilters = group.candidate,
			initializeFrame = function(frame)
				B:StyleAuraFrame(frame, box.bSize, group.glow, group.style)
			end,
		})
		if not okg then B:Error("AuraContainer: could not add group " .. tostring(group.key)) end
	end
	-- bar boxes: one aura per line (stacked)
	for _, g in ipairs(groups) do
		if g.style and g.style.bar then
			pcall(box.SetFlowLayoutMaximumLineSize, box, 1)
			break
		end
	end
	pcall(box.SetEnabled, box, true)
	return box
end

-- apply max counts after a settings change. Button size and glow only
-- apply to new buttons (existing ones are locked), so those need a /reload.
-- Blizzard's extra per-group filters (see Blizzard_CustomAuraContainer.lua:
-- maxDuration hides permanent auras, isFromPlayerOrPlayerPet, spell ID lists...)
function B:SetAuraGroupCandidate(box, key, filters)
	if not box or Forbidden(box) then return end
	local ok, err = pcall(box.SetAuraGroupCandidateFilters, box, key, filters)
	if not ok then B:Error("AuraContainer:SetAuraGroupCandidateFilters failed: " .. tostring(err)) end
end

function B:UpdateAuraBox(box, size, maxByKey)
	if not box or Forbidden(box) then return end
	for _, g in ipairs(box.bGroups) do
		local max = maxByKey and maxByKey[g.key]
		if max then
			g.max = max
			pcall(box.SetAuraGroupMaxFrameCount, box, g.key, max)
			pcall(box.SetAuraGroupEnabled, box, g.key, max > 0)
		end
	end
	pcall(box.UpdateAllAuras, box)
end

-- Flow layout: where the first aura sits and which way the rest grow.
-- The direction values come from Blizzard's own AnchorUtil.FlowDirection
-- table (looked up by name in-game, so nothing is hard-coded).
local function FlowValue(name)
	local t = AnchorUtil and AnchorUtil.FlowDirection
	if type(t) ~= "table" then return nil end
	for k, v in pairs(t) do
		if type(k) == "string" and k:lower() == name:lower() then return v end
	end
end

function B:SetAuraBoxFlow(box, anchorPoint, horizontal, vertical, spacing)
	if not box or Forbidden(box) then return end
	if anchorPoint then pcall(box.SetFlowLayoutAnchorPoint, box, anchorPoint) end
	if horizontal or vertical then
		local h, v = FlowValue(horizontal or "Right"), FlowValue(vertical or "Down")
		if h ~= nil and v ~= nil then
			local ok, err = pcall(box.SetFlowLayoutGrowthDirection, box, h, v)
			if not ok then B:Error("AuraContainer:SetFlowLayoutGrowthDirection failed: " .. tostring(err)) end
		end
	end
	if spacing then pcall(box.SetFlowLayoutPadding, box, 0, spacing, 0, spacing) end
end

-- Blizzard's aura containers don't notice when "target" / "focus" point at
-- another unit: they keep the old unit's auras (frozen bars, debuffs from
-- earlier targets). So every box on such a unit is refreshed on change.
local watched = setmetatable({}, { __mode = "k" })   -- box -> unit token
local REFRESH = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }
local watcher
local function Refresh(token)
	for box, unit in pairs(watched) do
		local hit = unit == token or (token == "target" and unit == "targettarget")
			or (token == "group" and type(unit) == "string" and (unit:find("^party") or unit:find("^raid")))
		if hit then
			if not Forbidden(box) then
				pcall(box.SetUnit, box, nil)
				pcall(box.SetUnit, box, unit)
				pcall(box.UpdateAllAuras, box)
			end
		end
	end
end

function B:SetAuraBoxUnit(box, unit)
	if not box or Forbidden(box) then return end
	pcall(box.SetUnit, box, unit)
	pcall(box.UpdateAllAuras, box)
	watched[box] = unit
	if not watcher then
		watcher = CreateFrame("Frame")
		for _, e in pairs(REFRESH) do pcall(watcher.RegisterEvent, watcher, e) end
		pcall(watcher.RegisterUnitEvent, watcher, "UNIT_TARGET", "target")
		pcall(watcher.RegisterEvent, watcher, "GROUP_ROSTER_UPDATE")
		watcher:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_TARGET_CHANGED" then Refresh("target")
			elseif event == "PLAYER_FOCUS_CHANGED" then Refresh("focus")
			elseif event == "UNIT_TARGET" then Refresh("targettarget")
			elseif event == "GROUP_ROSTER_UPDATE" then Refresh("group") end   -- party1 can be someone else now
		end)
	end
end

-------------------------------------------------------------------------------
-- Scanned auras (Classic clients have no AuraContainer; aura data is plain there)
-------------------------------------------------------------------------------
-- the client only knows a few filter words; Midnight-only ones are mapped/dropped
local FILTER_WORDS = { HELPFUL = true, HARMFUL = true, PLAYER = true, RAID = true, CANCELABLE = true, NOT_CANCELABLE = true, INCLUDE_NAME_PLATE_ONLY = true }
function B.ClassicFilter(filter)
	local out = {}
	for word in tostring(filter or "HELPFUL"):gmatch("[^|]+") do
		if word == "RAID_IN_COMBAT" then word = "RAID" end
		if FILTER_WORDS[word] then out[#out + 1] = word end
	end
	return table.concat(out, "|")
end

-- one aura as a table (C_UnitAuras when present, old UnitAura otherwise)
function B.GetAura(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
		if ok then return type(a) == "table" and a or nil end
	end
	if not UnitAura then return end
	local name, icon, count, dispel, duration, expires, source, steal, _, spellId = UnitAura(unit, index, filter)
	if not name then return end
	return { name = name, icon = icon, applications = count, dispelName = dispel, duration = duration,
		expirationTime = expires, sourceUnit = source, isStealable = steal, spellId = spellId }
end

function B.FormatTime(s)
	if not s or s <= 0 then return "" end
	if s >= 3600 then return string.format("%dh", math.ceil(s / 3600)) end
	if s >= 60 then return string.format("%dm", math.ceil(s / 60)) end
	if s >= 10 then return string.format("%d", math.floor(s)) end
	return string.format("%.1f", s)
end

-- plain icon for scanned auras: icon, swipe, stack count, coloured edge
function B:CreateAuraIcon(parent, size)
	local btn = CreateFrame("Frame", nil, parent)
	btn:SetSize(size, size)
	btn.edge = btn:CreateTexture(nil, "BACKGROUND")
	btn.edge:SetAllPoints()
	btn.edge:SetColorTexture(0, 0, 0, 1)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 1, -1)
	btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	B:SkinIcon(btn.icon, btn)
	btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	btn.cd:SetAllPoints(btn.icon)
	btn.cd:SetReverse(true)
	btn.cd:SetDrawEdge(false)
	if btn.cd.SetHideCountdownNumbers then btn.cd:SetHideCountdownNumbers(size < 16) end
	local cdText = btn.cd.GetCountdownFontString and btn.cd:GetCountdownFontString()
	if cdText then B:SetFont(cdText, math.max(8, math.floor(size * 0.42))) end
	btn.count = btn.cd:CreateFontString(nil, "OVERLAY")
	B:SetFont(btn.count, math.max(8, math.floor(size * 0.40)))
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 1)
	btn:EnableMouse(false)
	return btn
end

function B:SetAuraIcon(btn, aura, edgeColor)
	btn.icon:SetTexture(aura.icon)
	local n = B.Plain(aura.applications, 0) or 0
	btn.count:SetText(n > 1 and n or "")
	local dur, exp = B.Plain(aura.duration, 0) or 0, B.Plain(aura.expirationTime, 0) or 0
	if dur > 0 and exp > 0 then btn.cd:SetCooldown(exp - dur, dur) else btn.cd:Clear() end
	local c = edgeColor
	if not c and aura.dispelName and DebuffTypeColor then c = DebuffTypeColor[aura.dispelName] end
	if c then btn.edge:SetColorTexture(c.r, c.g, c.b, 1) else btn.edge:SetColorTexture(0, 0, 0, 1) end
	btn:Show()
end
