--[[
	BitsjUI - Quality of life
	Small automations and helpers, each with its own switch in /bui -> QoL.
	Merchant: auto repair (guild funds first), sell junk.
	Looting: fast loot, DELETE typed for you.
	Cutscenes: skip cinematics and movies.
	Auction house: current expansion filter on.
	Group finder: keystone slotted for you, double-click sign-up, reset announce.
	Extras: FPS / latency text, low durability warning, auto open containers,
	no screenshot message.
]]
local _, B = ...
local M = B:NewModule("QoL")

-- fonts: this file uses the "minimap" section font (/bui > General > Fonts)
local FONT_SECTION = "minimap"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local function db() return B.db.qol end

local function Money(c)
	if GetMoneyString then return GetMoneyString(c, true) end
	return string.format("%dg %ds", math.floor(c / 10000), math.floor((c % 10000) / 100))
end

-------------------------------------------------------------------------------
-- Merchant: repair + junk
-------------------------------------------------------------------------------
local function OnMerchant()
	local d = db()
	if d.sellJunk and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		pcall(C_MerchantFrame.SellAllJunkItems)
	end
	if d.autoRepair and CanMerchantRepair and CanMerchantRepair() then
		local cost, can = GetRepairAllCost()
		if can and cost and cost > 0 then
			local guild = d.guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
				and (GetGuildBankWithdrawMoney() or 0) >= cost
			RepairAllItems(guild and true or false)
			if guild then
				-- guild bank might refuse (daily limit): pay the rest yourself
				C_Timer.After(0.5, function()
					local left, still = GetRepairAllCost()
					if still and left and left > 0 then RepairAllItems(false) end
				end)
			end
			B:Print("Repaired for " .. Money(cost) .. (guild and " (guild bank)" or "") .. ".")
		end
	end
end

-------------------------------------------------------------------------------
-- Fast loot (hold Shift to look at the loot window instead)
-------------------------------------------------------------------------------
local lastLoot = -1
local function OnLootReady()
	if not db().fastLoot or IsShiftKeyDown() then return end
	local now = GetTime()
	if now - lastLoot < 0.3 then return end
	lastLoot = now
	for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

-------------------------------------------------------------------------------
-- Type DELETE for you
-------------------------------------------------------------------------------
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local function FillDelete(which)
	if not db().autoDelete or not DELETE_POPUPS[which] then return end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
	if not dialog then return end
	local eb = dialog.EditBox or dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
	if eb and DELETE_ITEM_CONFIRM_STRING then
		eb:SetText(DELETE_ITEM_CONFIRM_STRING)
		eb:ClearFocus()
	end
end

-------------------------------------------------------------------------------
-- Cutscenes
-------------------------------------------------------------------------------
local function OnCinematic(event)
	if not db().skipCinematics or IsShiftKeyDown() then return end
	if event == "CINEMATIC_START" then
		if CinematicFrame and CinematicFrame.isRealCinematic and StopCinematic then
			StopCinematic()
		elseif CanCancelScene and CanCancelScene() and CancelScene then
			CancelScene()
		end
	elseif event == "PLAY_MOVIE" and MovieFrame then
		pcall(MovieFrame.StopMovie, MovieFrame)
		MovieFrame:Hide()
	end
end

-------------------------------------------------------------------------------
-- Auction house: current expansion only
-------------------------------------------------------------------------------
local function OnAuctionHouse()
	if not db().ahCurrentExpansion then return end
	C_Timer.After(0, function()
		local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
		local fb = bar and bar.FilterButton
		local key = Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.CurrentExpansionOnly
		if not (fb and fb.filters and key) then return end
		fb.filters[key] = true
		if bar.UpdateClearFiltersButton then pcall(bar.UpdateClearFiltersButton, bar) end
	end)
end

-------------------------------------------------------------------------------
-- Mythic+: put the keystone in
-------------------------------------------------------------------------------
local function SlotKeystone()
	if not db().autoKeystone or not C_ChallengeMode then return end
	if C_ChallengeMode.GetSlottedKeystoneInfo and C_ChallengeMode.GetSlottedKeystoneInfo() then return end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link and link:find("|Hkeystone:", 1, true) then
				C_Container.PickupContainerItem(bag, slot)
				if CursorHasItem() then C_ChallengeMode.SlotKeystone() end
				return
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Group finder: double-click a group to sign up, skip the role dialog
-------------------------------------------------------------------------------
local quick = { id = nil, t = 0 }
local function HookGroupFinder()
	if M.lfgHooked or not LFGListSearchEntry_OnClick then return end
	M.lfgHooked = true
	hooksecurefunc("LFGListSearchEntry_OnClick", function(entry, button)
		if not db().quickSignup or button == "RightButton" then return end
		local panel = LFGListFrame and LFGListFrame.SearchPanel
		if not panel or not entry.resultID then return end
		local now = GetTime()
		if quick.id == entry.resultID and now - quick.t < 0.4 then
			quick.id = nil
			if panel.SignUpButton and panel.SignUpButton:IsEnabled() then
				if panel.selectedResult ~= entry.resultID and LFGListSearchPanel_SelectResult then
					LFGListSearchPanel_SelectResult(panel, entry.resultID)
				end
				if LFGListSearchPanel_SignUp then LFGListSearchPanel_SignUp(panel) end
			end
		else
			quick.id, quick.t = entry.resultID, now
		end
	end)
	if LFGListApplicationDialog then
		LFGListApplicationDialog:HookScript("OnShow", function(self)
			if not db().quickSignup or IsShiftKeyDown() then return end
			if self.SignUpButton and self.SignUpButton:IsEnabled() then self.SignUpButton:Click() end
		end)
	end
end

-------------------------------------------------------------------------------
-- Tell the group when you reset instances
-------------------------------------------------------------------------------
local resetPattern
local function OnSystemMessage(msg)
	if not db().announceReset or type(msg) ~= "string" or B.IsSecret(msg) then return end
	if not IsInGroup() then return end
	if not resetPattern and INSTANCE_RESET_SUCCESS then
		local escaped = INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		resetPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
	end
	local name = resetPattern and msg:match(resetPattern)
	if not name then return end
	local channel = IsInRaid() and "RAID" or "PARTY"
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	pcall(send, name .. " has been reset.", channel)
end

-------------------------------------------------------------------------------
-- Open containers (bags, caches...) out of combat
-------------------------------------------------------------------------------
local openable = {}
local function IsOpenable(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID or info.isLocked then return false end
	local known = openable[info.itemID]
	if known ~= nil then return known end
	local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
	local yes = false
	for _, line in ipairs(tip and tip.lines or {}) do
		if line.leftText == ITEM_OPENABLE then yes = true; break end
	end
	openable[info.itemID] = yes
	return yes
end

local opening
local function OpenContainers()
	if not db().openContainers or opening or InCombatLockdown() then return end
	opening = true
	C_Timer.After(0.4, function()
		opening = false
		if InCombatLockdown() or (MerchantFrame and MerchantFrame:IsShown()) then return end
		for bag = 0, (NUM_BAG_SLOTS or 4) do
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				if IsOpenable(bag, slot) then
					C_Container.UseContainerItem(bag, slot)
					return   -- one per bag update; the next update opens the next
				end
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Screenshot message
-------------------------------------------------------------------------------
local function HideScreenshotText()
	if not db().hideScreenshotText then return end
	C_Timer.After(0, function() if ActionStatus then ActionStatus:Hide() end end)
end

-------------------------------------------------------------------------------
-- FPS / latency text
-------------------------------------------------------------------------------
local perf
local function UpdatePerf()
	local d = db()
	if not perf then return end
	perf:SetShown(d.fpsText)
	perf.text:SetFont(GetFont(), d.fpsSize, B:GetOutline())
end

local function CreatePerf()
	perf = CreateFrame("Frame", "BitsjUIPerformance", UIParent)
	perf:SetSize(120, 16)
	perf.text = perf:CreateFontString(nil, "OVERLAY")
	perf.text:SetFont(GetFont(), db().fpsSize, B:GetOutline())
	perf.text:SetShadowOffset(1, -1)
	perf.text:SetPoint("CENTER")
	B:RegisterMover(perf, "perf", "FPS / latency", { "TOPRIGHT", "TOPRIGHT", -60, -222 })
	perf.elapsed = 1
	perf:SetScript("OnUpdate", function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 1 then return end
		self.elapsed = 0
		local fps = math.floor(GetFramerate() + 0.5)
		local _, _, home, world = GetNetStats()
		local ms = math.max(home or 0, world or 0)
		local function col(good, ok, v, low)
			if low then return v >= good and "|cff5fe08a" or v >= ok and "|cffffd060" or "|cffff5050" end
			return v <= good and "|cff5fe08a" or v <= ok and "|cffffd060" or "|cffff5050"
		end
		self.text:SetFormattedText("%s%d|r fps   %s%d|r ms", col(60, 30, fps, true), fps, col(80, 200, ms), ms)
	end)
	UpdatePerf()
end

-------------------------------------------------------------------------------
-- Low durability warning (out of combat, centre of the screen)
-------------------------------------------------------------------------------
local dura
local function CheckDurability()
	local d = db()
	if not dura then return end
	if not d.durabilityWarning or InCombatLockdown() then dura:Hide(); return end
	local lowest = 100
	for slot = 1, 19 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then lowest = math.min(lowest, cur / max * 100) end
	end
	if lowest <= d.durabilityPercent then
		dura.text:SetFormattedText("Low durability  (%d%%)", lowest)
		dura:Show()
	else
		dura:Hide()
	end
end

local function CreateDurability()
	dura = CreateFrame("Frame", "BitsjUIDurability", UIParent)
	dura:SetSize(260, 24)
	dura.text = dura:CreateFontString(nil, "OVERLAY")
	dura.text:SetFont(GetFont(), 18, B:Flags("OUTLINE"))
	dura.text:SetTextColor(1, 0.35, 0.3)
	dura.text:SetPoint("CENTER")
	B:RegisterMover(dura, "durability", "Durability warning", { "TOP", "TOP", 0, -180 })
	dura:Hide()
end

-------------------------------------------------------------------------------
function M:OnEnable()
	if not db().enabled then return end
	B:RegisterEvent("MERCHANT_SHOW", OnMerchant)
	B:RegisterEvent("LOOT_READY", OnLootReady)
	B:RegisterEvent("CINEMATIC_START", OnCinematic)
	B:RegisterEvent("PLAY_MOVIE", OnCinematic)
	B:RegisterEvent("AUCTION_HOUSE_SHOW", OnAuctionHouse)
	B:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN", SlotKeystone)
	B:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg) OnSystemMessage(msg) end)
	B:RegisterEvent("BAG_UPDATE_DELAYED", OpenContainers)
	B:RegisterEvent("SCREENSHOT_SUCCEEDED", HideScreenshotText)
	B:RegisterEvent("SCREENSHOT_FAILED", HideScreenshotText)
	if StaticPopup_Show then
		hooksecurefunc("StaticPopup_Show", function(which) B:Try(FillDelete, which) end)
	end
	HookGroupFinder()
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_GroupFinder" or name == "Blizzard_LookingForGroupUI" then HookGroupFinder() end
	end)

	CreatePerf()
	CreateDurability()
	for _, e in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
		B:RegisterEvent(e, CheckDurability)
	end
	CheckDurability()
end

function M:Update()
	UpdatePerf()
	CheckDurability()
end
