-- Local display controls hosted by the Settings tab for every class.
local _, ns = ...
local View = {}
ns.Tracker.View = View
local panel, toggles, displayButtons, sizeSlider, sizeText, warnText
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
	sizeSlider:SetValue(ns.db.iconSize)
	sizeText:SetText(("Clickable head size: |cffffffff%d|r px"):format(ns.db.iconSize))
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
		"The head stays in place. Buff icons grow above it near the bottom of the screen.")
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

	sizeText = ns.UI.Text(panel, "GameFontNormal", 20, -148)
	sizeSlider = CreateFrame("Slider", "Buffeteria_IconSize", panel, "BackdropTemplate")
	sizeSlider:SetSize(240, 16); sizeSlider:SetPoint("TOPLEFT", 20, -176)
	sizeSlider:SetOrientation("HORIZONTAL")
	sizeSlider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
	sizeSlider:SetBackdropColor(0, 0, 0, 0.8)
	sizeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	sizeSlider:GetThumbTexture():SetSize(24, 24)
	sizeSlider:SetMinMaxValues(32, 128); sizeSlider:SetValueStep(4)
	if sizeSlider.SetObeyStepOnDrag then sizeSlider:SetObeyStepOnDrag(true) end
	sizeSlider:SetScript("OnValueChanged", function(_, value)
		if refreshing then return end
		ns.db.iconSize = math.max(32, math.min(128, math.floor(value / 4 + 0.5) * 4))
		changed()
	end)
	ns.UI.Text(panel, "GameFontDisableSmall", 20, -198, nil, "32 px")
	ns.UI.Text(panel, "GameFontDisableSmall", 223, -198, nil, "128 px")
	ns.UI.Text(panel, "GameFontHighlightSmall", 330, -154, 280,
		"Size changes apply after combat. Unlock the tracker to drag it, or move it with Edit Mode.")

	ns.UI.Section(panel, "Buff icons", 20, -244)
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
	ns.UI.Text(panel, "GameFontDisableSmall", 330, -336, 280,
		"Display filters affect the small icons. The head and cast button still watch all your tracked buffs.")
	return panel
end
