--[[
	BitsjUI - Tooltip
	Dark flat tooltips, class coloured border on players, slim health bar.
]]
local _, B = ...
local M = B:NewModule("Tooltip")

local function db() return B.db.tooltip end

local tooltips = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip", "WorldMapTooltip" }

local function StyleTooltip(tt)
	if not tt or not db().enabled then return end
	local ns = tt.NineSlice
	if ns then
		local c = B.db.general.backdrop
		if ns.SetCenterColor then ns:SetCenterColor(c.r, c.g, c.b, 0.94) end
		if not tt.bClassBorder and ns.SetBorderColor then ns:SetBorderColor(0.15, 0.15, 0.17, 1) end
	end
end

local function StyleStatusBar()
	local sb = _G.GameTooltipStatusBar
	if not sb or sb.bStyled then return end
	sb.bStyled = true
	sb:SetStatusBarTexture(B:GetTexture())
	sb:SetHeight(5)
	sb:ClearAllPoints()
	sb:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 6, 6)
	sb:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -6, 6)
	local bg = sb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
end

local function OnUnit(tt)
	if tt ~= GameTooltip or not db().enabled then return end
	tt.bClassBorder = nil
	local unit
	pcall(function() local _, u = tt:GetUnit(); unit = u end)
	if B.IsSecret(unit) or not unit then return end

	if db().hideInCombat and InCombatLockdown() then
		tt:Hide()
		return
	end

	if db().classBorder and tt.NineSlice and tt.NineSlice.SetBorderColor then
		pcall(function()
			if UnitIsPlayer(unit) then
				local _, class = UnitClass(unit)
				local r, g, b = B:ClassColor(class)
				tt.NineSlice:SetBorderColor(r, g, b, 1)
				tt.bClassBorder = true
			end
		end)
	end
	local sb = _G.GameTooltipStatusBar
	if sb then sb:SetShown(db().healthBar) end
end

function M:OnEnable()
	if not db().enabled then return end
	for _, name in ipairs(tooltips) do StyleTooltip(_G[name]) end
	StyleStatusBar()

	if _G.SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) StyleTooltip(tt) end)
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
	end
	GameTooltip:HookScript("OnTooltipCleared", function(tt)
		tt.bClassBorder = nil
		StyleTooltip(tt)
	end)
	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
		if db().cursor and tt == GameTooltip and not InCombatLockdown() then
			tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 24, 4)
		end
	end)
end

function M:Update()
	for _, name in ipairs(tooltips) do StyleTooltip(_G[name]) end
end
