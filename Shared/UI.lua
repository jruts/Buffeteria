-- Controls and textures used by more than one feature.
local _, ns = ...
local UI = { ICON = ns.mediaPath .. "Icon", WHITE = "Interface\\Buttons\\WHITE8X8", GOLD = { 1, 0.82, 0 } }
ns.UI = UI
-- Inline color codes for font strings.
UI.COLOR = { GREY = "|cff808080", RED = "|cffff5040" }
local icons = {}

-- Talent tree backgrounds per class, in talent-tab order.
UI.TREE_ART = {
	WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
	ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
	HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
	MAGE = { "MageArcane", "MageFire", "MageFrost" },
	WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
	PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
	DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
	PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
	SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
}
-- Talent slot tints: learned, available, unavailable, and conflict.
UI.SLOT_COLORS = { gold = UI.GOLD, green = { 0.1, 1, 0.1 }, grey = { 0.5, 0.5, 0.5 }, red = { 1, 0.25, 0.2 } }
-- Visible area of the four-piece talent art (TopLeft 256x256, TopRight 64x256,
-- BottomLeft 256x128, BottomRight 64x128), as the native talent frame shows it.
local ART_W, ART_H = 296, 332

function UI.BuffIcon(key)
	if not icons[key] then
		local buff = ns.Buffs.byKey[key]
		icons[key] = (buff.groupIds[1] and ns.WoW.SpellIcon(buff.groupIds[1])) or ns.WoW.SpellIcon(buff.ids[1]) or 134400
	end
	return icons[key]
end

-- A dark panel with the tooltip border; edge 12 suits cards, 10 or less small controls.
function UI.Backdrop(frame, edgeSize, background, border)
	local inset = edgeSize >= 12 and 3 or 2
	frame:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = edgeSize,
		insets = { left = inset, right = inset, top = inset, bottom = inset } })
	if background then frame:SetBackdropColor(unpack(background)) end
	if border then frame:SetBackdropBorderColor(unpack(border)) end
end

function UI.Checkbox(parent, label, x, y, onClick)
	local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	button:SetSize(24, 24)
	button:SetPoint("TOPLEFT", x, y)
	button.text = button.text or button.Text or button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", button, "RIGHT", 2, 0)
	button.text:SetText(label)
	button:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return button
end

-- A standard push button, with an optional tooltip.
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

function UI.Text(parent, font, x, y, width, label)
	local region = parent:CreateFontString(nil, "OVERLAY", font)
	region:SetPoint("TOPLEFT", x, y)
	if width then region:SetWidth(width) end
	region:SetJustifyH("LEFT"); region:SetText(label or "")
	return region
end

-- A small framed box showing one value, like the talent panel's point counter.
function UI.ValueBox(parent, width, height, font)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(width, height)
	UI.Backdrop(box, 10, { 0, 0, 0, 0.8 }, { 0.6, 0.6, 0.6, 1 })
	box.value = box:CreateFontString(nil, "OVERLAY", font)
	box.value:SetPoint("CENTER", 0, 0)
	return box
end

-- The gold line under talent tree headers, with a dark shadow beneath it.
local function goldRule(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.85, 0.66, 0.26, 0.9); line:SetHeight(1)
	local shade = parent:CreateTexture(nil, "ARTWORK")
	shade:SetColorTexture(0, 0, 0, 0.6); shade:SetHeight(1)
	shade:SetPoint("TOPLEFT", line, "BOTTOMLEFT"); shade:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT")
	return line
end

-- A framed settings group: dark panel, shaded header with an icon and gold title.
function UI.Card(parent, title, icon)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(card, 12, { 0.04, 0.03, 0.02, 0.72 }, { 0.55, 0.45, 0.25, 1 })
	local shade = card:CreateTexture(nil, "BORDER")
	shade:SetPoint("TOPLEFT", 3, -3); shade:SetPoint("TOPRIGHT", -3, -3); shade:SetHeight(25)
	shade:SetColorTexture(0, 0, 0, 0.45)
	local badge = card:CreateTexture(nil, "ARTWORK")
	badge:SetSize(16, 16); badge:SetPoint("TOPLEFT", 10, -7)
	badge:SetTexture(icon); badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.title = UI.Text(card, "GameFontNormal", 32, -9, nil, title)
	local rule = goldRule(card)
	rule:SetPoint("TOPLEFT", 6, -28); rule:SetPoint("TOPRIGHT", -6, -28)
	return card
end

-- A selectable pill button, also used for the window's tabs. The label lives on
-- its own font string so lookups by label return the caption, whose parent is the chip.
function UI.Chip(parent, label, width, onClick, font)
	local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
	chip:SetSize(width, 22)
	UI.Backdrop(chip, 10)
	chip.caption = chip:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	chip.caption:SetPoint("CENTER", 0, 0); chip.caption:SetText(label)
	chip:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	function chip:SetChecked(value)
		self.checked = value and true or false
		if self.checked then
			self:SetBackdropColor(0.32, 0.22, 0.04, 0.95); self:SetBackdropBorderColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
			self.caption:SetTextColor(unpack(UI.GOLD))
		else
			self:SetBackdropColor(0, 0, 0, 0.6); self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
			self.caption:SetTextColor(0.75, 0.75, 0.75)
		end
	end
	function chip:GetChecked() return self.checked end
	chip:SetChecked(false)
	chip:SetScript("OnClick", function(self) onClick(self) end)
	return chip
end

-- Talent rank badge: the small numbered box at a talent button's corner.
local function badge(parent)
	local border = parent:CreateTexture(nil, "OVERLAY")
	border:SetSize(32, 32)
	border:SetTexture("Interface\\TalentFrame\\TalentFrame-RankBorder")
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER", border, "CENTER", 0, 0)
	return border, label
end

-- A talent button: icon in a stone slot tinted gold, green, grey, or red.
function UI.TalentButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(37, 37)
	button.slot = button:CreateTexture(nil, "BACKGROUND")
	button.slot:SetSize(64, 64); button.slot:SetPoint("CENTER", 0, 0)
	button.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot-White")
	button.icon = button:CreateTexture(nil, "BORDER")
	button.icon:SetAllPoints()
	-- Zoom past the icon's baked-in bevel so only the slot frames it.
	button.icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	function button:SetState(state, texture)
		local color = UI.SLOT_COLORS[state] or UI.SLOT_COLORS.grey
		self.state = state
		self.icon:SetTexture(texture)
		self.icon:SetDesaturated(state == "grey")
		self.slot:SetVertexColor(color[1], color[2], color[3])
	end
	return button
end

local function layoutArt(tree)
	local width, height = tree:GetWidth(), tree:GetHeight()
	local scale = math.max(width / ART_W, height / ART_H)
	local x0, y0 = (width - ART_W * scale) / 2, (height - ART_H * scale) / 2
	for _, piece in ipairs(tree.art) do
		piece.texture:ClearAllPoints()
		piece.texture:SetPoint("TOPLEFT", tree.clip, "TOPLEFT", x0 + piece.x * scale, -(y0 + piece.y * scale))
		piece.texture:SetSize(piece.w * scale, piece.h * scale)
	end
end

-- A talent-tree pane: class artwork cropped to fill, a round icon with a count
-- badge, a title, and the gold rule beneath the header.
function UI.Tree(parent)
	local tree = CreateFrame("Frame", nil, parent)
	-- Clip the artwork at the tree's own level so controls on the tree draw above it.
	tree.clip = CreateFrame("Frame", nil, tree)
	tree.clip:SetAllPoints(); tree.clip:SetClipsChildren(true)
	tree.clip:SetFrameLevel(tree:GetFrameLevel())
	local base = tree.clip:CreateTexture(nil, "BACKGROUND", nil, -1)
	base:SetAllPoints(); base:SetColorTexture(0.05, 0.035, 0.02, 1)
	tree.art = {
		{ name = "TopLeft", x = 0, y = 0, w = 256, h = 256, coords = { 0, 1, 0, 1 } },
		{ name = "TopRight", x = 256, y = 0, w = 40, h = 256, coords = { 0, 40 / 64, 0, 1 } },
		{ name = "BottomLeft", x = 0, y = 256, w = 256, h = 76, coords = { 0, 1, 0, 76 / 128 } },
		{ name = "BottomRight", x = 256, y = 256, w = 40, h = 76, coords = { 0, 40 / 64, 0, 76 / 128 } },
	}
	for _, piece in ipairs(tree.art) do
		piece.texture = tree.clip:CreateTexture(nil, "BACKGROUND")
		piece.texture:SetTexCoord(unpack(piece.coords))
	end
	-- Darken the header so its text stays readable over bright art.
	local top = tree.clip:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(70)
	top:SetColorTexture(0, 0, 0, 0.45)
	local separator = tree.clip:CreateTexture(nil, "BORDER")
	separator:SetPoint("TOPRIGHT"); separator:SetPoint("BOTTOMRIGHT"); separator:SetWidth(1)
	separator:SetColorTexture(0, 0, 0, 0.9)

	local header = CreateFrame("Frame", nil, tree)
	header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(70)
	tree.header = header
	tree.icon = header:CreateTexture(nil, "ARTWORK")
	tree.icon:SetSize(34, 34); tree.icon:SetPoint("TOPLEFT", 16, -12)
	-- Fill the round portrait with artwork, hiding the square icon bevel.
	tree.icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
	local mask = header:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tree.icon)
	tree.icon:AddMaskTexture(mask)
	local ring = header:CreateTexture(nil, "OVERLAY", nil, -1)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("talents-node-circle-yellow") then
		ring:SetSize(46, 46); ring:SetPoint("CENTER", tree.icon, "CENTER", 0, 0)
		ring:SetAtlas("talents-node-circle-yellow")
	else
		-- Without the round node art, use the gold minimap tracking ring.
		ring:SetSize(58, 58); ring:SetPoint("TOPLEFT", tree.icon, "TOPLEFT", -7, 7)
		ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	end
	tree.badgeBorder, tree.badge = badge(header)
	tree.badgeBorder:SetPoint("CENTER", tree.icon, "BOTTOM", 0, -3)
	tree.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	tree.title:SetPoint("LEFT", tree.icon, "RIGHT", 12, 6); tree.title:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	tree.title:SetJustifyH("LEFT"); tree.title:SetWordWrap(false)
	tree.note = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tree.note:SetPoint("TOPLEFT", tree.title, "BOTTOMLEFT", 0, -3); tree.note:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	tree.note:SetJustifyH("LEFT"); tree.note:SetWordWrap(false)
	local rule = goldRule(header)
	rule:SetPoint("BOTTOMLEFT", 10, 0); rule:SetPoint("BOTTOMRIGHT", -10, 0)

	function tree:SetArt(prefix, dim)
		for _, piece in ipairs(self.art) do
			piece.texture:SetTexture(prefix and ("Interface\\TalentFrame\\" .. prefix .. "-" .. piece.name) or nil)
			piece.texture:SetDesaturated(dim and true or false)
			local shade = dim and 0.4 or 0.9
			piece.texture:SetVertexColor(shade, shade, shade)
		end
	end
	function tree:SetHeader(icon, title, note, count)
		self.icon:SetTexture(icon); self.title:SetText(title or ""); self.note:SetText(note or "")
		self.badge:SetText(count and tostring(count) or "")
		self.badge:SetShown(count ~= nil); self.badgeBorder:SetShown(count ~= nil)
		self.icon:SetShown(icon ~= nil); ring:SetShown(icon ~= nil)
	end
	function tree:Resize(width, height)
		self:SetSize(width, height)
		layoutArt(self)
	end
	return tree
end

-- Dim `icon` while the button is pressed. `button.dragged` resets on every
-- press so release handlers can ignore the click that ends a drag.
function UI.PressFeedback(button, icon, onDown)
	button:SetScript("OnMouseDown", function(self)
		self.dragged = false
		if icon then icon:SetVertexColor(0.75, 0.75, 0.75) end
		if onDown then onDown(self) end
	end)
	if not icon then return end
	button:SetScript("OnMouseUp", function() icon:SetVertexColor(1, 1, 1) end)
	button:SetScript("OnLeave", function()
		icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
	end)
end

-- The band under the tabs: a title and help line, plus (withCount) a talent-panel
-- style counter box on the right, like "Unspent Talents [0]".
function UI.Band(parent, title, help, withCount)
	local band = CreateFrame("Frame", nil, parent)
	band:SetPoint("TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", 0, 0); band:SetHeight(44)
	local shade = band:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, 0.35)
	local rule = goldRule(band)
	rule:SetPoint("BOTTOMLEFT", 8, 0); rule:SetPoint("BOTTOMRIGHT", -8, 0)
	-- The heading belongs to the parent so a feature view can be found by it.
	band.title = UI.Text(parent, "GameFontNormal", 16, -7, nil, title)
	band.help = UI.Text(parent, "GameFontHighlightSmall", 16, -25, nil, help)
	band.help:SetWordWrap(false)
	if not withCount then
		band.help:SetPoint("RIGHT", band, "RIGHT", -16, 0)
		return band
	end
	band.help:SetPoint("RIGHT", band, "RIGHT", -170, 0)
	band.box = UI.ValueBox(band, 34, 24, "GameFontHighlightLarge")
	band.box:SetPoint("RIGHT", -14, 0)
	band.countLabel = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	band.countLabel:SetPoint("RIGHT", band.box, "LEFT", -8, 0)
	function band:SetCount(label, value)
		self.countLabel:SetText(label); self.box.value:SetText(tostring(value))
	end
	return band
end
