--[[
	BitsjUI - Chat
	Clean chat: font, no side buttons, flat edit box and quiet tabs.
]]
local _, B = ...
local M = B:NewModule("Chat")

-- fonts: this file uses the "chat" section font (/bui > General > Fonts)
local FONT_SECTION = "chat"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local function db() return B.db.chat end

local buttons = { "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }
local tabTextures = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight", "HighlightLeft", "HighlightMiddle", "HighlightRight", "ActiveLeft", "ActiveMiddle", "ActiveRight" }

-- Blizzard's floating chat window art (FloatingBorderedFrame + background)
local BLIZZ_BG = { "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
	"TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }

-- Blizzard re-applies alpha on these (window alpha setting, mouse over), so pin it at 0
local function KeepHidden(t)
	t:SetAlpha(0)
	if t.bKeepHidden then return end
	t.bKeepHidden = true
	hooksecurefunc(t, "SetAlpha", function(self, a)
		if self.bLock or a == 0 then return end
		self.bLock = true; self:SetAlpha(0); self.bLock = nil
	end)
end

local function StyleFrame(cf)
	if not cf then return end
	local d = db()
	local name = cf:GetName()

	-- font (keep Blizzard's per-window size unless a size is set)
	local _, size = cf:GetFont()
	local newSize = (d.fontSize and d.fontSize > 0) and d.fontSize or size or 14
	cf:SetFont(GetFont(), newSize, B:Flags(""))
	if d.shadow then
		cf:SetShadowColor(0, 0, 0, 1)
		cf:SetShadowOffset(1, -1)
	else
		cf:SetShadowOffset(0, 0)
	end

	-- side button frame
	local bf = _G[name .. "ButtonFrame"]
	if bf then
		if d.hideButtons then
			bf:SetAlpha(0)
			bf:EnableMouse(false)
		else
			bf:SetAlpha(1)
			bf:EnableMouse(true)
		end
	end

	-- window: Blizzard's grey panel goes, our dark rounded panel comes in
	if d.panel then
		for _, suffix in ipairs(BLIZZ_BG) do
			local t = _G[name .. suffix] or cf[suffix]
			if type(t) == "table" and t.SetAlpha then KeepHidden(t) end
		end
		if not cf.bPanel then
			local panel = CreateFrame("Frame", nil, cf)
			panel:SetFrameStrata("BACKGROUND")
			panel:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))
			cf.bPanel = panel
			B:CreateBackdrop(panel, d.panelAlpha)
		end
		local panel = cf.bPanel
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, 6)
		panel:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 6, -6)
		local c = B.db.general.backdrop
		panel.bBackdrop:SetVertexColor(c.r, c.g, c.b, d.panelAlpha)
		B:SetBorderSize(panel, d.borderSize or 2)
		panel:Show()
	elseif cf.bPanel then
		cf.bPanel:Hide()
	end

	-- edit box: same dark rounded box as the rest of the UI
	local eb = _G[name .. "EditBox"]
	if eb and d.styleEditBox then
		if not eb.bStyled then
			eb.bStyled = true
			for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
				local t = _G[name .. "EditBox" .. suffix] or eb[suffix]
				if type(t) == "table" and t.SetAlpha then KeepHidden(t) end
			end
			local box = CreateFrame("Frame", nil, eb)
			box:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
			box:SetPoint("TOPLEFT", eb, "TOPLEFT", 4, -4)
			box:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -4, 4)
			B:CreateBackdrop(box, 0.95)
			eb.bBox = box
		end
		B:SetBorderSize(eb.bBox, d.borderSize or 2)
		local _, ebSize = eb:GetFont()
		eb:SetFont(GetFont(), ebSize or 14, B:Flags(""))
		if eb.header then eb.header:SetFont(GetFont(), ebSize or 14, B:Flags("")) end
	end

	-- tabs
	local tab = _G[name .. "Tab"]
	if tab and d.styleTabs then
		for _, t in ipairs(tabTextures) do
			local tex = tab[t] or _G[name .. "Tab" .. t]
			if type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
		end
		local text = tab.Text or _G[name .. "TabText"]
		if text then
			text:SetFont(GetFont(), d.tabFontSize or 13, B:GetOutline())
			text:SetShadowColor(0, 0, 0, 1)
			text:SetShadowOffset(1, -1)
		end
		-- Blizzard fades idle tabs almost to nothing; keep them readable
		if not tab.bAlphaHooked then
			tab.bAlphaHooked = true
			hooksecurefunc(tab, "SetAlpha", function(self, a)
				if self.bLock or not db().styleTabs or a >= 0.6 then return end
				self.bLock = true; self:SetAlpha(0.6); self.bLock = nil
			end)
		end
		tab:SetAlpha(math.max(tab:GetAlpha(), 0.6))
	end
end

function M:StyleAll()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		StyleFrame(_G["ChatFrame" .. i])
	end
	local d = db()
	for _, name in ipairs(buttons) do
		local b = _G[name]
		if b then
			if d.hideButtons then
				b:SetAlpha(0)
				pcall(b.EnableMouse, b, false)
			else
				b:SetAlpha(1)
				pcall(b.EnableMouse, b, true)
			end
		end
	end
end

function M:OnEnable()
	if not db().enabled then return end
	self:StyleAll()
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			local cf = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
			if cf then StyleFrame(cf) end
		end)
	end
end

function M:Update()
	if not db().enabled then return end
	self:StyleAll()
end
