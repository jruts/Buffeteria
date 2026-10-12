-- Personal buff preferences and tracker options, laid out as three talent trees.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, band, trees, rows, wants, toggles, warnText, overrideCheck, tip, list, tankButtons, roleButton, roleText, tankTip
local ROW_H, EDGE, GAP, BOARD_H = 22, 8, 2, 360
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

-- Tank requests follow the role without changing the saved per-buff choices.
local function refreshTanks()
	local tank, mine = ns.Preferences.IsTank(), served()
	local _, class = UnitClass("player")
	roleButton:SetText("Role: " .. ({ AUTO = "Auto", TANK = "Tank", OFF = "Not tank" })[ns.db.tankRole])
	roleText:SetText(tank and "|cff40ff40Tank buffs active|r" or GREY .. "Tank buffs inactive|r")
	local wanted = 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button = tankButtons[buff.key]
		local relevant = not buff.selfOnly or class == buff.class
		button:SetShown(relevant)
		local on = tank and ns.db.tankBuffs[buff.key]
		if relevant and on then wanted = wanted + 1 end
		button:SetState(on and "gold" or "grey", blessingIcon(buff.key))
		if not tank then button.caster:SetText(GREY .. "Tank only|r")
		elseif not on then button.caster:SetText(GREY .. "Skipped|r")
		elseif mine[buff.key] then
			button.caster:SetText(buff.selfOnly and "Self" or ns.UI.MemberName(mine[buff.key]))
		else button.caster:SetText(RED .. (buff.selfOnly and "Not learned" or "No druid") .. "|r") end
	end
	return wanted
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
	trees[3]:SetHeader(blessingIcon("THORNS"), "Tanks", "Buffs for your tank role", refreshTanks())
	band:SetCount("Paladins", #ns.UI.PaladinNames())
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
	roleButton:SetWidth(column - 28)
	roleText:SetWidth(column - 28)
	tankTip:SetWidth(column - 28)
	local _, class = UnitClass("player")
	local row = 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button = tankButtons[buff.key]
		button:ClearAllPoints(); button:SetPoint("TOPLEFT", trees[3], "TOPLEFT", 20, -150 - row * 66)
		button.label:SetWidth(column - 80); button.caster:SetWidth(column - 80)
		if not buff.selfOnly or class == buff.class then row = row + 1 end
	end
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
	r.icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
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
	band = ns.UI.Band(personal, "Your buffet", "Rank your blessings and pick your buffs, including tank buffs.")
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

	-- 3) Tank buffs, with an automatic role and an override for unassigned groups.
	local tanks = trees[3]
	roleButton = CreateFrame("Button", nil, tanks, "UIPanelButtonTemplate")
	roleButton:SetHeight(22); roleButton:SetPoint("TOPLEFT", 14, -84)
	roleButton:SetScript("OnClick", function()
		ns.db.tankRole = ({ AUTO = "TANK", TANK = "OFF", OFF = "AUTO" })[ns.db.tankRole]
		ns.Preferences.Changed(); View.Refresh()
	end)
	roleText = ns.UI.Text(tanks, "GameFontHighlightSmall", 14, -114)
	tankButtons = {}
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button = ns.UI.TalentButton(tanks)
		button.key = buff.key
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.label:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, -3)
		button.label:SetJustifyH("LEFT"); button.label:SetWordWrap(false); button.label:SetText(buff.label)
		button.caster = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.caster:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, -23)
		button.caster:SetJustifyH("LEFT"); button.caster:SetWordWrap(false)
		button:SetScript("OnClick", function(self)
			ns.db.tankBuffs[self.key] = not ns.db.tankBuffs[self.key]
			ns.Preferences.Changed(); View.Refresh()
		end)
		button:SetScript("OnEnter", function(self)
			local b = Buffs.byKey[self.key]
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(b.label)
			GameTooltip:AddLine(ns.db.tankBuffs[self.key] and "Wanted when tanking" or "Not wanted", 1, 0.82, 0)
			GameTooltip:AddLine(b.selfOnly and "Self-cast by paladin tanks." or "Assigned to a druid for tank recipients.", 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine("Click to toggle.", 1, 1, 1); GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		tankButtons[buff.key] = button
	end
	tankTip = ns.UI.Text(tanks, "GameFontDisableSmall", 14, -286, nil,
		"Auto follows your Tank role or raid main-tank assignment. Click Role to override it. Buff choices apply only while tanking.")

	ns.UI.AnnounceButton(personal)
	personal.wants, personal.tankButtons, personal.tankRole = wants, tankButtons, roleButton
	return personal
end
