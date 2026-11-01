--[[
	BitsjUI - Installer
	Shown on first login. Sets UI scale 0.62, recommended CVars and reloads.
]]
local _, B = ...
local W = B.Widgets
local C = W.colors

local Installer = {}
B.Installer = Installer

local INSTALL_VERSION = 3
local frame, step

local function RecommendedCVars()
	local cvars = {
		ActionButtonUseKeyDown = 1,   -- spells fire on key down
		lockActionBars = 1,
		nameplateMotion = 1,          -- stacking nameplates
		cameraDistanceMaxZoomFactor = 2.6,
		showTutorials = 0,
		UberTooltips = 1,
	}
	for name, value in pairs(cvars) do
		if not (C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name) == nil) then
			pcall(SetCVar, name, tostring(value))
		end
	end
end

local steps = {
	{
		title = "Welcome to BitsjUI",
		text = "A clean UI made for 2560x1440 (27\") at UI scale 0.62.\n\n"
			.. "Setup takes less than a minute. Everything can be changed later in the menu (/bui), and every frame can be dragged where you want it with \"Unlock frames\".",
		button = "Start",
	},
	{
		title = "Layout",
		text = "Applies the BitsjUI layout: slim player and target frames either side of the centre, two rows of 24 action buttons at the bottom, your buffs beside a square minimap with zone name and clock.\n\n"
			.. "This resets BitsjUI frame positions and sizes (not your keybinds).",
		button = "Apply layout",
		skip = true,
		action = function() B:ApplyDefaultLayout() end,
	},
	{
		title = "UI scale",
		text = "BitsjUI sets the UI scale to 0.62. Blizzard's own slider stops at 0.64, but the addon sets the value directly.\n\n"
			.. "Tip: under Options > Action Bars, keep bars 2-5 enabled so the keybinds of the BitsjUI bars work.",
		button = "Use 0.62",
		action = function()
			B.db.general.uiScale = 0.62
			B:ApplyUIScale()
		end,
	},
	{
		title = "Recommended settings",
		text = "Sets a few game options that suit a clean UI:\n\n"
			.. "-  Cast on key down (faster response)\n-  Locked action bars\n-  Stacked nameplates\n-  Max camera distance\n-  No tutorials\n\nSkip this to keep your own.",
		button = "Apply settings",
		skip = true,
		action = RecommendedCVars,
	},
	{
		-- optional: party tracking comes from MiniAuras (formerly MiniCC)
		title = "Party tracking (optional)",
		text = function()
			if _G.MiniAurasApi then
				return "MiniAuras is installed. It adds crowd control, defensive and interrupt tracking to your party frames.\n\n"
					.. "Set it up to fit BitsjUI: crowd control right of each party tile, defensives left of it, and the party interrupt tracker right under the party frames.\n\n"
					.. "Skip this to keep MiniAuras as it is."
			end
			return "Crowd control, defensive and interrupt tracking on your party frames comes from the free addon |cffffffffMiniAuras|r (formerly MiniCC).\n\n"
				.. "It's optional: BitsjUI works fine without it. Install MiniAuras from CurseForge or Wago if you want the tracking, then run |cffffffff/bui install|r again or use /bui > Party & raid > Fit MiniAuras to BitsjUI."
		end,
		button = function() return _G.MiniAurasApi and "Set up MiniAuras" or "Continue" end,
		skip = function() return _G.MiniAurasApi ~= nil end,
		action = function()
			local MA = B:GetModule("MiniAuras")
			if _G.MiniAurasApi and MA and MA:Available() then MA:ApplyLayout() end
		end,
	},
	{
		title = "All done!",
		text = "Reload the UI to finish.\n\n"
			.. "-  /bui opens the menu\n-  /bui move unlocks every frame for drag and drop\n-  Right-click the BitsjUI minimap button for move mode",
		button = "Reload UI",
		reload = true,
	},
}

local function Finish()
	B.global.installed = true
	B.global.installVersion = INSTALL_VERSION
end

local function Value(v)
	if type(v) == "function" then return v() end
	return v
end

local function Render()
	local s = steps[step]
	frame.title:SetText(s.title)
	frame.text:SetText(Value(s.text))
	frame.next.text:SetText(Value(s.button))
	frame.reload.text:SetText(Value(s.button))
	-- the last step reloads through a secure button (Blizzard blocks ReloadUI from addons)
	frame.next:SetShown(not s.reload)
	frame.reload:SetShown(s.reload and true or false)
	frame.skip:SetShown(Value(s.skip) and true or false)
	frame.progress:SetText(step .. " / " .. #steps)
	frame.fill:SetWidth(math.max(1, (frame:GetWidth() - 2) * step / #steps))
end

local function Create()
	frame = CreateFrame("Frame", "BitsjUIInstaller", UIParent)
	frame:SetSize(560, 360)
	frame:SetPoint("CENTER", 0, 60)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	W.Fill(frame, C.bg)
	B:CreateBorder(frame, 0, 0, 0, 1)

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(B.mediaPath .. "Textures\\Logo")
	logo:SetSize(40, 40)
	logo:SetPoint("TOPLEFT", 24, -22)

	frame.title = frame:CreateFontString(nil, "OVERLAY")
	W.Font(frame.title, 22)
	frame.title:SetPoint("LEFT", logo, "RIGHT", 14, 0)

	frame.text = frame:CreateFontString(nil, "OVERLAY")
	W.Font(frame.text, 14, { 0.82, 0.83, 0.85 })
	frame.text:SetPoint("TOPLEFT", 28, -86)
	frame.text:SetPoint("TOPRIGHT", -28, -86)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetJustifyV("TOP")
	frame.text:SetSpacing(3)

	frame.next = W.Button(frame, "", 200, 32, function()
		local s = steps[step]
		if s.action then B:Try(s.action) end
		if step < #steps then step = step + 1; Render() end
	end)
	frame.next:SetPoint("BOTTOMRIGHT", -24, 24)

	frame.reload = W.ReloadButton(frame, "Reload UI", 200, 32, Finish)
	frame.reload:SetPoint("BOTTOMRIGHT", -24, 24)
	frame.reload:Hide()

	frame.skip = W.Button(frame, "Skip", 120, 32, function()
		if step < #steps then step = step + 1; Render() end
	end)
	frame.skip:SetPoint("RIGHT", frame.next, "LEFT", -10, 0)

	local close = W.Button(frame, "Later", 100, 32, function()
		frame:Hide()
		B:Print("Run the setup any time with /bui install")
	end)
	close:SetPoint("BOTTOMLEFT", 24, 24)

	frame.progress = frame:CreateFontString(nil, "OVERLAY")
	W.Font(frame.progress, 12, C.sub)
	frame.progress:SetPoint("TOPRIGHT", -24, -34)

	local bar = frame:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(C.element[1], C.element[2], C.element[3], 1)
	bar:SetPoint("BOTTOMLEFT", 1, 1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetHeight(3)
	frame.fill = frame:CreateTexture(nil, "OVERLAY")
	frame.fill:SetColorTexture(B:AccentColor())
	frame.fill:SetPoint("BOTTOMLEFT", 1, 1)
	frame.fill:SetHeight(3)
end

function Installer:Show()
	if not frame then Create() end
	step = 1
	Render()
	frame:Show()
end

B:RegisterCallback("LOGIN", function()
	if not B.global.installed or (B.global.installVersion or 0) < INSTALL_VERSION then
		C_Timer.After(2, function() Installer:Show() end)
	end
end)
