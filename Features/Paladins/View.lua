-- Classes down the rows, paladins across columns, with explicit slot pickers.
local _, ns = ...
local UI, Buffs = ns.UI, ns.Buffs
local View = {}
ns.Paladins.View = View
local panel, viewport, canvas, scrollbar, empty, picker, undo
local columns, classRows = {}, {}
local EDGE, STUB, HEADER, ROW, BOARD_H, BOARD_Y = 12, 148, 80, 42, 458, -56
local columnWidth, contentWidth, scrollOffset, count = 144, 0, 0, 0
local GREY = UI.COLOR.GREY
local PASS = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local RED_EDGE, DARK_EDGE = { 1, 0.25, 0.15, 1 }, { 0.2, 0.19, 0.17, 1 }
local closePicker

local function tooltip(button)
	local name = button.column.paladin
	local member = name and ns.Assignments.roster.members[name]
	if not member then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.WoW.Short(name) .. " - " .. (button.class == "AURA" and "Aura" or ns.WoW.ClassName(button.class)))
	GameTooltip:AddLine(button.detail or "", 1, 0.82, 0, true)
	if button.duplicate then GameTooltip:AddLine("A newer assignment took this blessing. Choose another or reset to Auto.", 1, 0.35, 0.2, true) end
	if not member.hasAddon then GameTooltip:AddLine("Spells unverified: choose only spells this paladin can cast.", 0.8, 0.8, 0.8, true) end
	GameTooltip:AddLine("Click: choose. Right-click: Auto. Shift-click: None.", 1, 1, 1, true)
	GameTooltip:Show()
end

closePicker = function()
	if picker then picker:Hide(); picker.target = nil end
end

local function openPicker(button)
	local name, slot = button.column.paladin, button.class
	local member = name and ns.Assignments.roster.members[name]
	if not member then return end
	if picker:IsShown() and picker.target == button then closePicker(); return end
	GameTooltip_Hide()
	picker.target = button
	local choices = ns.Paladins.Choices(name, slot)
	local height = #choices * 22 + 62
	picker:SetSize(220, height)
	-- Open just below the clicked slot, kept inside the page.
	local x = EDGE + STUB + (button.column.index - 1) * columnWidth - scrollOffset + 12
	local y = -BOARD_Y + (slot == "AURA" and 76 or HEADER + button.rowIndex * ROW - 2)
	x = math.max(EDGE, math.min(x, (panel.layoutWidth or 900) - 232))
	y = math.max(8, math.min(y, 560 - height))
	picker:ClearAllPoints(); picker:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
	picker.title:SetText(ns.WoW.Short(name) .. " > " .. (slot == "AURA" and "Aura" or ns.WoW.ClassName(slot)))
	picker.help:SetText(member.hasAddon and "Known spells only" or "Spells unverified; choose a castable spell")
	local current = ns.Paladins.Get(name, slot)
	for i, key in ipairs(choices) do
		local choice = picker.choices[i]
		if not choice then
			choice = UI.MenuItem(picker, 204, function(self)
				local target = picker.target
				if target and target.column.paladin == self.paladin then
					ns.Paladins.Set(self.paladin, target.class, self.key)
				end
				closePicker()
			end)
			choice:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 22)
			picker.choices[i] = choice
		end
		choice.key, choice.paladin = key, name
		local resolved = slot == "AURA" and ns.Assignments.Aura(name) or ns.Assignments.ClassBlessing(slot, name)
		local buff = Buffs.byKey[key == "AUTO" and resolved or key]
		choice.caption:SetText(key == "AUTO" and ("Auto: " .. (buff and buff.label or "None"))
			or (key == "NONE" and "None" or buff.label))
		choice.icon:SetTexture(buff and UI.BuffIcon(buff.key) or PASS)
		choice.icon:SetDesaturated(buff == nil)
		choice:SetChecked(key == current); choice:Show()
	end
	for i = #choices + 1, #picker.choices do picker.choices[i]:Hide() end
	picker:Show()
end

-- The small boxed "A" that marks an Auto slot.
local function autoBadge(parent)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(18, 18)
	UI.Backdrop(box, 8, { 0, 0, 0, 0.5 }, { 0.45, 0.45, 0.45, 1 })
	box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.text:SetPoint("CENTER", 0, 0); box.text:SetText("A"); box.text:SetTextColor(0.75, 0.75, 0.75)
	return box
end

local function slotButton(parent, column, slot, rowIndex)
	local button = UI.Chip(parent, "", 140, function() end)
	button:SetHeight(34); button.column, button.class, button.rowIndex = column, slot, rowIndex
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.icon = UI.Icon(button, 24)
	button.icon.frame:SetPoint("LEFT", 5, 0)
	button.caption:ClearAllPoints(); button.caption:SetPoint("LEFT", 37, 0)
	button.caption:SetPoint("RIGHT", -28, 0); button.caption:SetJustifyH("LEFT"); button.caption:SetWordWrap(false)
	button.autoBox = autoBadge(button)
	button.autoBox:SetPoint("RIGHT", -6, 0)
	button.auto = button.autoBox.text
	button:SetScript("OnClick", function(self, mouseButton)
		local name = self.column.paladin
		if not name or not ns.Assignments.roster.members[name] then return end
		if mouseButton == "RightButton" then closePicker(); ns.Paladins.Set(name, slot, "AUTO")
		elseif IsShiftKeyDown() then closePicker(); ns.Paladins.Set(name, slot, "NONE")
		else openPicker(self) end
	end)
	button:SetScript("OnEnter", tooltip); button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function createColumn()
	local column = CreateFrame("Frame", nil, canvas)
	-- A hairline between paladin columns.
	local separator = UI.Line(column, 1, 1, 1, 0.07, true, "BACKGROUND")
	separator:SetPoint("TOPLEFT", 0, -6); separator:SetPoint("BOTTOMLEFT", 0, 6)
	column.title = UI.Text(column, "GameFontNormal", 10, -10)
	column.title:SetWordWrap(false)
	column.note = UI.Text(column, "GameFontHighlightSmall", 10, -26)
	column.note:SetWordWrap(false); column.note:SetTextColor(0.65, 0.65, 0.65)
	column.aura = slotButton(column, column, "AURA")
	column.aura:SetPoint("TOPLEFT", 5, -42); column.aura:SetHeight(32)
	column.rows = {}
	for i, class in ipairs(Buffs.CLASS_KEYS) do
		local row = slotButton(column, column, class, i)
		row:SetPoint("TOPLEFT", 5, -HEADER - (i - 1) * ROW - 4)
		column.rows[class] = row
	end
	return column
end

local function showSlot(button, name, slot, resolved)
	local key = ns.Paladins.Get(name, slot)
	local buff = Buffs.byKey[key == "AUTO" and resolved or key]
	local duplicate = ns.Paladins.Overruled(name, slot)
	local state = duplicate and "red" or not buff and "grey" or key == "AUTO" and "green" or "gold"
	button.state, button.duplicate = state, duplicate
	button.detail = key == "AUTO" and ("Auto: " .. (buff and buff.label or "None"))
		or key == "NONE" and "None" or Buffs.byKey[key].label
	button.caption:SetText(duplicate and "Conflict" or buff and buff.label or "None")
	-- Manual picks get the gold edge; Auto stays grey with its badge; None and
	-- conflicts read at a glance from their dark and red edges.
	button:SetChecked(key ~= "AUTO" and key ~= "NONE" and buff ~= nil and not duplicate)
	if duplicate then
		button:SetBackdropBorderColor(unpack(RED_EDGE)); button.caption:SetTextColor(1, 0.35, 0.25)
	elseif not buff then
		button:SetBackdropBorderColor(unpack(DARK_EDGE)); button.caption:SetTextColor(0.5, 0.5, 0.5)
	end
	button.icon:SetTexture(buff and UI.BuffIcon(buff.key) or PASS)
	button.icon:SetDesaturated(not buff)
	button.auto:SetShown(key == "AUTO"); button.autoBox:SetShown(key == "AUTO")
	return buff
end

function View.Layout(width)
	if not panel then return end
	panel.layoutWidth = width
	local available = width - EDGE * 2 - STUB
	columnWidth = math.min(180, math.floor(available / math.max(1, math.min(5, count))))
	contentWidth = math.max(available, count * columnWidth)
	viewport:SetSize(available, BOARD_H); canvas:SetSize(contentWidth, BOARD_H)
	local maximum = math.max(0, contentWidth - available)
	scrollOffset = math.min(scrollOffset, maximum)
	scrollbar:SetWidth(available - 12); scrollbar:SetMinMaxValues(0, maximum)
	scrollbar:SetValue(scrollOffset); scrollbar:SetShown(maximum > 0)
	viewport:SetHorizontalScroll(scrollOffset)
	for i = 1, count do
		local column = columns[i]
		column:ClearAllPoints(); column:SetPoint("TOPLEFT", (i - 1) * columnWidth, 0); column:SetSize(columnWidth, BOARD_H)
		column.title:SetWidth(columnWidth - 16); column.note:SetWidth(columnWidth - 16)
		column.aura:SetWidth(columnWidth - 10)
		for _, row in pairs(column.rows) do row:SetWidth(columnWidth - 10) end
	end
end

function View.Refresh()
	if not panel then return end
	local pals = ns.Roster.Paladins()
	count = #pals
	empty:SetShown(count == 0)
	local stats = {}
	for _, member in pairs(ns.Assignments.roster.members) do
		local st = stats[member.class] or { count = 0, overrides = 0 }
		st.count = st.count + 1; st.overrides = st.overrides + (member.blessingsOverride and 1 or 0)
		stats[member.class] = st
	end
	for class, row in pairs(classRows) do
		local st = stats[class] or { count = 0, overrides = 0 }
		row.label:SetText(ns.WoW.ClassColorName(ns.WoW.ClassName(class), class) .. GREY .. "  (" .. st.count .. ")|r")
		row.note:SetText(st.overrides > 0 and (st.overrides .. " personal ranking" .. (st.overrides > 1 and "s" or "")) or "")
		row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 40, st.overrides > 0 and -7 or -14)
		row:SetAlpha(st.count == 0 and 0.4 or 1)
	end
	for i, name in ipairs(pals) do
		columns[i] = columns[i] or createColumn()
		local column, member = columns[i], ns.Assignments.roster.members[name]
		column.paladin, column.index = name, i; column:Show()
		column.title:SetText(ns.WoW.ClassColorName(name, "PALADIN"))
		local covered = 0
		for class, row in pairs(column.rows) do
			if showSlot(row, name, class, ns.Assignments.ClassBlessing(class, name)) then covered = covered + 1 end
			row:SetAlpha((stats[class] and stats[class].count > 0) and 1 or 0.45)
		end
		showSlot(column.aura, name, "AURA", ns.Assignments.Aura(name))
		column.note:SetText(covered .. "/9 classes" .. (member.hasAddon and "" or "  -  Unverified"))
	end
	for i = count + 1, #columns do columns[i].paladin = nil; columns[i]:Hide() end
	if picker.target then
		local target = picker.target
		if not target.column.paladin or target.column.paladin ~= picker.choices[1].paladin then closePicker() end
	end
	undo:SetEnabled(ns.Paladins.CanUndo())
	View.Layout(panel.layoutWidth or 900)
end

-- One legend entry: a sample swatch and its meaning.
local function legend(x, sample, label)
	sample:SetPoint("TOPLEFT", x, -538)
	local text = UI.Text(panel, "GameFontHighlightSmall", 0, 0, nil, label)
	text:ClearAllPoints(); text:SetPoint("LEFT", sample, "RIGHT", 6, 0)
	return text
end

local function swatch(border)
	local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	box:SetSize(18, 18)
	UI.Backdrop(box, 8, { 0.04, 0.035, 0.03, 0.85 }, border)
	return box
end

function View.Create(host)
	panel = host
	UI.PageHeader(panel, "Class blessings", "Classes are rows, paladins are columns.")
	undo = UI.Button(panel, "Undo", 64, function() closePicker(); ns.Paladins.Undo() end,
		"Undo the last bulk action. Newer group edits are preserved.")
	undo:SetPoint("TOPRIGHT", -12, -14)
	local clear = UI.Button(panel, "Reset all to Auto", 136, function() closePicker(); ns.Paladins.Clear(); View.Refresh() end,
		"Reset every blessing and aura to Auto. You can undo this action.")
	clear:SetPoint("RIGHT", undo, "LEFT", -6, 0)
	local fill = UI.Button(panel, "Lock in Auto picks", 146, function() closePicker(); ns.Paladins.Fill(); View.Refresh() end,
		"Keep Auto's current assignments when the group changes. Manual choices stay.")
	fill:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	local board = UI.Panel(panel)
	board:SetPoint("TOPLEFT", EDGE, BOARD_Y); board:SetPoint("TOPRIGHT", -EDGE, BOARD_Y); board:SetHeight(BOARD_H)
	UI.Text(board, "GameFontNormal", 12, -14, nil, "Class")
	local auraHint = UI.Text(board, "GameFontHighlightSmall", 12, -50, STUB - 20, "Aura")
	auraHint:SetTextColor(0.6, 0.6, 0.6)
	-- The header rule, the stub's edge, and a faint stripe on every other class row.
	local rule = UI.Line(board, 0.75, 0.6, 0.3, 0.5)
	rule:SetPoint("TOPLEFT", 4, -HEADER + 1); rule:SetPoint("TOPRIGHT", -4, -HEADER + 1)
	local edge = UI.Line(board, 1, 1, 1, 0.07, true)
	edge:SetPoint("TOPLEFT", STUB - 1, -6); edge:SetPoint("BOTTOMLEFT", STUB - 1, 6)
	for i, class in ipairs(Buffs.CLASS_KEYS) do
		if i % 2 == 1 then
			local stripe = board:CreateTexture(nil, "BORDER")
			stripe:SetPoint("TOPLEFT", 4, -HEADER - (i - 1) * ROW); stripe:SetPoint("TOPRIGHT", -4, -HEADER - (i - 1) * ROW)
			stripe:SetHeight(ROW); stripe:SetColorTexture(1, 1, 1, 0.03)
		end
		local row = CreateFrame("Frame", nil, board)
		row:SetSize(STUB - 8, ROW); row:SetPoint("TOPLEFT", 0, -HEADER - (i - 1) * ROW)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 10, 0)
		UI.ClassIcon(row.icon, class)
		row.label = UI.Text(row, "GameFontHighlight", 40, -14, STUB - 48)
		row.label:SetWordWrap(false)
		row.note = UI.Text(row, "GameFontHighlightSmall", 40, -23, STUB - 48); row.note:SetWordWrap(false)
		row.note:SetTextColor(0.6, 0.6, 0.6)
		classRows[class] = row
	end
	viewport = CreateFrame("ScrollFrame", nil, panel)
	viewport:SetPoint("TOPLEFT", EDGE + STUB, BOARD_Y)
	canvas = CreateFrame("Frame", nil, viewport); viewport:SetScrollChild(canvas)
	empty = UI.Text(viewport, "GameFontDisableLarge", 30, -140, nil, "No paladins in the group")
	scrollbar = UI.Slider(panel)
	scrollbar:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 6, -2)
	scrollbar:SetValueStep(1)
	scrollbar:SetScript("OnValueChanged", function(_, value) closePicker(); scrollOffset = value; viewport:SetHorizontalScroll(value) end)
	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta) scrollbar:SetValue(scrollOffset - delta * columnWidth) end)
	local auto = swatch({ 0.45, 0.45, 0.45, 1 })
	local letter = auto:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	letter:SetPoint("CENTER", 0, 0); letter:SetText("A"); letter:SetTextColor(0.75, 0.75, 0.75)
	legend(EDGE + 4, auto, "Auto")
	legend(EDGE + 84, swatch({ UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1 }), "Manual")
	local none = panel:CreateTexture(nil, "ARTWORK"); none:SetSize(18, 18); none:SetTexture(PASS)
	legend(EDGE + 174, none, "None")
	legend(EDGE + 254, swatch(RED_EDGE), "Conflict")
	local interaction = UI.Text(panel, "GameFontHighlightSmall", 0, 0, nil, "Click: choose     Right-click: Auto     Shift-click: None")
	interaction:ClearAllPoints(); interaction:SetPoint("TOPRIGHT", -EDGE - 4, -541)
	interaction:SetTextColor(0.65, 0.65, 0.65)
	picker = UI.Menu(panel, ns.globalPrefix .. "_PaladinPicker")
	picker:SetFrameLevel(panel:GetFrameLevel() + 30)
	picker.title = UI.Text(picker, "GameFontNormal", 12, -11, 196)
	local divider = UI.Line(picker, 1, 1, 1, 0.15)
	divider:SetPoint("TOPLEFT", 8, -28); divider:SetPoint("TOPRIGHT", -8, -28)
	picker.help = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	picker.help:SetPoint("BOTTOMLEFT", 12, 10); picker.help:SetWidth(196); picker.help:SetJustifyH("LEFT")
	picker.choices = {}; picker:Hide(); tinsert(UISpecialFrames, ns.globalPrefix .. "_PaladinPicker")
	panel:SetScript("OnHide", closePicker)
	panel.columns, panel.classRows, panel.viewport, panel.scrollbar = columns, classRows, viewport, scrollbar
	panel.fill, panel.clear, panel.undo, panel.picker = fill, clear, undo, picker
end
