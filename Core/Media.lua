--[[
	BitsjUI - Media & skin helpers
	Fonts, statusbar textures, borders and backdrops.
]]
local _, B = ...

local path = B.mediaPath

B.media = {
	fonts = {
		-- Barlow Semi Condensed: free (OFL) and the closest match to Expressway
		["Barlow"] = path .. "Fonts\\BarlowSemiCondensed-SemiBold.ttf",
		["Inter"] = path .. "Fonts\\Inter-SemiBold.ttf",
		["Outfit"] = path .. "Fonts\\Outfit-Bold.ttf",
		["Instrument Sans"] = path .. "Fonts\\InstrumentSans-Bold.ttf",
		["Big Shoulders"] = path .. "Fonts\\BigShoulders-Bold.ttf",
		["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
		["Arial Narrow"] = "Fonts\\ARIALN.TTF",
		["Morpheus"] = "Fonts\\MORPHEUS.TTF",
		["Skurri"] = "Fonts\\SKURRI.TTF",
		-- free fonts (SIL Open Font License / Ubuntu Font Licence, see Media\Fonts)
		["Poppins"] = path .. "Fonts\\Poppins.ttf",
		["Fira Sans Light"] = path .. "Fonts\\FiraSans-Light.ttf",
		["Fira Sans Medium"] = path .. "Fonts\\FiraSans-Medium.ttf",
		["Fira Sans Bold"] = path .. "Fonts\\FiraSans-Bold.ttf",
		["Barlow Condensed"] = path .. "Fonts\\BarlowCondensed.ttf",
		["Changa"] = path .. "Fonts\\Changa.ttf",
		["Cinzel Decorative"] = path .. "Fonts\\CinzelDecorative.ttf",
		["Exo"] = path .. "Fonts\\Exo.otf",
		["Russo One"] = path .. "Fonts\\RussoOne.ttf",
		["Ubuntu"] = path .. "Fonts\\Ubuntu.ttf",
		-- drop your own font into Media\Fonts\Custom.ttf and pick this
		["Custom (Custom.ttf)"] = path .. "Fonts\\Custom.ttf",
	},
	textures = {
		["Bitsj Gloss"] = path .. "Textures\\Gloss",
		["Bitsj Smooth"] = path .. "Textures\\Smooth",
		["Bitsj Glass"] = path .. "Textures\\Glass",
		["Bitsj Stripes"] = path .. "Textures\\Stripes",
		["Flat"] = B.white,
		["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
		["Blizzard Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
	},
}

-- Paid / restricted fonts that can be added by hand to Media\Fonts\Extra\ (taken from
-- other UI packs or bought). Several are paid fonts, so they are never shipped
-- with BitsjUI; each one only shows up in the font list when its file exists.
B.media.extraFonts = {
	["Expressway"] = "Expressway.ttf",
	["Expressway Bold"] = "Expressway Bold.ttf",
	["Expressway CAPS"] = "Expressway CAPS.ttf",
	["Avant Garde"] = "Avant Garde Naowh.ttf",
	["Arial Bold"] = "Arial Bold.ttf",
	["Future X Black"] = "Future X Black.otf",
	["Gotham Narrow"] = "Gotham Narrow.otf",
	["Gotham Narrow Ultra"] = "Gotham Narrow Ultra.otf",
	["Homespun"] = "Homespun.ttf",
	["HWT Artz"] = "HWT Artz.ttf",
	["KMT Kimberley"] = "KMT Kimberley.otf",
	["KMT Ninja Naruto"] = "KMT Ninja Naruto.ttf",
}
for name, file in pairs(B.media.extraFonts) do
	B.media.fonts[name] = path .. "Fonts\\Extra\\" .. file
end

B.outlines = {
	{ value = "NONE", label = "None" },
	{ value = "OUTLINE", label = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick outline" },
	{ value = "MONOCHROME,OUTLINE", label = "Pixel outline" },
}

-- Pull in LibSharedMedia (if another addon ships it) and register ours there too
local function GetLSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function B:RegisterSharedMedia()
	local LSM = GetLSM()
	if not LSM then return end
	-- LSM rejects (and errors on) font files that don't exist, e.g. Expressway
	-- before the user has added it, so only hand over fonts that really load
	for name, file in pairs(self.media.fonts) do
		if not name:find("Custom") and B.FontExists(file) then
			pcall(LSM.Register, LSM, "font", "Bitsj " .. name, file)
		end
	end
	for name, file in pairs(self.media.textures) do
		if name:find("Bitsj") then pcall(LSM.Register, LSM, "statusbar", name, file) end
	end
end

function B:GetFontList()
	local list, seen = {}, {}
	for name, file in pairs(self.media.fonts) do
		if not self.media.extraFonts[name] or B.FontExists(file) then list[#list + 1] = name end
		seen[name] = true
	end
	local LSM = GetLSM()
	if LSM then
		for _, name in ipairs(LSM:List("font")) do
			if not seen[name] and not name:find("^Bitsj ") then list[#list + 1] = name end
		end
	end
	table.sort(list)
	return list
end

function B:GetTextureList()
	local list, seen = {}, {}
	for name in pairs(self.media.textures) do list[#list + 1] = name; seen[name] = true end
	local LSM = GetLSM()
	if LSM then
		for _, name in ipairs(LSM:List("statusbar")) do
			if not seen[name] then list[#list + 1] = name end
		end
	end
	table.sort(list)
	return list
end

-- Fonts. The game loads addon font files in the background and SetFont's
-- answer can't be trusted for "does this font work" (it says no for fonts
-- that are fine). EllesmereUI simply sets its fonts; so does BitsjUI now.
-- The only thing checked is a missing file: SetFont then raises
-- "file not found", and that font is skipped.
local probe
local fontState = {}
function B.FontExists(file)
	if fontState[file] ~= nil then return fontState[file] end
	probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
	local ok = pcall(probe.SetFont, probe, file, 12, "")
	fontState[file] = ok and true or false
	return fontState[file]
end
B.FontWorks = B.FontExists

-- Text drawn before a font has finished loading keeps its previous font, so
-- apply all fonts again a little after login.
function B:RetryFonts() end
function B:PreloadFonts()
	for _, file in pairs(self.media.fonts) do pcall(B.FontExists, file) end
	if C_Timer then
		for _, t in ipairs({ 2, 6, 15 }) do
			C_Timer.After(t, function()
				if B.db then B:Try(B.RefreshFonts, B); B:Try(B.UpdateAll, B) end
			end)
		end
	end
end

-- Font sections: each part of the UI can use its own font, or "" for the
-- overall font (/bui > General > Fonts)
B.FONT_SECTIONS = {
	{ key = "unitframes", label = "Unit frames" },
	{ key = "raidframes", label = "Party & raid" },
	{ key = "nameplates", label = "Nameplates" },
	{ key = "castbars", label = "Castbars & swing timer" },
	{ key = "actionbars", label = "Action bars & cooldowns" },
	{ key = "auras", label = "Buffs, timers & defensives" },
	{ key = "meter", label = "Damage meter" },
	{ key = "chat", label = "Chat" },
	{ key = "minimap", label = "Minimap & info texts" },
	{ key = "quests", label = "Quest tracker" },
	{ key = "windows", label = "Bags, character & friends" },
}

-- the font name a section uses (its own, or the overall one)
function B:FontName(section)
	local own = section and self.db.fonts and self.db.fonts[section]
	if type(own) == "string" and own ~= "" then return own end
	return self.db.general.font
end

function B:GetFont(name, section)
	name = name or self:FontName(section)
	local file = self.media.fonts[name]
	if not file then
		local LSM = GetLSM()
		file = LSM and LSM:Fetch("font", name, true)
	end
	if not file or not B.FontExists(file) then file = self.media.fonts["Inter"] end
	return file
end

function B:GetTexture(name)
	name = name or self.db.general.texture
	local file = self.media.textures[name]
	if not file then
		local LSM = GetLSM()
		file = LSM and LSM:Fetch("statusbar", name, true)
	end
	return file or B.white
end

-- "SLUG" makes the client draw text as smooth vectors instead of a small
-- bitmap, which keeps it sharp at UI scales like 0.62 on 1440p
local slugOK
local function SlugSupported()
	if slugOK ~= nil then return slugOK end
	local fs = UIParent:CreateFontString(nil, "BACKGROUND")
	local ok, res = pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", 12, "SLUG")
	slugOK = ok and res ~= false
	return slugOK
end

-- add the quality flag to a set of font flags
function B:Flags(flags)
	flags = flags or ""
	local g = self.db and self.db.general
	if g and g.sharpText and SlugSupported() and not flags:find("SLUG", 1, true) then
		flags = (flags == "") and "SLUG" or (flags .. ",SLUG")
	end
	return flags
end

function B:GetOutline()
	local o = self.db.general.fontOutline
	if o == "NONE" then o = "" end
	return self:Flags(o)
end

-- apply BitsjUI font to a fontstring
function B:SetFont(fs, size, outline, section)
	if not fs or not fs.SetFont then return end
	if section then fs.bFontSection = section end
	local flags = outline and self:Flags(outline) or self:GetOutline()
	local file = self:GetFont(nil, fs.bFontSection)
	-- a safe font first: if the chosen one isn't loaded yet, the text keeps this
	if not (fs.GetFont and fs:GetFont()) then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size or 12, flags) end
	pcall(fs.SetFont, fs, file, size or 12, flags)
	if self.db.general.fontShadow then
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetShadowOffset(0, 0)
	end
end

function B:CreateText(parent, size, justify, layer, section)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	self:SetFont(fs, size, nil, section)
	fs:SetJustifyH(justify or "CENTER")
	fs:SetWordWrap(false)
	self.fontStrings = self.fontStrings or setmetatable({}, { __mode = "k" })
	self.fontStrings[fs] = size or 12
	return fs
end

-- re-apply the font to every fontstring we created (after font change)
function B:RefreshFonts()
	if not self.fontStrings then return end
	for fs, size in pairs(self.fontStrings) do
		self:SetFont(fs, fs.bSize or size)
	end
end

-------------------------------------------------------------------------------
-- Icons: one look everywhere (crop, inner shadow, soft gloss)
-------------------------------------------------------------------------------
local skinnedIcons = setmetatable({}, { __mode = "k" })

local function ApplyIcon(icon)
	local g = B.db and B.db.general or {}
	local z = g.iconZoom or 0.08
	icon:SetTexCoord(z, 1 - z, z, 1 - z)
	-- aura icons report a hidden (secret) value here; their whole button hides anyway
	local visible = B.Plain(icon:IsShown(), true)
	if icon.bShadow then
		icon.bShadow:SetAlpha(g.iconShadow or 0)
		icon.bShadow:SetShown(visible and (g.iconShadow or 0) > 0)
	end
	if icon.bGloss then
		icon.bGloss:SetAlpha(g.iconGloss or 0)
		icon.bGloss:SetShown(visible and (g.iconGloss or 0) > 0)
	end
end

-- icon: the texture; owner: frame to put the overlays on (defaults to its parent)
function B:SkinIcon(icon, owner)
	if not icon or (icon.IsForbidden and icon:IsForbidden()) then return end
	owner = owner or icon:GetParent()
	if not icon.bShadow and owner and owner.CreateTexture then
		local layer, sub = icon:GetDrawLayer()
		sub = math.min(7, (sub or 0) + 1)
		icon.bShadow = owner:CreateTexture(nil, layer or "ARTWORK", nil, sub)
		icon.bShadow:SetTexture(path .. "Textures\\IconShadow")
		icon.bShadow:SetAllPoints(icon)
		icon.bGloss = owner:CreateTexture(nil, layer or "ARTWORK", nil, math.min(7, sub + 1))
		icon.bGloss:SetTexture(path .. "Textures\\IconGloss")
		icon.bGloss:SetBlendMode("ADD")
		icon.bGloss:SetAllPoints(icon)
		-- overlays live on the owner, so follow the icon (empty action slots hide it)
		local function follow()
			if B.Plain(icon:IsShown(), true) then pcall(ApplyIcon, icon) else icon.bShadow:Hide(); icon.bGloss:Hide() end
		end
		hooksecurefunc(icon, "Show", follow)
		hooksecurefunc(icon, "Hide", follow)
		hooksecurefunc(icon, "SetShown", follow)
	end
	skinnedIcons[icon] = true
	ApplyIcon(icon)
end

-- keep the overlays in step with the icon's visibility
function B:RefreshIcons()
	for icon in pairs(skinnedIcons) do pcall(ApplyIcon, icon) end
end

-------------------------------------------------------------------------------
-- Theme: the UI takes on the colours of whoever you log in as
-------------------------------------------------------------------------------
local FACTION_COLORS = {
	Alliance = { 0.26, 0.52, 1.00 },
	Horde = { 0.90, 0.18, 0.14 },
	Neutral = { 0.95, 0.78, 0.30 },
}
B.FACTION_COLORS = FACTION_COLORS

-- who you are right now (name, class, race, faction) for theming
function B:Identity()
	local _, class = UnitClass("player")
	local className = UnitClass("player")
	local race = UnitRace("player")
	local faction, factionName = UnitFactionGroup("player")
	return {
		name = B.Plain(UnitName("player"), ""), class = class, className = className, race = race,
		faction = faction or "Neutral", factionName = factionName or faction or "",
	}
end

-- "BitsjUI" with "Bitsj" in the theme colour
function B:TitleText()
	local r, g, b = self:AccentColor()
	return string.format("|cff%02x%02x%02xBitsj|rUI", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

function B:FactionColor()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local c = FACTION_COLORS[faction or "Neutral"] or FACTION_COLORS.Neutral
	return c[1], c[2], c[3]
end

function B:AccentColor()
	local g = self.db and self.db.general
	local mode = g and g.themeMode or "class"
	if mode == "class" then
		local _, class = UnitClass("player")
		if class then return self:ClassColor(class) end
	elseif mode == "faction" then
		return self:FactionColor()
	end
	local c = g and g.accent or { r = 0.31, g = 0.82, b = 0.71 }
	return c.r, c.g, c.b
end

-- panel background with a faint wash of the theme colour
function B:PanelColor(alpha)
	local g = self.db.general
	local c = g.backdrop
	local t = g.themeTint or 0
	local r, gg, b = self:AccentColor()
	return c.r + (r - c.r) * t, c.g + (gg - c.g) * t, c.b + (b - c.b) * t, alpha or c.a
end

-- default border colour: black, or a deep shade of the theme colour
function B:BorderColor()
	local g = self.db and self.db.general
	if g and g.themeBorders then
		local r, gg, b = self:AccentColor()
		return r * 0.32, gg * 0.32, b * 0.32, 1
	end
	local c = g and g.border or { r = 0, g = 0, b = 0, a = 1 }
	return c.r, c.g, c.b, c.a
end

function B:ClassColor(class)
	if not class then return 1, 1, 1 end
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-------------------------------------------------------------------------------
-- Borders / backdrops (pixel perfect, 1 physical pixel)
-------------------------------------------------------------------------------
local bordered = setmetatable({}, { __mode = "k" })

-- Rounded corners: a quarter ring texture per corner (Media\Textures\Corners,
-- C<radius>_<thickness>.tga, radius/thickness in physical pixels). Only for
-- borders that sit outside their frame: the frame's square corner then always
-- lands under the ring, so nothing pokes out of the rounding.
local CORNER_COORDS = {
	{ 0, 1, 0, 1 },  -- top left (as drawn)
	{ 1, 0, 0, 1 },  -- top right
	{ 0, 1, 1, 0 },  -- bottom left
	{ 1, 0, 1, 0 },  -- bottom right
}

local function CornerRadius(thick)
	local g = B.db and B.db.general
	if not g or g.borderStyle ~= "rounded" then return 0 end
	local r = g.cornerRadius or 4
	-- keep the frame corner inside the ring: r <= thickness * 3.4
	r = math.min(r, math.floor(thick * 3.4), 8)
	if r <= thick then return 0 end
	return r
end

local function LayoutBorder(holder)
	local frame = holder.bOwner
	local px = B:Pixel(frame)
	local thick = holder.bThickness or 1
	local p = px * thick
	local o = holder.bOffset or 0
	local t = holder.bTex
	local R = o > 0 and CornerRadius(thick) or 0
	local c = R * px
	t[1]:ClearAllPoints(); t[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -o + c, o); t[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o - c, o); t[1]:SetHeight(p)
	t[2]:ClearAllPoints(); t[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o + c, -o); t[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o - c, -o); t[2]:SetHeight(p)
	t[3]:ClearAllPoints(); t[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o - c); t[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o + c); t[3]:SetWidth(p)
	t[4]:ClearAllPoints(); t[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o - c); t[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o + c); t[4]:SetWidth(p)

	if R > 0 then
		if not holder.bCorner then
			holder.bCorner = {}
			for i = 1, 4 do
				local ct = holder:CreateTexture(nil, t[1]:GetDrawLayer(), nil, 7)
				ct:SetTexCoord(unpack(CORNER_COORDS[i]))
				local col = holder.bColor
				ct:SetVertexColor(col[1], col[2], col[3], col[4])
				holder.bCorner[i] = ct
			end
		end
		local file = path .. "Textures\\Corners\\C" .. R .. "_" .. math.min(thick, 4)
		local cc = holder.bCorner
		local pts = { { "TOPLEFT", -o, o }, { "TOPRIGHT", o, o }, { "BOTTOMLEFT", -o, -o }, { "BOTTOMRIGHT", o, -o } }
		for i = 1, 4 do
			cc[i]:SetTexture(file)
			cc[i]:ClearAllPoints()
			cc[i]:SetPoint(pts[i][1], frame, pts[i][1], pts[i][2], pts[i][3])
			cc[i]:SetSize(c, c)
			cc[i]:Show()
		end
		-- fill the frame's own corners outside the ring's inner curve, so
		-- square bars inside don't poke out past the rounded border
		local inner = math.min(7, R - thick)
		if inner >= 1 then
			if not holder.bFillet then
				holder.bFillet = {}
				for i = 1, 4 do
					local ft = holder:CreateTexture(nil, t[1]:GetDrawLayer(), nil, 7)
					ft:SetTexCoord(unpack(CORNER_COORDS[i]))
					local col = holder.bColor
					ft:SetVertexColor(col[1], col[2], col[3], col[4])
					holder.bFillet[i] = ft
				end
			end
			local f = holder.bFillet
			local fs = inner * px
			for i = 1, 4 do
				f[i]:SetTexture(path .. "Textures\\Corners\\F" .. inner)
				f[i]:ClearAllPoints()
				f[i]:SetPoint(pts[i][1], frame, pts[i][1], 0, 0)
				f[i]:SetSize(fs, fs)
				f[i]:Show()
			end
		elseif holder.bFillet then
			for i = 1, 4 do holder.bFillet[i]:Hide() end
		end
	elseif holder.bCorner then
		for i = 1, 4 do holder.bCorner[i]:Hide() end
		if holder.bFillet then for i = 1, 4 do holder.bFillet[i]:Hide() end end
	end
end

-- offset: how far outside the frame the border sits (in frame units)
function B:CreateBorder(frame, r, g, b, a, offset, layer)
	if frame.bBorder then return frame.bBorder end
	local br, bg2, bb, ba = self:BorderColor()
	local c = { r = br, g = bg2, b = bb, a = ba }
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel(frame:GetFrameLevel() + 2)
	holder.bOwner = frame
	holder.bOffset = offset or 0
	holder.bTex = {}
	for i = 1, 4 do
		local t = holder:CreateTexture(nil, layer or "OVERLAY", nil, 7)
		t:SetTexture(B.white)
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
		t:SetVertexColor(r or c.r, g or c.g, b or c.b, a or c.a)
		holder.bTex[i] = t
	end
	holder.bColor = { r or c.r, g or c.g, b or c.b, a or c.a }
	function holder:SetColor(cr, cg, cb, ca)
		self.bColor = { cr, cg, cb, ca or 1 }
		for i = 1, 4 do self.bTex[i]:SetVertexColor(cr, cg, cb, ca or 1) end
		if self.bCorner then
			for i = 1, 4 do self.bCorner[i]:SetVertexColor(cr, cg, cb, ca or 1) end
		end
		if self.bFillet then
			for i = 1, 4 do self.bFillet[i]:SetVertexColor(cr, cg, cb, ca or 1) end
		end
	end
	LayoutBorder(holder)
	frame.bBorder = holder
	bordered[holder] = true
	return holder
end

-- dark background + 1px border sitting just outside the frame
function B:CreateBackdrop(frame, alpha, noBorder)
	if frame.bBackdrop then return frame.bBackdrop end
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetTexture(B.white)
	bg:SetVertexColor(self:PanelColor(alpha))
	bg:SetAllPoints(frame)
	frame.bBackdrop = bg
	if not noBorder then
		self:CreateBorder(frame, nil, nil, nil, nil, B:Pixel(frame))
	end
	return bg
end

-- thicker border sitting fully outside the frame (thickness in physical pixels)
function B:SetBorderSize(frame, thickness)
	local holder = frame and frame.bBorder
	if not holder then return end
	holder.bThickness = math.max(1, thickness or 1)
	holder.bOffset = B:Pixel(frame) * holder.bThickness
	LayoutBorder(holder)
end

function B:RefreshBorders()
	for holder in pairs(bordered) do
		-- skip borders that sit on forbidden (nameplate) frames
		if not (holder.IsForbidden and holder:IsForbidden()) then
			if holder.bOffset and holder.bOffset > 0 then
				holder.bOffset = B:Pixel(holder.bOwner) * (holder.bThickness or 1)
			end
			pcall(LayoutBorder, holder)
		end
	end
end

B:RegisterCallback("PIXEL_CHANGED", function() B:RefreshBorders() end)
B:RegisterCallback("UI_SCALE_APPLIED", function() B:RefreshBorders() end)

-- Bar colours go through one dial so the whole UI can be toned down:
-- saturation pulls colours towards grey, brightness darkens them.
function B:Soften(r, g, b)
	local gen = self.db and self.db.general
	if not gen or type(r) ~= "number" then return r, g, b end
	local sat, bright = gen.colorSaturation or 1, gen.colorBrightness or 1
	local grey = r * 0.3 + g * 0.59 + b * 0.11
	r, g, b = grey + (r - grey) * sat, grey + (g - grey) * sat, grey + (b - grey) * sat
	return r * bright, g * bright, b * bright
end

-- make a bar's SetStatusBarColor go through Soften (our own bars only)
local softBars = setmetatable({}, { __mode = "k" })
function B:SoftBar(sb)
	if not sb or sb.bSoft then return sb end
	sb.bSoft = true
	local orig = sb.SetStatusBarColor
	sb.bRawColor = { 1, 1, 1, 1 }
	function sb:SetStatusBarColor(r, g, b, a)
		self.bRawColor[1], self.bRawColor[2], self.bRawColor[3], self.bRawColor[4] = r, g, b, a
		local sr, sg, sbb = B:Soften(r, g, b)
		return orig(self, sr, sg, sbb, a)
	end
	softBars[sb] = true
	return sb
end

-- re-apply after the dial moved
function B:RefreshBarColors()
	for sb in pairs(softBars) do
		local c = sb.bRawColor
		if c and type(c[1]) == "number" then sb:SetStatusBarColor(c[1], c[2], c[3], c[4]) end
	end
end

-- simple statusbar with dark background
function B:CreateStatusBar(parent, name)
	local sb = CreateFrame("StatusBar", name, parent)
	self:SoftBar(sb)
	sb:SetStatusBarTexture(self:GetTexture())
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(1)
	local bg = sb:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(self:GetTexture())
	bg:SetAllPoints(sb)
	bg:SetVertexColor(0.08, 0.08, 0.09, 1)
	sb.bg = bg
	self.statusBars = self.statusBars or setmetatable({}, { __mode = "k" })
	self.statusBars[sb] = true
	return sb
end

-- Absorb shield on a health bar: a light bar that starts where the health
-- ends, clipped to the health bar. Takes Midnight's hidden numbers as they are.
function B:CreateAbsorb(hb)
	if hb.bAbsorb then return hb.bAbsorb end
	local clip = CreateFrame("Frame", nil, hb)
	clip:SetAllPoints(hb)
	clip:SetClipsChildren(true)
	local ab = CreateFrame("StatusBar", nil, clip)
	ab:SetStatusBarTexture(self.white)
	ab:SetStatusBarColor(0.80, 0.92, 1.00, 0.55)
	local fill = hb:GetStatusBarTexture()
	ab:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
	ab:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
	ab:SetWidth(math.max(1, hb:GetWidth() or 1))
	hb:HookScript("OnSizeChanged", function(_, w) if type(w) == "number" and w > 0 then ab:SetWidth(w) end end)
	ab:Hide()
	hb.bAbsorb = ab
	return ab
end

function B:UpdateAbsorb(hb, unit, enabled)
	local ab = hb and hb.bAbsorb
	if not ab then return end
	if not enabled or not unit or not UnitGetTotalAbsorbs then ab:Hide(); return end
	local ok, amount = pcall(UnitGetTotalAbsorbs, unit)
	if not ok or amount == nil or (not self.IsSecret(amount) and amount <= 0) then ab:Hide(); return end
	local okm, max = pcall(UnitHealthMax, unit)
	if not okm or max == nil then ab:Hide(); return end
	pcall(ab.SetMinMaxValues, ab, 0, max)
	pcall(ab.SetValue, ab, amount)
	ab:Show()
end

function B:RefreshTextures()
	if not self.statusBars then return end
	local tex = self:GetTexture()
	for sb in pairs(self.statusBars) do
		if not sb.bKeepTexture then
			sb:SetStatusBarTexture(tex)
			if sb.bg then sb.bg:SetTexture(tex) end
		end
	end
end

-- atlas only when the client has it (Classic lacks many modern atlases)
function B.HasAtlas(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return true end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

-- class icon: modern atlas, or the old class-icon sheet on Classic
function B:ClassIcon(tex, class)
	if not tex then return end
	if not class then tex:SetTexture(nil); return end
	local atlas = "classicon-" .. class:lower()
	if B.HasAtlas(atlas) then
		tex:SetAtlas(atlas)
		return
	end
	local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
	if c then tex:SetTexCoord(c[1] + 0.015, c[2] - 0.015, c[3] + 0.015, c[4] - 0.015) end
end
