-- Talent-panel class plan editor; one talent tree for every paladin in the roster.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Paladins.View = View
local panel, band, viewport, canvas, scrollbar, empty
local columns, seats = {}, {}
-- Paladins share the board's width; past three trees it scrolls sideways.
local MAX_VISIBLE, GAP, EDGE, BOARD_H, MIN_COLUMN, CELL = 3, 2, 8, 360, 196, 68
local SPEC_ICONS = { "Interface\\Icons\\Spell_Holy_HolyBolt", "Interface\\Icons\\Spell_Holy_DevotionAura",
	"Interface\\Icons\\Spell_Holy_AuraOfLight" }
local columnWidth, contentWidth, scrollOffset, paladinCount = MIN_COLUMN, 0, 0, 0

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
	GameTooltip:AddLine(button.detail, 1, 0.82, 0)
	if button.duplicate then GameTooltip:AddLine("Another paladin already has this blessing assigned.", 1, 0.35, 0.2, true) end
	if not ns.roster.members[name].hasAddon then
		GameTooltip:AddLine("Without Buffeteria: choose blessings this paladin can cast.", 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Left-click: next blessing. Right-click: previous.", 1, 1, 1, true)
	GameTooltip:AddLine("Auto follows the class plan. None leaves this class unassigned.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function createColumn()
	local column = ns.UI.Tree(canvas)
	column.rows = {}
	for _, class in ipairs(Buffs.CLASS_KEYS) do
		local row = ns.UI.TalentButton(column)
		row.column, row.class = column, class
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("TOP", row, "BOTTOM", 0, -5)
		row.name:SetText(ns.WoW.ClassColorName(ns.WoW.ClassName(class), class))
		row.assignment = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.assignment:SetPoint("TOP", row.name, "BOTTOM", 0, -1)
		row:SetScript("OnClick", function(_, mouseButton) cycle(column, class, mouseButton) end)
		row:SetScript("OnEnter", tooltip); row:SetScript("OnLeave", GameTooltip_Hide)
		column.rows[class] = row
	end
	return column
end

local function createSeat()
	local seat = ns.UI.Tree(canvas)
	seat:SetHeader(nil, "", "")
	return seat
end

-- Talent tiers sized to the tree: three classes per tier in a narrow tree, up to
-- five in a wide one, with tiers balanced and centered.
local function layoutColumn(column)
	local count = #Buffs.CLASS_KEYS
	local perTier = math.max(3, math.min(5, math.floor(columnWidth / CELL)))
	local tiers = math.ceil(count / perTier)
	perTier = math.ceil(count / tiers)
	local cell = columnWidth / perTier
	local top = -92 - (3 - tiers) * 44
	for i, class in ipairs(Buffs.CLASS_KEYS) do
		local row = column.rows[class]
		local tier, x = math.floor((i - 1) / perTier), (i - 1) % perTier
		local inTier = math.min(perTier, count - tier * perTier)
		local offset = (columnWidth - inTier * cell) / 2
		row:ClearAllPoints(); row:SetPoint("TOP", column, "TOPLEFT", offset + cell * (x + 0.5), top - tier * 88)
		row.name:SetWidth(cell - 4); row.assignment:SetWidth(cell - 4)
	end
end

function View.Layout(width)
	if not panel then return end
	local available = math.max(1, width - EDGE * 2)
	local visible = math.max(1, math.min(MAX_VISIBLE, paladinCount))
	columnWidth = math.max(MIN_COLUMN, math.floor((available - GAP * (visible - 1)) / visible))
	local trees = math.max(1, paladinCount)
	contentWidth = trees * (columnWidth + GAP) - GAP
	viewport:SetSize(available, BOARD_H)
	canvas:SetSize(math.max(available, contentWidth), BOARD_H)
	local maximum = math.max(0, contentWidth - available)
	scrollOffset = math.min(scrollOffset, maximum)
	scrollbar:SetWidth(math.max(1, available - 12)); scrollbar:SetMinMaxValues(0, maximum)
	scrollbar:SetValue(scrollOffset); scrollbar:SetShown(maximum > 0)
	viewport:SetHorizontalScroll(scrollOffset)
	local index = 0
	local function place(tree)
		tree:ClearAllPoints(); tree:SetPoint("TOPLEFT", index * (columnWidth + GAP), 0)
		tree:Resize(columnWidth, BOARD_H)
		index = index + 1
	end
	for i = 1, paladinCount do place(columns[i]); layoutColumn(columns[i]) end
	-- An empty group keeps one dimmed tree behind the "No paladins" note.
	if paladinCount == 0 and seats[1] then place(seats[1]) end
end

function View.Refresh()
	if not panel then return end
	local pals = ns.UI.PaladinNames()
	paladinCount = #pals
	band:SetCount("Paladins", paladinCount)
	empty:SetShown(paladinCount == 0)
	for i, name in ipairs(pals) do
		if not columns[i] then columns[i] = createColumn() end
		local column, member = columns[i], ns.roster.members[name]
		local spec = (i - 1) % 3 + 1
		column.paladin = name; column:Show()
		column:SetArt(ns.UI.TREE_ART.PALADIN[spec])
		local covered = 0
		for class, row in pairs(column.rows) do
			local key = ns.Paladins.Get(name, class)
			local resolved = ((ns.result.pally or {})[class] or {})[name]
			local buff = Buffs.byKey[key == "AUTO" and resolved or key]
			if buff then covered = covered + 1 end
			row.duplicate = Buffs.byKey[key] and (((ns.roster.paladinAssignments or {})[class] or {})[name] == "NONE")
			row.detail = key == "AUTO" and ("Auto: " .. (buff and buff.label or "none"))
				or (key == "NONE" and "None" or Buffs.byKey[key].label)
			if row.duplicate then row.detail = row.detail .. " (duplicate)" end
			local state = row.duplicate and "red" or not buff and "grey" or key == "AUTO" and "green" or "gold"
			row:SetState(state, buff and ns.UI.BuffIcon(buff.key) or "Interface\\Icons\\INV_Misc_QuestionMark")
			local color = ns.UI.SLOT_COLORS[state]
			row.assignment:SetText(buff and buff.label or (key == "NONE" and "None" or "Auto"))
			row.assignment:SetTextColor(color[1], color[2], color[3])
		end
		column:SetHeader(SPEC_ICONS[spec], ns.WoW.ClassColorName(name, "PALADIN"),
			member.hasAddon and "Buffeteria connected" or "Without Buffeteria", covered)
	end
	for i = paladinCount + 1, #columns do columns[i].paladin = nil; columns[i]:Hide() end
	seats[1] = seats[1] or createSeat()
	seats[1]:SetArt(ns.UI.TREE_ART.PALADIN[1], true)
	seats[1]:SetShown(paladinCount == 0)
end

function View.Create(parent)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetPoint("TOPLEFT", 0, -34); panel:SetPoint("BOTTOMRIGHT")
	band = ns.UI.Band(panel, "Class blessing assignments",
		"One tree per paladin. Click a class blessing to cycle; right-click reverses.")
	viewport = CreateFrame("ScrollFrame", nil, panel)
	viewport:SetPoint("TOPLEFT", EDGE, -48)
	canvas = CreateFrame("Frame", nil, viewport)
	viewport:SetScrollChild(canvas)
	empty = viewport:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
	empty:SetPoint("CENTER", 0, 0); empty:SetText("No paladins in the group")
	scrollbar = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	scrollbar:SetOrientation("HORIZONTAL"); scrollbar:SetSize(280, 10)
	scrollbar:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 6, -4)
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
		scrollbar:SetValue(math.max(0, math.min(scrollOffset - delta * (columnWidth + GAP),
			math.max(0, contentWidth - viewport:GetWidth()))))
	end)
	local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("BOTTOMLEFT", 16, 15)
	legend:SetText("|cffffd100Gold|r assigned  |cff19ff19Green|r auto  |cff808080Grey|r none")
	local priority = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	priority:SetPoint("BOTTOMRIGHT", -16, 9); priority:SetWidth(200); priority:SetJustifyH("RIGHT")
	priority:SetText("Personal overrides take priority. Your own tree is saved.")
	ns.UI.AnnounceButton(panel)
	panel.columns, panel.seats, panel.viewport, panel.scrollbar = columns, seats, viewport, scrollbar
	return panel
end
