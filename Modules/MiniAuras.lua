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
	  - the party interrupt tracker sits right under the party frames, same
	    width, with BitsjUI's bar texture
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
	-- MiniAuras keeps the live settings at the top and a copy per profile;
	-- write both so a profile switch / reload doesn't bring the old ones back
	local roots = { db }
	local prof = type(db.Profiles) == "table" and db.Profiles[db.ActiveProfile or "Default"]
	if type(prof) == "table" and type(prof.Modules) == "table" then roots[2] = prof end
	for _, root in ipairs(roots) do self:ApplyTo(root) end

	B.global.miniAurasStyled = true
	B.global.miniAurasLayout = M.LAYOUT_VERSION
	B:Print("MiniAuras set up to match BitsjUI.")
	-- no ReloadUI() here: Blizzard blocks it from addon code. The buttons that
	-- call this are secure /reload buttons (B.Widgets.ReloadButton).
end

-- bump when the layout below changes, so people get asked once more
M.LAYOUT_VERSION = 3

function M:ApplyTo(db)
	local m = db.Modules
	-- look
	if LibStub and LibStub("LibSharedMedia-3.0", true) then
		local fontName = "Bitsj " .. (B:FontName("raidframes") or "Barlow")
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

	-- interrupt tracker: right under the party frames, same width, BitsjUI bars
	local party = B.db.raidframes.party
	Set(m, "AllyKickTracker.RelativeTo", "BitsjUIParty")
	Set(m, "AllyKickTracker.Point", "TOPLEFT")
	Set(m, "AllyKickTracker.RelativePoint", "BOTTOMLEFT")
	Set(m, "AllyKickTracker.Offset.X", 0)
	Set(m, "AllyKickTracker.Offset.Y", -8)
	Set(m, "AllyKickTracker.Grow", "DOWN")
	Set(m, "AllyKickTracker.BarSpacing", party.spacing or 4)
	Set(m, "AllyKickTracker.Locked", true)
	Set(m, "AllyKickTracker.Bars.Width", math.floor((party.width or 120) + 0.5))
	Set(m, "AllyKickTracker.Bars.Height", 20)
	local tex = B.db.general.texture
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if type(tex) == "string" and LSM and LSM:IsValid("statusbar", tex) then Set(m, "AllyKickTracker.Bars.Texture", tex) end

	-- MiniAuras' debug mode is on by default and spams chat with notes like
	-- "Sound registration failed"; those are for its author, not for players
	Set(db, "DebugMode", false)

end

-- popup when BitsjUI finds MiniAuras (newly installed, or our layout for it
-- changed). It opens the installer at its MiniAuras step, which does the
-- setup and ends with the reload.
local prompt
function M:ShowPrompt()
	local W = B.Widgets
	if not W or InCombatLockdown() then return end
	if not prompt then
		prompt = CreateFrame("Frame", "BitsjUIMiniAurasPrompt", UIParent)
		prompt:SetSize(380, 130)
		prompt:SetPoint("TOP", 0, -160)
		prompt:SetFrameStrata("DIALOG")
		prompt:EnableMouse(true)
		local bg = prompt:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
		B:CreateBorder(prompt, 0, 0, 0, 1)
		local text = prompt:CreateFontString(nil, "OVERLAY")
		B:SetFont(text, 13)
		text:SetPoint("TOPLEFT", 14, -14)
		text:SetPoint("TOPRIGHT", -14, -14)
		text:SetJustifyH("CENTER")
		text:SetWordWrap(true)
		prompt.text = text
		local open = W.Button(prompt, "Open setup", 110, 26, function()
			prompt:Hide()
			if B.Installer then B.Installer:Show("miniauras") end
		end)
		open:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -61, 14)
		prompt.open = open
		local later = W.Button(prompt, "Not now", 110, 26, function()
			prompt:Hide()   -- asked again next login
		end)
		later:SetPoint("BOTTOM", prompt, "BOTTOM", 0, 14)
		local never = W.Button(prompt, "Don't ask", 110, 26, function()
			B.global.miniAurasDeclined = true
			prompt:Hide()
			B:Print("Set up MiniAuras any time in /bui > Party & raid, or with /bui install.")
		end)
		never:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 61, 14)
	end
	if B.global.miniAurasStyled then
		prompt.text:SetText("BitsjUI's MiniAuras layout has been updated.\nOpen the setup to apply it to your party frames?")
	else
		prompt.text:SetText("BitsjUI found |cffffffffMiniAuras|r!\nOpen the setup to fit its crowd control, defensive and interrupt tracking to BitsjUI's party frames?")
	end
	prompt:Show()
end

function M:OnEnable()
	if not _G.MiniAurasApi then
		-- not installed / disabled: ask again if it shows up later
		B.global.miniAurasSeen = nil
		return
	end
	-- MiniAuras ships LibSharedMedia; make sure our fonts are in it
	B:RegisterSharedMedia()
	RegisterProvider()
	-- newly found (first time, or installed again after being removed):
	-- a fresh "Don't ask" is not carried over from the old install
	local isNew = not B.global.miniAurasSeen
	if isNew and not B.global.miniAurasStyled then B.global.miniAurasDeclined = nil end
	local outdated = (B.global.miniAurasLayout or 0) < M.LAYOUT_VERSION
	if not outdated or B.global.miniAurasDeclined then
		B.global.miniAurasSeen = true
		return
	end
	C_Timer.After(6, function()
		-- first-time setup asks about MiniAuras itself
		local inst = _G.BitsjUIInstaller
		if not B.global.installed or (inst and inst:IsShown()) then return end
		-- MiniAuras writes its settings on its first login; until then try next time
		if not M:Available() then return end
		B.global.miniAurasSeen = true
		if InCombatLockdown() then
			local f = CreateFrame("Frame")
			f:RegisterEvent("PLAYER_REGEN_ENABLED")
			f:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				M:ShowPrompt()
			end)
		else
			M:ShowPrompt()
		end
	end)
end
