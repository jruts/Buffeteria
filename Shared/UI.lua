-- Controls and textures used by more than one feature. Everything here is drawn
-- with art shipped in the game client (tooltip, checkbox, radio, slider, tab and
-- panel-button files), so the window reads as part of the default interface.
local _, ns = ...
local UI = { ICON = ns.mediaPath .. "Icon", WHITE = "Interface\\Buttons\\WHITE8X8", GOLD = { 1, 0.82, 0 } }
ns.UI = UI
-- Inline color codes for font strings.
UI.COLOR = { GREY = "|cff808080", RED = "|cffff5040", GREEN = "|cff40c040" }
-- Shared palette: panel fill, idle and selected borders, and body text.
UI.PANEL = { 0.02, 0.018, 0.015, 0.78 }
UI.EDGE = { 0.42, 0.38, 0.32, 1 }
UI.IDLE = { 0.32, 0.3, 0.27, 1 }
UI.GOLD_EDGE = { 0.75, 0.6, 0.3, 1 }
UI.TEXT = { 0.9, 0.9, 0.9 }
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local icons = {}
-- Spell data may be unavailable on login; never cache a question-mark result.
local FALLBACK_ICONS = { SANCT = "Interface\\Icons\\Spell_Nature_LightningShield" }

function UI.BuffIcon(key)
	if not icons[key] then
		local buff = ns.Buffs.byKey[key]
		if not buff then return 134400 end
		for _, ids in ipairs({ buff.groupIds, buff.ids }) do
			for _, id in ipairs(ids) do
				local icon = ns.WoW.SpellIcon(id)
				if icon and icon ~= 134400 and icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
					icons[key] = icon
					return icon
				end
			end
		end
	end
	return icons[key] or FALLBACK_ICONS[key] or 134400
end

-- Prefer the client's class atlas, with the native character-create sheet fallback.
function UI.ClassIcon(texture, class)
	local atlas = "classicon-" .. class:lower()
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas); return
	end
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	local index = ({ WARRIOR = 0, MAGE = 1, ROGUE = 2, DRUID = 3, HUNTER = 4,
		SHAMAN = 5, PRIEST = 6, WARLOCK = 7, PALADIN = 8 })[class] or 0
	texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
	texture:SetTexCoord(unpack(coords or { (index % 4) / 4, (index % 4 + 1) / 4,
		math.floor(index / 4) / 4, (math.floor(index / 4) + 1) / 4 }))
end

-- Set a client texture file. Modern clients return false for a missing file;
-- report that so callers can fall back to a plain look instead of a green box.
function UI.SetFile(texture, path)
	return texture:SetTexture(path) ~= false
end

-- A dark panel with the tooltip border; edge 12+ suits panels, 10 or less small controls.
function UI.Backdrop(frame, edgeSize, background, border)
	local inset = edgeSize >= 12 and 3 or 2
	frame:SetBackdrop({ bgFile = UI.WHITE, edgeFile = TOOLTIP_EDGE, edgeSize = edgeSize,
		insets = { left = inset, right = inset, top = inset, bottom = inset } })
	if background then frame:SetBackdropColor(unpack(background)) end
	if border then frame:SetBackdropBorderColor(unpack(border)) end
end

-- Fill a texture with a gradient from `low` (bottom or left) to `high` (top or
-- right), each { r, g, b, a }; clients without gradients get the flat `low` color.
function UI.Gradient(texture, orientation, low, high)
	texture:SetTexture(UI.WHITE)
	if CreateColor and texture.SetGradient
		and pcall(texture.SetGradient, texture, orientation, CreateColor(unpack(low)), CreateColor(unpack(high))) then
		return
	end
	if texture.SetGradientAlpha then
		texture:SetGradientAlpha(orientation, low[1], low[2], low[3], low[4], high[1], high[2], high[3], high[4])
		return
	end
	texture:SetColorTexture(unpack(low))
end

function UI.Text(parent, font, x, y, width, label)
	local region = parent:CreateFontString(nil, "OVERLAY", font)
	region:SetPoint("TOPLEFT", x, y)
	if width then region:SetWidth(width) end
	region:SetJustifyH("LEFT"); region:SetText(label or "")
	return region
end

-- A one-pixel line; horizontal unless `vertical`.
function UI.Line(parent, r, g, b, a, vertical, layer)
	local line = parent:CreateTexture(nil, layer or "ARTWORK")
	line:SetColorTexture(r, g, b, a)
	if vertical then line:SetWidth(1) else line:SetHeight(1) end
	return line
end

-- The gold divider used under headings, with a dark shadow beneath it.
local function goldRule(parent)
	local line = UI.Line(parent, 0.75, 0.6, 0.3, 0.55)
	local shade = UI.Line(parent, 0, 0, 0, 0.5)
	shade:SetPoint("TOPLEFT", line, "BOTTOMLEFT"); shade:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT")
	return line
end

function UI.Rule(parent, x, y, width)
	local rule = goldRule(parent)
	rule:SetPoint("TOPLEFT", x, y); rule:SetWidth(width)
	return rule
end

-- A section heading whose rule runs from the end of its text to the right edge.
function UI.Section(parent, label, x, y, right)
	local heading = UI.Text(parent, "GameFontNormal", x, y, nil, label)
	local rule = goldRule(parent)
	-- The heading's top sits at `y`, so both ends share one vertical position.
	rule:SetPoint("TOPLEFT", heading, "TOPRIGHT", 8, -6)
	rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(right or x), y - 6)
	return heading
end

-- A page title and help line at the top of a tab. Both belong to `parent` so a
-- feature view can be found by its heading.
function UI.PageHeader(parent, title, help)
	local heading = UI.Text(parent, "GameFontNormalLarge", 16, -8, nil, title)
	local note = UI.Text(parent, "GameFontHighlightSmall", 16, -30, nil, help)
	note:SetTextColor(0.7, 0.7, 0.7)
	return heading, note
end

-- A recessed panel: dark fill inside the tooltip border, tinted bronze.
function UI.Panel(parent)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(frame, 14, UI.PANEL, UI.EDGE)
	return frame
end

-- A titled panel: a large gold heading over a softly shaded header band.
-- The icon argument is accepted for older callers and ignored.
function UI.Card(parent, title)
	local card = UI.Panel(parent)
	local band = card:CreateTexture(nil, "BORDER")
	band:SetPoint("TOPLEFT", 4, -4); band:SetPoint("TOPRIGHT", -4, -4); band:SetHeight(30)
	UI.Gradient(band, "VERTICAL", { 0, 0, 0, 0 }, { 1, 0.82, 0.4, 0.07 })
	card.title = UI.Text(card, "GameFontNormalLarge", 12, -10, nil, title)
	local divider = UI.Line(card, 0.6, 0.5, 0.3, 0.35)
	divider:SetPoint("TOPLEFT", 6, -34); divider:SetPoint("TOPRIGHT", -6, -34)
	return card
end

-- A standard red panel button, with an optional tooltip.
function UI.Button(parent, label, width, onClick, tip)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", function() onClick() end)
	if tip then
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(label)
			GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	return button
end

function UI.Checkbox(parent, label, x, y, onClick)
	local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	button:SetSize(26, 26)
	button:SetPoint("TOPLEFT", x, y)
	button.text = button.text or button.Text or button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.text:SetFontObject("GameFontHighlight")
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", button, "RIGHT", 2, 1)
	button.text:SetText(label)
	button:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return button
end

-- The client's checkbox as a display-only mark, for rows that are clicked as a whole.
function UI.CheckMark(parent, size)
	local box = parent:CreateTexture(nil, "ARTWORK")
	box:SetSize(size, size); box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
	local check = parent:CreateTexture(nil, "OVERLAY")
	check:SetSize(size, size); check:SetPoint("CENTER", box, "CENTER", 0, 0)
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	return box, check
end

-- The client's radio button art: unchecked ring, checked dot, and hover glow.
local RADIO = "Interface\\Buttons\\UI-RadioButton"
function UI.RadioMark(parent, size)
	local ring = parent:CreateTexture(nil, "ARTWORK")
	ring:SetSize(size, size); ring:SetTexture(RADIO); ring:SetTexCoord(0, 0.25, 0, 1)
	local dot = parent:CreateTexture(nil, "OVERLAY")
	dot:SetAllPoints(ring); dot:SetTexture(RADIO); dot:SetTexCoord(0.25, 0.5, 0, 1)
	return ring, dot
end

-- A labelled radio option. The caption is its own font string so a lookup by
-- label returns it, whose parent is the clickable option.
function UI.Radio(parent, label, width, onClick)
	local option = CreateFrame("Button", nil, parent)
	option:SetSize(width, 20)
	option.ring, option.dot = UI.RadioMark(option, 16)
	option.ring:SetPoint("LEFT", 0, 0)
	local glow = option:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints(option.ring); glow:SetTexture(RADIO); glow:SetTexCoord(0.5, 0.75, 0, 1); glow:SetBlendMode("ADD")
	option.caption = option:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	option.caption:SetPoint("LEFT", option.ring, "RIGHT", 6, 0); option.caption:SetText(label)
	function option:SetChecked(value)
		self.checked = value and true or false
		self.dot:SetShown(self.checked)
		if self.checked then self.caption:SetTextColor(unpack(UI.GOLD)) else self.caption:SetTextColor(unpack(UI.TEXT)) end
	end
	function option:GetChecked() return self.checked end
	option:SetChecked(false)
	option:SetScript("OnClick", function(self) onClick(self) end)
	return option
end

-- A spell icon with a one-pixel frame; `icon.frame` takes a vertex color.
function UI.Icon(parent, size, layer)
	local frame = parent:CreateTexture(nil, "BORDER")
	frame:SetSize(size + 2, size + 2); frame:SetColorTexture(1, 1, 1, 1); frame:SetVertexColor(0, 0, 0)
	local icon = parent:CreateTexture(nil, layer or "ARTWORK")
	icon:SetSize(size, size); icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.frame = frame
	return icon, frame
end

-- A small framed box showing one value, like the talent panel's point counter.
function UI.ValueBox(parent, width, height, font)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(width, height)
	UI.Backdrop(box, 10, { 0, 0, 0, 0.75 }, UI.IDLE)
	box.value = box:CreateFontString(nil, "OVERLAY", font)
	box.value:SetPoint("CENTER", 0, 0)
	return box
end

-- A selectable button: dark with a grey edge, or a gold edge and caption when
-- checked. The label lives on its own font string so lookups by label return the
-- caption, whose parent is the chip.
function UI.Chip(parent, label, width, onClick, font)
	local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
	chip:SetSize(width, 24)
	UI.Backdrop(chip, 10)
	chip.caption = chip:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	chip.caption:SetPoint("CENTER", 0, 0); chip.caption:SetText(label)
	chip:SetHighlightTexture(HIGHLIGHT, "ADD")
	function chip:SetChecked(value)
		self.checked = value and true or false
		if self.checked then
			self:SetBackdropColor(0.16, 0.11, 0.02, 0.92); self:SetBackdropBorderColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
			self.caption:SetTextColor(unpack(UI.GOLD))
		else
			self:SetBackdropColor(0.04, 0.035, 0.03, 0.85); self:SetBackdropBorderColor(unpack(UI.IDLE))
			self.caption:SetTextColor(unpack(UI.TEXT))
		end
	end
	function chip:GetChecked() return self.checked end
	chip:SetChecked(false)
	chip:SetScript("OnClick", function(self) onClick(self) end)
	return chip
end

-- A top tab: a filled body with edges on three sides. The active tab is taller,
-- gold-edged and runs past its bottom to cover the baseline, opening into the page.
function UI.Tab(parent, label, width, onClick)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(width, 28)
	tab.fill = tab:CreateTexture(nil, "BACKGROUND")
	tab.edges = {}
	for i = 1, 3 do tab.edges[i] = UI.Line(tab, 1, 1, 1, 1, i > 1, "BORDER") end
	tab.shine = UI.Line(tab, 1, 0.9, 0.7, 0.18, false, "ARTWORK")
	local glow = tab:CreateTexture(nil, "HIGHLIGHT")
	glow:SetPoint("TOPLEFT", 2, -6); glow:SetPoint("BOTTOMRIGHT", -2, 0)
	glow:SetTexture(HIGHLIGHT); glow:SetBlendMode("ADD"); glow:SetAlpha(0.5)
	tab.caption = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.caption:SetText(label)
	function tab:SetChecked(value)
		self.checked = value and true or false
		local top, bottom = self.checked and 0 or -5, self.checked and -2 or 0
		local top_, left, right = self.edges[1], self.edges[2], self.edges[3]
		self.fill:ClearAllPoints(); self.fill:SetPoint("TOPLEFT", 0, top); self.fill:SetPoint("BOTTOMRIGHT", 0, bottom)
		top_:ClearAllPoints(); top_:SetPoint("TOPLEFT", 0, top); top_:SetPoint("TOPRIGHT", 0, top)
		left:ClearAllPoints(); left:SetPoint("TOPLEFT", 0, top); left:SetPoint("BOTTOMLEFT", 0, bottom)
		right:ClearAllPoints(); right:SetPoint("TOPRIGHT", 0, top); right:SetPoint("BOTTOMRIGHT", 0, bottom)
		self.shine:ClearAllPoints(); self.shine:SetPoint("TOPLEFT", 1, top - 1); self.shine:SetPoint("TOPRIGHT", -1, top - 1)
		self.caption:ClearAllPoints(); self.caption:SetPoint("CENTER", 0, (top + bottom) / 2 - 1)
		local edge = self.checked and UI.GOLD_EDGE or UI.IDLE
		for _, line in ipairs(self.edges) do line:SetColorTexture(edge[1], edge[2], edge[3], 1) end
		self.shine:SetShown(self.checked)
		if self.checked then
			UI.Gradient(self.fill, "VERTICAL", { 0.09, 0.08, 0.07, 1 }, { 0.26, 0.2, 0.11, 1 })
			self.caption:SetTextColor(1, 1, 1)
		else
			UI.Gradient(self.fill, "VERTICAL", { 0.04, 0.035, 0.03, 0.95 }, { 0.12, 0.1, 0.08, 0.95 })
			self.caption:SetTextColor(unpack(UI.GOLD))
		end
	end
	function tab:GetChecked() return self.checked end
	tab:SetChecked(false)
	tab:SetScript("OnClick", function(self)
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		onClick(self)
	end)
	return tab
end

-- A horizontal slider with the client's options-slider track and thumb.
function UI.Slider(parent, name)
	local bar = CreateFrame("Slider", name, parent, "BackdropTemplate")
	bar:SetOrientation("HORIZONTAL"); bar:SetHeight(17)
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 } })
	bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	bar:GetThumbTexture():SetSize(32, 32)
	return bar
end

-- A dropdown menu frame in the client's tooltip style, and its rows: a flat
-- list item with an optional icon, a check for the current choice, and hover glow.
function UI.Menu(parent, name)
	local menu = CreateFrame("Frame", name, parent, "BackdropTemplate")
	menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = TOOLTIP_EDGE,
		tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	menu:SetBackdropColor(0.03, 0.03, 0.03, 0.96); menu:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
	menu:SetFrameStrata("DIALOG"); menu:EnableMouse(true)
	return menu
end

function UI.MenuItem(parent, width, onClick)
	local item = CreateFrame("Button", nil, parent)
	item:SetSize(width, 22)
	item:SetHighlightTexture(HIGHLIGHT, "ADD")
	item.check = item:CreateTexture(nil, "OVERLAY")
	item.check:SetSize(16, 16); item.check:SetPoint("LEFT", 2, 0)
	item.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetSize(18, 18); item.icon:SetPoint("LEFT", 20, 0); item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	item.caption = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	item.caption:SetPoint("LEFT", item.icon, "RIGHT", 6, 0); item.caption:SetJustifyH("LEFT")
	function item:SetChecked(value)
		self.checked = value and true or false
		self.check:SetShown(self.checked)
		if self.checked then self.caption:SetTextColor(unpack(UI.GOLD)) else self.caption:SetTextColor(1, 1, 1) end
	end
	function item:GetChecked() return self.checked end
	item:SetChecked(false)
	item:SetScript("OnClick", function(self) onClick(self) end)
	return item
end

-- A wanted-buff row: checkbox, framed icon, name and the caster serving it.
-- Skipped buff rows dim; the row itself never fills with color.
function UI.BuffRow(parent, key, onClick)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetSize(180, 48)
	UI.Backdrop(row, 10, { 0, 0, 0, 0.35 }, { 0.25, 0.23, 0.2, 1 })
	row:SetHighlightTexture(HIGHLIGHT, "ADD")
	row.key = key
	row.checkSlot, row.check = UI.CheckMark(row, 24)
	row.checkSlot:SetPoint("LEFT", 6, 0)
	row.icon = UI.Icon(row, 32)
	row.icon.frame:SetPoint("LEFT", 36, 0)
	row.label = UI.Text(row, "GameFontHighlight", 78, -9, nil, ns.Buffs.byKey[key].label)
	row.label:SetPoint("RIGHT", -8, 0); row.label:SetWordWrap(false)
	row.caster = UI.Text(row, "GameFontHighlightSmall", 78, -27)
	row.caster:SetPoint("RIGHT", -8, 0); row.caster:SetWordWrap(false)
	row.caster:SetTextColor(0.7, 0.7, 0.7)
	function row:SetState(state, texture)
		self.state = state
		self.checked = state == "gold"
		self.check:SetShown(self.checked)
		self.icon:SetTexture(texture); self.icon:SetDesaturated(not self.checked)
		self.icon:SetAlpha(self.checked and 1 or 0.6)
		if self.checked then self.label:SetTextColor(1, 1, 1) else self.label:SetTextColor(0.6, 0.6, 0.6) end
	end
	function row:GetChecked() return self.checked end
	row:SetScript("OnClick", function(self) onClick(self) end)
	return row
end

-- Dim `icon` while the button is pressed, unless `button.inert` says the press
-- does nothing. `button.dragged` resets on every press so release handlers can
-- ignore the click that ends a drag.
function UI.PressFeedback(button, icon, onDown)
	button:SetScript("OnMouseDown", function(self)
		self.dragged = false
		if icon and not self.inert then icon:SetVertexColor(0.75, 0.75, 0.75) end
		if onDown then onDown(self) end
	end)
	if not icon then return end
	button:SetScript("OnMouseUp", function() icon:SetVertexColor(1, 1, 1) end)
	button:SetScript("OnLeave", function()
		icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
	end)
end
