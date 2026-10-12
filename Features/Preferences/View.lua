-- Personal buff preferences, laid out as three talent trees.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, band, trees, rows, wants, overrideCheck, tip, list, tankButtons, roleButton, roleText, tankTip
local ROW_H, ICON, EDGE, GAP, BOARD_H = 30, 22, 8, 2, 360
-- Drag state: the slot being moved, where the cursor grabbed it, and the lifted copy.
local dragging, grabY, ghost, ghostY, dropping, moved

local blessingIcon = ns.UI.BuffIcon
local GREY, RED = "|cff808080", "|cffff5040"

-- What the solver expects you to receive: buff key -> caster.
local function served()
	local result = ns.result or {}
	return (result.expected or {})[ns.WoW.FullName("player")] or {}
end

-- Paint one ranking row (or the lifted copy) for a key.
local function paintRow(r, key, rank, below, mine)
	r.icon:SetShown(key ~= "|"); r.border:SetShown(key ~= "|")
	r.text:ClearAllPoints()
	if key == "|" then
		r.rank:SetText(""); r.served:SetText("")
		r.text:SetPoint("CENTER", 0, 0)
		r.text:SetText(RED .. "Not wanted below|r")
		r.bg:SetColorTexture(0.32, 0.06, 0.03, 0.75)
		r.accent:SetColorTexture(0.9, 0.2, 0.1, 1)
		return
	end
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 9, 0); r.text:SetPoint("RIGHT", r.served, "LEFT", -6, 0)
	r.icon:SetTexture(blessingIcon(key))
	r.icon:SetDesaturated(below)
	if below then
		r.border:SetVertexColor(0.5, 0.5, 0.5)
		r.rank:SetText(""); r.served:SetText("")
		r.text:SetText(GREY .. Buffs.byKey[key].label .. "|r")
		r.accent:SetColorTexture(0.35, 0.35, 0.35, 1)
		r.bg:SetColorTexture(0, 0, 0, 0.35)
	else
		r.border:SetVertexColor(1, 0.82, 0)
		r.rank:SetText(tostring(rank))
		r.text:SetText(Buffs.byKey[key].label)
		-- The paladin actually serving this blessing to you.
		r.served:SetText(mine[key] and ns.UI.MemberName(mine[key]) or (GREY .. "-|r"))
		r.accent:SetColorTexture(1, 0.82, 0, 1)
		r.bg:SetColorTexture(0, 0, 0, 0.6)
	end
end

local function showContent(r, shown)
	for _, region in ipairs(r.content) do region:SetShown(shown) end
	for _, edge in ipairs(r.outline) do edge:SetShown(not shown) end
end

local function refreshRows()
	local rank, below, mine = 0, false, served()
	for i, key in ipairs(ns.db.order) do
		local r = rows[i]
		if key == "|" then below = true elseif not below then rank = rank + 1 end
		if i == dragging then
			-- The empty slot the lifted row will drop into.
			showContent(r, false)
			r.icon:Hide(); r.border:Hide()
			r.bg:SetColorTexture(1, 0.82, 0, 0.08)
			paintRow(ghost, key, rank, below and key ~= "|", mine)
			if key ~= "|" then ghost.bg:SetColorTexture(0.22, 0.15, 0.02, 0.97) end
		else
			showContent(r, true)
			paintRow(r, key, rank, below and key ~= "|", mine)
		end
		r.grip:SetShown(key ~= "|" and i ~= dragging)
		if i == dragging then ghost.grip:SetShown(key ~= "|") end
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
	list:SetWidth(column - 20)
	for _, r in ipairs(rows) do r:SetWidth(column - 20) end
	ghost:SetWidth(column - 20)
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

local function placeRows()
	for i, r in ipairs(rows) do
		r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H + r.offset)
	end
	if dragging then
		-- Lifted: nudged right and drawn over the other rows.
		ghost:ClearAllPoints(); ghost:SetPoint("TOPLEFT", 6, -ghostY)
	end
end

local function finishDrop()
	dragging, dropping = nil, false
	ghost:Hide()
	if ResetCursor then ResetCursor() end
	refreshRows()
end

local function releaseDrag()
	dropping = true
	if not moved then return end
	ns.db.blessingsOverride = true
	View.Refresh()
	ns.Preferences.Changed()
end

local function cursorY()
	local _, y = GetCursorPosition()
	return list:GetTop() - y / list:GetEffectiveScale()
end

-- Follows the cursor while dragging, then eases the lifted row and shifted rows into place.
local function animate(_, elapsed)
	local settle = math.min(1, (elapsed or 0) * 16)
	if dragging and not dropping then
		if not IsMouseButtonDown("LeftButton") then releaseDrag()
		else
			ghostY = math.max(0, math.min((#ns.db.order - 1) * ROW_H, cursorY() - grabY))
			local idx = math.floor((ghostY + ROW_H / 2) / ROW_H) + 1
			if idx ~= dragging then
				local item = table.remove(ns.db.order, dragging)
				table.insert(ns.db.order, idx, item)
				-- Rows passed over slide from their old slot into the new one.
				local step = idx > dragging and -ROW_H or ROW_H
				for i = math.min(idx, dragging), math.max(idx, dragging) do
					if i ~= idx then rows[i].offset = step end
				end
				dragging, moved = idx, true
				refreshRows()
			end
		end
	end
	if dropping then
		local target = (dragging - 1) * ROW_H
		ghostY = ghostY + (target - ghostY) * settle
		if math.abs(target - ghostY) < 0.5 then finishDrop() end
	end
	local busy = dragging ~= nil
	for _, r in ipairs(rows) do
		r.offset = r.offset * (1 - settle)
		if math.abs(r.offset) < 0.5 then r.offset = 0 else busy = true end
	end
	placeRows()
	if not busy then list:SetScript("OnUpdate", nil) end
end

local function startDrag(i)
	dragging, moved, dropping = i, false, false
	ghostY = (i - 1) * ROW_H
	grabY = cursorY() - ghostY
	ghost:Show()
	if SetCursor then SetCursor("UI_MOVE_CURSOR") end
	refreshRows()
	placeRows()
	list:SetScript("OnUpdate", animate)
end

local function setGrip(r, lit)
	for _, dot in ipairs(r.dots) do
		if lit then dot:SetColorTexture(1, 0.82, 0, 1) else dot:SetColorTexture(0.65, 0.65, 0.65, 0.7) end
	end
end

-- Rank number, framed icon, blessing, the paladin serving it, and a grip.
local function rowVisuals(r)
	r.offset = 0
	r:SetHeight(ROW_H - 2)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT"); r.accent:SetPoint("BOTTOMLEFT"); r.accent:SetWidth(3)
	r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	r.rank:SetPoint("LEFT", 5, 0); r.rank:SetWidth(18); r.rank:SetJustifyH("CENTER")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ICON, ICON)
	r.icon:SetPoint("LEFT", 30, 0)
	r.icon:SetTexCoord(0.14, 0.86, 0.14, 0.86)
	-- Action-button style slot ring around the icon.
	r.border = r:CreateTexture(nil, "OVERLAY")
	r.border:SetSize(ICON * 2.1, ICON * 2.1); r.border:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
	r.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	-- Six-dot drag handle.
	r.grip = CreateFrame("Frame", nil, r)
	r.grip:SetSize(8, 14); r.grip:SetPoint("RIGHT", -8, 0)
	r.dots = {}
	for d = 0, 5 do
		local dot = r.grip:CreateTexture(nil, "OVERLAY")
		dot:SetSize(2, 2); dot:SetPoint("TOPLEFT", (d % 2) * 5, -math.floor(d / 2) * 5 - 1)
		r.dots[#r.dots + 1] = dot
	end
	setGrip(r, false)
	r.served = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.served:SetPoint("RIGHT", r.grip, "LEFT", -8, 0); r.served:SetJustifyH("RIGHT"); r.served:SetWordWrap(false)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
	r.content = { r.accent, r.rank, r.served, r.text }
	-- Gold outline, shown on the empty drop slot and the lifted row.
	r.outline = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "H" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "H" },
		{ "TOPLEFT", "BOTTOMLEFT", "V" }, { "TOPRIGHT", "BOTTOMRIGHT", "V" } }) do
		local edge = r:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1]); edge:SetPoint(side[2])
		if side[3] == "V" then edge:SetWidth(1) else edge:SetHeight(1) end
		edge:SetColorTexture(1, 0.82, 0, 0.55)
		edge:Hide()
		r.outline[#r.outline + 1] = edge
	end
	return r
end

local function createRow(i)
	local r = rowVisuals(CreateFrame("Button", nil, list))
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r:SetScript("OnEnter", function(self) if not dragging then setGrip(self, true) end end)
	r:SetScript("OnLeave", function(self) setGrip(self, false) end)
	r:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or dragging then return end
		setGrip(self, false)
		startDrag(i)
	end)
	return r
end

-- The lifted copy of the dragged row, with a drop shadow and a solid outline.
local function createGhost()
	local g = rowVisuals(CreateFrame("Frame", nil, list))
	g:SetFrameLevel(list:GetFrameLevel() + 20)
	local shadow = g:CreateTexture(nil, "BACKGROUND", nil, -2)
	shadow:SetPoint("TOPLEFT", 3, -4); shadow:SetPoint("BOTTOMRIGHT", 5, -5)
	shadow:SetColorTexture(0, 0, 0, 0.6)
	for _, edge in ipairs(g.outline) do edge:SetColorTexture(1, 0.82, 0, 1); edge:Show() end
	setGrip(g, true)
	g:Hide()
	return g
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

function View.Create(parent)
	personal = CreateFrame("Frame", nil, parent)
	personal:SetPoint("TOPLEFT", 0, -34); personal:SetPoint("BOTTOMRIGHT")
	band = ns.UI.Band(personal, "Your buffet", "Rank your blessings and pick your buffs, including tank buffs.")
	trees = { ns.UI.Tree(personal), ns.UI.Tree(personal), ns.UI.Tree(personal) }

	-- 1) Blessing ranking, with the paladin serving each ranked blessing
	local blessings = trees[1]
	list = CreateFrame("Frame", nil, blessings)
	list:SetPoint("TOPLEFT", 10, -80)
	list:SetHeight(ROW_H * (#Buffs.BLESSINGS + 1))
	rows = {}
	for i = 1, #Buffs.BLESSINGS + 1 do rows[i] = createRow(i) end
	ghost = createGhost()
	-- Closing the window mid-drag keeps the order reached so far.
	list:SetScript("OnHide", function()
		if not dragging then return end
		if not dropping then releaseDrag() end
		finishDrop()
		for _, r in ipairs(rows) do r.offset = 0 end
		placeRows()
		list:SetScript("OnUpdate", nil)
	end)
	tip = ns.UI.Text(blessings, "GameFontDisableSmall", 14, -84 - ROW_H * (#Buffs.BLESSINGS + 1), nil,
		"#1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	overrideCheck = ns.UI.Checkbox(blessings, "Override the Paladins class plan", 10, -322, function(value)
		ns.db.blessingsOverride = value
		ns.Preferences.Changed(); View.Refresh()
	end)
	overrideCheck.text:SetJustifyH("LEFT")

	-- 2) Buffs I want as talent buttons naming their caster
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
	personal.rankList, personal.rankRows, personal.rankGhost = list, rows, ghost
	return personal
end
