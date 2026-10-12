-- Local display controls hosted by the Settings tab for every class.
local _, ns = ...
local View = {}
ns.Tracker.View = View
local panel, toggles, displayButtons, rowButtons, positionButtons, sizeSlider, sizeText, warnText
local iconSizeSlider, iconSizeText
local refreshing = false
local MODES = {
	{ key = "ALL", label = "Always show all" },
	{ key = "MISSING", label = "Missing only" },
	{ key = "PROBLEMS", label = "Missing or expiring" },
	{ key = "EXPIRING", label = "Expiring only" },
}

local function changed()
	ns.Events.Emit("TrackerSettingsChanged")
	View.Refresh()
end

function View.Refresh()
	if not panel then return end
	refreshing = true
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	for _, cb in ipairs(displayButtons) do cb:SetChecked(ns.db.buffDisplay == cb.mode) end
	for _, cb in ipairs(rowButtons) do cb:SetChecked(ns.db.iconsPerRow == cb.columns) end
	for _, cb in ipairs(positionButtons) do cb:SetChecked(ns.db.iconPosition == cb.side) end
	sizeSlider:SetValue(ns.db.iconSize)
	sizeText:SetText(("Clickable head size: |cffffffff%d|r px"):format(ns.db.iconSize))
	iconSizeSlider:SetValue(ns.db.statusIconSize)
	iconSizeText:SetText(("Small icon size: |cffffffff%d|r px"):format(ns.db.statusIconSize))
	warnText:SetText(("Expiring below |cffffffff%d|r minutes"):format(ns.db.warnMinutes))
	refreshing = false
end

function View.Layout(width)
	if panel then panel:SetWidth(width) end
end

function View.Create(parent)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetPoint("TOPLEFT", 0, -34); panel:SetPoint("BOTTOMRIGHT")
	ns.UI.Text(panel, "GameFontNormalLarge", 20, -16, nil, "Tracker settings")
	ns.UI.Text(panel, "GameFontHighlightSmall", 20, -42, nil,
		"Choose where icons sit around the face. The head stays in place.")
	toggles = {}
	local function toggle(label, get, set, x, y)
		local cb = ns.UI.Checkbox(panel, label, x, y, function(value) set(value); changed() end)
		cb.get = get; toggles[#toggles + 1] = cb
	end
	toggle("Show tracker", function() return ns.db.showTracker end,
		function(v) ns.db.showTracker = v end, 16, -70)
	toggle("Lock tracker", function() return ns.db.locked end,
		function(v) ns.db.locked = v end, 16, -98)
	toggle("Minimap button", function() return not ns.db.minimap.hide end,
		function(v) ns.db.minimap.hide = not v; ns.Minimap.Refresh() end, 330, -70)
	toggle("Preview (fake raid)", function() return ns.Preview.active end,
		function(v) ns.Preview.Set(v) end, 330, -98)

	local function sizeControl(name, x, minimum, maximum, step, set)
		local text = ns.UI.Text(panel, "GameFontNormal", x, -148)
		local slider = CreateFrame("Slider", name, panel, "BackdropTemplate")
		slider:SetSize(240, 16); slider:SetPoint("TOPLEFT", x, -176)
		slider:SetOrientation("HORIZONTAL")
		slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
		slider:SetBackdropColor(0, 0, 0, 0.8)
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		slider:GetThumbTexture():SetSize(24, 24)
		slider:SetMinMaxValues(minimum, maximum); slider:SetValueStep(step)
		if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
		slider:SetScript("OnValueChanged", function(_, value)
			if refreshing then return end
			set(math.max(minimum, math.min(maximum, math.floor(value / step + 0.5) * step)))
			changed()
		end)
		ns.UI.Text(panel, "GameFontDisableSmall", x, -198, nil, minimum .. " px")
		ns.UI.Text(panel, "GameFontDisableSmall", x + 203, -198, nil, maximum .. " px")
		return text, slider
	end
	sizeText, sizeSlider = sizeControl("Buffeteria_IconSize", 20, 32, 128, 4,
		function(value) ns.db.iconSize = value end)
	iconSizeText, iconSizeSlider = sizeControl("Buffeteria_StatusIconSize", 330, 16, 64, 1,
		function(value) ns.db.statusIconSize = value end)
	ns.UI.Text(panel, "GameFontHighlightSmall", 20, -222, 590,
		"Head size applies after combat. Unlock the tracker to drag it, or move it with Edit Mode.")

	ns.UI.Section(panel, "Icons", 20, -244)
	displayButtons = {}
	for i, mode in ipairs(MODES) do
		local key = mode.key
		local cb = ns.UI.Checkbox(panel, mode.label, 16, -264 - (i - 1) * 28, function()
			ns.db.buffDisplay = key
			-- Retain the legacy value for older copies of the add-on.
			ns.db.onlyProblems = key ~= "ALL"
			changed()
		end)
		cb.mode = key; displayButtons[#displayButtons + 1] = cb
	end
	warnText = ns.UI.Text(panel, "GameFontNormal", 330, -274)
	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(28, 22); minus:SetPoint("TOPLEFT", 330, -300); minus:SetText("-")
	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(28, 22); plus:SetPoint("LEFT", minus, "RIGHT", 6, 0); plus:SetText("+")
	minus:SetScript("OnClick", function() ns.db.warnMinutes = math.max(1, ns.db.warnMinutes - 1); changed() end)
	plus:SetScript("OnClick", function() ns.db.warnMinutes = math.min(15, ns.db.warnMinutes + 1); changed() end)
	ns.UI.Text(panel, "GameFontNormal", 330, -338, nil, "Icons per row")
	rowButtons = {}
	for columns = 2, 4 do
		local count = columns
		local cb = ns.UI.Checkbox(panel, tostring(count), 326 + (count - 2) * 88, -360, function()
			ns.db.iconsPerRow = count
			changed()
		end)
		cb.columns = count; rowButtons[#rowButtons + 1] = cb
	end
	ns.UI.Text(panel, "GameFontNormal", 20, -392, nil, "Icon position")
	positionButtons = {}
	for i, position in ipairs({
		{ key = "LEFT", label = "Left" }, { key = "TOP", label = "Top" },
		{ key = "RIGHT", label = "Right" }, { key = "BOTTOM", label = "Bottom" },
		{ key = "AUTO", label = "Auto" },
	}) do
		local side = position.key
		local cb = ns.UI.Checkbox(panel, position.label, 16 + (i - 1) * 112, -412, function()
			ns.db.iconPosition = side
			changed()
		end)
		cb.side = side; positionButtons[#positionButtons + 1] = cb
	end
	ns.UI.Text(panel, "GameFontHighlightSmall", 20, -448, 590,
		"Full-color icons: red = missing, orange = expiring, green = buffed.")
	return panel
end
