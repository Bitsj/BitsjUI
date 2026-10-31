--[[
	BitsjUI - Minimap
	Square minimap with a 1px border, a zone name header above it and a clock
	box below it, mouse-wheel zoom and optional coordinates.
	Position and size of the minimap itself stay in Blizzard's Edit Mode.
]]
local _, B = ...
local M = B:NewModule("Minimap")

local function db() return B.db.minimap end

local function Hide(region)
	if type(region) == "table" and region.SetAlpha then
		region:SetAlpha(0)
		if region.EnableMouse then pcall(region.EnableMouse, region, false) end
	end
end

local function Show(region)
	if type(region) == "table" and region.SetAlpha then
		region:SetAlpha(1)
		if region.EnableMouse then pcall(region.EnableMouse, region, true) end
	end
end

local header, clockBox, overlay

-------------------------------------------------------------------------------
-- Tidy buttons: tracking, calendar, expansion summary, addon compartment,
-- Blizzard's coordinates and addon (LibDBIcon) buttons only appear while the
-- mouse is over the minimap. Mail and dungeon difficulty always stay.
-------------------------------------------------------------------------------
local function Buttons()
	local list = {}
	local cluster = MinimapCluster
	local function add(f) if type(f) == "table" and f.SetAlpha and not (f.IsForbidden and f:IsForbidden()) then list[#list + 1] = f end end
	add(cluster and cluster.Tracking)
	add(_G.ExpansionLandingPageMinimapButton)
	add(_G.GameTimeFrame)
	add(_G.AddonCompartmentFrame)
	add(cluster and cluster.PlayerCoords)
	-- Classic names
	add(_G.MiniMapTracking)
	add(_G.MiniMapWorldMapButton)
	add(_G.MinimapToggleButton)
	add(_G.MiniMapLFGFrame)
	add(_G.LFGMinimapFrame)
	for _, child in ipairs({ Minimap:GetChildren() }) do
		local name = child.GetName and child:GetName()
		if name and (name:find("^LibDBIcon") or name:find("MinimapButton")) and child ~= _G.ExpansionLandingPageMinimapButton then
			add(child)
		end
	end
	return list
end

function M:UpdateButtons(force)
	local mode = db().buttons or "hover"
	if mode == "show" and not force then return end
	local over = Minimap:IsMouseOver(20, -20, -20, 20)
	local list = self.buttonList
	if not list then list = Buttons(); self.buttonList = list end
	if not over then
		for _, b in ipairs(list) do if b:IsMouseOver() then over = true; break end end
	end
	local target = (mode == "show" or (mode == "hover" and over)) and 1 or 0
	for _, b in ipairs(list) do
		if b:GetAlpha() ~= target then b:SetAlpha(target) end
		if force and b.EnableMouse and b:IsMouseEnabled() == (mode == "hide") then pcall(b.EnableMouse, b, mode ~= "hide") end
	end
end

local function Box(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(20)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
	B:CreateBorder(f, 0, 0, 0, 1)
	f.text = B:CreateText(f, 12, "CENTER")
	f.text:SetPoint("LEFT", 4, 0)
	f.text:SetPoint("RIGHT", -4, 0)
	return f
end

function M:Style()
	local d = db()
	local mm, cluster = Minimap, MinimapCluster

	if d.square then
		mm:SetMaskTexture(B.white)
		_G.GetMinimapShape = function() return "SQUARE" end
		for _, fn in ipairs({ "SetArchBlobRingScalar", "SetArchBlobRingAlpha", "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha" }) do
			if mm[fn] then pcall(mm[fn], mm, 0) end
		end
		Hide(_G.MinimapCompassTexture)
		Hide(cluster and cluster.BorderTop)
		Hide(_G.MinimapBorder)
		Hide(_G.MinimapBorderTop)
		Hide(_G.MinimapNorthTag)
		Hide(_G.MinimapCompassTexture)
		if _G.HybridMinimap and _G.HybridMinimap.CircleMask then
			_G.HybridMinimap.CircleMask:SetTexture(B.white)
		end
	else
		mm:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		_G.GetMinimapShape = function() return "ROUND" end
		Show(_G.MinimapCompassTexture)
		Show(cluster and cluster.BorderTop)
		Show(_G.MinimapBorder)
		Show(_G.MinimapNorthTag)
	end

	if d.square and d.border then
		if not mm.bBorder then B:CreateBorder(mm, 0, 0, 0, 1, B:Pixel(mm)) end
		mm.bBorder:Show()
	elseif mm.bBorder then
		mm.bBorder:Hide()
	end

	if d.hideZoomButtons then
		Hide(mm.ZoomIn); Hide(mm.ZoomOut); Hide(_G.MinimapZoomIn); Hide(_G.MinimapZoomOut); Hide(mm.ZoomHitArea)
	else
		Show(mm.ZoomIn); Show(mm.ZoomOut); Show(_G.MinimapZoomIn); Show(_G.MinimapZoomOut)
	end

	-- Blizzard's zone text button is replaced by our header
	local zone = cluster and (cluster.ZoneTextButton or _G.MinimapZoneTextButton)
	if d.zoneText == "header" or d.zoneText == "hover" or d.zoneText == "hide" then Hide(zone) else Show(zone) end

	-- header above, clock below
	header:ClearAllPoints()
	header:SetPoint("BOTTOMLEFT", mm, "TOPLEFT", 0, 3)
	header:SetPoint("BOTTOMRIGHT", mm, "TOPRIGHT", 0, 3)
	local clock = d.clock
	if clock == true then clock = "header" elseif clock == false then clock = "off" end
	header:SetShown(d.zoneText == "header" or clock == "header")
	-- zone left, clock right, in one slim strip
	local faction = UnitFactionGroup("player")
	local crest = B.db.general.factionCrest and (faction == "Alliance" or faction == "Horde")
		and B.HasAtlas("pvpqueue-sidebar-honorbar-badge-" .. faction:lower())
	-- same faction badge Blizzard's PvP window uses
	if crest then header.crest:SetAtlas("pvpqueue-sidebar-honorbar-badge-" .. faction:lower()) end
	header.crest:SetShown(crest and true or false)
	header.text:ClearAllPoints()
	header.text:SetPoint("LEFT", header, "LEFT", crest and 21 or 6, 0)
	header.text:SetPoint("RIGHT", header.clock, "LEFT", -6, 0)
	header.text:SetJustifyH("LEFT")
	header.text:SetShown(d.zoneText == "header")
	header.clock:SetShown(clock == "header")
	clockBox:ClearAllPoints()
	clockBox:SetPoint("TOP", mm, "BOTTOM", 0, -3)
	clockBox:SetWidth(56)
	clockBox:SetShown(clock == "below")
	-- Blizzard's own clock button would double up with ours
	if clock ~= "off" then Hide(_G.TimeManagerClockButton) else Show(_G.TimeManagerClockButton) end

	self:UpdateZoneText()
end

function M:UpdateZoneText()
	if not header then return end
	local d = db()
	local text = GetMinimapZoneText and GetMinimapZoneText() or ""
	local r, g, b = 1, 0.82, 0.1
	local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
	if pvp == "sanctuary" then r, g, b = 0.41, 0.8, 0.94
	elseif pvp == "friendly" then r, g, b = 0.1, 1, 0.1
	elseif pvp == "hostile" then r, g, b = 1, 0.1, 0.1
	elseif pvp == "contested" then r, g, b = 1, 0.7, 0 end
	header.text:SetText(text)
	header.text:SetTextColor(r, g, b)
	overlay.zone:SetText(text)
	overlay.zone:SetTextColor(r, g, b)
	overlay.zone:SetShown(d.zoneText == "hover" and Minimap:IsMouseOver())
	overlay.coords:SetShown(d.coords)
end

function M:OnEnable()
	if not db().enabled then return end
	header = Box(Minimap)
	header:SetHeight(18)
	header.clock = B:CreateText(header, 11, "RIGHT")
	header.clock:SetPoint("RIGHT", header, "RIGHT", -6, 0)
	-- faction emblem at the start of the bar
	header.crest = header:CreateTexture(nil, "OVERLAY")
	header.crest:SetSize(14, 14)
	header.crest:SetPoint("LEFT", header, "LEFT", 4, 0)
	clockBox = Box(Minimap)

	overlay = CreateFrame("Frame", nil, Minimap)
	overlay:SetAllPoints(Minimap)
	overlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	overlay.zone = B:CreateText(overlay, 13, "CENTER")
	overlay.zone:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 4, -6)
	overlay.zone:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -6)
	overlay.coords = B:CreateText(overlay, 12, "CENTER")
	overlay.coords:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 6)

	overlay.elapsed = 0
	overlay:SetScript("OnUpdate", B.Safe(function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		local d = db()
		if d.zoneText == "hover" then self.zone:SetShown(Minimap:IsMouseOver()) end
		M:UpdateButtons()
		if d.clock and d.clock ~= "off" then
			local t = date("%H:%M")
			clockBox.text:SetText(t)
			header.clock:SetText(t)
		end
		self.coordTick = (self.coordTick or 0) + 1
		if d.coords and self.coordTick % 3 == 0 then
			local x, y
			pcall(function()
				local map = C_Map.GetBestMapForUnit("player")
				local pos = map and C_Map.GetPlayerMapPosition(map, "player")
				if pos then x, y = pos:GetXY() end
			end)
			if not B.IsSecret(x) and not B.IsSecret(y) and x and y and x > 0 then
				self.coords:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
			else
				self.coords:SetText("")
			end
		end
	end))

	self:Style()

	Minimap:EnableMouseWheel(true)
	Minimap:HookScript("OnMouseWheel", function(self, delta)
		if not db().mouseZoom then return end
		local zoom = self:GetZoom()
		if delta > 0 and zoom < self:GetZoomLevels() - 1 then
			self:SetZoom(zoom + 1)
		elseif delta < 0 and zoom > 0 then
			self:SetZoom(zoom - 1)
		end
	end)

	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		B:RegisterEvent(e, function() M:UpdateZoneText() end)
	end
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_HybridMinimap" or name == "Blizzard_TimeManager" then M:Style() end
		M.buttonList = nil
	end)
	-- addon buttons appear a little after login; collect them again then
	C_Timer.After(3, function() M.buttonList = Buttons(); M:UpdateButtons(true) end)
	C_Timer.After(10, function() M.buttonList = Buttons() end)
end

function M:Update()
	if not db().enabled or not header then return end
	self.buttonList = Buttons()
	self:UpdateButtons(true)
	self:Style()
end
