--[[
	BitsjUI - Quest tracker
	Blizzard's objective tracker (the quest list on the right) in the BitsjUI
	look, plus smarter ordering:
	  - flat section headers with a line in the theme colour instead of the
	    gold banner art; quest titles and objectives in the UI font
	  - tracked quests keep re-sorting by distance while you move (Blizzard
	    only re-sorts when you change zone), so the closest quest is on top
	Only fonts, header art and Blizzard's own sort call are used, so quest
	item buttons and clicking quests keep working in combat.
]]
local _, B = ...
local M = B:NewModule("Quests")

local function db() return B.db.quests end

local TRACKERS = {
	"ScenarioObjectiveTracker", "UIWidgetObjectiveTracker", "CampaignQuestObjectiveTracker", "QuestObjectiveTracker",
	"AdventureObjectiveTracker", "AchievementObjectiveTracker", "MonthlyActivitiesObjectiveTracker",
	"ProfessionsRecipeTracker", "BonusObjectiveTracker", "WorldQuestObjectiveTracker", "InitiativeTasksObjectiveTracker",
}

-- the font objects the tracker draws with
function M:ApplyFonts()
	local d = db()
	local font = B:GetFont()
	local function set(name, size)
		local fo = _G[name]
		if fo and fo.SetFont then
			fo:SetFont(font, size, B:Flags(d.outline and "OUTLINE" or ""))
			fo:SetShadowColor(0, 0, 0, 1)
			fo:SetShadowOffset(1, -1)
		end
	end
	set("ObjectiveTrackerHeaderFont", d.headerSize)
	set("ObjectiveTrackerLineFont", d.lineSize)
	set("ObjectiveTrackerFont12", d.lineSize)
	set("ObjectiveTrackerFont13", d.lineSize + 1)
	set("ObjectiveTrackerFont14", d.lineSize + 2)
end

-- gold banner -> flat dark strip with a theme-coloured line
local function SkinHeader(header, main)
	if not header or header.bSkinned then return end
	header.bSkinned = true
	B.HideRegion(header.Background)
	local bg = header:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", header, "TOPLEFT", main and 0 or 2, -4)
	bg:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -2, 4)
	local r, g, b = B:PanelColor()
	bg:SetColorTexture(r, g, b, main and 0.75 or 0.55)
	local line = header:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetHeight(main and 2 or 1)
	line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
	if header.Text then header.Text:SetTextColor(B:AccentColor()) end
end

function M:SkinHeaders()
	local otf = ObjectiveTrackerFrame
	if not otf then return end
	SkinHeader(otf.Header, true)
	for _, name in ipairs(TRACKERS) do
		local t = _G[name]
		if t and t.Header then SkinHeader(t.Header) end
	end
end

-------------------------------------------------------------------------------
-- Keep tracked quests ordered by distance while moving (out of combat)
-------------------------------------------------------------------------------
local lastX, lastY, lastMap
local function MaybeSort()
	if not db().sortByDistance or InCombatLockdown() then return end
	if not (C_QuestLog and C_QuestLog.SortQuestWatches) then return end
	local map = C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if B.IsSecret(x) or B.IsSecret(y) or not x then return end
	if map == lastMap and lastX and math.abs(x - lastX) + math.abs(y - lastY) < 0.01 then return end
	lastX, lastY, lastMap = x, y, map
	C_QuestLog.SortQuestWatches()
end

-------------------------------------------------------------------------------
-- Classic: the old quest watch list (QuestWatchLine1..n under the minimap)
-- quest titles in the theme colour, objectives in the UI font, done ones green
-------------------------------------------------------------------------------
function M:StyleClassicWatch()
	local d = db()
	local ar, ag, ab = B:AccentColor()
	for i = 1, (MAX_QUESTWATCH_LINES or 30) do
		local line = _G["QuestWatchLine" .. i]
		if not line then break end
		local text = line:GetText()
		local isObjective = type(text) == "string" and text:sub(1, 3) == " - "
		B:SetFont(line, isObjective and d.lineSize or d.headerSize, d.outline and "OUTLINE" or "")
		line:SetShadowColor(0, 0, 0, 1)
		line:SetShadowOffset(1, -1)
		if not isObjective and text and text ~= "" then
			line:SetTextColor(ar, ag, ab)
		elseif isObjective then
			local r, g = line:GetTextColor()
			-- Blizzard draws finished objectives white, open ones grey
			if r and r > 0.95 and g > 0.95 then line:SetTextColor(0.37, 0.88, 0.54) end
		end
	end
end

function M:EnableClassic()
	if QuestWatch_Update and not self.classicHooked then
		self.classicHooked = true
		hooksecurefunc("QuestWatch_Update", function() B:Try(M.StyleClassicWatch, M) end)
	end
	self:StyleClassicWatch()
end

function M:OnEnable()
	if not db().enabled then return end
	if not _G.ObjectiveTrackerFrame and _G.QuestWatchFrame then return self:EnableClassic() end
	self:ApplyFonts()
	self:SkinHeaders()
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_ObjectiveTracker" then M:ApplyFonts(); M:SkinHeaders() end
	end)
	-- trackers that appear later (scenarios, world quests...) get their header on first show
	B:RegisterEvent("QUEST_WATCH_LIST_CHANGED", function() M:SkinHeaders() end)
	B:RegisterEvent("SCENARIO_UPDATE", function() M:SkinHeaders() end)
	C_Timer.NewTicker(5, function() B:Try(MaybeSort) end)
	B:RegisterEvent("QUEST_ACCEPTED", function() C_Timer.After(0.5, function() lastMap = nil; B:Try(MaybeSort) end) end)
end

function M:Update()
	if not db().enabled then return end
	if self.classicHooked then return self:StyleClassicWatch() end
	self:ApplyFonts()
	lastMap = nil
	MaybeSort()
end
