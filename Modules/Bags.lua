--[[
	BitsjUI - Bags
	Restyles Blizzard's own bag windows (combined backpack, single bags and
	the reagent bag) in the BitsjUI look: dark panel with a rounded border,
	no portrait ring or stone art, clean cropped icons with the shared icon
	shading, dark empty slots and a thin border in the item's quality colour.
	Only looks are changed: Blizzard still does the layout, sorting, search
	and clicks, so nothing about using items is affected.
]]
local _, B = ...
local M = B:NewModule("Bags")

-- fonts: this file uses the "windows" section font (/bui > General > Fonts)
local FONT_SECTION = "windows"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local function db() return B.db.bags end

local FRAMES = { "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
	"ContainerFrame4", "ContainerFrame5", "ContainerFrame6" }

local function Hide(region)
	if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
end

local function QualityColor(quality)
	if not quality or quality < 2 then return nil end   -- poor / common: plain border
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then return c.r, c.g, c.b end
end

-------------------------------------------------------------------------------
-- Item buttons
-------------------------------------------------------------------------------
local function SkinButton(btn)
	if not btn or btn.bSkinned then return end
	btn.bSkinned = true
	local icon = btn.icon or btn.Icon
	Hide(btn:GetNormalTexture())
	Hide(btn.IconBorder)
	Hide(btn.ItemSlotBackground)
	-- dark empty slot
	local slot = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
	slot:SetAllPoints(btn)
	slot:SetColorTexture(0.07, 0.07, 0.08, 0.9)
	btn.bSlot = slot
	if icon then
		icon:ClearAllPoints()
		icon:SetAllPoints(btn)
		B:SkinIcon(icon, btn)
	end
	B:CreateBorder(btn, nil, nil, nil, nil, B:Pixel(btn))
	-- softer highlight / pushed
	local hl = btn:GetHighlightTexture()
	if hl then hl:SetColorTexture(1, 1, 1, 0.12); hl:SetAllPoints(btn) end
	local pushed = btn:GetPushedTexture()
	if pushed then pushed:SetColorTexture(0, 0, 0, 0.35); pushed:SetAllPoints(btn) end
	if btn.Count then
		SetFont(btn.Count, db().countSize, "OUTLINE")
		btn.Count:ClearAllPoints()
		btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
	end
end

local function ColorButton(btn, bagID)
	if not btn or not btn.bBorder then return end
	Hide(btn.IconBorder)
	Hide(btn.ItemSlotBackground)
	local r, g, b
	if db().qualityBorders then
		local bag, slot = bagID or (btn.GetBagID and btn:GetBagID()), btn:GetID()
		local info = bag and C_Container.GetContainerItemInfo(bag, slot)
		r, g, b = QualityColor(info and info.quality)
	end
	if r then btn.bBorder:SetColor(r, g, b, 1) else btn.bBorder:SetColor(B:BorderColor()) end
end

-------------------------------------------------------------------------------
-- Windows
-------------------------------------------------------------------------------
local function UpdateFrame(frame)
	if not frame or not frame.EnumerateValidItems then return end
	-- Blizzard's list can have gaps before a bag has built all its buttons
	for _, btn in frame:EnumerateValidItems() do
		if btn then
			B:Try(SkinButton, btn)
			B:Try(ColorButton, btn)
		end
	end
end

local function SkinFrame(frame)
	if not frame or frame.bSkinned then return end
	frame.bSkinned = true
	-- Blizzard's stone frame, background and portrait ring
	Hide(frame.NineSlice)
	Hide(frame.Bg)
	Hide(frame.Background1Slot)
	Hide(frame.TopTileStreaks)
	if frame.PortraitContainer then
		-- keep the bag icon (it is the bag-settings button), lose the ring
		local p = frame.PortraitContainer
		if p.portrait then p.portrait:SetSize(26, 26) end
	end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetAllPoints(frame)
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	B:CreateBackdrop(panel, db().alpha)
	B:SetBorderSize(panel, 2)
	frame.bPanel = panel
	-- title + money in the UI font
	local title = frame.TitleContainer and frame.TitleContainer.TitleText
	if title then SetFont(title, 13); title:SetTextColor(B:AccentColor()) end
	if frame.MoneyFrame then
		for _, region in ipairs({ frame.MoneyFrame:GetRegions() }) do
			if region.SetFont then SetFont(region, 12) end
		end
		for _, child in ipairs({ frame.MoneyFrame:GetChildren() }) do
			local t = child.Text or (child.GetFontString and child:GetFontString())
			if t then SetFont(t, 12) end
		end
	end
	hooksecurefunc(frame, "UpdateItems", function(self) UpdateFrame(self) end)
	if frame.UpdateItemSlots then hooksecurefunc(frame, "UpdateItemSlots", function(self) UpdateFrame(self) end) end
	frame:HookScript("OnShow", function(self) UpdateFrame(self) end)
end

-- search box shared by the bag windows
local function SkinSearch()
	local box = _G.BagItemSearchBox
	if not box or box.bSkinned then return end
	box.bSkinned = true
	for _, k in ipairs({ "Left", "Middle", "Right", "Mid" }) do Hide(box[k]) end
	local bg = CreateFrame("Frame", nil, box)
	bg:SetPoint("TOPLEFT", box, "TOPLEFT", -4, -1)
	bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 1)
	bg:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
	B:CreateBackdrop(bg, 0.9)
	box:SetFont(GetFont(), 12, B:Flags(""))
end

-------------------------------------------------------------------------------
-- Classic clients: the old bag windows (ContainerFrame1-13). Their art is
-- one big texture per window; it is hidden and a dark panel drawn instead.
-------------------------------------------------------------------------------
local function ClassicFrames()
	local out = {}
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then out[#out + 1] = f end
	end
	return out
end

local function UpdateClassic(frame)
	if not frame or not frame.size then return end
	local name = frame:GetName()
	for i = 1, frame.size do
		local btn = _G[name .. "Item" .. i]
		if btn then
			B:Try(SkinButton, btn)
			B:Try(ColorButton, btn, frame:GetID())
		end
	end
end

local function SkinClassic(frame)
	if frame.bSkinned then return end
	frame.bSkinned = true
	local name = frame:GetName()
	for _, k in ipairs({ "BackgroundTop", "BackgroundMiddle1", "BackgroundMiddle2", "BackgroundBottom", "Background1Slot", "Portrait" }) do
		Hide(_G[name .. k])
	end
	for i = 1, 4 do Hide(_G[name .. "BackgroundMiddle" .. i]) end
	if frame.extendedOverlay then Hide(frame.extendedOverlay) end
	-- the art had transparent margins: the panel hugs the slots instead
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -4)
	panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 2)
	panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	B:CreateBackdrop(panel, db().alpha)
	B:SetBorderSize(panel, 2)
	frame.bPanel = panel
	-- small bag icon where the round portrait was (still the bag menu button)
	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -5)
	B:SkinIcon(icon, panel)
	frame.bIcon = icon
	local title = _G[name .. "Name"]
	if title then
		SetFont(title, 13)
		title:SetTextColor(B:AccentColor())
	end
	local money = _G[name .. "MoneyFrame"]
	if money then
		for _, region in ipairs({ money:GetRegions() }) do
			if region.SetFont then SetFont(region, 12) end
		end
		for _, child in ipairs({ money:GetChildren() }) do
			local t = child.Text or (child.GetFontString and child:GetFontString())
			if t then SetFont(t, 12) end
		end
	end
	frame:HookScript("OnShow", function(self)
		local id = self:GetID()
		local tex
		if id == 0 then tex = "Interface\\Buttons\\Button-Backpack-Up"
		elseif id == -2 then tex = "Interface\\ContainerFrame\\KeyRing-Bag-Icon"
		elseif C_Container and C_Container.ContainerIDToInventoryID then
			local ok, inv = pcall(C_Container.ContainerIDToInventoryID, id)
			if ok and inv then tex = GetInventoryItemTexture("player", inv) end
		end
		self.bIcon:SetTexture(tex)
		UpdateClassic(self)
	end)
end

function M:SkinClassic()
	for _, f in ipairs(ClassicFrames()) do B:Try(SkinClassic, f) end
	B:Try(SkinSearch)
	if ContainerFrame_Update and not self.classicHooked then
		self.classicHooked = true
		hooksecurefunc("ContainerFrame_Update", function(frame) B:Try(UpdateClassic, frame) end)
	end
end

function M:SkinAll()
	if not _G.ContainerFrameCombinedBags and ContainerFrame_Update then return self:SkinClassic() end
	for _, name in ipairs(FRAMES) do
		local f = _G[name]
		if f then B:Try(SkinFrame, f); B:Try(UpdateFrame, f) end
	end
	B:Try(SkinSearch)
end

function M:OnEnable()
	if not db().enabled then return end
	self:SkinAll()
	B:RegisterEvent("BAG_UPDATE_DELAYED", function()
		if M.classicHooked then
			for _, f in ipairs(ClassicFrames()) do if f:IsShown() then B:Try(UpdateClassic, f) end end
			return
		end
		for _, name in ipairs(FRAMES) do
			local f = _G[name]
			if f and f:IsShown() then B:Try(UpdateFrame, f) end
		end
	end)
end

function M:Update()
	if not db().enabled then return end
	if self.classicHooked then
		for _, f in ipairs(ClassicFrames()) do
			if f.bPanel then
				f.bPanel.bBackdrop:SetVertexColor(B:PanelColor(db().alpha))
				if f:IsShown() then UpdateClassic(f) end
				local name = f:GetName()
				for i = 1, (f.size or 0) do
					local btn = _G[name .. "Item" .. i]
					if btn and btn.Count and btn.bSkinned then SetFont(btn.Count, db().countSize, "OUTLINE") end
				end
			end
		end
		return
	end
	for _, name in ipairs(FRAMES) do
		local f = _G[name]
		if f and f.bPanel then
			f.bPanel.bBackdrop:SetVertexColor(B:PanelColor(db().alpha))
			UpdateFrame(f)
		end
	end
	for _, name in ipairs(FRAMES) do
		local f = _G[name]
		if f and f.EnumerateValidItems then
			for _, btn in f:EnumerateValidItems() do
				if btn and btn.Count and btn.bSkinned then SetFont(btn.Count, db().countSize, "OUTLINE") end
			end
		end
	end
end
