--[[
	BitsjUI - Update notice and "What's new"
	WoW addons can't reach the internet, so BitsjUI learns about new versions
	the way boss mods do: every copy quietly tells the others in your guild,
	group or raid which version it runs (a hidden addon message, not chat).
	If anyone has a newer one you get a small notice, once per version, and
	it is remembered across logins until you update.
	After you update and log in / /reload, a "What's new" window lists the
	changes of the new version.

	/bui version     - your version and the newest one seen
	/bui whatsnew    - show the "What's new" window again
	/bui updatetest  - show the update notice with a fake newer version
]]
local _, B = ...
local M = B:NewModule("Update")

local PREFIX = "BitsjUI"
local lastSent = {}      -- channel -> time
local replied = {}       -- sender -> true (answered once per session)
local notified = {}      -- version -> true (notice shown this session)

-------------------------------------------------------------------------------
-- Changelog: newest first. Shown once after updating to that version.
-------------------------------------------------------------------------------
B.CHANGELOG = {
	{ "1.2.0", {
		"Defensives: icons above the player frame while a defensive is active on you, for every class, including ones others cast on you.",
		"Set size, spacing and extra or ignored spell IDs in /bui > Defensives.",
	} },
	{ "1.1.0", {
		"Unit frames fit around Blizzard's Cooldown Manager: player left, target right, moving with it as it grows or shrinks.",
		"Character window: the stats list scrolls with the mouse wheel when it is too long.",
	} },
	{ "1.0.0", {
		"First official release of BitsjUI.",
		"Clean, rounded UI with its own menu (/bui) and drag and drop for every frame (/bui move).",
		"Action bars, unit frames, castbars, nameplates, party and raid frames, damage meter, spell timers and buffs.",
		"Minimap, chat, tooltips, bags, character sheet, friends list and quest tracker in the same style.",
		"Works on Retail and WoW Forever.",
		"Update notice when a newer version is around, and this window after each update.",
	} },
}

-------------------------------------------------------------------------------
-- Versions
-------------------------------------------------------------------------------
local function Parse(v)
	local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
	if not a then return nil end
	return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end

-- true when version a is newer than b
function M.Newer(a, b)
	local x, y = Parse(a), Parse(b)
	if not x or not y then return false end
	for i = 1, 3 do
		if x[i] ~= y[i] then return x[i] > y[i] end
	end
	return false
end

local function Global() return B.global end

-------------------------------------------------------------------------------
-- Notice: small panel at the top of the screen + a chat line
-------------------------------------------------------------------------------
local notice
local function CreateNotice()
	local f = CreateFrame("Frame", "BitsjUIUpdateNotice", UIParent)
	f:SetSize(360, 64)
	f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	f:SetFrameStrata("DIALOG")
	B:CreateBackdrop(f, 0.95)
	B:SetBorderSize(f, 2)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetPoint("TOPLEFT", 0, 0)
	f.line:SetPoint("BOTTOMLEFT", 0, 0)
	f.line:SetWidth(3)
	f.title = B:CreateText(f, 14, "LEFT")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.text = B:CreateText(f, 11, "LEFT")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.text:SetPoint("RIGHT", f, "RIGHT", -70, 0)
	f.text:SetTextColor(0.8, 0.82, 0.86)
	local ok = CreateFrame("Button", nil, f)
	ok:SetSize(52, 22)
	ok:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	B:CreateBackdrop(ok, 1)
	ok.text = B:CreateText(ok, 11, "CENTER")
	ok.text:SetPoint("CENTER")
	ok.text:SetText("OK")
	ok:SetScript("OnClick", function() f:Hide() end)
	ok:SetScript("OnEnter", function(self) self.text:SetTextColor(B:AccentColor()) end)
	ok:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
	f:EnableMouse(true)
	f:Hide()
	return f
end

function M:Notify(newVersion, from)
	if not B.db.general.updateNotify then return end
	if notified[newVersion] then return end
	notified[newVersion] = true
	notice = notice or CreateNotice()
	notice.line:SetColorTexture(B:AccentColor())
	notice.title:SetText(B:TitleText() .. " |cffffffff" .. newVersion .. " is available|r")
	notice.text:SetText("You have " .. B.version .. ". Update in the CurseForge / Wago app (or copy the new files), then /reload or relog."
		.. (from and ("  |cff8a8a90(seen from " .. from .. ")|r") or ""))
	notice.text:SetWidth(270)
	notice:SetHeight(math.max(64, 30 + notice.text:GetStringHeight() + 8))
	notice:Show()
	B:Print("Version |cffffffff" .. newVersion .. "|r is available (you have " .. B.version .. ").")
	if PlaySound and SOUNDKIT and SOUNDKIT.UI_CHAT_SCROLL_BUTTON then pcall(PlaySound, SOUNDKIT.UI_CHAT_SCROLL_BUTTON) end
end

-- a version heard from another player
local function Heard(version, sender)
	if not Parse(version) then return end
	local g = Global()
	if M.Newer(version, B.version) then
		if not g.latestSeen or M.Newer(version, g.latestSeen) then g.latestSeen = version end
		if not InCombatLockdown() then
			M:Notify(version, sender)
		else
			M.pending = { version, sender }
		end
	elseif M.Newer(B.version, version) and sender and not replied[sender] then
		-- they're behind: tell them (once), so the notice reaches them too
		replied[sender] = true
		C_Timer.After(math.random() * 3, function() M:Send("WHISPER", sender) end)
	end
end

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------
local function Channels()
	local list = {}
	if IsInGuild and IsInGuild() then list[#list + 1] = "GUILD" end
	if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then list[#list + 1] = "INSTANCE_CHAT"
	elseif IsInRaid and IsInRaid() then list[#list + 1] = "RAID"
	elseif IsInGroup and IsInGroup() then list[#list + 1] = "PARTY" end
	return list
end

function M:Send(channel, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	local now = GetTime()
	local key = channel .. (target or "")
	if lastSent[key] and now - lastSent[key] < 30 then return end
	lastSent[key] = now
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. B.version, channel, target)
end

function M:Broadcast()
	if not B.db.general.updateNotify then return end
	if InCombatLockdown() then return end   -- addon messages are throttled / restricted in combat
	for _, ch in ipairs(Channels()) do self:Send(ch) end
end

local function OnMessage(prefix, text, _, sender)
	if prefix ~= PREFIX or B.IsSecret(text) or type(text) ~= "string" then return end
	if B.IsSecret(sender) then sender = nil end
	local me = UnitName("player")
	if sender and me and (sender == me or sender:match("^([^%-]+)") == me) then return end
	local v = text:match("^V:(.+)$")
	if v then Heard(v, sender and sender:gsub("%-.+$", "")) end
end

-------------------------------------------------------------------------------
-- What's new window
-------------------------------------------------------------------------------
local whatsNew
local function CreateWhatsNew()
	local f = CreateFrame("Frame", "BitsjUIWhatsNew", UIParent)
	f:SetSize(440, 260)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	B:CreateBackdrop(f, 0.96)
	B:SetBorderSize(f, 2)
	f.title = B:CreateText(f, 16, "LEFT")
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("TOPLEFT", 12, -40)
	f.line:SetPoint("TOPRIGHT", -12, -40)
	f.body = B:CreateText(f, 12, "LEFT")
	f.body:SetPoint("TOPLEFT", 18, -52)
	f.body:SetPoint("RIGHT", f, "RIGHT", -18, 0)
	f.body:SetJustifyV("TOP")
	f.body:SetSpacing(4)
	local close = CreateFrame("Button", nil, f)
	close:SetSize(80, 24)
	close:SetPoint("BOTTOM", 0, 12)
	B:CreateBackdrop(close, 1)
	close.text = B:CreateText(close, 12, "CENTER")
	close.text:SetPoint("CENTER")
	close.text:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(B:AccentColor()) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
	tinsert(UISpecialFrames, "BitsjUIWhatsNew")   -- Esc closes it
	f:Hide()
	return f
end

-- every changelog entry newer than `since` (or just the current one)
function M:ShowWhatsNew(since)
	whatsNew = whatsNew or CreateWhatsNew()
	local ar, ag, ab = B:AccentColor()
	local hex = string.format("|cff%02x%02x%02x", math.floor(ar * 255), math.floor(ag * 255), math.floor(ab * 255))
	local lines = {}
	for _, entry in ipairs(B.CHANGELOG) do
		local v, items = entry[1], entry[2]
		if (since and M.Newer(v, since) and not M.Newer(v, B.version)) or (not since and v == B.version) then
			lines[#lines + 1] = hex .. "Version " .. v .. "|r"
			for _, item in ipairs(items) do lines[#lines + 1] = "|cffd0d2d6-|r  " .. item end
			lines[#lines + 1] = " "
		end
	end
	if #lines == 0 then lines[1] = "No notes for this version." end
	whatsNew.title:SetText(B:TitleText() .. " |cffffffffupdated to " .. B.version .. "|r")
	whatsNew.line:SetColorTexture(ar, ag, ab, 0.7)
	whatsNew.body:SetText(table.concat(lines, "\n"))
	whatsNew:SetHeight(math.min(520, 52 + whatsNew.body:GetStringHeight() + 50))
	whatsNew:Show()
end

-------------------------------------------------------------------------------
function M:OnEnable()
	local g = Global()
	-- updated since last time? -> What's new (existing installs only, not first run)
	local last = g.lastRunVersion
	if last and M.Newer(B.version, last) and B.db.general.whatsNew then
		C_Timer.After(4, function() B:Try(M.ShowWhatsNew, M, last) end)
	elseif not last and g.installed then
		C_Timer.After(4, function() B:Try(M.ShowWhatsNew, M) end)
	end
	g.lastRunVersion = B.version
	-- we already know a newer one exists (heard on an earlier login)
	if g.latestSeen and not M.Newer(g.latestSeen, B.version) then g.latestSeen = nil end
	if g.latestSeen then C_Timer.After(8, function() M:Notify(g.latestSeen) end) end

	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
	local f = CreateFrame("Frame")
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(f.RegisterEvent, f, "GUILD_ROSTER_UPDATE")
	f:SetScript("OnEvent", B.Safe(function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			OnMessage(...)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if M.pending then local p = M.pending; M.pending = nil; M:Notify(p[1], p[2]) end
		elseif event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(10, function() M:Broadcast() end)
		else
			M:Broadcast()
		end
	end))
end

-- slash helpers (/bui version, /bui whatsnew, /bui updatetest)
function M:Slash(cmd)
	if cmd == "version" then
		local g = Global()
		B:Print("You have " .. B.version .. (g.latestSeen and (", newest seen: " .. g.latestSeen) or ", that's the newest one seen."))
	elseif cmd == "whatsnew" then
		self:ShowWhatsNew()
	elseif cmd == "updatetest" then
		local p = Parse(B.version) or { 0, 0, 0 }
		notified = {}
		self:Notify(string.format("%d.%d.%d", p[1], p[2] + 1, 0), "test")
	end
end
