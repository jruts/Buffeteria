-- Purpose-based settings with an isolated, non-casting tracker preview.
local _, ns = ...
local UI, Tracker, set = ns.UI, ns.Tracker, ns.Database.Set
local View = {}
Tracker.View = View
local panel, controls, previewCard, layoutCard, stage, sample, headPicker, headMenu, warnValue, combatNote, hair
local toggles, headButtons, displayButtons, rowButtons, positionButtons, sliders, moods = {}, {}, {}, {}, {}, {}, {}
local refreshing = false
local TOP, CONTROLS_H, PREVIEW_H, LAYOUT_H = -56, 506, 304, 194
local MODES = { { "ALL", "All" }, { "MISSING", "Missing" },
	{ "PROBLEMS", "Missing or expiring" }, { "EXPIRING", "Expiring" } }
-- Icon position chips in a compass: key, label, x offset, row.
local POSITIONS = { { "TOP", "Top", 0, 0 }, { "LEFT", "Left", -76, 1 },
	{ "AUTO", "Auto", 0, 1 }, { "RIGHT", "Right", 76, 1 }, { "BOTTOM", "Bottom", 0, 2 } }

local function hint(parent, x, y, width, label)
	local text = UI.Text(parent, "GameFontHighlightSmall", x, y, width, label)
	text:SetTextColor(0.65, 0.65, 0.65)
	return text
end

local function toggle(label, get, setter, x, y)
	local cb = UI.Checkbox(controls, label, x, y, setter)
	cb.get = get; toggles[#toggles + 1] = cb
	return cb
end

-- A labelled slider row: name on the left, track in the middle, value on the right.
local function slider(key, name, label, y)
	local minimum, maximum, step = unpack(ns.Database.RANGES[key])
	UI.Text(controls, "GameFontHighlight", 20, y, nil, label)
	local bar = UI.Slider(controls, ns.globalPrefix .. "_" .. name)
	bar.key = key
	bar:SetPoint("TOPLEFT", 130, y + 3); bar:SetPoint("TOPRIGHT", -74, y + 3)
	bar.readout = controls:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.readout:SetPoint("TOPRIGHT", -16, y); bar.readout:SetJustifyH("RIGHT")
	bar:SetMinMaxValues(minimum, maximum); bar:SetValueStep(step)
	if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
	bar:SetScript("OnValueChanged", function(_, raw) if not refreshing then set(key, raw) end end)
	sliders[#sliders + 1] = bar
end

function View.Refresh()
	if not panel then return end
	refreshing = true
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	local clean = ns.db.trackerStyle == "CLEAN"
	for _, choice in ipairs(headButtons) do
		if choice.style == "CLEAN" then
			choice:SetChecked(clean)
		else
			choice:SetChecked(not clean and ns.db.headStyle == choice.style)
			choice.portrait:SetTexture(Tracker.Art.Texture("happy", choice.style))
		end
	end
	headPicker.caption:SetText("Head: " .. (clean and "None (clean)" or Tracker.Art.Label()))
	headPicker.portrait:SetTexture(clean and UI.ICON or Tracker.Art.Texture("happy"))
	-- Hair only exists on a head.
	hair:SetEnabled(not clean)
	hair.text:SetTextColor(clean and 0.5 or 1, clean and 0.5 or 1, clean and 0.5 or 1)
	for _, option in ipairs(displayButtons) do option:SetChecked(ns.db.buffDisplay == option.mode) end
	for _, chip in ipairs(rowButtons) do chip:SetChecked(ns.db.iconsPerRow == chip.columns) end
	for _, chip in ipairs(positionButtons) do chip:SetChecked(ns.db.iconPosition == chip.side) end
	for _, chip in ipairs(moods) do chip:SetChecked(sample.mood == chip.mood) end
	for _, bar in ipairs(sliders) do
		bar:SetValue(ns.db[bar.key]); bar.readout:SetText(ns.db[bar.key] .. " px")
	end
	warnValue:SetText(ns.db.warnPercent .. "%")
	combatNote:SetShown(InCombatLockdown())
	refreshing = false
	Tracker.SettingsPreview.Refresh(sample)
end

function View.Layout(width)
	if not panel then return end
	local usable, gap = width - 24, 10
	local left = math.floor((usable - gap) * 0.57)
	local right = usable - gap - left
	controls:ClearAllPoints(); controls:SetPoint("TOPLEFT", 12, TOP); controls:SetSize(left, CONTROLS_H)
	previewCard:ClearAllPoints(); previewCard:SetPoint("TOPLEFT", 12 + left + gap, TOP); previewCard:SetSize(right, PREVIEW_H)
	layoutCard:ClearAllPoints(); layoutCard:SetPoint("TOPLEFT", 12 + left + gap, TOP - PREVIEW_H - 8)
	layoutCard:SetSize(right, LAYOUT_H)
	sample:SetSize(right - 28, PREVIEW_H - 90)
	for i, option in ipairs(displayButtons) do
		local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
		option:ClearAllPoints(); option:SetPoint("TOPLEFT", 22 + column * (left - 40) / 2, -336 - row * 24)
		option:SetWidth((left - 48) / 2)
	end
	for i = 1, 3 do
		local cb = toggles[i]
		cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", 16 + (i - 1) * (left - 32) / 3, -34)
	end
	panel.behaviorHelp:SetWidth(left - 64)
	Tracker.SettingsPreview.Refresh(sample)
end

-- The head choice: a dropdown-style button with the portrait, and its menu.
local function headChooser()
	headPicker = UI.Chip(controls, "", 210, function() headMenu:SetShown(not headMenu:IsShown()) end, "GameFontHighlight")
	headPicker:SetHeight(30); headPicker:SetPoint("TOPLEFT", 20, -186)
	headPicker.portrait = headPicker:CreateTexture(nil, "ARTWORK")
	headPicker.portrait:SetSize(24, 24); headPicker.portrait:SetPoint("LEFT", 5, 0)
	headPicker.caption:ClearAllPoints(); headPicker.caption:SetPoint("LEFT", 36, 0)
	local arrow = headPicker:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	arrow:SetSize(22, 22); arrow:SetPoint("RIGHT", -4, 0)
	_G[ns.globalPrefix .. "_HeadPicker"] = headPicker
	headMenu = UI.Menu(headPicker, ns.globalPrefix .. "_HeadMenu")
	headMenu:SetSize(210, (#Tracker.Art.CHOICES + 1) * 24 + 16); headMenu:SetPoint("TOPLEFT", headPicker, "BOTTOMLEFT", 0, -2)
	headMenu:SetFrameLevel(headPicker:GetFrameLevel() + 25)
	headMenu:Hide(); headPicker.menu = headMenu
	tinsert(UISpecialFrames, ns.globalPrefix .. "_HeadMenu")
	headPicker:SetScript("OnHide", function() headMenu:Hide() end)
	for i, choice in ipairs(Tracker.Art.CHOICES) do
		local style = choice.key
		local item = UI.MenuItem(headMenu, 194, function()
			set("headStyle", style); set("trackerStyle", "HEAD"); headMenu:Hide()
		end)
		item.style = style; item:SetHeight(24); item:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 24)
		item.caption:SetText(choice.label)
		item.portrait = item.icon
		item.portrait:SetSize(22, 22); item.portrait:SetTexCoord(0, 1, 0, 1)
		headButtons[#headButtons + 1] = item
	end
	-- For players who'd rather not have a mascot: a plain spell button, no halo or GIEF.
	local item = UI.MenuItem(headMenu, 194, function() set("trackerStyle", "CLEAN"); headMenu:Hide() end)
	item.style = "CLEAN"; item:SetHeight(24); item:SetPoint("TOPLEFT", 8, -8 - #Tracker.Art.CHOICES * 24)
	item.caption:SetText("None (clean)")
	item.portrait = item.icon
	item.portrait:SetSize(22, 22); item.portrait:SetTexCoord(0, 1, 0, 1); item.portrait:SetTexture(UI.ICON)
	headButtons[#headButtons + 1] = item
end

function View.Create(host)
	panel = host
	UI.PageHeader(panel, "Tracker settings", "See changes as you edit.")
	combatNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	combatNote:SetPoint("TOPRIGHT", -16, -14)
	combatNote:SetText("In combat: head size applies after combat.")
	controls = UI.Panel(panel)

	UI.Section(controls, "Display", 16, -14)
	toggle("Show tracker", function() return ns.db.showTracker end, function(v) set("showTracker", v) end, 16, -34)
	toggle("Lock tracker", function() return ns.db.locked end, function(v) set("locked", v) end, 170, -34)
	toggle("Minimap button", function() return not ns.db.minimap.hide end, function(v) ns.Minimap.SetShown(v) end, 330, -34)

	UI.Section(controls, "Behavior", 16, -74)
	toggle("Help with overdue buffs", function() return ns.db.helpOthers end, function(v) set("helpOthers", v) end, 16, -94)
	panel.behaviorHelp = hint(controls, 46, -122, 440,
		"After your own jobs, cover late, dead or out-of-sight casters. Never replaces blessings.")

	UI.Section(controls, "Appearance", 16, -162)
	headChooser()
	hair = toggle("Colored hair", function() return ns.db.coloredHair end, function(v) set("coloredHair", v) end, 252, -188)
	hair:ClearAllPoints(); hair:SetPoint("LEFT", headPicker, "RIGHT", 16, 0)
	slider("iconSize", "IconSize", "Head size", -232)
	slider("statusIconSize", "StatusIconSize", "Small icons", -262)
	slider("shoutSize", "ShoutSize", "Shout-out text", -292)

	UI.Section(controls, "Buff icons", 16, -316)
	for _, mode in ipairs(MODES) do
		local key = mode[1]
		local option = UI.Radio(controls, mode[2], 200, function() set("buffDisplay", key) end)
		option.mode = key; displayButtons[#displayButtons + 1] = option
	end
	UI.Text(controls, "GameFontHighlight", 22, -396, nil, "Expiring below")
	local step = ns.Database.RANGES.warnPercent[3]
	local minus = UI.Chip(controls, "-", 26, function() set("warnPercent", ns.db.warnPercent - step) end, "GameFontNormal")
	minus:SetPoint("TOPLEFT", 140, -390)
	local box = UI.ValueBox(controls, 64, 24, "GameFontHighlight")
	box:SetPoint("LEFT", minus, "RIGHT", 2, 0); warnValue = box.value
	local plus = UI.Chip(controls, "+", 26, function() set("warnPercent", ns.db.warnPercent + step) end, "GameFontNormal")
	plus:SetPoint("LEFT", box, "RIGHT", 2, 0)
	hint(controls, 22, -424, nil, "Percent of buff duration left. 5% of 10 min = 30 sec.")
	for i, entry in ipairs({ { "bad", "Missing" }, { "warn", "Expiring" }, { "ok", "Buffed" } }) do
		local swatch = CreateFrame("Frame", nil, controls, "BackdropTemplate")
		swatch:SetSize(16, 16); swatch:SetPoint("TOPLEFT", 22 + (i - 1) * 120, -452)
		swatch:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 2 })
		swatch:SetBackdropColor(0, 0, 0, 0.6); swatch:SetBackdropBorderColor(unpack(Tracker.Status.Color(entry[1])))
		local label = UI.Text(controls, "GameFontHighlight", 0, 0, nil, entry[2])
		label:ClearAllPoints(); label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	end

	previewCard = UI.Card(panel, "Tracker preview")
	local caption = hint(previewCard, 0, 0, nil, "Sample raid  -  casting disabled")
	caption:ClearAllPoints(); caption:SetPoint("TOPRIGHT", -14, -15)
	-- A darker stage behind the sample, like a model viewer.
	stage = CreateFrame("Frame", nil, previewCard, "BackdropTemplate")
	stage:SetPoint("TOPLEFT", 10, -42); stage:SetPoint("BOTTOMRIGHT", -10, 44)
	UI.Backdrop(stage, 10, { 0.2, 0.19, 0.17, 1 }, { 0.42, 0.38, 0.32, 1 })
	-- A soft top light so the sample reads like the game world, not a hole.
	local light = stage:CreateTexture(nil, "BORDER")
	light:SetPoint("TOPLEFT", 3, -3); light:SetPoint("BOTTOMRIGHT", -3, 3)
	UI.Gradient(light, "VERTICAL", { 0.1, 0.09, 0.08, 0.6 }, { 0.42, 0.4, 0.36, 0.45 })
	sample = Tracker.SettingsPreview.Create(previewCard); sample:SetPoint("TOPLEFT", 14, -46)
	sample:SetFrameLevel(stage:GetFrameLevel() + 2)
	for i, mood in ipairs({ { "happy", "Happy" }, { "grumpy", "Grumpy" }, { "angry", "Angry" } }) do
		local key = mood[1]
		local chip = UI.Chip(previewCard, mood[2], 80, function() sample.mood = key; View.Refresh() end, "GameFontHighlight")
		chip.mood = key; chip:SetPoint("BOTTOM", (i - 2) * 86, 12); moods[#moods + 1] = chip
	end

	layoutCard = UI.Card(panel, "Layout")
	UI.Text(layoutCard, "GameFontHighlight", 14, -46, nil, "Icon position")
	for _, position in ipairs(POSITIONS) do
		local key = position[1]
		local chip = UI.Chip(layoutCard, position[2], 72, function() set("iconPosition", key) end, "GameFontHighlight")
		chip.side = key; chip:SetPoint("TOP", position[3], -64 - position[4] * 28)
		positionButtons[#positionButtons + 1] = chip
	end
	UI.Text(layoutCard, "GameFontHighlight", 14, -160, nil, "Icons per row")
	for columns = 2, 4 do
		local value = columns
		local chip = UI.Chip(layoutCard, tostring(value), 48, function() set("iconsPerRow", value) end, "GameFontHighlight")
		chip.columns = value; chip:SetPoint("TOP", 40 + (value - 3) * 54, -155)
		rowButtons[#rowButtons + 1] = chip
	end
	panel.preview, panel.controls, panel.combatNote = sample, controls, combatNote
	panel.headButtons = headButtons
	-- The inset sample remains independent of /buff preview and of tracker visibility.
	panel:SetScript("OnHide", function() headMenu:Hide() end)
end
