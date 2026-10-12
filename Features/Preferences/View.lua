-- Personal buff preferences and tracker options, laid out as three talent trees.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, band, trees, rows, wants, toggles, warnText, assignText, overrideCheck, tip, list
local ROW_H, EDGE, GAP, BOARD_H = 22, 8, 2, 360
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
			r.text:SetText("|cff888888--- nothing below this line ---|r")
			r.bg:SetColorTexture(0.3, 0.08, 0.05, 0.7)
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
			if i == dragging then r.bg:SetColorTexture(1, 0.82, 0, 0.3)
			else r.bg:SetColorTexture(0, 0, 0, 0.55) end
		end
	end
	return rank
end

local function refreshAssignments()
	if not assignText then return end
	assignText:SetText(table.concat(ns.Assignments.Lines(true), "\n"))
end

function View.Refresh()
	if not personal then return end
	local wanted = 0
	for key, button in pairs(wants) do
		local on = ns.db.wants[key] and true or false
		if on then wanted = wanted + 1 end
		button:SetState(on and "gold" or "grey", blessingIcon(key))
	end
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	warnText:SetText(("Orange below: %d min"):format(ns.db.warnMinutes))
	overrideCheck:SetChecked(ns.db.blessingsOverride and true or false)
	local ranked = refreshRows()
	local _, class = UnitClass("player")
	local art = ns.UI.TREE_ART[class] or ns.UI.TREE_ART.PALADIN
	for i, tree in ipairs(trees) do tree:SetArt(art[i]) end
	trees[1]:SetHeader(blessingIcon("KINGS"), "Blessings", "Best first, drag to reorder", ranked)
	trees[2]:SetHeader(blessingIcon("FORT"), "On my plate", "Buffs you want", wanted)
	trees[3]:SetHeader(ns.UI.ICON, "Who's cooking what", "Current assignments")
	band:SetCount("Paladins", #ns.UI.PaladinNames())
	refreshAssignments()
end

function View.Layout(width)
	if not personal then return end
	local column = math.floor((width - EDGE * 2 - GAP * 2) / 3)
	for i, tree in ipairs(trees) do
		tree:ClearAllPoints(); tree:SetPoint("TOPLEFT", EDGE + (i - 1) * (column + GAP), -48)
		tree:Resize(column, BOARD_H)
	end
	list:SetWidth(column - 24)
	for _, r in ipairs(rows) do r:SetWidth(column - 24) end
	tip:SetWidth(column - 24)
	overrideCheck.text:SetWidth(column - 44)
	local cell = column / 3
	for i, buff in ipairs(Buffs.GROUP_BUFFS) do
		-- Talent tiers: three on top, the rest centered below.
		local tier = math.floor((i - 1) / 3)
		local x = tier == 0 and cell * ((i - 1) + 0.5) or cell * (i - 3)
		wants[buff.key]:ClearAllPoints(); wants[buff.key]:SetPoint("TOP", trees[2], "TOPLEFT", x, -86 - tier * 56)
	end
end

local function stopDrag()
	if not dragging then return end
	dragging = nil
	ns.db.blessingsOverride = true
	list:SetScript("OnUpdate", nil)
	refreshRows()
	View.Refresh()
	ns.Preferences.Changed()
end

local function wantTooltip(button)
	local buff = Buffs.byKey[button.key]
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(buff.label)
	GameTooltip:AddLine(ns.db.wants[button.key] and "On your plate" or "Not wanted", 1, 0.82, 0)
	GameTooltip:AddLine("Click to toggle.", 1, 1, 1)
	GameTooltip:Show()
end

function View.Create(parent)
	personal = CreateFrame("Frame", nil, parent)
	personal:SetPoint("TOPLEFT", 0, -34); personal:SetPoint("BOTTOMRIGHT")
	band = ns.UI.Band(personal, "Your buffet", "Rank your blessings, pick your buffs, and see who serves what.")
	trees = { ns.UI.Tree(personal), ns.UI.Tree(personal), ns.UI.Tree(personal) }

	-- 1) Blessing ranking
	local blessings = trees[1]
	list = CreateFrame("Frame", nil, blessings)
	list:SetPoint("TOPLEFT", 12, -82)
	list:SetHeight(ROW_H * (#Buffs.BLESSINGS + 1))
	rows = {}
	for i = 1, #Buffs.BLESSINGS + 1 do
		local r = CreateFrame("Button", nil, list)
		r:SetHeight(ROW_H - 2)
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
				if not IsMouseButtonDown("LeftButton") then stopDrag(); return end
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
	tip = ns.UI.Text(blessings, "GameFontHighlightSmall", 12, -88 - ROW_H * (#Buffs.BLESSINGS + 1), nil,
		"#1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	overrideCheck = ns.UI.Checkbox(blessings, "Override the Paladins class plan", 10, -290, function(value)
		ns.db.blessingsOverride = value
		ns.Preferences.Changed(); View.Refresh()
	end)
	overrideCheck.text:SetJustifyH("LEFT")

	-- 2) Buffs I want, as talent buttons, then the tracker options
	local plate = trees[2]
	wants = {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local button = ns.UI.TalentButton(plate)
		button.key = buff.key
		button:SetScript("OnClick", function(self)
			ns.db.wants[self.key] = not ns.db.wants[self.key]
			ns.Preferences.Changed(); View.Refresh()
			if GameTooltip:IsOwned(self) then wantTooltip(self) end
		end)
		button:SetScript("OnEnter", wantTooltip); button:SetScript("OnLeave", GameTooltip_Hide)
		wants[buff.key] = button
	end
	ns.UI.Text(plate, "GameFontNormal", 14, -196, nil, "Tracker")
	warnText = ns.UI.Text(plate, "GameFontHighlightSmall", 14, -222)
	local minus = CreateFrame("Button", nil, plate, "UIPanelButtonTemplate")
	minus:SetSize(22, 20); minus:SetPoint("TOPRIGHT", -40, -216); minus:SetText("-")
	local plus = CreateFrame("Button", nil, plate, "UIPanelButtonTemplate")
	plus:SetSize(22, 20); plus:SetPoint("LEFT", minus, "RIGHT", 2, 0); plus:SetText("+")
	minus:SetScript("OnClick", function() ns.db.warnMinutes = math.max(1, ns.db.warnMinutes - 1); View.Refresh(); ns.Tracker.Refresh() end)
	plus:SetScript("OnClick", function() ns.db.warnMinutes = math.min(15, ns.db.warnMinutes + 1); View.Refresh(); ns.Tracker.Refresh() end)
	toggles = {}
	local function toggle(label, get, set)
		local cb = ns.UI.Checkbox(plate, label, 10, -240 - #toggles * 22, set)
		cb.get = get
		toggles[#toggles + 1] = cb
	end
	toggle("Show tracker", function() return ns.db.showTracker end,
		function(v) ns.db.showTracker = v; ns.Tracker.Refresh() end)
	toggle("Lock tracker", function() return ns.db.locked end,
		function(v) ns.db.locked = v end)
	toggle("Small icons: problems only", function() return ns.db.onlyProblems end,
		function(v) ns.db.onlyProblems = v; ns.Tracker.Refresh() end)
	toggle("Minimap button", function() return not ns.db.minimap.hide end,
		function(v) ns.db.minimap.hide = not v; ns.Minimap.Refresh() end)
	toggle("Preview (fake raid)", function() return ns.Preview.active end,
		function(v) ns.Preview.Set(v) end)

	-- 3) Current assignments
	assignText = trees[3]:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	assignText:SetPoint("TOPLEFT", 14, -82)
	assignText:SetPoint("BOTTOMRIGHT", -12, 12)
	assignText:SetJustifyH("LEFT")
	assignText:SetJustifyV("TOP")

	ns.UI.AnnounceButton(personal)
	personal.wants = wants
	return personal
end
