--[[
	BitsjUI - MiniAuras support
	MiniAuras (crowd control, defensives and important buffs on party / raid
	frames and nameplates) only knows the frames of the big UI suites. This
	hands it BitsjUI's party and raid tiles through MiniAuras' own public API
	(MiniAurasApi.v1:RegisterFrameProvider), so its icons sit on our frames.

	"Fit MiniAuras to BitsjUI" (asked once when MiniAuras is found, and a
	button in /bui -> Raid frames) sets MiniAuras' look to match:
	  - BitsjUI's font, cropped icons
	  - party: crowd control right of each tile, defensives / important buffs
	    left of it, both sized to the tile height
	  - raid: small icons centred on the tile
	  - nameplate icons sized to BitsjUI's nameplates
	  - MiniAuras' own frame buff / debuff rows stay off (BitsjUI shows those)
	MiniAuras applies the changes after the reload that follows.
]]
local _, B = ...
local M = B:NewModule("MiniAuras")

local refreshCallback

-------------------------------------------------------------------------------
-- Frame provider
-------------------------------------------------------------------------------
local function RegisterProvider()
	local api = _G.MiniAurasApi and _G.MiniAurasApi.v1
	if not api or not api.RegisterFrameProvider or M.registered then return end
	M.registered = true
	api:RegisterFrameProvider({
		Name = "BitsjUI",
		GetFrames = function()
			local RF = B:GetModule("RaidFrames")
			return RF and RF.GetUnitButtons and RF:GetUnitButtons() or {}
		end,
		RegisterRefreshFrames = function(cb) refreshCallback = cb end,
	})
	-- tell MiniAuras whenever a tile gets a new unit (MiniAuras batches these itself)
	B:RegisterCallback("RAID_BUTTONS_CHANGED", function()
		if refreshCallback then pcall(refreshCallback) end
	end)
end

-------------------------------------------------------------------------------
-- One-time look setup
-------------------------------------------------------------------------------
-- set db.a.b.c = value, but only where MiniAuras already has that table
-- (so a different MiniAuras version never gets keys it doesn't know)
local function Set(root, path, value)
	local t = root
	local keys = {}
	for k in path:gmatch("[^%.]+") do keys[#keys + 1] = k end
	for i = 1, #keys - 1 do
		t = type(t) == "table" and t[keys[i]] or nil
		if type(t) ~= "table" then return false end
	end
	if t[keys[#keys]] == nil then return false end
	t[keys[#keys]] = value
	return true
end

function M:Available()
	return _G.MiniAurasDB ~= nil and type(_G.MiniAurasDB.Modules) == "table"
end

function M:ApplyLayout()
	local db = _G.MiniAurasDB
	if not self:Available() then
		B:Print("MiniAuras isn't loaded (or hasn't saved its settings yet). Log in once with it enabled, then try again.")
		return
	end
	local m = db.Modules
	-- look
	if LibStub and LibStub("LibSharedMedia-3.0", true) then
		local fontName = "Bitsj " .. (B.db.general.font or "Barlow")
		if LibStub("LibSharedMedia-3.0"):IsValid("font", fontName) then Set(db, "Font", fontName) end
	end
	Set(db, "IconZoom", true)

	-- party tiles: crowd control right of the tile, defensives / important left of it
	Set(m, "CrowdControl.Default.Grow", "RIGHT")
	Set(m, "CrowdControl.Default.Offset.X", 4)
	Set(m, "CrowdControl.Default.Offset.Y", 0)
	Set(m, "CrowdControl.Default.IconSpacing", 3)
	Set(m, "CrowdControl.Default.Icons.SizeIsPercent", true)
	Set(m, "CrowdControl.Default.Icons.SizePercent", 90)
	Set(m, "ImportantAuras.Default.Grow", "LEFT")
	Set(m, "ImportantAuras.Default.Offset.X", -4)
	Set(m, "ImportantAuras.Default.Offset.Y", 0)
	Set(m, "ImportantAuras.Default.IconSpacing", 3)
	Set(m, "ImportantAuras.Default.Icons.SizeIsPercent", true)
	Set(m, "ImportantAuras.Default.Icons.SizePercent", 80)

	-- raid tiles are small: icons in the middle of the tile
	Set(m, "CrowdControl.Raid.Grow", "CENTER")
	Set(m, "CrowdControl.Raid.Icons.SizeIsPercent", true)
	Set(m, "CrowdControl.Raid.Icons.SizePercent", 50)
	Set(m, "ImportantAuras.Raid.Grow", "CENTER")
	Set(m, "ImportantAuras.Raid.Icons.SizeIsPercent", true)
	Set(m, "ImportantAuras.Raid.Icons.SizePercent", 45)

	-- BitsjUI already draws buffs / debuffs on its tiles
	Set(m, "FrameAuras.Buffs.Enabled", false)
	Set(m, "FrameAuras.Debuffs.Enabled", false)

	-- nameplate icons the size of BitsjUI's plate debuffs
	local size = math.max(18, (B.db.nameplates.debuffSize or 22) + 2)
	for _, side in ipairs({ "Enemy", "Friendly" }) do
		for _, bar in ipairs({ "Bar1", "Bar2" }) do
			Set(m, "Nameplates." .. side .. "." .. bar .. ".Icons.Size", size)
		end
	end

	B.global.miniAurasStyled = true
	B:Print("MiniAuras set up to match BitsjUI. Reloading...")
	-- ReloadUI only works straight from a click (it's a protected call),
	-- so it runs right here, inside the button / popup click
	ReloadUI()
end

StaticPopupDialogs["BITSJUI_MINIAURAS"] = {
	text = "BitsjUI found MiniAuras.\n\nSet MiniAuras up to fit BitsjUI's party and raid frames? (Reloads the UI.)",
	button1 = YES, button2 = NO,
	OnAccept = function() M:ApplyLayout() end,
	OnCancel = function() B.global.miniAurasStyled = true end,   -- don't ask again
	timeout = 0, whileDead = true, hideOnEscape = true,
}

function M:OnEnable()
	if not _G.MiniAurasApi then return end
	-- MiniAuras ships LibSharedMedia; make sure our fonts are in it
	B:RegisterSharedMedia()
	RegisterProvider()
	if not B.global.miniAurasStyled then
		C_Timer.After(6, function()
			if M:Available() and not InCombatLockdown() and not B.global.miniAurasStyled then
				StaticPopup_Show("BITSJUI_MINIAURAS")
			end
		end)
	end
end
