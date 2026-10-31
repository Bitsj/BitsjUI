--[[
	BitsjUI - Core
	Namespace, event system, database, combat-queue, pixel helpers and modules.
	Written for the Retail (Midnight 12.x) client. Code that reads combat data is
	"secret value" safe: everything that may receive a secret goes through pcall
	or a widget API that accepts secrets.
]]
local ADDON, B = ...
_G.BitsjUI = B

B.name = ADDON
B.title = "|cff4fd1b5Bitsj|rUI"
B.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
B.mediaPath = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- which game this is: retail (Midnight) or Classic Era. Classic Era runs on
-- the same modern client, but without some systems (aura containers, the
-- built-in damage meter, Cooldown Manager, specs, holy power...).
B.isClassic = WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
-- WoW Forever ("Camelot"): the modern retail engine with classic game content
B.isForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
B.isRetail = not B.isClassic and not B.isForever
-- classic game rules (no specs/holy power, old enchant slots, ranged slot, pet happiness)
B.classicContent = B.isClassic or B.isForever
B.white = "Interface\\Buttons\\WHITE8X8"
B.modules, B.moduleOrder = {}, {}

-------------------------------------------------------------------------------
-- Small utilities
-------------------------------------------------------------------------------
local issecret = _G.issecretvalue or function() return false end
B.IsSecret = issecret

-- true when v holds a value (works for secret values, which are never nil)
function B.HasValue(v)
	if issecret(v) then return true end
	return v ~= nil
end

-- returns v if it is a normal value, otherwise the fallback
function B.Plain(v, fallback)
	if issecret(v) then return fallback end
	if v == nil then return fallback end
	return v
end

function B.Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

function B.Round(v, dec)
	local m = 10 ^ (dec or 0)
	return math.floor(v * m + 0.5) / m
end

function B.Split(str, sep)
	local out = {}
	for part in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = part end
	return out
end

function B.CopyTable(src)
	if type(src) ~= "table" then return src end
	local t = {}
	for k, v in pairs(src) do t[k] = B.CopyTable(v) end
	return t
end

-- fill missing keys in dst from src (recursive)
function B.MergeDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			B.MergeDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function B:Print(...)
	local msg = ""
	for i = 1, select("#", ...) do msg = msg .. tostring(select(i, ...)) .. " " end
	local title = self.title
	if self.AccentColor then
		local ok, r, g, b = pcall(self.AccentColor, self)
		if ok and r then title = string.format("|cff%02x%02x%02xBitsj|rUI", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end
	end
	DEFAULT_CHAT_FRAME:AddMessage(title .. ": " .. msg)
end

-- Errors are logged (see /bui errors) and each unique message is only
-- reported to the game's error handler once, so a bug that fires every
-- frame in combat can never flood the client.
B.errorLog, B.errorSeen = {}, {}
function B:Error(err)
	err = tostring(err)
	local key = err:gsub("%d+", "#")
	local seen = self.errorSeen[key]
	if seen then
		seen.count = seen.count + 1
		return
	end
	local entry = { msg = err, count = 1, time = date and date("%H:%M:%S") or "" }
	if debugstack then entry.stack = debugstack(3, 8, 0) end
	self.errorSeen[key] = entry
	table.insert(self.errorLog, entry)
	if #self.errorLog > 50 then table.remove(self.errorLog, 1) end
	local handler = geterrorhandler and geterrorhandler()
	if handler then pcall(handler, err) end
	if not self.errorNotified and self.Print then
		self.errorNotified = true
		self:Print("A BitsjUI error was caught. Type /bui errors to see and copy it.")
	end
end

-- Also catch errors that happen inside Blizzard code but involve BitsjUI
-- (e.g. Blizzard updating regions we handed it). They are logged and passed
-- on to the normal error handler.
local inHandler = false
local function Capture(msg)
	if inHandler then return end
	inHandler = true
	local text = tostring(msg)
	local stack = debugstack and debugstack(3, 12, 0) or ""
	do
		if not (text:find("BitsjUI") or stack:find("BitsjUI")) then text = "[not BitsjUI?] " .. text end
		local key = text:gsub("%d+", "#")
		local seen = B.errorSeen[key]
		if seen then
			seen.count = seen.count + 1
		else
			local entry = { msg = text, count = 1, time = date and date("%H:%M:%S") or "", stack = stack }
			B.errorSeen[key] = entry
			table.insert(B.errorLog, entry)
			if #B.errorLog > 50 then table.remove(B.errorLog, 1) end
		end
	end
	inHandler = false
end

-- Blizzard installs its own handler later (when its error window loads), so
-- (re)wrap whatever handler is current at a few points. Every error is
-- logged; BitsjUI-related ones are marked.
local wrapped
local function InstallCapture()
	if not (seterrorhandler and geterrorhandler) then return end
	local current = geterrorhandler()
	if current == wrapped then return end
	wrapped = function(msg, ...)
		pcall(Capture, msg)
		if current then return current(msg, ...) end
	end
	seterrorhandler(wrapped)
end
B.InstallErrorCapture = InstallCapture
InstallCapture()

-- wrap a script handler so errors are logged instead of thrown
function B.Safe(func)
	return function(...)
		local ok, err = pcall(func, ...)
		if not ok then B:Error(err) end
	end
end

-- protected call that reports errors but never breaks the caller
function B:Try(func, ...)
	local ok, err = pcall(func, ...)
	if not ok then self:Error(err) end
	return ok
end

-------------------------------------------------------------------------------
-- Event system
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function B:RegisterEvent(event, func)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)   -- some events only exist on one client
	end
	table.insert(handlers[event], func)
end

function B:UnregisterEvent(event, func)
	local list = handlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == func then table.remove(list, i) end
	end
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then B:Error(err) end
	end
end)

-- Internal callbacks (for the config, movers etc.)
local callbacks = {}
function B:RegisterCallback(name, func)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], func)
end
function B:Fire(name, ...)
	local list = callbacks[name]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then B:Error(err) end
	end
end

-------------------------------------------------------------------------------
-- Preview mode (shown while the menu is open): modules show sample content
-- so every change can be seen right away. Never active in combat.
-------------------------------------------------------------------------------
function B:SetPreview(on)
	on = on and not InCombatLockdown() and true or false
	if self.previewing == on then return end
	self.previewing = on
	self:Fire("PREVIEW", on)
end

-------------------------------------------------------------------------------
-- Combat queue: protected changes wait until combat ends
-------------------------------------------------------------------------------
local queue = {}
function B:RunOOC(key, func)
	if not InCombatLockdown() then
		return self:Try(func)
	end
	queue[key] = func
end
B:RegisterEvent("PLAYER_REGEN_DISABLED", function() B:SetPreview(false) end)
B:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	for key, func in pairs(queue) do
		queue[key] = nil
		B:Try(func)
	end
end)

-------------------------------------------------------------------------------
-- Hidden parent (for Blizzard frames we replace)
-------------------------------------------------------------------------------
B.hiddenParent = CreateFrame("Frame", "BitsjUIHiddenParent", UIParent)
B.hiddenParent:SetAllPoints(UIParent)
B.hiddenParent:Hide()

-------------------------------------------------------------------------------
-- Pixel perfection
-------------------------------------------------------------------------------
function B:UpdatePixelSize()
	local _, h = GetPhysicalScreenSize()
	self.screenHeight = h or 1440
end

-- size of one physical pixel in the coordinate space of `frame`
function B:Pixel(frame)
	local h = self.screenHeight or 1440
	local scale = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or UIParent:GetEffectiveScale()
	if not scale or scale == 0 then scale = 1 end
	return 768 / h / scale
end

-- snap a value to whole physical pixels in frame space
function B:Snap(frame, v)
	local p = self:Pixel(frame)
	return p * math.floor(v / p + 0.5)
end

-------------------------------------------------------------------------------
-- Database / profiles
-------------------------------------------------------------------------------
function B:InitDB()
	BitsjUIDB = BitsjUIDB or {}
	BitsjUICharDB = BitsjUICharDB or {}
	local db = BitsjUIDB
	db.profiles = db.profiles or {}
	db.global = B.MergeDefaults(db.global or {}, B.globalDefaults)

	local key = BitsjUICharDB.profile or "Default"
	if not db.profiles[key] then
		key = "Default"
	end
	db.profiles[key] = db.profiles[key] or {}
	BitsjUICharDB.profile = key

	self.global = db.global
	self.profileKey = key
	self.db = B.MergeDefaults(db.profiles[key], B.defaults)
end

function B:GetProfiles()
	local list = {}
	for name in pairs(BitsjUIDB.profiles) do list[#list + 1] = name end
	table.sort(list)
	return list
end

function B:SetProfile(name)
	if not BitsjUIDB.profiles[name] then
		BitsjUIDB.profiles[name] = {}
	end
	BitsjUICharDB.profile = name
	self.profileKey = name
	self.db = B.MergeDefaults(BitsjUIDB.profiles[name], B.defaults)
end

function B:CopyProfile(from)
	local src = BitsjUIDB.profiles[from]
	if not src or from == self.profileKey then return end
	local copy = B.CopyTable(src)
	BitsjUIDB.profiles[self.profileKey] = copy
	self.db = B.MergeDefaults(copy, B.defaults)
end

function B:ResetProfile()
	BitsjUIDB.profiles[self.profileKey] = {}
	self.db = B.MergeDefaults(BitsjUIDB.profiles[self.profileKey], B.defaults)
end

function B:DeleteProfile(name)
	if name == self.profileKey or name == "Default" then return false end
	BitsjUIDB.profiles[name] = nil
	return true
end

-- Path helpers used by the config ("actionbars.bars.1.size")
local function resolveKey(t, k)
	local n = tonumber(k)
	if n and t[n] ~= nil then return n end
	return k
end

function B:GetPath(path)
	local t = self.db
	local parts = B.Split(path, ".")
	for i = 1, #parts do
		if type(t) ~= "table" then return nil end
		t = t[resolveKey(t, parts[i])]
	end
	return t
end

function B:SetPath(path, value)
	local t = self.db
	local parts = B.Split(path, ".")
	for i = 1, #parts - 1 do
		local k = resolveKey(t, parts[i])
		if type(t[k]) ~= "table" then t[k] = {} end
		t = t[k]
	end
	t[resolveKey(t, parts[#parts])] = value
end

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------
function B:NewModule(name)
	local m = { name = name }
	self.modules[name] = m
	table.insert(self.moduleOrder, m)
	return m
end

function B:GetModule(name)
	return self.modules[name]
end

-- refresh every module that supports live updates
function B:UpdateAll()
	for _, m in ipairs(self.moduleOrder) do
		if m.Update then self:Try(m.Update, m) end
	end
	self:Fire("UPDATE_ALL")
end

-------------------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------------------
B:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	B:InitDB()
	B:UpdatePixelSize()
	for _, m in ipairs(B.moduleOrder) do
		if m.OnInitialize then B:Try(m.OnInitialize, m) end
	end
end)

B:RegisterEvent("ADDON_LOADED", function() InstallCapture() end)

B:RegisterEvent("PLAYER_LOGIN", function()
	InstallCapture()
	C_Timer.After(5, InstallCapture)
	for _, m in ipairs(B.moduleOrder) do
		if m.OnEnable then B:Try(m.OnEnable, m) end
	end
	B.loggedIn = true
	B:Fire("LOGIN")
end)

B:RegisterEvent("DISPLAY_SIZE_CHANGED", function()
	B:UpdatePixelSize()
	B:Fire("PIXEL_CHANGED")
end)
