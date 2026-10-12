-- Buffeteria: the options window (what I want + drag-to-rank blessings).
local _, ns = ...
local D = ns.Data

local P = {}
ns.Prefs = P

local win, content, panel, rows, checks, toggles, warnText, assignText
local personal, paladinPanel, personalTab, paladinTab, overrideCheck
local paladinName, paladinNote, paladinRows, paladinSummary, selectedPaladin
local ROW_H = 22
local dragging -- index of the row being dragged

local function blessingIcon(key)
	local b = D.byKey[key]
	return ns.SpellIcon(b.groupIds[1]) or ns.SpellIcon(b.ids[1]) or 134400
end

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
				r.text:SetText("|cff999999" .. D.byKey[key].label .. "|r")
			else
				rank = rank + 1
				r.text:SetText(("%d. %s"):format(rank, D.byKey[key].label))
			end
			r.bg:SetColorTexture(1, 1, 1, (i == dragging) and 0.25 or 0.06)
		end
	end
end

local function refreshAssignments()
	if not assignText then return end
	assignText:SetText(table.concat(ns.AssignmentLines(true), "\n"))
end

local function paladinNames()
	local out = {}
	for full, m in pairs(ns.roster.members) do if m.class == "PALADIN" then out[#out + 1] = full end end
	table.sort(out)
	return out
end

local function refreshPaladins()
	if not paladinPanel then return end
	local pals = paladinNames()
	if not selectedPaladin or not ns.roster.members[selectedPaladin] then
		local me = ns.roster.members[ns.FullName("player")]
		selectedPaladin = me and me.class == "PALADIN" and ns.FullName("player") or pals[1]
	end
	local m = selectedPaladin and ns.roster.members[selectedPaladin]
	paladinName:SetText(m and ns.ClassColorName(selectedPaladin, "PALADIN") or "No paladins in the group")
	paladinNote:SetText(m and (m.hasAddon and "Spellbook shared by Buffeteria" or "Without Buffeteria: assignments confirm known blessings") or "")
	for class, button in pairs(paladinRows) do
		local key = selectedPaladin and ns.Paladins.Get(selectedPaladin, class) or "AUTO"
		local resolved = ((ns.result.pally or {})[class] or {})[selectedPaladin]
		local label = key == "AUTO" and ("Auto: " .. (resolved and D.byKey[resolved].label or "none"))
			or (key == "NONE" and "None" or D.byKey[key].label)
		if D.byKey[key] and (((ns.roster.paladinAssignments or {})[class] or {})[selectedPaladin] == "NONE") then
			label = D.byKey[key].label .. " (duplicate)"
		end
		button:SetText(label)
		button:SetEnabled(m ~= nil)
	end
	paladinSummary:SetText(table.concat(ns.AssignmentLines(true), "\n"))
end

local function selectTab(isPaladin)
	local _, class = UnitClass("player")
	isPaladin = isPaladin and class == "PALADIN"
	personal:SetShown(not isPaladin)
	paladinPanel:SetShown(isPaladin)
	personalTab:SetEnabled(isPaladin)
	paladinTab:SetEnabled(not isPaladin)
	P.Refresh()
end

function P.Refresh()
	if not content then return end
	for key, cb in pairs(checks) do cb:SetChecked(ns.db.wants[key] and true or false) end
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	warnText:SetText(("Turn orange below: %d min"):format(ns.db.warnMinutes))
	overrideCheck:SetChecked(ns.db.blessingsOverride and true or false)
	refreshRows()
	refreshAssignments()
	refreshPaladins()
end

local function stopDrag(list)
	if not dragging then return end
	dragging = nil
	ns.db.blessingsOverride = true
	list:SetScript("OnUpdate", nil)
	refreshRows()
	P.Refresh()
	ns.PrefsChanged()
end

local function build()
	win = CreateFrame("Frame", "Buffeteria_Prefs", UIParent, "BasicFrameTemplateWithInset")
	win:SetSize(340, 686)
	win:SetPoint("CENTER")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "Buffeteria_Prefs")
	if not win.TitleText then
		win.TitleText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		win.TitleText:SetPoint("TOP", 0, -6)
	end
	win.TitleText:SetText("Buffeteria")

	-- All controls live on "content", which moves between this window and the
	-- Settings > AddOns page (whichever is showing).
	content = CreateFrame("Frame", nil, win)
	content:SetSize(340, 658)
	content:SetPoint("TOPLEFT", 0, -26)
	personalTab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	personalTab:SetSize(148, 24); personalTab:SetPoint("TOPLEFT", 16, -4); personalTab:SetText("My preferences")
	paladinTab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	paladinTab:SetSize(148, 24); paladinTab:SetPoint("LEFT", personalTab, "RIGHT", 8, 0); paladinTab:SetText("Paladins")
	local _, playerClass = UnitClass("player")
	paladinTab:SetShown(playerClass == "PALADIN")
	personal = CreateFrame("Frame", nil, content)
	personal:SetPoint("TOPLEFT", 0, -32); personal:SetPoint("BOTTOMRIGHT")
	paladinPanel = CreateFrame("Frame", nil, content)
	paladinPanel:SetPoint("TOPLEFT", 0, -32); paladinPanel:SetPoint("BOTTOMRIGHT")
	personalTab:SetScript("OnClick", function() selectTab(false) end)
	paladinTab:SetScript("OnClick", function() selectTab(true) end)

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
	for i, buff in ipairs(D.GROUP_BUFFS) do
		local cb = CreateFrame("CheckButton", nil, personal, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		cb:SetPoint("TOPLEFT", 14 + col * 155, y - row * 24)
		cb.text = cb.text or cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:ClearAllPoints()
		cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetText(buff.label)
		cb:SetScript("OnClick", function(self)
			ns.db.wants[buff.key] = self:GetChecked() and true or false
			ns.PrefsChanged()
		end)
		checks[buff.key] = cb
	end
	y = y - math.ceil(#D.GROUP_BUFFS / 2) * 24 - 10

	-- 2) Blessing ranking
	header("Blessings, best first (drag to reorder)")
	local list = CreateFrame("Frame", nil, personal)
	list:SetPoint("TOPLEFT", 16, y)
	list:SetSize(300, ROW_H * (#D.BLESSINGS + 1))
	rows = {}
	for i = 1, #D.BLESSINGS + 1 do
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
	y = y - ROW_H * (#D.BLESSINGS + 1) - 6

	local tip = personal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tip:SetPoint("TOPLEFT", 16, y)
	tip:SetWidth(300)
	tip:SetJustifyH("LEFT")
	tip:SetText("Drag to set a personal override: #1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	y = y - 38
	overrideCheck = CreateFrame("CheckButton", nil, personal, "UICheckButtonTemplate")
	overrideCheck:SetSize(24, 24); overrideCheck:SetPoint("TOPLEFT", 14, y)
	overrideCheck.text = overrideCheck.text or overrideCheck.Text or overrideCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	overrideCheck.text:ClearAllPoints(); overrideCheck.text:SetPoint("LEFT", overrideCheck, "RIGHT", 2, 0)
	overrideCheck.text:SetText("Override the Paladins class plan")
	overrideCheck:SetScript("OnClick", function(self)
		ns.db.blessingsOverride = self:GetChecked() and true or false
		ns.PrefsChanged(); P.Refresh()
	end)
	y = y - 30

	-- 3) Warning threshold
	warnText = personal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	warnText:SetPoint("TOPLEFT", 16, y - 4)
	local minus = CreateFrame("Button", nil, personal, "UIPanelButtonTemplate")
	minus:SetSize(24, 20); minus:SetPoint("TOPLEFT", 210, y); minus:SetText("-")
	local plus = CreateFrame("Button", nil, personal, "UIPanelButtonTemplate")
	plus:SetSize(24, 20); plus:SetPoint("LEFT", minus, "RIGHT", 4, 0); plus:SetText("+")
	minus:SetScript("OnClick", function() ns.db.warnMinutes = math.max(1, ns.db.warnMinutes - 1); P.Refresh(); ns.Tracker.Refresh() end)
	plus:SetScript("OnClick", function() ns.db.warnMinutes = math.min(15, ns.db.warnMinutes + 1); P.Refresh(); ns.Tracker.Refresh() end)
	y = y - 28

	-- Toggles: tracker, lock, minimap button
	toggles = {}
	local function toggle(label, x, rowY, get, set)
		local cb = CreateFrame("CheckButton", nil, personal, "UICheckButtonTemplate")
		cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", x, rowY)
		cb.text = cb.text or cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:ClearAllPoints(); cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetText(label)
		cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
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
		function(v) ns.db.minimap.hide = not v; if ns.Minimap then ns.Minimap.Refresh() end end)
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

	local announce = CreateFrame("Button", nil, personal, "UIPanelButtonTemplate")
	announce:SetSize(140, 22)
	announce:SetPoint("BOTTOM", 0, 14)
	announce:SetText("Announce to group")
	announce:SetScript("OnClick", ns.Announce)

	local title = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -8); title:SetText("Class blessing assignments")
	local help = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 16, -30); help:SetWidth(300); help:SetJustifyH("LEFT")
	help:SetText("Choose a paladin, then click a class blessing to cycle it (right-click reverses). Auto uses the solver; None leaves the class unassigned.")
	local prevPaladin = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
	prevPaladin:SetSize(26, 24); prevPaladin:SetPoint("TOPLEFT", 16, -84); prevPaladin:SetText("<")
	local nextPaladin = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
	nextPaladin:SetSize(26, 24); nextPaladin:SetPoint("TOPRIGHT", -16, -84); nextPaladin:SetText(">")
	paladinName = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	paladinName:SetPoint("LEFT", prevPaladin, "RIGHT", 8, 0); paladinName:SetPoint("RIGHT", nextPaladin, "LEFT", -8, 0)
	local function movePaladin(delta)
		local pals = paladinNames()
		for i, name in ipairs(pals) do
			if name == selectedPaladin then selectedPaladin = pals[((i - 1 + delta) % #pals) + 1]; break end
		end
		refreshPaladins()
	end
	prevPaladin:SetScript("OnClick", function() movePaladin(-1) end)
	nextPaladin:SetScript("OnClick", function() movePaladin(1) end)
	paladinNote = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	paladinNote:SetPoint("TOPLEFT", 16, -114); paladinNote:SetWidth(300); paladinNote:SetJustifyH("LEFT")
	paladinRows = {}
	for i, class in ipairs(D.CLASS_KEYS) do
		local label = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 20, -146 - (i - 1) * 30); label:SetText(ns.ClassName(class))
		local button = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
		button:SetSize(152, 24); button:SetPoint("TOPLEFT", 168, -140 - (i - 1) * 30)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(_, mouseButton)
			local m = selectedPaladin and ns.roster.members[selectedPaladin]
			if not m then return end
			local choices = { "AUTO" }
			for _, key in ipairs(D.BLESSING_KEYS) do
				if not m.hasAddon or m.caps[key] or m.caps["g" .. key] then choices[#choices + 1] = key end
			end
			choices[#choices + 1] = "NONE"
			local current, index = ns.Paladins.Get(selectedPaladin, class), 1
			for j, key in ipairs(choices) do if key == current then index = j; break end end
			local delta = mouseButton == "RightButton" and -1 or 1
			ns.Paladins.Set(selectedPaladin, class, choices[((index - 1 + delta) % #choices) + 1])
		end)
		paladinRows[class] = button
	end
	local priority = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	priority:SetPoint("TOPLEFT", 16, -418); priority:SetWidth(300); priority:SetJustifyH("LEFT")
	priority:SetText("Shared with the group's Buffeteria users. Personal overrides take priority; everyone else follows this plan. Your own row is saved between sessions.")
	paladinSummary = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	paladinSummary:SetPoint("TOPLEFT", 16, -470); paladinSummary:SetPoint("BOTTOMRIGHT", -16, 44)
	paladinSummary:SetJustifyH("LEFT"); paladinSummary:SetJustifyV("TOP")
	local paladinAnnounce = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
	paladinAnnounce:SetSize(140, 22); paladinAnnounce:SetPoint("BOTTOM", 0, 14); paladinAnnounce:SetText("Announce to group")
	paladinAnnounce:SetScript("OnClick", ns.Announce)
	paladinPanel:Hide(); personalTab:Disable()

	win:SetScript("OnShow", function()
		content:SetParent(win); content:ClearAllPoints(); content:SetPoint("TOPLEFT", 0, -26); content:Show()
		P.Refresh()
	end)
	win:Hide()

	-- Keep the assignment list fresh while open.
	local prev = ns.OnSolved
	ns.OnSolved = function()
		if prev then prev() end
		if content:IsVisible() then P.Refresh() end
	end
end

function P.Toggle()
	if not win then build() end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then HideUIPanel(SettingsPanel) end
	win:SetShown(not win:IsShown())
end

-- Esc > Options > AddOns > Buffeteria (same controls as the /buff window).
function P.RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	panel = CreateFrame("Frame")
	panel.name = "Buffeteria"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Buffeteria")
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("The raid buff buffet. Unlimited refills.")
	panel:SetScript("OnShow", function()
		if not win then build() end
		win:Hide()
		content:SetParent(panel); content:ClearAllPoints(); content:SetPoint("TOPLEFT", 0, -56); content:Show()
		P.Refresh()
	end)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Buffeteria")
	if ok and category then
		Settings.RegisterAddOnCategory(category)
		P.category = category
	end
end

function P.OpenSettings()
	if P.category and Settings.OpenToCategory then
		Settings.OpenToCategory(P.category:GetID())
	else
		P.Toggle()
	end
end
