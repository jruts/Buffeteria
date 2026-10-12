-- Talent-window class plan editor; one column for every paladin in the roster.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Paladins.View = View
local panel, viewport, canvas, scrollbar, empty, help
local columns = {}
local COLUMN_W, GAP, EDGE, BOARD_H, ROW_H = 252, 2, 14, 476, 41
local contentWidth, scrollOffset = 0, 0

local function paladinNames()
	local out = {}
	for full, m in pairs(ns.roster.members) do
		if m.class == "PALADIN" then out[#out + 1] = full end
	end
	table.sort(out)
	return out
end

local function fill(parent, layer, r, g, b, a)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetAllPoints(); texture:SetColorTexture(r, g, b, a)
	return texture
end

local function rule(parent, y)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetColorTexture(0.65, 0.48, 0.19, 0.65)
	texture:SetHeight(1)
	texture:SetPoint("TOPLEFT", 10, y); texture:SetPoint("TOPRIGHT", -10, y)
end

local function text(parent, font, x, y, width, label)
	local region = parent:CreateFontString(nil, "OVERLAY", font)
	region:SetPoint("TOPLEFT", x, y); region:SetWidth(width)
	region:SetJustifyH("LEFT"); region:SetText(label or "")
	return region
end

local function cycle(column, class, mouseButton)
	local name = column.paladin
	local member = name and ns.roster.members[name]
	if not member or member.class ~= "PALADIN" then return end
	local choices = { "AUTO" }
	local caps = member.caps or {}
	for _, key in ipairs(Buffs.BLESSING_KEYS) do
		if not member.hasAddon or caps[key] or caps["g" .. key] then choices[#choices + 1] = key end
	end
	choices[#choices + 1] = "NONE"
	local current, index = ns.Paladins.Get(name, class), 1
	for i, key in ipairs(choices) do if key == current then index = i; break end end
	local delta = mouseButton == "RightButton" and -1 or 1
	ns.Paladins.Set(name, class, choices[((index - 1 + delta) % #choices) + 1])
end

local function tooltip(button)
	local column, class = button.column, button.class
	local name = column.paladin
	if not name or not ns.roster.members[name] then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.WoW.Short(name) .. " - " .. ns.WoW.ClassName(class))
	GameTooltip:AddLine(button.assignment:GetText(), 1, 0.82, 0)
	if button.duplicate then GameTooltip:AddLine("Another paladin already has this blessing assigned.", 1, 0.35, 0.2, true) end
	if not ns.roster.members[name].hasAddon then
		GameTooltip:AddLine("Without Buffeteria: choose blessings this paladin can cast.", 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Left-click: next blessing. Right-click: previous.", 1, 1, 1, true)
	GameTooltip:AddLine("Auto follows the class plan. None leaves this class unassigned.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function createColumn()
	local column = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
	column:SetSize(COLUMN_W, BOARD_H)
	column:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	column:SetBackdropColor(0.12, 0.09, 0.04, 1)
	column:SetBackdropBorderColor(0.65, 0.48, 0.19, 1)
	-- Use the same centered crop as the native narrow talent-tree panels.
	local pieces = {
		{ "TopLeft", 0, 256 / 331, 1 },
		{ "BottomLeft", 256 / 331, 75 / 331, 0.4140625 },
	}
	for _, piece in ipairs(pieces) do
		local art = column:CreateTexture(nil, "BACKGROUND", nil, 1)
		art:SetTexture("Interface\\TalentFrame\\PaladinHoly-" .. piece[1])
		art:SetPoint("TOPLEFT", 4, -4 - (BOARD_H - 8) * piece[2])
		art:SetSize(COLUMN_W - 8, (BOARD_H - 8) * piece[3])
		art:SetTexCoord(0.19921875, 0.97265625, 0, piece[4]); art:SetVertexColor(0.8, 0.8, 0.8)
	end
	fill(column, "BORDER", 0.025, 0.018, 0.01, 0.4)
	local portrait = column:CreateTexture(nil, "ARTWORK")
	portrait:SetSize(42, 42); portrait:SetPoint("TOPLEFT", 18, -19)
	portrait:SetTexture("Interface\\Icons\\Spell_Holy_HolyBolt")
	local portraitBorder = column:CreateTexture(nil, "OVERLAY")
	portraitBorder:SetSize(64, 64); portraitBorder:SetPoint("CENTER", portrait, "CENTER", 0, 0)
	portraitBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	column.name = text(column, "GameFontHighlightLarge", 72, -21, COLUMN_W - 88)
	column.name:SetWordWrap(false)
	column.note = text(column, "GameFontDisableSmall", 72, -46, COLUMN_W - 88)
	rule(column, -77)
	column.rows = {}
	for i, class in ipairs(Buffs.CLASS_KEYS) do
		local row = CreateFrame("Button", nil, column)
		row:SetSize(COLUMN_W - 28, ROW_H - 2); row:SetPoint("TOPLEFT", 14, -90 - (i - 1) * ROW_H)
		row.column, row.class = column, class
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		local classIcon = row:CreateTexture(nil, "ARTWORK")
		classIcon:SetSize(24, 24); classIcon:SetPoint("LEFT", 0, 0)
		classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if coords then classIcon:SetTexCoord(unpack(coords)) else classIcon:Hide() end
		text(row, "GameFontHighlightSmall", 32, -3, 142, ns.WoW.ClassName(class))
		row.assignment = text(row, "GameFontNormalSmall", 32, -22, 142)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(34, 34); row.icon:SetPoint("RIGHT", -4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.border = row:CreateTexture(nil, "OVERLAY")
		row.border:SetSize(58, 58); row.border:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
		row.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		row:SetScript("OnClick", function(_, mouseButton) cycle(column, class, mouseButton) end)
		row:SetScript("OnEnter", tooltip); row:SetScript("OnLeave", GameTooltip_Hide)
		column.rows[class] = row
	end
	return column
end

function View.GetPreferredWidth()
	local count = #paladinNames()
	return math.max(340, EDGE * 2 + count * (COLUMN_W + GAP) - GAP)
end

function View.Layout(width)
	if not panel then return end
	local available = math.max(1, width - EDGE * 2)
	viewport:SetSize(available, BOARD_H)
	canvas:SetSize(math.max(available, contentWidth), BOARD_H)
	local maximum = math.max(0, contentWidth - available)
	scrollOffset = math.min(scrollOffset, maximum)
	scrollbar:SetWidth(math.max(1, available - 12)); scrollbar:SetMinMaxValues(0, maximum)
	scrollbar:SetValue(scrollOffset); scrollbar:SetShown(maximum > 0)
	viewport:SetHorizontalScroll(scrollOffset)
	help:SetWidth(available)
	-- Center a lone column in the minimum-width preferences host.
	local inset = math.max(0, (available - contentWidth) / 2)
	for i, column in ipairs(columns) do
		column:ClearAllPoints(); column:SetPoint("TOPLEFT", inset + (i - 1) * (COLUMN_W + GAP), 0)
	end
end

function View.Refresh()
	if not panel then return end
	local pals = paladinNames()
	contentWidth = math.max(0, #pals * (COLUMN_W + GAP) - GAP)
	empty:SetShown(#pals == 0)
	for i, name in ipairs(pals) do
		if not columns[i] then columns[i] = createColumn() end
		local column, member = columns[i], ns.roster.members[name]
		column.paladin = name; column:Show()
		column.name:SetText(ns.WoW.ClassColorName(name, "PALADIN"))
		column.note:SetText(member.hasAddon and "Buffeteria connected" or "Without Buffeteria")
		for class, row in pairs(column.rows) do
			local key = ns.Paladins.Get(name, class)
			local resolved = ((ns.result.pally or {})[class] or {})[name]
			local buff = Buffs.byKey[key == "AUTO" and resolved or key]
			row.duplicate = Buffs.byKey[key] and (((ns.roster.paladinAssignments or {})[class] or {})[name] == "NONE")
			local label = key == "AUTO" and ("Auto: " .. (buff and buff.label or "none"))
				or (key == "NONE" and "None" or Buffs.byKey[key].label)
			if row.duplicate then label = label .. " (duplicate)" end
			row.assignment:SetText(label)
			row.icon:SetTexture(buff and ns.UI.BuffIcon(buff.key) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.icon:SetDesaturated(not buff or row.duplicate and true or false)
			if row.duplicate then row.border:SetVertexColor(1, 0.3, 0.2)
			elseif not buff then row.border:SetVertexColor(0.4, 0.4, 0.4)
			elseif key == "AUTO" then row.border:SetVertexColor(0.4, 0.85, 0.35)
			else row.border:SetVertexColor(1, 0.82, 0) end
		end
	end
	for i = #pals + 1, #columns do columns[i].paladin = nil; columns[i]:Hide() end
end

function View.Create(parent)
	panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", 0, -32); panel:SetPoint("BOTTOMRIGHT")
	panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
	panel:SetBackdropColor(0.06, 0.045, 0.025, 1); panel:SetBackdropBorderColor(0.65, 0.48, 0.19, 1)
	text(panel, "GameFontNormal", EDGE, -12, 300, "Class blessing assignments")
	help = text(panel, "GameFontHighlightSmall", EDGE, -34, 300,
		"One column per paladin. Click a class blessing to cycle; right-click reverses.")
	viewport = CreateFrame("ScrollFrame", nil, panel)
	viewport:SetPoint("TOPLEFT", EDGE, -66)
	canvas = CreateFrame("Frame", nil, viewport)
	viewport:SetScrollChild(canvas)
	empty = text(viewport, "GameFontDisable", 20, -40, 270, "No paladins in the group")
	scrollbar = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	scrollbar:SetOrientation("HORIZONTAL"); scrollbar:SetSize(280, 12)
	scrollbar:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 6, -6)
	scrollbar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	scrollbar:SetBackdropColor(0.22, 0.17, 0.08, 1)
	scrollbar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	scrollbar:GetThumbTexture():SetSize(24, 16)
	scrollbar:SetValueStep(1)
	scrollbar:SetScript("OnValueChanged", function(_, value)
		scrollOffset = value; viewport:SetHorizontalScroll(value)
	end)
	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta)
		scrollbar:SetValue(math.max(0, math.min(scrollOffset - delta * (COLUMN_W + GAP), math.max(0, contentWidth - viewport:GetWidth()))))
	end)
	local priority = text(panel, "GameFontDisableSmall", EDGE, -570, 300,
		"Personal overrides take priority. Your column is saved.")
	priority:SetPoint("TOPRIGHT", -EDGE, -570)
	ns.UI.AnnounceButton(panel)
	panel.columns, panel.viewport, panel.scrollbar = columns, viewport, scrollbar
	return panel
end
