-- Personal buff preferences and tracker options.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, rows, checks, toggles, warnText, assignText, overrideCheck
local ROW_H = 22
local dragging

local blessingIcon = ns.UI.BuffIcon

local function refreshRows()
	local rank = 0
	local below = false
	for i, key in ipairs(ns.db.order) do
		local r = rows[i]
		if key == "|" then
			below = true
			r.icon:Hide()
			r.text:SetText("|cff888888--- don't want anything below this line ---|r")
			r.bg:SetColorTexture(0.3, 0.1, 0.1, 0.35)
		else
			r.icon:Show()
			r.icon:SetTexture(blessingIcon(key))
			r.icon:SetDesaturated(below)
			if below then
				r.text:SetText("|cff999999" .. Buffs.byKey[key].label .. "|r")
			else
				rank = rank + 1
				r.text:SetText(("%d. %s"):format(rank, Buffs.byKey[key].label))
			end
			r.bg:SetColorTexture(1, 1, 1, (i == dragging) and 0.25 or 0.06)
		end
	end
end

local function refreshAssignments()
	if not assignText then return end
	assignText:SetText(table.concat(ns.Assignments.Lines(true), "\n"))
end

function View.Refresh()
	if not personal then return end
	for key, cb in pairs(checks) do cb:SetChecked(ns.db.wants[key] and true or false) end
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	warnText:SetText(("Turn orange below: %d min"):format(ns.db.warnMinutes))
	overrideCheck:SetChecked(ns.db.blessingsOverride and true or false)
	refreshRows()
	refreshAssignments()
end

local function stopDrag(list)
	if not dragging then return end
	dragging = nil
	ns.db.blessingsOverride = true
	list:SetScript("OnUpdate", nil)
	refreshRows()
	View.Refresh()
	ns.Preferences.Changed()
end

function View.Create(parent)
	personal = CreateFrame("Frame", nil, parent)
	personal:SetPoint("TOPLEFT", 0, -32); personal:SetPoint("BOTTOMRIGHT")
	local y = -8
	local function header(text)
		local fs = personal:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", 16, y)
		fs:SetText(text)
		y = y - 20
		return fs
	end

	-- 1) Buffs I want
	header("On my plate (single-source buffs)")
	checks = {}
	for i, buff in ipairs(Buffs.GROUP_BUFFS) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		checks[buff.key] = ns.UI.Checkbox(personal, buff.label, 14 + col * 155, y - row * 24, function(value)
			ns.db.wants[buff.key] = value
			ns.Preferences.Changed()
		end)
	end
	y = y - math.ceil(#Buffs.GROUP_BUFFS / 2) * 24 - 10

	-- 2) Blessing ranking
	header("Blessings, best first (drag to reorder)")
	local list = CreateFrame("Frame", nil, personal)
	list:SetPoint("TOPLEFT", 16, y)
	list:SetSize(300, ROW_H * (#Buffs.BLESSINGS + 1))
	rows = {}
	for i = 1, #Buffs.BLESSINGS + 1 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(300, ROW_H - 2)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(ROW_H - 4, ROW_H - 4)
		r.icon:SetPoint("LEFT", 2, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.grip = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.grip:SetPoint("RIGHT", -6, 0)
		r.grip:SetText("::")
		r:SetScript("OnMouseDown", function(_, button)
			if button ~= "LeftButton" then return end
			dragging = i
			refreshRows()
			list:SetScript("OnUpdate", function(self)
				if not IsMouseButtonDown("LeftButton") then stopDrag(self); return end
				local _, cy = GetCursorPosition()
				cy = cy / self:GetEffectiveScale()
				local idx = math.floor((self:GetTop() - cy) / ROW_H) + 1
				idx = math.max(1, math.min(#ns.db.order, idx))
				if idx ~= dragging then
					local item = table.remove(ns.db.order, dragging)
					table.insert(ns.db.order, idx, item)
					dragging = idx
					refreshRows()
				end
			end)
		end)
		rows[i] = r
	end
	y = y - ROW_H * (#Buffs.BLESSINGS + 1) - 6

	local tip = personal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tip:SetPoint("TOPLEFT", 16, y)
	tip:SetWidth(300)
	tip:SetJustifyH("LEFT")
	tip:SetText("Drag to set a personal override: #1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	y = y - 38
	overrideCheck = ns.UI.Checkbox(personal, "Override the Paladins class plan", 14, y, function(value)
		ns.db.blessingsOverride = value
		ns.Preferences.Changed(); View.Refresh()
	end)
	y = y - 30

	-- 3) Warning threshold
	warnText = personal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	warnText:SetPoint("TOPLEFT", 16, y - 4)
	local minus = CreateFrame("Button", nil, personal, "UIPanelButtonTemplate")
	minus:SetSize(24, 20); minus:SetPoint("TOPLEFT", 210, y); minus:SetText("-")
	local plus = CreateFrame("Button", nil, personal, "UIPanelButtonTemplate")
	plus:SetSize(24, 20); plus:SetPoint("LEFT", minus, "RIGHT", 4, 0); plus:SetText("+")
	minus:SetScript("OnClick", function() ns.db.warnMinutes = math.max(1, ns.db.warnMinutes - 1); View.Refresh(); ns.Tracker.Refresh() end)
	plus:SetScript("OnClick", function() ns.db.warnMinutes = math.min(15, ns.db.warnMinutes + 1); View.Refresh(); ns.Tracker.Refresh() end)
	y = y - 28

	-- Toggles: tracker, lock, minimap button
	toggles = {}
	local function toggle(label, x, rowY, get, set)
		local cb = ns.UI.Checkbox(personal, label, x, rowY, set)
		cb.get = get
		toggles[#toggles + 1] = cb
	end
	toggle("Show tracker", 14, y, function() return ns.db.showTracker end,
		function(v) ns.db.showTracker = v; ns.Tracker.Refresh() end)
	toggle("Lock tracker", 169, y, function() return ns.db.locked end,
		function(v) ns.db.locked = v end)
	toggle("Preview (fake raid)", 169, y - 24, function() return ns.Preview.active end,
		function(v) ns.Preview.Set(v) end)
	toggle("Minimap button", 14, y - 24, function() return not ns.db.minimap.hide end,
		function(v) ns.db.minimap.hide = not v; ns.Minimap.Refresh() end)
	toggle("Small icons: only buffs that need attention", 14, y - 48, function() return ns.db.onlyProblems end,
		function(v) ns.db.onlyProblems = v; ns.Tracker.Refresh() end)
	y = y - 78

	-- 4) Current assignments
	header("Who's cooking what")
	assignText = personal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	assignText:SetPoint("TOPLEFT", 16, y)
	assignText:SetPoint("BOTTOMRIGHT", -16, 44)
	assignText:SetJustifyH("LEFT")
	assignText:SetJustifyV("TOP")

	ns.UI.AnnounceButton(personal)
	return personal
end
