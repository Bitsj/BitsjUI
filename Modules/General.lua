--[[
	BitsjUI - General
	UI scale (supports values below Blizzard's 0.64 minimum, e.g. 0.62),
	global font replacement and decluttering.
]]
local _, B = ...
local M = B:NewModule("General")

-------------------------------------------------------------------------------
-- UI scale
-------------------------------------------------------------------------------
local applyingScale = false
function B:ApplyUIScale()
	local scale = self.db.general.uiScale or 0.62
	scale = B.Clamp(scale, 0.40, 1.15)
	B:RunOOC("uiscale", function()
		applyingScale = true
		-- keep Blizzard's CVar as close as it allows (0.64 minimum)
		pcall(SetCVar, "useUiScale", "1")
		pcall(SetCVar, "uiScale", tostring(math.max(0.64, scale)))
		UIParent:SetScale(scale)
		applyingScale = false
		B:Fire("UI_SCALE_APPLIED")
	end)
end

local function ReapplyScale()
	if applyingScale or not B.db then return end
	-- Blizzard resets UIParent scale on these events; put ours back next frame
	C_Timer.After(0, function() B:ApplyUIScale() end)
end
B:RegisterEvent("UI_SCALE_CHANGED", ReapplyScale)
B:RegisterEvent("DISPLAY_SIZE_CHANGED", ReapplyScale)

-------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------
local fontObjects = {
	"SystemFont_Tiny", "SystemFont_Small", "SystemFont_Small2", "SystemFont_Med1", "SystemFont_Med2",
	"SystemFont_Med3", "SystemFont_Large", "SystemFont_Huge1", "SystemFont_Huge2", "SystemFont_Outline",
	"SystemFont_Outline_Small", "SystemFont_Shadow_Small", "SystemFont_Shadow_Med1", "SystemFont_Shadow_Med2",
	"SystemFont_Shadow_Med3", "SystemFont_Shadow_Large", "SystemFont_Shadow_Huge1", "SystemFont_Shadow_Huge3",
	"SystemFont_InverseShadow_Small", "SystemFont_NamePlate", "SystemFont_LargeNamePlate",
	"GameFontNormal", "GameFontNormalSmall", "GameFontNormalMed3", "GameFontNormalLarge", "GameFontNormalHuge",
	"GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightMedium", "GameFontHighlightLarge",
	"GameFontDisable", "GameFontDisableSmall", "GameFontGreen", "GameFontRed", "GameFontWhite",
	"GameTooltipHeader", "GameTooltipText", "GameTooltipTextSmall", "Tooltip_Med", "Tooltip_Small",
	"NumberFont_Shadow_Small", "NumberFont_Shadow_Med", "NumberFont_Outline_Med", "NumberFont_Outline_Large",
	"NumberFont_OutlineThick_Mono_Small", "NumberFont_Small", "NumberFontNormal", "NumberFontNormalSmall",
	"QuestFont", "QuestFont_Large", "QuestFont_Shadow_Small", "QuestFontNormalSmall",
	"ObjectiveFont", "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont",
	"FriendsFont_Normal", "FriendsFont_Small", "FriendsFont_Large", "FriendsFont_UserText",
	"ChatBubbleFont", "MailFont_Large", "SpellFont_Small", "InvoiceFont_Med", "InvoiceFont_Small",
	"ReputationDetailFont", "AchievementFont_Small", "Game12Font", "Game13Font", "Game15Font",
	"Game18Font", "Game20Font", "Game24Font", "Game27Font", "Game30Font", "Game32Font",
	"Fancy12Font", "Fancy14Font", "Fancy16Font", "Fancy18Font", "Fancy20Font", "Fancy22Font", "Fancy24Font",
	"SubZoneTextFont", "ZoneTextFont", "PVPInfoTextFont", "ErrorFont", "CombatTextFont",
}

local originalFonts = {}
function M:ApplyGameFonts()
	local enabled = B.db.general.replaceGameFonts
	local file = B:GetFont()
	for _, name in ipairs(fontObjects) do
		local obj = _G[name]
		if obj and obj.GetFont then
			local cur, size, flags = obj:GetFont()
			if cur then
				if not originalFonts[name] then originalFonts[name] = cur end
				if enabled then
					obj:SetFont(file, size, B:Flags(flags or ""))
				elseif originalFonts[name] then
					obj:SetFont(originalFonts[name], size, flags or "")
				end
			end
		end
	end
	if enabled then
		_G.STANDARD_TEXT_FONT = file
		_G.UNIT_NAME_FONT = file
		_G.NAMEPLATE_FONT = file
	end
end

-------------------------------------------------------------------------------
-- Declutter
-------------------------------------------------------------------------------
local function SetMouseoverFade(frame, enabled)
	if not frame then return end
	if not frame.bFade then
		frame.bFade = CreateFrame("Frame", nil, UIParent)
		frame.bFade.elapsed = 0
		frame.bFade:SetScript("OnUpdate", function(self, el)
			self.elapsed = self.elapsed + el
			if self.elapsed < 0.15 then return end
			self.elapsed = 0
			if not frame.bFadeEnabled then return end
			local over = frame:IsMouseOver(4, -4, -4, 4)
			frame:SetAlpha(over and 1 or 0)
		end)
	end
	frame.bFadeEnabled = enabled
	if not enabled then frame:SetAlpha(1) end
end

function M:Declutter()
	local g = B.db.general

	-- bag bar
	local bags = _G.BagsBar
	if bags then
		B:RunOOC("bagsbar", function()
			if g.hideBagsBar then
				bags.bOrigParent = bags.bOrigParent or bags:GetParent()
				bags:SetParent(B.hiddenParent)
			elseif bags.bOrigParent then
				bags:SetParent(bags.bOrigParent)
			end
		end)
	end

	-- micro menu on mouseover
	SetMouseoverFade(_G.MicroMenuContainer or _G.MicroMenu, g.microMenuMouseover)

	-- talking head
	local th = _G.TalkingHeadFrame
	if th and not th.bHooked and th.PlayCurrent then
		th.bHooked = true
		hooksecurefunc(th, "PlayCurrent", function(self)
			if B.db.general.hideTalkingHead and self.CloseImmediately then
				self:CloseImmediately()
			end
		end)
	end

	-- red error text
	if UIErrorsFrame then
		if g.hideErrors then
			UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		else
			UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
		end
	end
end

-------------------------------------------------------------------------------
function M:OnInitialize()
	-- Expressway only works where the font file has been added by hand
	if B.db.general.font == "Expressway" and not B.FontWorks(B.media.fonts.Expressway) then B.db.general.font = "Barlow" end
	-- 1.6.1: cleaner spell timers (saved profiles hold full copies of the old values)
	if not B.db.migrated161 then
		local t = B.db.timers
		t.width, t.height, t.spacing, t.groupGap, t.fontSize = 180, 16, 2, 6, 11
		t.playerBuffs, t.buffNum, t.debuffNum = false, 5, 6
		if B.db.positions then B.db.positions.timers = nil end
		B.db.migrated161 = true
	end
	-- 1.6.2: centred bar stack, side bars on mouseover, bolder frames with texts
	if not B.db.migrated162 then
		local bars = B.db.actionbars.bars
		for _, k in ipairs({ 4, 5 }) do
			local b = bars[k]
			b.enabled, b.perRow, b.size, b.spacing, b.mouseover, b.mouseoverAlpha = true, 1, 32, 2, true, 0
		end
		for _, k in ipairs({ 1, 2, 3 }) do
			local b = bars[k]
			b.enabled, b.perRow, b.size, b.spacing, b.mouseover = true, 12, 36, 2, false
		end
		local uf = B.db.unitframes
		uf.borderSize = 2
		for _, k in ipairs({ "player", "target" }) do
			local u = uf[k]
			u.width, u.healthHeight, u.healthText, u.showName = 200, 26, "split", true
		end
		local pos = B.db.positions
		if pos then
			for _, k in ipairs({ "bar1", "bar2", "bar3", "bar4", "bar5", "barpet", "barstance",
				"player", "target", "targettarget", "pet", "uf_player", "uf_target", "uf_targettarget", "uf_pet" }) do
				pos[k] = nil
			end
		end
		B.db.migrated162 = true
	end
	-- 1.7.0: nameplate look from the reference (name above, no health text)
	if not B.db.migrated170 then
		local n = B.db.nameplates
		n.width, n.height, n.nameSize, n.healthText = 170, 14, 12, "none"
		B.db.migrated170 = true
	end
	-- 1.7.1: player castbar in the middle, target castbar under its frame, timers left
	if not B.db.migrated171 then
		local cb = B.db.castbars
		cb.player.width, cb.player.height = 260, 22
		cb.target.height, cb.target.attach = 18, true
		local pos = B.db.positions
		if pos then pos.cb_player, pos.cb_target, pos.timers = nil, nil, nil end
		B.db.migrated171 = true
	end
	-- 1.7.2: player castbar right above the action bars (as wide as them),
	-- stance bar to the left of the bars, pet bar to the right
	if not B.db.migrated172 then
		local cb = B.db.castbars.player
		cb.width, cb.height = 428, 22
		local pos = B.db.positions
		if pos then pos.cb_player, pos.barstance, pos.barpet = nil, nil, nil end
		B.db.migrated172 = true
	end
	-- 1.8.1: thicker rounded theme; action buttons get the rounded border too
	if not B.db.migrated181 then
		B.db.general.borderStyle = "rounded"
		B.db.general.cornerRadius = 5
		B.db.unitframes.borderSize = math.max(3, B.db.unitframes.borderSize or 1)
		local ab = B.db.actionbars
		ab.borderSize = 2
		for k = 1, 5 do ab.bars[k].spacing = 4 end
		B.db.castbars.player.width = 450
		local pos = B.db.positions
		if pos then
			for _, k in ipairs({ "bar1", "bar2", "bar3", "bar4", "bar5", "barpet", "barstance", "cb_player" }) do pos[k] = nil end
		end
		B.db.migrated181 = true
	end
	-- 1.9.2: no buff toggle button any more, permanent buffs simply hidden
	if not B.db.migrated192 then
		B.db.buffs.collapse, B.db.buffs.collapsePassive = true, true
		B.db.migrated192 = true
	end
	-- 2.4.0: separate party / raid settings; unit frames a bit higher
	if not B.db.migrated240 then
		local rf = B.db.raidframes
		for _, kind in ipairs({ "party", "raid" }) do
			local t = rf[kind]
			for _, k in ipairs({ "spacing", "borderSize", "colorMode", "nameColor", "roleIcon", "aggro", "rangeAlpha", "debuffs", "myBuffs" }) do
				if rf[k] ~= nil then t[k] = rf[k] end
			end
		end
		if rf.groupLabels ~= nil then rf.raid.groupLabels = rf.groupLabels end
		if rf.width then rf.raid.width, rf.raid.height = rf.width, rf.height end
		local pos = B.db.positions
		for _, k in ipairs({ "uf_player", "uf_target", "uf_targettarget", "uf_pet" }) do
			if pos and pos[k] and type(pos[k][4]) == "number" then pos[k][4] = pos[k][4] + 40 end
		end
		B.db.migrated240 = true
	end
	-- 2.8.0: clearer nameplates
	if not B.db.migrated280 then
		local n = B.db.nameplates
		n.height, n.nameSize, n.targetScale, n.nonTargetAlpha = 16, 13, 1.2, 0.55
		B.db.migrated280 = true
	end
	-- must happen before the client builds its font cache
	if B.db.general.replaceGameFonts then
		local file = B:GetFont()
		_G.STANDARD_TEXT_FONT = file
		_G.UNIT_NAME_FONT = file
		_G.NAMEPLATE_FONT = file
	end
	B:RegisterSharedMedia()
end

-- greeting in your class colour, once per login
local function Welcome()
	if not B.db.general.welcome then return end
	local me = B:Identity()
	local r, g, b = B:ClassColor(me.class)
	local fr, fg, fb = B:FactionColor()
	local hex = string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
	local fhex = string.format("|cff%02x%02x%02x", math.floor(fr * 255), math.floor(fg * 255), math.floor(fb * 255))
	local who = string.format("%s %s", me.race or "", me.className or "")
	local side = (me.faction == "Alliance" or me.faction == "Horde") and (" of the " .. fhex .. me.factionName .. "|r") or ""
	B:Print(string.format("Welcome back, %s%s|r - %s%s|r%s.", hex, me.name or "", hex, who, side))
end

function M:OnEnable()
	B:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
		if isLogin then C_Timer.After(2, Welcome) end
	end)
	B:ApplyUIScale()
	self:ApplyGameFonts()
	self:Declutter()
	-- talking head is load-on-demand in some versions
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_TalkingHeadUI" then M:Declutter() end
	end)
end

function M:Update()
	B:ApplyUIScale()
	self:ApplyGameFonts()
	self:Declutter()
	B:RefreshFonts()
	B:RefreshTextures()
end
