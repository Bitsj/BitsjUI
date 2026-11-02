--[[
	BitsjUI - Friends list
	Blizzard's friends window in the BitsjUI look:
	  - dark rounded panel, flat tabs in the theme colour
	  - friend rows on a dark tile; online WoW friends get a faint tint in
	    their faction colour, offline friends fade back
	  - character names in class colour, with a class icon where Blizzard
	    shows the WoW logo
	  - hover highlight in the theme colour
	Only the look is changed; Blizzard still builds the list, so whispering,
	inviting and the right-click menu work as normal.
]]
local _, B = ...
local M = B:NewModule("Friends")

-- fonts: this file uses the "windows" section font (/bui > General > Fonts)
local FONT_SECTION = "windows"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local function db() return B.db.friends end

-- localized class name -> class file ("Paladin" -> "PALADIN")
local classByName
local function ClassFile(localized, classID)
	if classID and classID > 0 and GetClassInfo then
		local _, file = GetClassInfo(classID)
		if file then return file end
	end
	if not localized then return end
	if not classByName then
		classByName = {}
		for file, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByName[name] = file end
		for file, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByName[name] = file end
	end
	return classByName[localized]
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-------------------------------------------------------------------------------
local function SkinButton(btn)
	if btn.bSkinned then return end
	btn.bSkinned = true
	if btn.name then SetFont(btn.name, 12) end
	if btn.info then SetFont(btn.info, 10) end
	local hl = btn.highlight or btn:GetHighlightTexture()
	if hl then
		hl:SetTexture(B.white)
		hl:SetVertexColor(1, 1, 1, 0.06)
	end
	btn.bLine = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	btn.bLine:SetWidth(2)
	btn.bLine:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -1)
	btn.bLine:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 1)
	btn.bClass = btn:CreateTexture(nil, "ARTWORK", nil, 2)
	btn.bClass:Hide()
end

local function UpdateButton(btn)
	if not btn or not btn.buttonType then return end
	if btn.buttonType ~= FRIENDS_BUTTON_TYPE_WOW and btn.buttonType ~= FRIENDS_BUTTON_TYPE_BNET then return end
	SkinButton(btn)
	local d = db()
	local online, classFile, faction, isRetail = false, nil, nil, false
	if btn.buttonType == FRIENDS_BUTTON_TYPE_WOW then
		local info = C_FriendList.GetFriendInfoByIndex(btn.id)
		if info then
			online = info.connected
			classFile = ClassFile(info.className)
			faction = UnitFactionGroup("player")
			isRetail = online
		end
	else
		local acc = C_BattleNet.GetFriendAccountInfo(btn.id)
		local g = acc and acc.gameAccountInfo
		if g and g.isOnline then
			online = true
			if g.clientProgram == BNET_CLIENT_WOW then
				isRetail = (g.wowProjectID == nil or g.wowProjectID == WOW_PROJECT_ID)
				classFile = ClassFile(g.className, g.classID)
				faction = g.factionName
			end
		end
	end

	-- row tile: dark, faction tint when they're on retail, faded when offline
	local r, g, b = B:PanelColor()
	local a = online and 0.85 or 0.55
	if isRetail and d.factionTint and (faction == "Alliance" or faction == "Horde") then
		local fr, fg, fb = unpack(B.FACTION_COLORS[faction])
		r, g, b = r + (fr - r) * 0.18, g + (fg - g) * 0.18, b + (fb - b) * 0.18
	end
	if btn.background then btn.background:SetColorTexture(r, g, b, a) end
	local ar, ag, ab = B:AccentColor()
	btn.bLine:SetColorTexture(ar, ag, ab, online and 0.9 or 0.25)

	-- class icon instead of the WoW logo, name in class colour
	local cr, cg, cb
	if classFile then cr, cg, cb = B:ClassColor(classFile) end
	if classFile and isRetail and d.classIcons and btn.gameIcon then
		btn.gameIcon:SetAlpha(0)
		btn.bClass:ClearAllPoints()
		btn.bClass:SetPoint("CENTER", btn.gameIcon, "CENTER", 0, 0)
		btn.bClass:SetSize(22, 22)
		B:ClassIcon(btn.bClass, classFile)
		btn.bClass:Show()
	else
		btn.bClass:Hide()
	end
	if d.classColors and cr and btn.name then
		local text = btn.name:GetText()
		if type(text) == "string" and not B.IsSecret(text) then
			if btn.buttonType == FRIENDS_BUTTON_TYPE_WOW then
				btn.name:SetTextColor(cr, cg, cb)
			else
				-- "BattleTag (Character)": colour just the character part
				local colored = text:gsub("%((.-)%)", "(" .. Hex(cr, cg, cb) .. "%1|r)")
				if colored ~= text then btn.name:SetText(colored) end
			end
		end
	end
	if btn.info then btn.info:SetTextColor(0.62, 0.64, 0.68) end
end

-------------------------------------------------------------------------------
function M:Skin()
	local f = FriendsFrame
	if not f or f.bBitsj then return end
	f.bBitsj = true
	B:SkinWindow(f)
	for i = 1, 4 do B:SkinTab(_G["FriendsFrameTab" .. i]) end
	for _, inset in ipairs({ _G.FriendsFrameInset, f.Inset }) do
		if inset then B.HideRegion(inset.NineSlice); B.HideRegion(inset.Bg); B:Underlay(inset, 0.3) end
	end
	-- the little "who / add friend / send message" buttons keep Blizzard's style; the
	-- broadcast box and status dropdown get the UI font where they have text
	local status = _G.FriendsFrameBattlenetFrame
	if status and status.Tag then SetFont(status.Tag, 12) end
end

function M:OnEnable()
	if not db().enabled then return end
	local function go()
		if not FriendsFrame then return end
		M:Skin()
		if FriendsFrame_UpdateFriendButton and not M.hooked then
			M.hooked = true
			hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
				B:Try(UpdateButton, button)
			end)
		end
	end
	if FriendsFrame then go() end
	B:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_FriendsFrame" then go() end
	end)
end

function M:Update()
	local sb = FriendsListFrame and FriendsListFrame.ScrollBox
	if sb and sb.EnumerateFrames then
		for _, btn in sb:EnumerateFrames() do B:Try(UpdateButton, btn) end
	end
end
