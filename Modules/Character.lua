--[[
	BitsjUI - Character window
	Blizzard's character sheet in the BitsjUI look, plus gear info at a glance:
	  - item level on every piece (in its quality colour)
	  - the enchant next to each enchantable piece, or "No enchant" in red
	  - upgrade track (e.g. 4/6) under the item level
	  - average equipped item level in the title bar
	Gems are shown by Blizzard's own socket display beside each slot.
	Enchant names come from C_TooltipInfo (no hidden tooltip frames, which
	would taint), cached per enchant.
]]
local _, B = ...
local M = B:NewModule("Character")

local function db() return B.db.character end

-- slot name, inventory slot id, side the text goes on
local SLOTS = {
	{ "CharacterHeadSlot", 1, "RIGHT" }, { "CharacterNeckSlot", 2, "RIGHT" }, { "CharacterShoulderSlot", 3, "RIGHT" },
	{ "CharacterBackSlot", 15, "RIGHT" }, { "CharacterChestSlot", 5, "RIGHT" }, { "CharacterShirtSlot", 4, "RIGHT" },
	{ "CharacterTabardSlot", 19, "RIGHT" }, { "CharacterWristSlot", 9, "RIGHT" },
	{ "CharacterHandsSlot", 10, "LEFT" }, { "CharacterWaistSlot", 6, "LEFT" }, { "CharacterLegsSlot", 7, "LEFT" },
	{ "CharacterFeetSlot", 8, "LEFT" }, { "CharacterFinger0Slot", 11, "LEFT" }, { "CharacterFinger1Slot", 12, "LEFT" },
	{ "CharacterTrinket0Slot", 13, "LEFT" }, { "CharacterTrinket1Slot", 14, "LEFT" },
	{ "CharacterMainHandSlot", 16, "LEFT" }, { "CharacterSecondaryHandSlot", 17, "RIGHT" },
}

-- slots that take an enchant in Midnight: helm, shoulders, chest, boots, rings, weapons
local ENCHANTABLE = { [1] = true, [3] = true, [5] = true, [8] = true, [11] = true, [12] = true, [16] = true, [17] = true }
if B.classicContent then
	-- Classic / Forever: helm/legs (librams), shoulders, cloak, chest, bracers, gloves, boots, weapons
	ENCHANTABLE = { [1] = true, [3] = true, [15] = true, [5] = true, [9] = true, [10] = true, [7] = true, [8] = true, [16] = true, [17] = true }
	-- weapons and ranged sit in a row under the model: text goes above them
	SLOTS[17][3], SLOTS[18][3] = "TOP", "TOP"
	table.insert(SLOTS, { "CharacterRangedSlot", 18, "TOP" })
end
local NO_ILVL = { [4] = true, [19] = true }   -- shirt, tabard

local TRACK_COLORS = {
	Myth = { 1, 0.5, 0 }, Hero = { 1, 0.3, 1 }, Champion = { 0, 0.44, 0.87 },
	Veteran = { 0.12, 1, 0 }, Adventurer = { 1, 1, 1 }, Explorer = { 0.62, 0.62, 0.62 },
}

-------------------------------------------------------------------------------
-- Gear data
-------------------------------------------------------------------------------
local enchantCache = {}
local ENCHANT_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent or 15
local enchantPattern
if ENCHANTED_TOOLTIP_LINE then
	local head, tail = ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s(.*)$")
	if head then
		local function esc(t) return (t:gsub("([%(%)%.%[%]%^%$%*%+%-%?%%])", "%%%1")) end
		enchantPattern = "^" .. esc(head) .. "(.+)" .. esc(tail) .. "$"
	end
end

local function Clean(t)
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	t = t:gsub("|A.-|a", ""):gsub("|T.-|t", "")
	return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- enchant name on an equipped item, "" when it has none
local function EnchantText(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then return nil end
	local id = tonumber(link:match("item:%d+:(%d+)"))
	if not id or id == 0 then return "" end
	if enchantCache[id] then return enchantCache[id] end
	local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", slot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText and Clean(line.leftText) or ""
		-- the line reads "Enchanted: <name>"; keep just the name
		local found = enchantPattern and text:match(enchantPattern)
		if not found and line.type == ENCHANT_LINE and text ~= "" then found = text:gsub("^[^:]+:%s*", "") end
		if found then
			found = found:gsub("^Enchant%s+[^-]+%-%s*", "")
			enchantCache[id] = found
			return found
		end
	end
	return "?"   -- has an enchant we couldn't name (data not loaded yet)
end

local function ItemLevel(slot)
	if ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
		local ok, lvl = pcall(function()
			local loc = ItemLocation:CreateFromEquipmentSlot(slot)
			if loc and C_Item.DoesItemExist(loc) then return C_Item.GetCurrentItemLevel(loc) end
		end)
		if ok and lvl then return lvl end
	end
	local link = GetInventoryItemLink("player", slot)
	if not link then return end
	if GetDetailedItemLevelInfo then
		local ok, lvl = pcall(GetDetailedItemLevelInfo, link)
		if ok and lvl then return lvl end
	end
	local _, _, _, lvl = GetItemInfo(link)
	return lvl
end

-- average equipped item level (Classic has no GetAverageItemLevel)
local function AverageItemLevel()
	if GetAverageItemLevel then
		local overall, equipped = GetAverageItemLevel()
		if equipped then return overall, equipped end
	end
	local sum, n = 0, 0
	for slot = 1, 18 do
		if not NO_ILVL[slot] and slot ~= 0 then
			local lvl = ItemLevel(slot)
			if lvl and lvl > 1 then sum, n = sum + lvl, n + 1 end
		end
	end
	if n == 0 then return end
	return sum / n, sum / n
end

local function UpgradeTrack(link)
	if not link or not (C_Item and C_Item.GetItemUpgradeInfo) then return end
	local info = C_Item.GetItemUpgradeInfo(link)
	if not info or not info.currentLevel or not info.maxLevel or info.maxLevel == 0 then return end
	local c = { 1, 1, 1 }
	for name, col in pairs(TRACK_COLORS) do
		if (info.trackString or ""):find(name) then c = col end
	end
	return string.format("%d/%d", info.currentLevel, info.maxLevel), c
end

local function IsWeapon(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link or not C_Item.GetItemInfoInstant then return false end
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
	return classID == (Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

-------------------------------------------------------------------------------
-- Slots
-------------------------------------------------------------------------------
local function SkinSlot(btn, side)
	if btn.bSkinned then return end
	btn.bSkinned = true
	B.HideRegion(_G[btn:GetName() .. "Frame"])
	B.HideRegion(btn:GetNormalTexture())
	B.HideRegion(btn.IconBorder)
	local icon = btn.icon or btn.Icon
	if icon then
		icon:ClearAllPoints()
		icon:SetAllPoints(btn)
		B:SkinIcon(icon, btn)
	end
	local slotBg = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
	slotBg:SetAllPoints(btn)
	slotBg:SetColorTexture(0.07, 0.07, 0.08, 0.9)
	B:CreateBorder(btn, nil, nil, nil, nil, B:Pixel(btn))
	local hl = btn:GetHighlightTexture()
	if hl then hl:SetColorTexture(1, 1, 1, 0.12); hl:SetAllPoints(btn) end

	-- text beside the slot (not on the icon, so it stays readable):
	-- line 1 = item level + upgrade track, line 2 = enchant
	local o = CreateFrame("Frame", nil, btn)
	o:SetAllPoints(btn)
	o:SetFrameLevel(btn:GetFrameLevel() + 5)
	local just = side == "RIGHT" and "LEFT" or "RIGHT"
	if side == "TOP" then just = "CENTER" end
	btn.bSide = side
	btn.bIlvl = B:CreateText(o, db().ilvlSize, just)
	btn.bEnchant = B:CreateText(o, db().enchantSize, just)
	btn.bEnchant:SetWidth(104)
	for _, fs in ipairs({ btn.bIlvl, btn.bEnchant }) do
		B:SetFont(fs, fs == btn.bIlvl and db().ilvlSize or db().enchantSize, "OUTLINE")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	end
	if side == "TOP" then
		-- row of slots: item level above, enchant state as a thin line under the icon
		btn.bIlvl:SetPoint("BOTTOM", btn, "TOP", 0, 3)
		btn.bEnchant:Hide()
		btn.bEnchantBar = o:CreateTexture(nil, "OVERLAY")
		btn.bEnchantBar:SetHeight(3)
		btn.bEnchantBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -2)
		btn.bEnchantBar:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", -2, -2)
		btn.bEnchantBar:Hide()
	elseif side == "RIGHT" then
		btn.bIlvl:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, -3)
		btn.bEnchant:SetPoint("TOPLEFT", btn.bIlvl, "BOTTOMLEFT", 0, -2)
	else
		btn.bIlvl:SetPoint("TOPRIGHT", btn, "TOPLEFT", -6, -3)
		btn.bEnchant:SetPoint("TOPRIGHT", btn.bIlvl, "BOTTOMRIGHT", 0, -2)
	end
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor((r or 1) * 255), math.floor((g or 1) * 255), math.floor((b or 1) * 255))
end

local function UpdateSlot(btn, slot)
	local d = db()
	local link = GetInventoryItemLink("player", slot)
	local quality = GetInventoryItemQuality("player", slot)
	-- border in the quality colour
	if btn.bBorder then
		local r, g, b
		if link and quality and quality >= 2 and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
		if r then btn.bBorder:SetColor(r, g, b, 1) else btn.bBorder:SetColor(B:BorderColor()) end
	end
	B.HideRegion(btn.IconBorder)
	-- item level (quality colour) + upgrade track (track colour)
	local parts = {}
	local ilvl = link and not NO_ILVL[slot] and d.showIlvl and ItemLevel(slot)
	if ilvl and ilvl > 1 then
		local r, g, b = 1, 1, 1
		if quality and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
		-- poor / common quality text is grey/white; lift dark colours so they read on the model
		parts[#parts + 1] = Hex(math.max(r or 1, 0.45), math.max(g or 1, 0.45), math.max(b or 1, 0.45)) .. ilvl .. "|r"
	end
	if d.showTrack and link then
		local track, tc = UpgradeTrack(link)
		if track then parts[#parts + 1] = Hex(tc[1], tc[2], tc[3]) .. track .. "|r" end
	end
	if #parts > 0 and btn.bSide == "LEFT" then
		-- right column reads towards the slot: "4/6  321"
		parts[1], parts[2] = parts[2] or parts[1], parts[2] and parts[1] or nil
	end
	btn.bIlvl:SetText(table.concat(parts, "  "))
	-- enchant
	local text = ""
	if link and d.showEnchants then
		local ench = EnchantText(slot)
		local needs = ENCHANTABLE[slot] and (slot ~= 17 or IsWeapon(17))
		if ench and ench ~= "" and ench ~= "?" then
			text = "|cff5fe08a" .. ench .. "|r"
		elseif ench == "?" then
			text = "|cff5fe08aEnchanted|r"
		elseif needs and d.missingEnchants then
			text = "|cffff5050No enchant|r"
		end
	end
	btn.bEnchant:SetText(text)
	if btn.bEnchantBar then
		local hasText = text ~= ""
		btn.bEnchantBar:SetShown(hasText)
		if text:find("ff5050", 1, true) then btn.bEnchantBar:SetColorTexture(1, 0.31, 0.31, 0.9)
		else btn.bEnchantBar:SetColorTexture(0.37, 0.88, 0.54, 0.9) end
	end
end

function M:UpdateAll()
	if not CharacterFrame or not CharacterFrame:IsShown() then return end
	for _, s in ipairs(SLOTS) do
		local btn = _G[s[1]]
		if btn then
			B:Try(SkinSlot, btn, s[3])
			B:Try(UpdateSlot, btn, s[2])
		end
	end
	-- average item level in the title bar
	if self.avg then
		local _, equipped = AverageItemLevel()
		if equipped and db().showAverage then
			local r, g, b = B:AccentColor()
			self.avg:SetFormattedText("Item level |cff%02x%02x%02x%.1f|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), equipped)
		else
			self.avg:SetText("")
		end
	end
end

-------------------------------------------------------------------------------
-- Stats: flat headers, exact percentages with the rating behind them, and an
-- extra block (Mythic+ rating, movement speed, durability) under the list
-------------------------------------------------------------------------------
local RATINGS -- label text -> combat rating id(s), built on first use
local function RatingFor(label)
	if not RATINGS then
		RATINGS = {}
		local function add(name, ...) if name then RATINGS[name] = { ... } end end
		add(STAT_CRITICAL_STRIKE, CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL)
		add(STAT_HASTE, CR_HASTE_MELEE)
		add(STAT_MASTERY, CR_MASTERY)
		add(STAT_VERSATILITY, CR_VERSATILITY_DAMAGE_DONE)
		add(STAT_LIFESTEAL, CR_LIFESTEAL)
		add(STAT_AVOIDANCE, CR_AVOIDANCE)
		add(STAT_SPEED, CR_SPEED)
	end
	for name, ids in pairs(RATINGS) do
		if label:find(name, 1, true) then return ids end
	end
end

local function Rating(ids)
	local best = 0
	for _, id in ipairs(ids) do
		local ok, v = pcall(GetCombatRating, id)
		v = ok and B.Plain(v, 0) or 0
		if type(v) == "number" and v > best then best = v end
	end
	return best
end

local function SkinCategory(cat)
	if not cat or cat.bSkinned then return end
	cat.bSkinned = true
	B.HideRegion(cat.Background)
	local bg = cat:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 2, -2)
	bg:SetPoint("BOTTOMRIGHT", -2, 2)
	bg:SetColorTexture(B:PanelColor(0.9))
	local line = cat:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(B:AccentColor())
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
	if cat.Title then
		B:SetFont(cat.Title, 13, "OUTLINE")
		cat.Title:SetTextColor(B:AccentColor())
	end
end

local function StatRow(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(15)
	f.Label = B:CreateText(f, 11, "LEFT")
	f.Label:SetPoint("LEFT", 10, 0)
	f.Label:SetTextColor(0.85, 0.75, 0.45)
	f.Value = B:CreateText(f, 11, "RIGHT")
	f.Value:SetPoint("RIGHT", -10, 0)
	return f
end

function M:ExtraBlock()
	local pane = CharacterStatsPane
	if not pane then return end
	if not self.extra then
		local e = CreateFrame("Frame", nil, pane)
		e:SetSize(190, 80)
		e.cat = CreateFrame("Frame", nil, e)
		e.cat:SetSize(190, 28)
		e.cat:SetPoint("TOP")
		e.cat.Title = B:CreateText(e.cat, 13, "CENTER")
		e.cat.Title:SetPoint("CENTER")
		e.cat.Title:SetText("More")
		SkinCategory(e.cat)
		e.rows = {}
		for i = 1, 3 do
			local r = StatRow(e)
			r:SetPoint("TOPLEFT", e.cat, "BOTTOMLEFT", 0, -2 - (i - 1) * 15)
			r:SetPoint("TOPRIGHT", e.cat, "BOTTOMRIGHT", 0, -2 - (i - 1) * 15)
			e.rows[i] = r
		end
		self.extra = e
	end
	local e = self.extra
	-- below the lowest visible stat row
	local lowest, lowestY
	for _, region in ipairs({ pane:GetChildren() }) do
		if region ~= e and region:IsShown() and region.GetBottom then
			local y = region:GetBottom()
			if y and (not lowestY or y < lowestY) then lowest, lowestY = region, y end
		end
	end
	e:ClearAllPoints()
	if lowest then e:SetPoint("TOP", lowest, "BOTTOM", 0, -8) else e:SetPoint("TOP", pane, "TOP", 0, -300) end
	-- Mythic+ rating in its rarity colour
	local score = C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and B.Plain(C_ChallengeMode.GetOverallDungeonScore(), 0) or 0
	local col = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
	e.rows[1].Label:SetText("Mythic+ rating:")
	e.rows[1].Value:SetText(col and (col:WrapTextInColorCode(tostring(score))) or tostring(score))
	-- run speed in % of normal
	local _, run = GetUnitSpeed("player")
	run = B.Plain(run, 7) or 7
	e.rows[2].Label:SetText("Movement speed:")
	e.rows[2].Value:SetFormattedText("%d%%", math.floor(run / 7 * 100 + 0.5))
	-- lowest durability
	local low = 100
	for slot = 1, 19 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then low = math.min(low, cur / max * 100) end
	end
	e.rows[3].Label:SetText("Durability:")
	local dr = low < 25 and "|cffff5050" or low < 50 and "|cffffd060" or "|cff5fe08a"
	e.rows[3].Value:SetFormattedText("%s%d%%|r", dr, low)
	e:SetShown(db().extraStats)
end

function M:UpdateStats()
	local pane = CharacterStatsPane
	if not pane or not db().betterStats then return end
	SkinCategory(pane.ItemLevelCategory)
	SkinCategory(pane.AttributesCategory)
	SkinCategory(pane.EnhancementsCategory)
	B.HideRegion(pane.ClassBackground)
	-- item level with two decimals: equipped / overall
	local ilf = pane.ItemLevelFrame
	if ilf and ilf.Value then
		B.HideRegion(ilf.Background)
		local overall, equipped = AverageItemLevel()
		if equipped then
			B:SetFont(ilf.Value, 17, "OUTLINE")
			local r, g, b = ilf.Value:GetTextColor()
			ilf.Value:SetFormattedText("%s%.2f|r  |cff8a8a90/ %.2f|r", Hex(r, g, b), equipped, overall or equipped)
		end
	end
	if pane.statsFramePool then
		for frame in pane.statsFramePool:EnumerateActive() do
			if frame.Label and frame.Value then
				B:SetFont(frame.Label, 11)
				B:SetFont(frame.Value, 11)
				frame.Label:SetTextColor(0.85, 0.75, 0.45)
				if frame.Background then frame.Background:SetAtlas(nil); frame.Background:SetColorTexture(1, 1, 1, 0.04) end
				local label = frame.Label:GetText()
				local ids = type(label) == "string" and RatingFor(label)
				local v = B.Plain(frame.numericValue, nil)
				if ids and type(v) == "number" then
					local rating = Rating(ids)
					if rating > 0 then
						frame.Value:SetFormattedText("%.2f%%  |cff8a8a90%s|r", v, BreakUpLargeNumbers(rating))
					else
						frame.Value:SetFormattedText("%.2f%%", v)
					end
				end
			end
		end
	end
	C_Timer.After(0, function() B:Try(M.ExtraBlock, M) end)
end

-------------------------------------------------------------------------------
-- Classic: the old stat boxes get the UI font, and a "More" panel beside the
-- window lists what Blizzard's sheet leaves out (crit, hit, avoidance...)
-------------------------------------------------------------------------------
local function pct(fn, ...)
	if not fn then return end
	local ok, v = pcall(fn, ...)
	if ok and type(v) == "number" then return v end
end

local function ClassicStatLines()
	local _, class = UnitClass("player")
	local lines = {}
	local function add(label, value, fmt)
		if value then lines[#lines + 1] = { label, string.format(fmt or "%.2f%%", value) } end
	end
	add("Melee crit", pct(GetCritChance))
	add("Ranged crit", pct(GetRangedCritChance))
	local spell
	for school = 2, 7 do
		local v = pct(GetSpellCritChance, school)
		if v and (not spell or v > spell) then spell = v end
	end
	if class ~= "WARRIOR" and class ~= "ROGUE" then add("Spell crit", spell) end
	add("Hit (gear)", pct(GetHitModifier))
	if class ~= "WARRIOR" and class ~= "ROGUE" then add("Spell hit (gear)", pct(GetSpellHitModifier)) end
	add("Dodge", pct(GetDodgeChance))
	add("Parry", pct(GetParryChance))
	add("Block", pct(GetBlockChance))
	if GetManaRegen and UnitPowerType("player") == 0 then
		local ok, base, casting = pcall(GetManaRegen)
		if ok and base then
			lines[#lines + 1] = { "Mana regen (5s)", string.format("%d  |cff8a8a90/ %d casting|r", math.floor(base * 5 + 0.5), math.floor((casting or 0) * 5 + 0.5)) }
		end
	end
	local _, run = GetUnitSpeed("player")
	run = B.Plain(run, 7) or 7
	lines[#lines + 1] = { "Movement speed", string.format("%d%%", math.floor(run / 7 * 100 + 0.5)) }
	local low = 100
	for slot = 1, 19 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then low = math.min(low, cur / max * 100) end
	end
	local dr = low < 25 and "|cffff5050" or low < 50 and "|cffffd060" or "|cff5fe08a"
	lines[#lines + 1] = { "Durability", string.format("%s%d%%|r", dr, low) }
	return lines
end

function M:ClassicStats()
	local cf = CharacterFrame
	if not cf then return end
	if not self.side then
		local p = CreateFrame("Frame", nil, PaperDollFrame or cf)
		p:SetWidth(180)
		p:SetPoint("TOPLEFT", cf, "TOPRIGHT", -28, -12)
		B:CreateBackdrop(p, 0.94)
		B:SetBorderSize(p, 2)
		p.cat = CreateFrame("Frame", nil, p)
		p.cat:SetHeight(24)
		p.cat:SetPoint("TOPLEFT", 4, -4)
		p.cat:SetPoint("TOPRIGHT", -4, -4)
		p.cat.Title = B:CreateText(p.cat, 13, "CENTER")
		p.cat.Title:SetPoint("CENTER")
		p.cat.Title:SetText("More")
		SkinCategory(p.cat)
		p.rows = {}
		self.side = p
	end
	local p = self.side
	local lines = ClassicStatLines()
	for i, line in ipairs(lines) do
		local r = p.rows[i]
		if not r then
			r = StatRow(p)
			r:SetPoint("TOPLEFT", p.cat, "BOTTOMLEFT", -4, -4 - (i - 1) * 15)
			r:SetPoint("TOPRIGHT", p.cat, "BOTTOMRIGHT", 4, -4 - (i - 1) * 15)
			p.rows[i] = r
		end
		r.Label:SetText(line[1] .. ":")
		r.Value:SetText(line[2])
		r:Show()
	end
	for i = #lines + 1, #p.rows do p.rows[i]:Hide() end
	p:SetHeight(36 + #lines * 15)
	p:SetShown(db().extraStats)
end

function M:ClassicStatFonts()
	if not db().betterStats then return end
	for _, n in ipairs({ "PlayerStatBackgroundTop", "PlayerStatBackgroundMiddle", "PlayerStatBackgroundBottom",
		"MeleeAttackBackgroundTop", "MeleeAttackBackgroundMiddle", "MeleeAttackBackgroundBottom",
		"RangedAttackBackgroundTop", "RangedAttackBackgroundMiddle", "RangedAttackBackgroundBottom" }) do
		B.HideRegion(_G[n])
	end
	local attr = _G.CharacterAttributesFrame
	if attr and not attr.bUnder then
		local left = CreateFrame("Frame", nil, attr)
		left:SetPoint("TOPLEFT", attr, "TOPLEFT", -2, 2)
		left:SetPoint("BOTTOMRIGHT", attr, "BOTTOM", -2, -2)
		left:SetFrameLevel(math.max(0, attr:GetFrameLevel() - 1))
		B:CreateBackdrop(left, 0.5)
		local right = CreateFrame("Frame", nil, attr)
		right:SetPoint("TOPLEFT", attr, "TOP", 2, 2)
		right:SetPoint("BOTTOMRIGHT", attr, "BOTTOMRIGHT", 2, -2)
		right:SetFrameLevel(math.max(0, attr:GetFrameLevel() - 1))
		B:CreateBackdrop(right, 0.5)
		attr.bUnder = true
	end
	local names = { "CharacterStatFrame1", "CharacterStatFrame2", "CharacterStatFrame3", "CharacterStatFrame4", "CharacterStatFrame5",
		"CharacterArmorFrame", "CharacterAttackFrame", "CharacterAttackPowerFrame", "CharacterDamageFrame",
		"CharacterRangedAttackFrame", "CharacterRangedAttackPowerFrame", "CharacterRangedDamageFrame" }
	for _, n in ipairs(names) do
		local label, value = _G[n .. "Label"], _G[n .. "StatText"]
		if label then B:SetFont(label, 11); label:SetTextColor(0.85, 0.75, 0.45) end
		if value then B:SetFont(value, 11) end
	end
	for i = 1, 5 do
		local t = _G["MagicResText" .. i]
		if t then B:SetFont(t, 11, "OUTLINE") end
	end
	for _, n in ipairs({ "CharacterNameText", "CharacterLevelText", "CharacterGuildText" }) do
		local t = _G[n]
		if t then B:SetFont(t, n == "CharacterNameText" and 14 or 11) end
	end
	if _G.CharacterNameText then _G.CharacterNameText:SetTextColor(B:AccentColor()) end
end

function M:SkinClassic()
	local cf = CharacterFrame
	cf.bBitsj = true
	local subs = {}
	for _, n in ipairs({ "PaperDollFrame", "PetPaperDollFrame", "ReputationFrame", "SkillFrame", "HonorFrame" }) do
		if _G[n] then subs[#subs + 1] = _G[n] end
	end
	B:SkinClassicWindow(cf, 11, -12, -32, 76, subs)
	B.HideRegion(_G.CharacterFramePortrait)
	for i = 1, 5 do B:SkinTab(_G["CharacterFrameTab" .. i]) end
	if PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", function()
			B:Try(M.ClassicStatFonts, M)
			B:Try(M.ClassicStats, M)
		end)
	end
	local o = CreateFrame("Frame", nil, cf)
	o:SetAllPoints(cf)
	o:SetFrameLevel(cf:GetFrameLevel() + 20)
	self.avg = B:CreateText(o, 12, "LEFT")
	self.avg:SetPoint("TOPLEFT", cf, "TOPLEFT", 20, -20)
	if PaperDollFrame then
		PaperDollFrame:HookScript("OnShow", function() B:Try(M.ClassicStatFonts, M); B:Try(M.ClassicStats, M) end)
	end
end

function M:Skin()
	local cf = CharacterFrame
	if not cf or cf.bBitsj then return end
	if not cf.NineSlice and _G.CharacterAttributesFrame then return self:SkinClassic() end
	cf.bBitsj = true
	B:SkinWindow(cf)
	for _, inset in ipairs({ _G.CharacterFrameInset, _G.CharacterFrameInsetRight }) do
		if inset then
			B.HideRegion(inset.NineSlice)
			B.HideRegion(inset.Bg)
			B:Underlay(inset, 0.35)
		end
	end
	for i = 1, 4 do B:SkinTab(_G["CharacterFrameTab" .. i]) end
	if PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", function() B:Try(M.UpdateStats, M) end)
	end
	-- average item level next to the title
	local o = CreateFrame("Frame", nil, cf)
	o:SetAllPoints(cf)
	o:SetFrameLevel(cf:GetFrameLevel() + 20)
	self.avg = B:CreateText(o, 12, "RIGHT")
	self.avg:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -30, -5)
end

function M:OnEnable()
	if not db().enabled then return end
	local function go()
		if not CharacterFrame then return end
		M:Skin()
		CharacterFrame:HookScript("OnShow", function() C_Timer.After(0, function() M:UpdateAll() end) end)
	end
	if CharacterFrame then go() end
	for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "SOCKET_INFO_UPDATE",
		"PLAYER_AVG_ITEM_LEVEL_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do
		B:RegisterEvent(e, function(_, unit)
			if e == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
			if e == "PLAYER_EQUIPMENT_CHANGED" then wipe(enchantCache) end
			if not M.pending then
				M.pending = true
				C_Timer.After(0.2, function() M.pending = false; M:UpdateAll() end)
			end
		end)
	end
end

function M:Update()
	if not CharacterFrame then return end
	for _, s in ipairs(SLOTS) do
		local btn = _G[s[1]]
		if btn and btn.bIlvl then
			B:SetFont(btn.bIlvl, db().ilvlSize, "OUTLINE")
			B:SetFont(btn.bEnchant, db().enchantSize, "OUTLINE")
		end
	end
	self:UpdateAll()
end
