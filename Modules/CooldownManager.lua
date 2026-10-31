--[[
	BitsjUI - Cooldown Manager skin
	Restyles Blizzard's built-in Cooldown Manager (Essential, Utility,
	Buff Icons, Buff Bars) to match BitsjUI: square zoomed icons, 1px border,
	darker swipe, clean fonts and flat bars.
	Only visual properties are touched. Which spells are tracked, and where
	the viewers sit, stay in Blizzard's own Cooldown Settings / Edit Mode,
	because changing their layout data from an addon is blocked by the client.
]]
local _, B = ...
local M = B:NewModule("CooldownManager")

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
M.VIEWERS = VIEWERS

local function db() return B.db.cdm end

local function IconTexture(item)
	local icon = item.Icon
	if type(icon) ~= "table" then return nil end
	if icon.GetObjectType and icon:GetObjectType() == "Texture" then return icon end
	-- bar items keep the texture one level deeper
	if type(icon.Icon) == "table" then return icon.Icon end
end

local function IconHolder(item)
	local icon = item.Icon
	if type(icon) == "table" and icon.GetObjectType and icon:GetObjectType() ~= "Texture" then return icon end
	return item
end

local function StyleItem(item)
	local d = db()
	local icon = IconTexture(item)
	if not icon then return end

	if not item.bStyled then
		item.bStyled = true
		-- remove the round mask and Blizzard's overlay ring
		if icon.GetNumMaskTextures then
			for i = icon:GetNumMaskTextures(), 1, -1 do
				local mask = icon:GetMaskTexture(i)
				if mask then pcall(icon.RemoveMaskTexture, icon, mask) end
			end
		end
		local holder = IconHolder(item)
		item.bOverlays = {}
		for _, region in ipairs({ holder:GetRegions() }) do
			if region ~= icon and region.GetObjectType and region:GetObjectType() == "Texture" then
				local atlas = region.GetAtlas and region:GetAtlas()
				if type(atlas) == "string" and (atlas:find("Overlay") or atlas:find("Border") or atlas:find("Frame")) then
					item.bOverlays[#item.bOverlays + 1] = region
				end
			end
		end
		-- 1px border around the icon
		local border = CreateFrame("Frame", nil, holder)
		border:SetAllPoints(icon)
		B:CreateBorder(border, 0, 0, 0, 1)
		item.bBorderFrame = border
	end

	B:SkinIcon(icon, item)
	if not d.zoom then icon:SetTexCoord(0, 1, 0, 1) end
	for _, region in ipairs(item.bOverlays) do region:SetAlpha(d.hideOverlay and 0 or 1) end
	item.bBorderFrame:SetShown(d.border)

	local cd = item.Cooldown
	if type(cd) == "table" and cd.SetSwipeColor then
		if cd.SetSwipeTexture then cd:SetSwipeTexture(B.white) end
		cd:SetSwipeColor(0, 0, 0, d.swipeAlpha)
		cd:ClearAllPoints()
		cd:SetAllPoints(icon)
		local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
		if fs then B:SetFont(fs, d.countdownSize) end
	end

	-- stack / charge counters (names differ between viewers)
	local counters = {
		item.Count,
		type(item.Applications) == "table" and item.Applications.Applications or nil,
		type(item.ChargeCount) == "table" and item.ChargeCount.Current or nil,
	}
	for _, fs in ipairs(counters) do
		if type(fs) == "table" and fs.SetFont then B:SetFont(fs, d.countSize) end
	end

	-- buff bars
	local bar = item.Bar
	if d.styleBars and type(bar) == "table" and bar.SetStatusBarTexture then
		bar:SetStatusBarTexture(B:GetTexture())
		if not bar.bStyled then
			bar.bStyled = true
			for _, region in ipairs({ bar:GetRegions() }) do
				local atlas = region.GetAtlas and region:GetAtlas()
				if type(atlas) == "string" and (atlas:find("BarBG") or atlas:find("Background") or atlas:find("Border")) then
					region:SetAlpha(0)
				end
			end
			local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
			bg:SetAllPoints()
			bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)
			B:CreateBorder(bar, 0, 0, 0, 1)
		end
		for _, key in ipairs({ "Name", "Duration" }) do
			if type(bar[key]) == "table" and bar[key].SetFont then B:SetFont(bar[key], d.barFontSize) end
		end
	end
end

function M:StyleViewer(viewer)
	if not viewer or not db().enabled then return end
	for _, child in ipairs({ viewer:GetChildren() }) do
		if type(child) == "table" and child.Icon then
			local ok, err = pcall(StyleItem, child)
			if not ok and not self.reported then
				self.reported = true
				B:Error(err)
			end
		end
	end
end

function M:StyleAll()
	for _, name in ipairs(VIEWERS) do self:StyleViewer(_G[name]) end
end

local function HookViewer(viewer)
	if not viewer or viewer.bHooked then return end
	viewer.bHooked = true
	-- post-hooks only: they never change what Blizzard's code does
	for _, method in ipairs({ "RefreshLayout", "Layout", "RefreshData" }) do
		if viewer[method] then
			hooksecurefunc(viewer, method, function(self) M:StyleViewer(self) end)
		end
	end
	viewer:HookScript("OnShow", function(self) M:StyleViewer(self) end)
end

function M:OnEnable()
	if not db().enabled then return end
	local function setup()
		for _, name in ipairs(VIEWERS) do HookViewer(_G[name]) end
		M:StyleAll()
	end
	setup()
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_CooldownViewer" then setup() end
	end)
	-- new icons appear when spells are learned or talents change
	B:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, setup) end)
	B:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() C_Timer.After(1, function() M:StyleAll() end) end)
	B:RegisterEvent("TRAIT_CONFIG_UPDATED", function() C_Timer.After(1, function() M:StyleAll() end) end)
	-- safety net for pooled icons created between layout passes
	self.ticker = C_Timer.NewTicker(2, function() M:StyleAll() end)
end

function M:Update()
	if not db().enabled then return end
	self:StyleAll()
end

function M:OpenSettings()
	if InCombatLockdown() then return end
	if not _G.CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
	end
	if _G.CooldownViewerSettings then
		ShowUIPanel(_G.CooldownViewerSettings)
	else
		B:Print("Couldn't find Blizzard's Cooldown Settings (turn on the Cooldown Manager under Options > Gameplay > Combat).")
	end
end
