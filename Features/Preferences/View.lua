-- Personal buff preferences and tracker options, laid out as three talent trees.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, band, trees, rows, wants, toggles, warnText, overrideCheck, tip, list, menu
local ROW_H, EDGE, GAP, BOARD_H, MENU_ROW = 22, 8, 2, 360, 20
local MENU_TOP, MENU_ROWS = -80, 13
local dragging

local blessingIcon = ns.UI.BuffIcon
local GREY, RED = "|cff808080", "|cffff5040"

-- What the solver expects you to receive: buff key -> caster.
local function served()
	local result = ns.result or {}
	return (result.expected or {})[ns.WoW.FullName("player")] or {}
end

local function refreshRows()
	local rank, below, mine = 0, false, served()
	for i, key in ipairs(ns.db.order) do
		local r = rows[i]
		r.icon:SetShown(key ~= "|"); r.border:SetShown(key ~= "|"); r.grip:SetShown(key ~= "|")
		r.text:ClearAllPoints()
		if key == "|" then
			below = true
			r.rank:SetText(""); r.served:SetText("")
			r.text:SetPoint("CENTER", 0, 0)
			r.text:SetText(RED .. "Not wanted below|r")
			r.bg:SetColorTexture(0.32, 0.06, 0.03, 0.75)
			r.accent:SetColorTexture(0.9, 0.2, 0.1, 1)
		else
			r.text:SetPoint("LEFT", r.icon, "RIGHT", 7, 0); r.text:SetPoint("RIGHT", r.served, "LEFT", -4, 0)
			r.icon:SetTexture(blessingIcon(key))
			r.icon:SetDesaturated(below)
			if below then
				r.border:SetVertexColor(0.5, 0.5, 0.5)
				r.rank:SetText(""); r.served:SetText("")
				r.text:SetText(GREY .. Buffs.byKey[key].label .. "|r")
				r.accent:SetColorTexture(0.35, 0.35, 0.35, 1)
			else
				rank = rank + 1
				r.border:SetVertexColor(1, 0.82, 0)
				r.rank:SetText(tostring(rank))
				r.text:SetText(Buffs.byKey[key].label)
				-- The paladin actually serving this blessing to you.
				r.served:SetText(mine[key] and ns.UI.MemberName(mine[key]) or (GREY .. "-|r"))
				r.accent:SetColorTexture(1, 0.82, 0, 1)
			end
			if i == dragging then r.bg:SetColorTexture(1, 0.82, 0, 0.3)
			elseif below then r.bg:SetColorTexture(0, 0, 0, 0.35)
			else r.bg:SetColorTexture(0, 0, 0, 0.6) end
		end
	end
	return rank
end

-- The third tree is a menu of pooled rows: section headings or icon entries.
local function menuRow(i)
	if menu[i] then return menu[i] end
	local row = CreateFrame("Frame", nil, trees[3])
	row:SetHeight(MENU_ROW)
	row.head = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.head:SetPoint("LEFT", 0, -2)
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetColorTexture(0.85, 0.66, 0.26, 0.6); row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", row.head, "RIGHT", 6, 0); row.rule:SetPoint("RIGHT", 0, -2)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetPoint("TOPLEFT", 0, -1); row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
	row.bg:SetColorTexture(0, 0, 0, 0.55)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16); row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -4, 0); row.right:SetJustifyH("RIGHT"); row.right:SetWordWrap(false)
	row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.left:SetJustifyH("LEFT"); row.left:SetWordWrap(false)
	menu[i] = row
	return row
end

local function setMenuRow(i, entry)
	local row = menuRow(i)
	local heading, icon = entry.heading, entry.icon
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", trees[3], "TOPLEFT", 12, MENU_TOP - (i - 1) * MENU_ROW)
	row:SetPoint("RIGHT", trees[3], "RIGHT", -12, 0)
	row.head:SetText(heading or ""); row.head:SetShown(heading ~= nil); row.rule:SetShown(heading ~= nil)
	row.bg:SetShown(heading == nil); row.icon:SetShown(heading == nil and icon ~= nil)
	row.icon:SetTexture(icon)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", icon and 24 or 6, 0); row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
	row.left:SetText(entry.left or ""); row.right:SetText(entry.right or "")
	row.left:SetShown(heading == nil); row.right:SetShown(heading == nil)
	row:Show()
end

-- The whole group's plan: every paladin's aura and blessings, then every group-buff caster.
local function menuEntries()
	local out, result = {}, ns.result or {}
	out[#out + 1] = { heading = "Paladins" }
	local before = #out
	-- Paladins: each blessing they cast, with how many classes get it.
	local stations, paladins = {}, {}
	for _, map in pairs(result.pally or {}) do
		for paladin, key in pairs(map) do
			if Buffs.byKey[key] then
				if not stations[paladin] then stations[paladin] = {}; paladins[#paladins + 1] = paladin end
				stations[paladin][key] = (stations[paladin][key] or 0) + 1
			end
		end
	end
	for paladin in pairs(result.auras or {}) do
		if not stations[paladin] then stations[paladin] = {}; paladins[#paladins + 1] = paladin end
	end
	table.sort(paladins)
	for _, paladin in ipairs(paladins) do
		local dishes = {}
		for _, key in ipairs(Buffs.BLESSING_KEYS) do
			local count = stations[paladin][key]
			if count then dishes[#dishes + 1] = ns.UI.InlineIcon(blessingIcon(key), 13) .. count end
		end
		-- The row's icon is the aura that paladin runs.
		local aura = (result.auras or {})[paladin]
		out[#out + 1] = { icon = aura and blessingIcon(aura), left = ns.UI.MemberName(paladin), right = table.concat(dishes, " ") }
	end
	if #out == before then out[#out + 1] = { left = GREY .. "No paladins cooking.|r" } end
	out[#out + 1] = { heading = "Group buffs" }
	before = #out
	-- Group buffs: each caster with the raid groups they cover.
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local byCaster, casters = {}, {}
		for group, caster in pairs((result.groups or {})[buff.key] or {}) do
			if not byCaster[caster] then byCaster[caster] = {}; casters[#casters + 1] = caster end
			table.insert(byCaster[caster], group)
		end
		table.sort(casters)
		for _, caster in ipairs(casters) do
			table.sort(byCaster[caster])
			out[#out + 1] = { icon = blessingIcon(buff.key), left = ns.UI.MemberName(caster),
				right = GREY .. "G" .. table.concat(byCaster[caster], ",") .. "|r" }
		end
	end
	if #out == before then out[#out + 1] = { left = GREY .. "No priests, druids or mages.|r" } end
	return out
end

local function refreshMenu()
	local entries = menuEntries()
	if #entries > MENU_ROWS then
		local hidden = #entries - MENU_ROWS + 1
		for i = #entries, MENU_ROWS + 1, -1 do entries[i] = nil end
		entries[MENU_ROWS] = { left = GREY .. ("+%d more: Announce lists all|r"):format(hidden) }
	end
	for i, entry in ipairs(entries) do setMenuRow(i, entry) end
	for i = #entries + 1, #menu do menu[i]:Hide() end
end

local function refreshWants()
	local wanted, mine = 0, served()
	for key, button in pairs(wants) do
		local on = ns.db.wants[key] and true or false
		if on then wanted = wanted + 1 end
		button:SetState(on and "gold" or "grey", blessingIcon(key))
		if not on then button.caster:SetText(GREY .. "Skipped|r")
		elseif mine[key] then button.caster:SetText(ns.UI.MemberName(mine[key]))
		else button.caster:SetText(RED .. "No caster|r") end
	end
	return wanted
end

function View.Refresh()
	if not personal then return end
	local wanted = refreshWants()
	for _, cb in ipairs(toggles) do cb:SetChecked(cb.get() and true or false) end
	warnText:SetText(("Orange below |cffffffff%d|r min"):format(ns.db.warnMinutes))
	overrideCheck:SetChecked(ns.db.blessingsOverride and true or false)
	local ranked = refreshRows()
	local _, class = UnitClass("player")
	local art = ns.UI.TREE_ART[class] or ns.UI.TREE_ART.PALADIN
	for i, tree in ipairs(trees) do tree:SetArt(art[i]) end
	trees[1]:SetHeader(blessingIcon("KINGS"), "Blessings", "Best first, drag to reorder", ranked)
	trees[2]:SetHeader(blessingIcon("FORT"), "Buffs", "Click the buffs you want", wanted)
	trees[3]:SetHeader(ns.UI.ICON, "Kitchen", "Who casts what for the group")
	band:SetCount("Paladins", #ns.UI.PaladinNames())
	refreshMenu()
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
	tip:SetWidth(column - 28)
	overrideCheck.text:SetWidth(column - 44)
	local cell = column / 3
	for i, buff in ipairs(Buffs.GROUP_BUFFS) do
		-- Talent tiers: three on top, the rest centered below.
		local tier = math.floor((i - 1) / 3)
		local x = tier == 0 and cell * ((i - 1) + 0.5) or cell * (i - 3)
		local button = wants[buff.key]
		button:ClearAllPoints(); button:SetPoint("TOP", trees[2], "TOPLEFT", x, -84 - tier * 60)
		button.caster:SetWidth(cell - 2)
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
	local caster = served()[button.key]
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(buff.label)
	GameTooltip:AddLine(ns.db.wants[button.key] and "Wanted" or "Not wanted", 1, 0.82, 0)
	if ns.db.wants[button.key] then
		GameTooltip:AddLine(caster and ("Cast by " .. ns.UI.MemberName(caster)) or "Nobody in the group casts it yet.",
			0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Click to toggle.", 1, 1, 1)
	GameTooltip:Show()
end

-- A ranking row: rank number, framed icon, blessing, the paladin serving it, grip.
local function createRow(i)
	local r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H - 2)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT"); r.accent:SetPoint("BOTTOMLEFT"); r.accent:SetWidth(2)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.rank:SetPoint("LEFT", 4, 0); r.rank:SetWidth(14); r.rank:SetJustifyH("CENTER")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW_H - 6, ROW_H - 6)
	r.icon:SetPoint("LEFT", 22, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Action-button style slot ring around the icon.
	r.border = r:CreateTexture(nil, "OVERLAY")
	r.border:SetSize(ROW_H * 1.55, ROW_H * 1.55); r.border:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
	r.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	r.grip = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.grip:SetPoint("RIGHT", -6, 0)
	r.grip:SetText("::")
	r.served = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.served:SetPoint("RIGHT", r.grip, "LEFT", -6, 0); r.served:SetJustifyH("RIGHT"); r.served:SetWordWrap(false)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
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
	return r
end

function View.Create(parent)
	personal = CreateFrame("Frame", nil, parent)
	personal:SetPoint("TOPLEFT", 0, -34); personal:SetPoint("BOTTOMRIGHT")
	band = ns.UI.Band(personal, "Your buffet", "Rank your blessings, pick your buffs, and see who serves what.")
	trees = { ns.UI.Tree(personal), ns.UI.Tree(personal), ns.UI.Tree(personal) }

	-- 1) Blessing ranking, with the paladin serving each ranked blessing
	local blessings = trees[1]
	list = CreateFrame("Frame", nil, blessings)
	list:SetPoint("TOPLEFT", 12, -82)
	list:SetHeight(ROW_H * (#Buffs.BLESSINGS + 1))
	rows = {}
	for i = 1, #Buffs.BLESSINGS + 1 do rows[i] = createRow(i) end
	tip = ns.UI.Text(blessings, "GameFontDisableSmall", 14, -90 - ROW_H * (#Buffs.BLESSINGS + 1), nil,
		"#1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	overrideCheck = ns.UI.Checkbox(blessings, "Override the Paladins class plan", 10, -300, function(value)
		ns.db.blessingsOverride = value
		ns.Preferences.Changed(); View.Refresh()
	end)
	overrideCheck.text:SetJustifyH("LEFT")

	-- 2) Buffs I want as talent buttons naming their caster, then the tracker options
	local buffs = trees[2]
	wants = {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local button = ns.UI.TalentButton(buffs)
		button.key = buff.key
		button.caster = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.caster:SetPoint("TOP", button, "BOTTOM", 0, -4); button.caster:SetWordWrap(false)
		button:SetScript("OnClick", function(self)
			ns.db.wants[self.key] = not ns.db.wants[self.key]
			ns.Preferences.Changed(); View.Refresh()
			if GameTooltip:IsOwned(self) then wantTooltip(self) end
		end)
		button:SetScript("OnEnter", wantTooltip); button:SetScript("OnLeave", GameTooltip_Hide)
		wants[buff.key] = button
	end
	ns.UI.Section(buffs, "Tracker", 14, -206)
	warnText = ns.UI.Text(buffs, "GameFontHighlightSmall", 16, -228)
	local minus = CreateFrame("Button", nil, buffs, "UIPanelButtonTemplate")
	minus:SetSize(22, 20); minus:SetPoint("TOPRIGHT", -38, -222); minus:SetText("-")
	local plus = CreateFrame("Button", nil, buffs, "UIPanelButtonTemplate")
	plus:SetSize(22, 20); plus:SetPoint("LEFT", minus, "RIGHT", 2, 0); plus:SetText("+")
	minus:SetScript("OnClick", function() ns.db.warnMinutes = math.max(1, ns.db.warnMinutes - 1); View.Refresh(); ns.Tracker.Refresh() end)
	plus:SetScript("OnClick", function() ns.db.warnMinutes = math.min(15, ns.db.warnMinutes + 1); View.Refresh(); ns.Tracker.Refresh() end)
	toggles = {}
	local function toggle(label, get, set)
		local cb = ns.UI.Checkbox(buffs, label, 10, -244 - #toggles * 21, set)
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

	-- 3) The whole group's plan (rows built on refresh)
	menu = {}

	ns.UI.AnnounceButton(personal)
	personal.wants, personal.menu = wants, menu
	return personal
end
