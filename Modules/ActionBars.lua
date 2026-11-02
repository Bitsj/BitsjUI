--[[
	BitsjUI - Action bars
	Re-uses Blizzard's own action buttons (so keybinds, paging, cooldowns,
	proc glows, Quick Keybind mode etc. keep working and stay secret-value safe)
	but moves them into BitsjUI containers that can be dragged, resized and
	restyled. Blizzard's bar art (gryphons, background, page arrows) is hidden.
]]
local _, B = ...
local M = B:NewModule("ActionBars")

-- fonts: this file uses the "actionbars" section font (/bui > General > Fonts)
local FONT_SECTION = "actionbars"
local function SetFont(fs, size, outline) return B:SetFont(fs, size, outline, FONT_SECTION) end
local function CreateText(parent, size, justify, layer) return B:CreateText(parent, size, justify, layer, FONT_SECTION) end
local function GetFont() return B:GetFont(nil, FONT_SECTION) end

local BARS = {
	[1] = { blizz = { "MainActionBar", "MainMenuBar" }, prefix = "ActionButton", num = 12, label = "Action bar 1", default = { "BOTTOM", "BOTTOM", 0, 6 } },
	[2] = { blizz = { "MultiBarBottomLeft" }, prefix = "MultiBarBottomLeftButton", num = 12, label = "Action bar 2", default = { "BOTTOM", "BOTTOM", 0, 46 } },
	[3] = { blizz = { "MultiBarBottomRight" }, prefix = "MultiBarBottomRightButton", num = 12, label = "Action bar 3", default = { "BOTTOM", "BOTTOM", 0, 86 } },
	[4] = { blizz = { "MultiBarRight" }, prefix = "MultiBarRightButton", num = 12, label = "Action bar 4", default = { "RIGHT", "RIGHT", -6, 0 } },
	[5] = { blizz = { "MultiBarLeft" }, prefix = "MultiBarLeftButton", num = 12, label = "Action bar 5", default = { "RIGHT", "RIGHT", -46, 0 } },
	[6] = { blizz = { "MultiBar5" }, prefix = "MultiBar5Button", num = 12, label = "Action bar 6", default = { "BOTTOM", "BOTTOM", 0, 200 } },
	[7] = { blizz = { "MultiBar6" }, prefix = "MultiBar6Button", num = 12, label = "Action bar 7", default = { "BOTTOM", "BOTTOM", 0, 240 } },
	[8] = { blizz = { "MultiBar7" }, prefix = "MultiBar7Button", num = 12, label = "Action bar 8", default = { "BOTTOM", "BOTTOM", 0, 280 } },
	pet = { blizz = { "PetActionBar" }, prefix = "PetActionButton", num = 10, label = "Pet bar", default = { "BOTTOMLEFT", "BOTTOM", 246, 6 } },
	stance = { blizz = { "StanceBar" }, prefix = "StanceButton", num = 10, label = "Stance bar", default = { "BOTTOMRIGHT", "BOTTOM", -246, 6 } },
}
M.BARS = BARS
M.order = { 1, 2, 3, 4, 5, 6, 7, 8, "pet", "stance" }
M.bars = {}

local VIS_DEFAULT = "[petbattle][vehicleui][overridebar] hide; show"
local VIS_PET = "[petbattle][vehicleui][overridebar][possessbar][nopet] hide; show"

local function GetBlizzBar(def)
	for _, name in ipairs(def.blizz) do
		if _G[name] then return _G[name] end
	end
end

local function cfg(id) return B.db.actionbars.bars[id] end

-------------------------------------------------------------------------------
-- Hotkey text
-------------------------------------------------------------------------------
local replacements = {
	{ "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
	{ "s%-", "S" }, { "c%-", "C" }, { "a%-", "A" }, { "m%-", "M" },
	{ "Middle Mouse", "M3" }, { "Mouse Button ", "M" }, { "Button", "M" },
	{ "Mouse Wheel Up", "WU" }, { "Mouse Wheel Down", "WD" },
	{ "Num Pad ", "N" }, { "Spacebar", "Spc" }, { "Space", "Spc" },
	{ "Insert", "Ins" }, { "Delete", "Del" }, { "Home", "Hm" }, { "Page Up", "PU" }, { "Page Down", "PD" },
	{ "Capslock", "Cap" },
}

local function ShortenHotkey(button)
	local hk = button.HotKey or (button.GetName and button:GetName() and _G[button:GetName() .. "HotKey"])
	if not hk then return end
	local db = B.db.actionbars
	if not db.showHotkey then
		hk:SetAlpha(0)
		return
	end
	hk:SetAlpha(1)
	SetFont(hk, db.hotkeySize)
	if not db.abbreviate then return end
	local text = hk:GetText()
	if not text or text == "" or text == RANGE_INDICATOR then return end
	for _, r in ipairs(replacements) do text = text:gsub(r[1], r[2]) end
	hk:SetText(text)
end

-------------------------------------------------------------------------------
-- Button skin
-------------------------------------------------------------------------------
local function Region(button, key, suffix)
	if button[key] then return button[key] end
	local name = button.GetName and button:GetName()
	if name and suffix then return _G[name .. suffix] end
end

local function HideArt(button)
	local nt = button.GetNormalTexture and button:GetNormalTexture()
	if nt then nt:SetAlpha(0) end
	for _, key in ipairs({ "SlotArt", "SlotBackground", "RightDivider", "BottomDivider", "FloatingBG", "Background" }) do
		local r = button[key]
		if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
	end
	local hl = button.GetHighlightTexture and button:GetHighlightTexture()
	if hl and hl ~= button.bHighlight then hl:SetAlpha(0) end
	local pushed = button.GetPushedTexture and button:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(0, 0, 0, 0.35)
		pushed:ClearAllPoints()
		pushed:SetAllPoints(button.bIcon or button)
	end
	local checked = button.GetCheckedTexture and button:GetCheckedTexture()
	if checked then
		local r, g, b = B:AccentColor()
		checked:SetColorTexture(r, g, b, 0.35)
		checked:ClearAllPoints()
		checked:SetAllPoints(button.bIcon or button)
	end
end

-------------------------------------------------------------------------------
-- Press feedback: a short flash + icon "pop" on every press (key or mouse).
-- Blizzard's own cast animations on buttons are sized for 45px buttons and
-- look off on resized buttons, so they can be hidden.
-------------------------------------------------------------------------------
local CAST_ANIMS = { "SpellCastAnimFrame", "InterruptDisplay", "TargetReticleAnimFrame", "CooldownFlash" }

local function ScaleAnim(group, from, to, duration, order)
	local a = group:CreateAnimation("Scale")
	if a.SetScaleFrom then
		a:SetScaleFrom(from, from)
		a:SetScaleTo(to, to)
	else
		a:SetFromScale(from, from)
		a:SetToScale(to, to)
	end
	a:SetDuration(duration)
	a:SetOrder(order)
	a:SetOrigin("CENTER", 0, 0)
	a:SetSmoothing(order == 1 and "OUT" or "IN_OUT")
	return a
end

local function SetupPress(button)
	local icon = button.bIcon
	local flash = button:CreateTexture(nil, "OVERLAY", nil, 6)
	flash:SetAllPoints(icon or button)
	flash:SetTexture(B.white)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	button.bFlash = flash
	local fg = flash:CreateAnimationGroup()
	local fa = fg:CreateAnimation("Alpha")
	fa:SetFromAlpha(0.55)
	fa:SetToAlpha(0)
	fa:SetDuration(0.25)
	fa:SetSmoothing("OUT")
	fg:SetScript("OnFinished", function() flash:SetAlpha(0) end)
	button.bFlashAnim = fg

	if icon then
		local sg = icon:CreateAnimationGroup()
		ScaleAnim(sg, 1, 0.86, 0.05, 1)
		ScaleAnim(sg, 0.86, 1, 0.14, 2)
		button.bPopAnim = sg
	end
end

local function Press(button)
	local db = B.db.actionbars
	if not db.pressAnim or not button.bFlashAnim then return end
	local now = GetTime()
	if button.bLastPress and now - button.bLastPress < 0.08 then return end
	button.bLastPress = now
	local style = db.pressStyle
	if style == "flash" or style == "both" then
		local r, g, b = 1, 1, 1
		if db.pressAccent then r, g, b = B:AccentColor() end
		button.bFlash:SetVertexColor(r, g, b)
		button.bFlashAnim:Stop()
		button.bFlashAnim:Play()
	end
	if (style == "pop" or style == "both") and button.bPopAnim then
		button.bPopAnim:Stop()
		button.bPopAnim:Play()
	end
end

local function HookPress(button)
	if button.SetButtonState then
		hooksecurefunc(button, "SetButtonState", function(self, state)
			if state == "PUSHED" then Press(self) end
		end)
	end
	button:HookScript("OnMouseDown", Press)
	button:HookScript("PreClick", Press)
	for _, key in ipairs(CAST_ANIMS) do
		local f = button[key]
		if type(f) == "table" and f.HookScript then
			f:HookScript("OnShow", function(self)
				if B.db.actionbars.hideCastAnim then self:Hide() end
			end)
		end
	end
end

local SetupCooldowns -- defined in the cooldown section below

local function SkinButton(button)
	local db = B.db.actionbars
	local icon = Region(button, "icon", "Icon") or button.Icon
	button.bIcon = icon

	if not button.bSkinned then
		button.bSkinned = true

		-- background for empty slots
		local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints(button)
		bg:SetTexture(B.white)
		local c = B.db.general.backdrop
		bg:SetVertexColor(c.r, c.g, c.b, 0.6)
		button.bBg = bg

		if icon then
			local mask = button.IconMask
			if mask then
				pcall(icon.RemoveMaskTexture, icon, mask)
				mask:Hide()
			end
			icon:SetDrawLayer("ARTWORK", 1)
			B:SkinIcon(icon, button)
		end

		-- our own mouseover highlight (HIGHLIGHT layer shows on hover automatically)
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetColorTexture(1, 1, 1, 0.15)
		hl:SetAllPoints(icon or button)
		button.bHighlight = hl

		-- border sits outside the button so the theme can round it
		B:CreateBorder(button, nil, nil, nil, nil, B:Pixel(button))
		if button.bActionButton then SetupCooldowns(button) end
		SetupPress(button)
		HookPress(button)

		-- Blizzard re-applies its art on some updates
		if button.UpdateButtonArt then
			hooksecurefunc(button, "UpdateButtonArt", HideArt)
		end
		for _, method in ipairs({ "UpdateHotkeys", "SetHotkeys" }) do
			if button[method] then
				hooksecurefunc(button, method, ShortenHotkey)
				break
			end
		end
		-- out-of-range tint as our own overlay: we never call Blizzard's
		-- button functions (that would taint the button, see ActionButton.lua
		-- SetCooldown errors with hidden values)
		local range = button:CreateTexture(nil, "ARTWORK", nil, 4)
		range:SetColorTexture(0.9, 0.1, 0.1, 0.45)
		range:SetBlendMode("BLEND")
		range:SetAllPoints(icon or button)
		range:Hide()
		button.bRange = range
	end

	-- layout of inner regions (re-run on resize)
	local p = B:Pixel(button)
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", button, "TOPLEFT", p, -p)
		icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -p, p)
	end
	local cd = Region(button, "cooldown", "Cooldown") or button.Cooldown
	if cd and icon then
		cd:ClearAllPoints()
		cd:SetAllPoints(icon)
	end
	local flash = Region(button, "Flash", "Flash")
	if flash and icon then
		flash:ClearAllPoints()
		flash:SetAllPoints(icon)
	end
	HideArt(button)

	-- Cooldown swipe: Blizzard's cooldown frame shares the button's frame
	-- level ("useParentLevel"). After the button moves into our bar, the
	-- swipe can end up drawn under the icon, leaving only the numbers.
	-- Lift it explicitly and use a square swipe that fits our square icons.
	local level = button:GetFrameLevel()
	for _, c in ipairs({ cd, button.chargeCooldown, button.lossOfControlCooldown }) do
		if type(c) == "table" and c.SetFrameLevel then
			if c.SetUsingParentFrameLevel then pcall(c.SetUsingParentFrameLevel, c, false) end
			c:SetFrameLevel(level + 2)
		end
	end
	if cd then
		if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
		if not cd.bSwipe then
			cd.bSwipe = true
			if cd.SetSwipeTexture then cd:SetSwipeTexture(B.white) end
			if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.75) end
		end
	end
	if button.bCD then
		local ours = db.bitsjCooldowns
		for _, c in ipairs({ cd, button.chargeCooldown }) do
			if type(c) == "table" and c.SetAlpha then c:SetAlpha(ours and 0 or 1) end
		end
		local size = math.max(10, math.floor((button:GetWidth() or 40) * 0.42 + 0.5))
		button.bDim:ClearAllPoints()
		button.bDim:SetAllPoints(icon or button)
		for i, c in ipairs({ button.bGCD, button.bCD, button.bChargeCD }) do
			c:ClearAllPoints()
			c:SetAllPoints(icon or button)
			c:SetFrameLevel(level + 1 + i)
		end
		local fs = button.bCD.GetCountdownFontString and button.bCD:GetCountdownFontString()
		if fs then SetFont(fs, size) end
	end
	if button.bBorder then button.bBorder:SetFrameLevel(level + 6) end

	-- texts
	ShortenHotkey(button)
	local hk = button.HotKey
	if hk then
		hk:ClearAllPoints()
		hk:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -3)
		hk:SetJustifyH("RIGHT")
	end
	local count = Region(button, "Count", "Count")
	if count then
		SetFont(count, db.countSize)
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
		count:SetAlpha(db.showCount and 1 or 0)
	end
	local macro = Region(button, "Name", "Name")
	if macro then
		SetFont(macro, db.macroSize)
		macro:ClearAllPoints()
		macro:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 3)
		macro:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
		macro:SetAlpha(db.showMacro and 1 or 0)
	end
end

-- range colouring of the icon
local function HookRange()
	if M.rangeHooked or not _G.ActionButton_UpdateRangeIndicator then return end
	M.rangeHooked = true
	hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
		if not self.bSkinned or not self.bIcon then return end
		local out = false
		pcall(function()
			-- may be secret in some situations; then we simply skip
			out = (checksRange and not inRange) and true or false
		end)
		self.bOutOfRange = out
		if self.bRange then self.bRange:SetShown(out and B.db.actionbars.range) end
	end)
end

-------------------------------------------------------------------------------
-- BitsjUI cooldown layer (bars 1-8)
-- Midnight hides cooldown numbers from addons in combat, and Blizzard's own
-- cooldown frame does not always draw on buttons that live in another bar.
-- We draw our own swipe from the client's duration objects, which are made
-- for exactly this and work with hidden ("secret") values.
-------------------------------------------------------------------------------
local function NewCooldown(button, swipeAlpha, edge, numbers)
	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	if cd.SetUsingParentFrameLevel then pcall(cd.SetUsingParentFrameLevel, cd, false) end
	cd:SetDrawSwipe(swipeAlpha > 0)
	if cd.SetSwipeTexture then cd:SetSwipeTexture(B.white) end
	cd:SetSwipeColor(0, 0, 0, swipeAlpha)
	cd:SetDrawEdge(edge)
	if cd.SetDrawBling then cd:SetDrawBling(false) end
	cd:SetHideCountdownNumbers(not numbers)
	return cd
end

function SetupCooldowns(button)
	button.bGCD = NewCooldown(button, 0.35, false, false)
	button.bCD = NewCooldown(button, 0.75, false, true)
	button.bChargeCD = NewCooldown(button, 0, true, false)
	-- dims the whole icon while the spell is on cooldown
	local dim = button:CreateTexture(nil, "ARTWORK", nil, 3)
	dim:SetColorTexture(0, 0, 0, 1)
	dim:SetAlpha(0)
	button.bDim = dim
	button.bCD:HookScript("OnCooldownDone", function() dim:SetAlpha(0) end)
end

-- Duration objects can be hidden ("secret") in combat, and so is the answer
-- to IsZero(). We never compare them: they go straight into widget calls
-- that accept hidden values.
local function ApplyDuration(cd, dur)
	if type(dur) == "table" or type(dur) == "userdata" then
		if pcall(cd.SetCooldownFromDurationObject, cd, dur) then return true end
	end
	cd:Clear()
	return false
end

local function ActionSlot(button)
	if button.CalculateAction then
		local ok, a = pcall(button.CalculateAction, button)
		if ok and type(a) == "number" then return a end
	end
	if type(button.action) == "number" then return button.action end
end

-- plain number of charges left, or nil when unknown / hidden
local function ChargesLeft(slot)
	local api = C_ActionBar
	local fn = (api and api.GetActionCharges) or _G.GetActionCharges
	if not fn then return nil end
	local ok, a = pcall(fn, slot)
	if not ok then return nil end
	if type(a) == "table" then a = a.currentCharges end
	return B.Plain(a, nil)
end

-- dim the icon from the duration's (possibly hidden) "is zero" flag
local function UpdateDim(button, dur, enabled)
	local dim = button.bDim
	if not enabled or (type(dur) ~= "table" and type(dur) ~= "userdata") then dim:SetAlpha(0); return end
	local ok, zero = pcall(dur.IsZero, dur)
	if not ok then dim:SetAlpha(0); return end
	if B.IsSecret(zero) then
		if not (dim.SetAlphaFromBoolean and pcall(dim.SetAlphaFromBoolean, dim, zero, 0, 0.45)) then dim:SetAlpha(0) end
	else
		dim:SetAlpha(zero and 0 or 0.45)
	end
end

local QueueCooldowns -- forward

local function UpdateCooldown(button)
	if not button.bCD then return end
	local db = B.db.actionbars
	local api = C_ActionBar
	local slot = ActionSlot(button)
	local hasAction = slot and B.Plain(HasAction(slot), true)
	if not db.bitsjCooldowns or not hasAction or not (api and api.GetActionCooldownDuration) then
		button.bCD:Clear(); button.bGCD:Clear(); button.bChargeCD:Clear()
		button.bDim:SetAlpha(0)
		return
	end

	-- real cooldown (GCD ignored)
	local ok, dur = pcall(api.GetActionCooldownDuration, slot, true)
	if not ok then dur = nil end

	-- charges: thin recharge edge; at 0 charges (when readable) the recharge is the cooldown
	local chargeDur
	if api.GetActionChargeDuration then
		local okc, c = pcall(api.GetActionChargeDuration, slot, true)
		if okc then chargeDur = c end
	end
	ApplyDuration(button.bChargeCD, chargeDur)
	if chargeDur and ChargesLeft(slot) == 0 then dur = chargeDur end

	ApplyDuration(button.bCD, dur)
	UpdateDim(button, dur, db.desaturateCD)

	-- light global cooldown swipe underneath
	if db.showGCD then
		local okg, g = pcall(api.GetActionCooldownDuration, slot, false)
		ApplyDuration(button.bGCD, okg and g or nil)
	else
		button.bGCD:Clear()
	end
end

local pendingCD
local function RefreshCooldowns()
	pendingCD = nil
	for id, bar in pairs(M.bars) do
		if type(id) == "number" then
			for _, b in ipairs(bar.buttons) do
				if b.bCD then UpdateCooldown(b) end
			end
		end
	end
end
function QueueCooldowns()
	if not pendingCD then
		pendingCD = true
		C_Timer.After(0, B.Safe(RefreshCooldowns))
	end
end
M.QueueCooldowns = QueueCooldowns

local function HookCooldownEvents()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
		"ACTIONBAR_UPDATE_STATE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
		"UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "LOSS_OF_CONTROL_UPDATE", "PLAYER_TARGET_CHANGED" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function() QueueCooldowns() end)
end

-------------------------------------------------------------------------------
-- Bars
-------------------------------------------------------------------------------
local function CreateBar(id)
	local def = BARS[id]
	local frame = CreateFrame("Frame", "BitsjUIActionBar" .. id, UIParent, "SecureHandlerStateTemplate")
	frame.id = id
	frame.def = def
	frame.buttons = {}
	frame:SetSize(40, 40)
	frame:SetFrameStrata("LOW")

	local blizz = GetBlizzBar(def)
	frame.blizz = blizz
	-- bar 1 pages dynamically (stances, skyriding ...); never copy a fixed page
	if id ~= 1 and blizz and blizz.GetAttribute then
		local page = blizz:GetAttribute("actionpage")
		if page then frame.page = page end
	end

	for i = 1, def.num do
		local b = _G[def.prefix .. i]
		if b then
			frame.buttons[i] = b
			frame:SetFrameRef("button" .. i, b)
		end
	end

	-- mouseover fade
	frame.fader = CreateFrame("Frame", nil, frame)
	frame.fader.elapsed = 0
	frame.fader:SetScript("OnUpdate", function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		local c = cfg(id)
		if not c.mouseover then return end
		local show = frame:IsMouseOver(4, -4, -4, 4)
			or (GetCursorInfo and GetCursorInfo() ~= nil)
			or (SpellBookFrame and SpellBookFrame:IsShown())
			or (PlayerSpellsFrame and PlayerSpellsFrame:IsShown())
		frame:SetAlpha(show and c.alpha or c.mouseoverAlpha)
	end)

	if id == 1 then M:SetupPaging(frame) end

	M.bars[id] = frame
	return frame
end

-------------------------------------------------------------------------------
-- Main bar paging
-- Blizzard pages bar 1 from its own (now hidden) bar. We own the paging
-- instead with a secure state driver, so the bar follows skyriding, druid
-- forms, stealth, possess/vehicle and Shift+wheel paging, and always
-- returns to page 1 when the condition ends.
-------------------------------------------------------------------------------
local PAGE_DRIVER = table.concat({
	"[vehicleui][possessbar][overridebar][shapeshift] special",
	"[bonusbar:5] 11",            -- skyriding / dragonriding
	"[bar:2] 2", "[bar:3] 3", "[bar:4] 4", "[bar:5] 5", "[bar:6] 6",
	"[bonusbar:1] 7", "[bonusbar:2] 8", "[bonusbar:3] 9", "[bonusbar:4] 10",
	"1",
}, "; ")

function M:SetupPaging(frame)
	for i, b in ipairs(frame.buttons) do
		frame:SetFrameRef("button" .. i, b)
		-- Blizzard refreshes the button itself on the paging events; we only
		-- refresh our own cooldown layer. (Calling Blizzard's UpdateAction from
		-- addon code taints the button and breaks its cooldowns in combat.)
		b:HookScript("OnAttributeChanged", function(self, name)
			if name == "actionpage" then QueueCooldowns() end
		end)
	end
	frame:SetAttribute("_onstate-page", string.format([[
		local page = newstate
		if page == "special" then
			if HasVehicleActionBar() then page = GetVehicleBarIndex()
			elseif HasOverrideActionBar() then page = GetOverrideBarIndex()
			elseif HasTempShapeshiftActionBar() then page = GetTempShapeshiftBarIndex()
			elseif HasBonusActionBar() then page = GetBonusBarIndex()
			else page = GetActionBarPage() end
		end
		page = tonumber(page) or 1
		self:SetAttribute("actionpage", page)
		for i = 1, %d do
			local b = self:GetFrameRef("button" .. i)
			if b then b:SetAttribute("actionpage", page) end
		end
	]], #frame.buttons))
	-- stop Blizzard's hidden main bar from paging the same buttons
	if frame.blizz then
		pcall(UnregisterStateDriver, frame.blizz, "page")
		pcall(UnregisterStateDriver, frame.blizz, "actionpage")
	end
	RegisterStateDriver(frame, "page", PAGE_DRIVER)
end

function M:LayoutBar(id)
	local frame = self.bars[id]
	if not frame then return end
	local c = cfg(id)
	local db = B.db.actionbars

	if InCombatLockdown() then
		B:RunOOC("bar" .. tostring(id), function() M:LayoutBar(id) end)
		return
	end

	local n = math.min(c.buttons, #frame.buttons)
	local perRow = B.Clamp(c.perRow, 1, math.max(1, n))
	local rows = math.ceil(n / perRow)
	local size, sp = c.size, c.spacing
	frame:SetSize(math.max(1, perRow * size + (perRow - 1) * sp), math.max(1, rows * size + (rows - 1) * sp))

	local vertical = perRow < rows
	for i, b in ipairs(frame.buttons) do
		if c.enabled and i <= n then
			b:SetParent(frame)
			b:ClearAllPoints()
			local col = (i - 1) % perRow
			local row = math.floor((i - 1) / perRow)
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (size + sp), -row * (size + sp))
			b:SetSize(size, size)
			b:SetScale(1)
			b.bActionButton = type(id) == "number"
			SkinButton(b)
			B:SetBorderSize(b, B.db.actionbars.borderSize or 1)
		else
			b:SetParent(B.hiddenParent)
		end
	end

	-- Button attributes are set from a secure snippet. Attributes written by
	-- normal addon code are "tainted", and Blizzard's button code reading them
	-- then refuses the hidden cooldown values in combat.
	local body = string.format([[
		for i = 1, %d do
			local b = self:GetFrameRef("button" .. i)
			if b then
				%s
				b:SetAttribute("flyoutDirection", %q)
				%s
			end
		end
	]], #frame.buttons,
		frame.page and string.format('b:SetAttribute("actionpage", %d)', frame.page) or "",
		vertical and "LEFT" or "UP",
		db.emptyButtons and 'b:SetAttribute("showgrid", 1)' or "")
	if frame.Execute then
		local ok, err = pcall(frame.Execute, frame, body)
		if not ok then B:Error(err) end
	end

	if c.enabled then
		local driver = (id == "pet") and VIS_PET or VIS_DEFAULT
		RegisterStateDriver(frame, "visibility", driver)
	else
		RegisterStateDriver(frame, "visibility", "hide")
	end
	frame:SetAlpha(c.mouseover and c.mouseoverAlpha or c.alpha)
	B:SetMoverEnabled("bar" .. tostring(id), c.enabled)
	B.Movers:Apply("bar" .. tostring(id))
end

function M:LayoutAll()
	for _, id in ipairs(self.order) do self:LayoutBar(id) end
	QueueCooldowns()
end

-- keep Blizzard from pulling the buttons back into its own (hidden) bars
local function ProtectBlizzBar(frame)
	local blizz = frame.blizz
	if not blizz or blizz.bHooked then return end
	blizz.bHooked = true
	for _, method in ipairs({ "UpdateGridLayout", "UpdateShownButtons", "UpdateButtonLayout", "Layout" }) do
		if blizz[method] then
			hooksecurefunc(blizz, method, function()
				if not frame.bPending then
					frame.bPending = true
					C_Timer.After(0, function()
						frame.bPending = false
						M:LayoutBar(frame.id)
					end)
				end
			end)
		end
	end
	blizz.bOrigParent = blizz:GetParent()
	blizz:SetParent(B.hiddenParent)
	-- Classic: the big stone bar (MainMenuBar) is only art (gryphons, background)
	-- drawn around the main bar; it goes with it
	local art = _G.MainMenuBar
	if B.isClassic and frame.id == 1 and art and art ~= blizz and not art.bHidden then
		art.bHidden = true
		art:SetParent(B.hiddenParent)
	end
end

function M:OnEnable()
	if not B.db.actionbars.enabled then return end
	HookRange()
	HookCooldownEvents()
	for _, id in ipairs(self.order) do
		local def = BARS[id]
		local frame = CreateBar(id)
		B:RegisterMover(frame, "bar" .. tostring(id), def.label, def.default)
		ProtectBlizzBar(frame)
	end
	self:LayoutAll()

	-- Edit Mode re-applies layouts; restore ours afterwards
	local emm = _G.EditModeManagerFrame
	if emm and not emm.bHooked then
		emm.bHooked = true
		for _, method in ipairs({ "ExitEditMode", "UpdateLayoutInfo" }) do
			if emm[method] then
				hooksecurefunc(emm, method, function()
					C_Timer.After(0.1, function() M:LayoutAll() end)
				end)
			end
		end
	end
	B:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		C_Timer.After(0.5, function() M:LayoutAll() end)
	end)
end

function M:Update()
	if not B.db.actionbars.enabled or not next(self.bars) then return end
	self:LayoutAll()
end
