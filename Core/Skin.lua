--[[
	BitsjUI - Skin helpers for Blizzard windows
	Turns a Blizzard "portrait" window (character sheet, friends list...) into
	a BitsjUI panel: the stone frame, parchment and portrait ring disappear,
	a dark rounded panel takes their place, titles and tabs get the UI font
	and the theme colour. Only looks are touched, never layout or behaviour.
]]
local _, B = ...

local function Hide(region)
	if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
end
B.HideRegion = Hide

-- every texture directly on a frame (not its children)
function B:HideTextures(frame)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
	end
end

-- a dark inset panel behind a frame (used for insets / list areas)
function B:Underlay(frame, alpha, inset)
	if not frame or frame.bUnderlay then return frame and frame.bUnderlay end
	local u = CreateFrame("Frame", nil, frame)
	u:SetPoint("TOPLEFT", frame, "TOPLEFT", inset or 0, -(inset or 0))
	u:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset or 0), inset or 0)
	u:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	self:CreateBackdrop(u, alpha or 0.5)
	frame.bUnderlay = u
	return u
end

function B:SkinWindow(frame, opts)
	if not frame or frame.bWindowSkinned then return end
	frame.bWindowSkinned = true
	opts = opts or {}
	Hide(frame.NineSlice)
	Hide(frame.Bg)
	Hide(frame.TopTileStreaks)
	Hide(frame.Background)
	if frame.PortraitContainer then
		if opts.keepPortrait then
			if frame.PortraitContainer.portrait then frame.PortraitContainer.portrait:SetSize(30, 30) end
		else
			Hide(frame.PortraitContainer)
		end
	end
	if frame.Inset then
		Hide(frame.Inset.NineSlice)
		Hide(frame.Inset.Bg)
		B:Underlay(frame.Inset, 0.35)
	end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetAllPoints(frame)
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	self:CreateBackdrop(panel, opts.alpha or 0.94)
	self:SetBorderSize(panel, 2)
	frame.bPanel = panel
	-- thin theme line under the title bar
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(self:AccentColor())
	line:SetAlpha(0.7)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -22)
	line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -22)
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
	if title then
		self:SetFont(title, 13)
		title:SetTextColor(self:AccentColor())
	end
	return panel
end

-- old-style (Classic) windows: one big art texture with transparent margins.
-- The art is hidden and the panel drawn inside the given insets.
function B:SkinClassicWindow(frame, l, t, r, b, extraFrames)
	if not frame or frame.bWindowSkinned then return end
	frame.bWindowSkinned = true
	self:HideTextures(frame)
	for _, f in ipairs(extraFrames or {}) do self:HideTextures(f) end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetPoint("TOPLEFT", frame, "TOPLEFT", l, t)
	panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", r, b)
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	self:CreateBackdrop(panel, 0.94)
	self:SetBorderSize(panel, 2)
	frame.bPanel = panel
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(self:AccentColor())
	line:SetAlpha(0.7)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
	line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -26)
	return panel
end

-- PanelTabButtonTemplate tabs: flat dark tab, theme colour when selected
local function TabState(tab)
	if not tab.bTabBg then return end
	local selected = tab.bSelected
	if selected == nil and tab.IsEnabled then selected = not tab:IsEnabled() end
	local r, g, b = B:AccentColor()
	if selected then
		tab.bTabBg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.95)
		tab.bTabLine:Show()
		if tab.bText then tab.bText:SetTextColor(1, 1, 1) end
	else
		tab.bTabBg:SetVertexColor(B:PanelColor(0.9))
		tab.bTabLine:Hide()
		if tab.bText then tab.bText:SetTextColor(0.7, 0.72, 0.75) end
	end
end

function B:SkinTab(tab)
	if not tab or tab.bTabSkinned then return end
	tab.bTabSkinned = true
	local name = tab.GetName and tab:GetName()
	for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
		"LeftHighlight", "MiddleHighlight", "RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
		Hide(tab[k])
		if name then Hide(_G[name .. k]) end   -- older (Classic) tabs only have named textures
	end
	if tab.GetHighlightTexture and tab:GetHighlightTexture() then tab:GetHighlightTexture():SetAlpha(0) end
	tab.bText = tab.Text or (name and _G[name .. "Text"]) or (tab.GetFontString and tab:GetFontString())
	local bg = tab:CreateTexture(nil, "BACKGROUND", nil, -6)
	bg:SetTexture(B.white)
	bg:SetPoint("TOPLEFT", 3, -4)
	bg:SetPoint("BOTTOMRIGHT", -3, 4)
	tab.bTabBg = bg
	local line = tab:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(self:AccentColor())
	line:SetHeight(2)
	line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
	tab.bTabLine = line
	if tab.bText then self:SetFont(tab.bText, 12) end
	TabState(tab)
end

if PanelTemplates_SelectTab then
	hooksecurefunc("PanelTemplates_SelectTab", function(tab) if tab and tab.bTabSkinned then tab.bSelected = true; TabState(tab) end end)
	hooksecurefunc("PanelTemplates_DeselectTab", function(tab) if tab and tab.bTabSkinned then tab.bSelected = false; TabState(tab) end end)
end
