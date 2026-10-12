-- Local display controls hosted by the Settings tab for every class.
local _, ns = ...
local View = {}
ns.Tracker.View = View
local set = ns.Database.Set
local panel, cards, toggles, displayButtons, rowButtons, positionButtons, sliders, warnValue
local refreshing = false
local MODES = {
	{ key = "ALL", label = "Always show all" },
	{ key = "MISSING", label = "Missing only" },
	{ key = "PROBLEMS", label = "Missing or expiring" },
	{ key = "EXPIRING", label = "Expiring only" },
}
-- Position chips form a compass around Auto: { key, label, x, row }.
local POSITIONS = {
	{ "TOP", "Top", 0, 0 },
	{ "LEFT", "Left", -70, 1 }, { "AUTO", "Auto", 0, 1 }, { "RIGHT", "Right", 70, 1 },
	{ "BOTTOM", "Bottom", 0, 2 },
}
local MARGIN, GAP, TOP_ROW, TOP_H, BOTTOM_ROW, BOTTOM_H = 12, 10, -54, 168, -232, 230

function View.Refresh()
	if not panel then return end
	refreshing = true
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	for _, chip in ipairs(displayButtons) do chip:SetChecked(ns.db.buffDisplay == chip.mode) end
	for _, chip in ipairs(rowButtons) do chip:SetChecked(ns.db.iconsPerRow == chip.columns) end
	for _, chip in ipairs(positionButtons) do chip:SetChecked(ns.db.iconPosition == chip.side) end
	for _, bar in ipairs(sliders) do
		bar:SetValue(ns.db[bar.key])
		bar.readout:SetText(ns.db[bar.key] .. " px")
	end
	warnValue:SetText(ns.db.warnMinutes .. " min")
	refreshing = false
end

-- Two columns of cards that share the available width.
function View.Layout(width)
	if not panel then return end
	panel:SetWidth(width)
	local half = math.floor((width - MARGIN * 2 - GAP) / 2)
	for i, card in ipairs(cards) do
		local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", MARGIN + column * (half + GAP), row == 0 and TOP_ROW or BOTTOM_ROW)
		card:SetSize(half, row == 0 and TOP_H or BOTTOM_H)
	end
end

-- A labelled slider for a ranged setting, its value on the right and the range at either end.
local function slider(card, key, name, label, y)
	local minimum, maximum, step = unpack(ns.Database.RANGES[key])
	ns.UI.Text(card, "GameFontHighlight", 14, y, nil, label)
	local bar = CreateFrame("Slider", ns.globalPrefix .. "_" .. name, card, "BackdropTemplate")
	bar.key = key
	bar.readout = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.readout:SetPoint("TOPRIGHT", -14, y); bar.readout:SetJustifyH("RIGHT")
	bar:SetHeight(14)
	bar:SetPoint("TOPLEFT", 40, y - 20); bar:SetPoint("TOPRIGHT", -40, y - 20)
	bar:SetOrientation("HORIZONTAL")
	ns.UI.Backdrop(bar, 8, { 0, 0, 0, 0.8 }, { 0.5, 0.5, 0.5, 1 })
	bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	bar:GetThumbTexture():SetSize(24, 24)
	bar:SetMinMaxValues(minimum, maximum); bar:SetValueStep(step)
	if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
	bar:SetScript("OnValueChanged", function(_, raw)
		if refreshing then return end
		set(key, math.max(minimum, math.min(maximum, math.floor(raw / step + 0.5) * step)))
	end)
	local low = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	low:SetPoint("RIGHT", bar, "LEFT", -6, 0); low:SetText(minimum)
	local high = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	high:SetPoint("LEFT", bar, "RIGHT", 6, 0); high:SetText(maximum)
	sliders[#sliders + 1] = bar
end

-- Chips that pick one value of a setting; returns them for View.Refresh.
local function choiceChip(card, label, width, key, value, field)
	local chip = ns.UI.Chip(card, label, width, function() set(key, value) end)
	chip[field] = value
	return chip
end

local function trackerCard()
	local card = ns.UI.Card(panel, "Tracker", ns.UI.ICON)
	toggles = {}
	local function toggle(label, get, setter, x, y)
		local cb = ns.UI.Checkbox(card, label, x, y, setter)
		cb.get = get; toggles[#toggles + 1] = cb
	end
	toggle("Show tracker", function() return ns.db.showTracker end, function(v) set("showTracker", v) end, 10, -36)
	toggle("Lock tracker", function() return ns.db.locked end, function(v) set("locked", v) end, 10, -62)
	toggle("Minimap button", function() return not ns.db.minimap.hide end, function(v) ns.Minimap.SetShown(v) end, 150, -36)
	toggle("Preview (fake raid)", function() return ns.Tracker.Preview.active end, function(v) ns.Tracker.Preview.Set(v) end, 150, -62)
	local hint = ns.UI.Text(card, "GameFontDisableSmall", 14, -96, nil,
		"Unlock the tracker to drag it, or move it with Edit Mode.")
	hint:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	return card
end

local function sizeCard()
	local card = ns.UI.Card(panel, "Size", "Interface\\Icons\\INV_Misc_Spyglass_02")
	slider(card, "iconSize", "IconSize", "Clickable head", -38)
	slider(card, "statusIconSize", "StatusIconSize", "Small icons", -78)
	slider(card, "shoutSize", "ShoutSize", "Shout-out text", -118)
	ns.UI.Text(card, "GameFontDisableSmall", 14, -154, nil, "Head size applies after combat.")
	return card
end

local function showCard()
	local card = ns.UI.Card(panel, "Show icons", "Interface\\Icons\\Spell_Holy_WordFortitude")
	displayButtons = {}
	for i, mode in ipairs(MODES) do
		local chip = choiceChip(card, mode.label, 0, "buffDisplay", mode.key, "mode")
		local y = -38 - (i - 1) * 27
		chip:SetPoint("TOPLEFT", 14, y); chip:SetPoint("TOPRIGHT", -14, y)
		displayButtons[#displayButtons + 1] = chip
	end
	local rule = card:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.55, 0.45, 0.25, 0.5); rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 14, -152); rule:SetPoint("TOPRIGHT", -14, -152)
	ns.UI.Text(card, "GameFontHighlight", 14, -166, nil, "Expiring below")
	ns.UI.Text(card, "GameFontDisableSmall", 14, -190, 160,
		"A buff is expiring when anyone has less time left than this.")
	local minimum, maximum = unpack(ns.Database.RANGES.warnMinutes)
	local function step(delta)
		set("warnMinutes", math.max(minimum, math.min(maximum, ns.db.warnMinutes + delta)))
	end
	local plus = ns.UI.Chip(card, "+", 24, function() step(1) end)
	plus:SetPoint("TOPRIGHT", -14, -162)
	local box = ns.UI.ValueBox(card, 54, 22, "GameFontHighlight")
	box:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	warnValue = box.value
	local minus = ns.UI.Chip(card, "-", 24, function() step(-1) end)
	minus:SetPoint("RIGHT", box, "LEFT", -4, 0)
	return card
end

local function layoutCard()
	local card = ns.UI.Card(panel, "Layout", "Interface\\Icons\\INV_Misc_Map_01")
	ns.UI.Text(card, "GameFontHighlight", 14, -38, nil, "Icon position")
	positionButtons = {}
	for _, position in ipairs(POSITIONS) do
		local chip = choiceChip(card, position[2], 64, "iconPosition", position[1], "side")
		chip:SetPoint("TOP", position[3], -58 - position[4] * 26)
		positionButtons[#positionButtons + 1] = chip
	end
	ns.UI.Text(card, "GameFontHighlight", 14, -150, nil, "Icons per row")
	rowButtons = {}
	for columns = 2, 4 do
		local chip = choiceChip(card, tostring(columns), 44, "iconsPerRow", columns, "columns")
		chip:SetPoint("TOP", (columns - 3) * 52, -172)
		rowButtons[#rowButtons + 1] = chip
	end
	ns.UI.Text(card, "GameFontDisableSmall", 14, -206, nil, "Auto keeps icons on screen near edges.")
	return card
end

-- Swatches matching the icon borders on the tracker.
local function legend()
	local anchor = ns.UI.Text(panel, "GameFontDisableSmall", MARGIN + 4, -470, nil, "Icon borders:")
	for _, entry in ipairs({ { "bad", "Missing" }, { "warn", "Expiring" }, { "ok", "Buffed" } }) do
		local edge = panel:CreateTexture(nil, "ARTWORK")
		edge:SetSize(12, 12); edge:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
		edge:SetColorTexture(0, 0, 0, 1)
		local swatch = panel:CreateTexture(nil, "OVERLAY")
		swatch:SetSize(10, 10); swatch:SetPoint("CENTER", edge, "CENTER", 0, 0)
		swatch:SetColorTexture(unpack(ns.Tracker.Status.COLORS[entry[1]]))
		anchor = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		anchor:SetPoint("LEFT", edge, "RIGHT", 4, 0); anchor:SetText(entry[2])
	end
end

function View.Create(parent)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetPoint("TOPLEFT", 0, -34); panel:SetPoint("BOTTOMRIGHT")
	sliders = {}
	local band = ns.UI.Band(panel, "Tracker settings",
		"Tune the clickable head and the buff icons around it. Changes apply instantly.")
	band.box:Hide(); band.countLabel:Hide()
	band.help:SetPoint("RIGHT", band, "RIGHT", -16, 0)
	cards = { trackerCard(), sizeCard(), showCard(), layoutCard() }
	legend()
	return panel
end
