-- The blessing ranking: one row per entry of the saved order, including the "not
-- wanted" divider. Dragging lifts a row that follows the cursor while the others
-- slide aside; the order is saved as it changes.
local _, ns = ...
local Buffs, GOLD = ns.Buffs, ns.UI.GOLD
local RankList = {}
ns.Preferences.RankList = RankList
local ROW_H, ROW, ICON = 40, 30, 24
local GREY, RED = ns.UI.COLOR.GREY, ns.UI.COLOR.RED
-- Drag state: the slot being moved, where the cursor grabbed it, and the lifted copy.
local list, rows, ghost, served, onMoved, cutoff
local dragging, grabY, ghostY, dropping, moved

-- Paint one ranking row (or the lifted copy) for a key.
local function paintRow(r, key, rank, below, mine)
	local divider = key == "|"
	r.icon:SetShown(not divider); r.border:SetShown(not divider); r.rule:SetShown(divider)
	for _, edge in ipairs(r.edges) do edge:SetShown(not divider) end
	r.check:SetShown(not divider and mine[key] ~= nil)
	r.text:ClearAllPoints()
	if divider then
		-- A heading for the blessings below it, not a row of its own.
		r.rank:SetText(""); r.served:SetText("")
		r.text:SetPoint("LEFT", 4, -2)
		r.text:SetText(RED .. "Excluded from my ranking|r")
		r.bg:SetColorTexture(0, 0, 0, 0)
		r.accent:SetColorTexture(0, 0, 0, 0)
		return
	end
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, mine[key] and 6 or 0)
	r.text:SetPoint("RIGHT", r.grip, "LEFT", -28, 0)
	r.icon:SetTexture(ns.UI.BuffIcon(key))
	r.icon:SetDesaturated(below)
	if below then
		r.border:SetVertexColor(0.25, 0.25, 0.25)
		r.rank:SetText(""); r.served:SetText(mine[key] and ns.Roster.Name(mine[key]) or "")
		r.text:SetText(GREY .. Buffs.byKey[key].label .. "|r")
		r.accent:SetColorTexture(0, 0, 0, 0)
		r.bg:SetColorTexture(0.12, 0.03, 0.02, 0.35)
	else
		r.border:SetVertexColor(0, 0, 0)
		r.rank:SetText(tostring(rank))
		r.text:SetText(Buffs.byKey[key].label)
		-- The paladin actually serving this blessing to you.
		r.served:SetText(mine[key] and ns.Roster.Name(mine[key]) or "")
		-- A thin gold accent marks blessings someone is actually casting on you.
		if mine[key] then r.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9) else r.accent:SetColorTexture(0, 0, 0, 0) end
		r.bg:SetColorTexture(0, 0, 0, 0.4)
	end
end

local function showContent(r, shown)
	for _, region in ipairs(r.content) do region:SetShown(shown) end
	for _, edge in ipairs(r.outline) do edge:SetShown(not shown) end
end

local function setGrip(r, lit)
	for _, dot in ipairs(r.dots) do
		if lit then dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) else dot:SetColorTexture(0.55, 0.55, 0.55, 0.8) end
	end
end

-- Repaint every row; returns how many blessings are ranked above the divider.
local function refreshRows()
	local rank, below, mine = 0, false, served()
	local prefix, assigned, gap = 0, 0, false
	for i, key in ipairs(ns.Preferences.Order()) do
		local r = rows[i]
		if key == "|" then below = true elseif not below then rank = rank + 1 end
		if key ~= "|" then
			if mine[key] then
				assigned = assigned + 1
				if not gap and not below then prefix = i end
			else gap = true end
		end
		if i == dragging then
			-- The empty slot the lifted row will drop into.
			showContent(r, false)
			r.icon:Hide(); r.border:Hide()
			r.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
			paintRow(ghost, key, rank, below and key ~= "|", mine)
			if key ~= "|" then ghost.bg:SetColorTexture(0.22, 0.15, 0.02, 0.97) end
			ghost.grip:SetShown(key ~= "|")
		else
			showContent(r, true)
			paintRow(r, key, rank, below and key ~= "|", mine)
		end
		r.grip:SetShown(key ~= "|" and i ~= dragging)
	end
	-- A cutoff is honest only when assignments form a contiguous ranked prefix.
	cutoff:SetShown(ns.db.blessingsOverride and not dragging and prefix > 0 and prefix == assigned)
	if prefix > 0 then
		-- Centered in the gap below the last assigned row.
		cutoff:ClearAllPoints(); cutoff:SetPoint("TOPLEFT", 0, -prefix * ROW_H + ROW_H - ROW)
		cutoff.label:SetText(assigned .. (assigned == 1 and " blessing" or " blessings") .. " assigned now")
	end
	return rank
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
	if moved then onMoved() end
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
			local order = ns.Preferences.Order()
			ghostY = math.max(0, math.min((#order - 1) * ROW_H, cursorY() - grabY))
			local idx = math.floor((ghostY + ROW_H / 2) / ROW_H) + 1
			if idx ~= dragging then
				table.insert(order, idx, table.remove(order, dragging))
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

-- Rank number, framed icon, blessing, the paladin serving it, and a grip.
local function rowVisuals(r)
	r.offset = 0
	r:SetHeight(ROW)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	-- A faint one-pixel edge around each row.
	r.edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
		local edge = ns.UI.Line(r, 1, 1, 1, 0.07, false, "BORDER")
		edge:SetPoint(side[1]); edge:SetPoint(side[2])
		r.edges[#r.edges + 1] = edge
	end
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT"); r.accent:SetPoint("BOTTOMLEFT"); r.accent:SetWidth(2)
	r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	r.rank:SetPoint("LEFT", 4, 0); r.rank:SetWidth(20); r.rank:SetJustifyH("CENTER")
	r.icon, r.border = ns.UI.Icon(r, ICON)
	r.border:SetPoint("LEFT", 30, 0)
	-- Three-bar drag handle.
	r.grip = CreateFrame("Frame", nil, r)
	r.grip:SetSize(12, 10); r.grip:SetPoint("RIGHT", -10, 0)
	r.dots = {}
	for d = 0, 2 do
		local bar = r.grip:CreateTexture(nil, "OVERLAY")
		bar:SetSize(12, 2); bar:SetPoint("TOPLEFT", 0, -d * 4)
		r.dots[#r.dots + 1] = bar
	end
	setGrip(r, false)
	r.served = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.served:SetPoint("LEFT", r.icon, "RIGHT", 10, -7); r.served:SetJustifyH("LEFT"); r.served:SetWordWrap(false)
	r.served:SetPoint("RIGHT", r.grip, "LEFT", -28, 0)
	r.served:SetTextColor(0.75, 0.75, 0.75)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
	r.check = r:CreateTexture(nil, "OVERLAY")
	r.check:SetSize(18, 18); r.check:SetPoint("RIGHT", r.grip, "LEFT", -8, 0)
	r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	-- The red rule after the "Excluded" heading.
	r.rule = ns.UI.Line(r, 0.9, 0.25, 0.15, 0.6)
	r.rule:SetPoint("LEFT", r.text, "RIGHT", 8, 0); r.rule:SetPoint("RIGHT", r, "RIGHT", -4, -2)
	r.content = { r.accent, r.rank, r.served, r.text, r.check, r.rule }
	-- Gold outline, shown on the empty drop slot and the lifted row.
	r.outline = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "H" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "H" },
		{ "TOPLEFT", "BOTTOMLEFT", "V" }, { "TOPRIGHT", "BOTTOMRIGHT", "V" } }) do
		local edge = r:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1]); edge:SetPoint(side[2])
		if side[3] == "V" then edge:SetWidth(1) else edge:SetHeight(1) end
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
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
	for _, edge in ipairs(g.outline) do edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); edge:Show() end
	setGrip(g, true)
	g:Hide()
	return g
end

-- servedBy() -> blessing key -> paladin; moved() runs once when a drag changed the order.
function RankList.Create(parent, servedBy, movedCallback)
	served, onMoved = servedBy, movedCallback
	list = CreateFrame("Frame", nil, parent)
	list:SetHeight(ROW_H * (#Buffs.BLESSINGS + 1))
	rows = {}
	for i = 1, #Buffs.BLESSINGS + 1 do rows[i] = createRow(i) end
	ghost = createGhost()
	-- "N blessings assigned now": a gold label between two gold rules.
	cutoff = CreateFrame("Frame", nil, list)
	cutoff:SetHeight(ROW_H - ROW)
	cutoff.label = cutoff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cutoff.label:SetPoint("CENTER", 0, 0)
	local font = cutoff.label:GetFont()
	cutoff.label:SetFont(font, 10)
	for _, side in ipairs({ { "LEFT", "LEFT", "RIGHT", -8 }, { "RIGHT", "RIGHT", "LEFT", 8 } }) do
		local rule = ns.UI.Line(cutoff, GOLD[1], GOLD[2], GOLD[3], 0.5)
		rule:SetPoint(side[1], cutoff, side[2], side[1] == "LEFT" and 4 or -4, 0)
		rule:SetPoint(side[3], cutoff.label, side[1], side[4], 0)
	end
	cutoff:Hide()
	-- Closing the window mid-drag keeps the order reached so far.
	list:SetScript("OnHide", function()
		if not dragging then return end
		if not dropping then releaseDrag() end
		finishDrop()
		for _, r in ipairs(rows) do r.offset = 0 end
		placeRows()
		list:SetScript("OnUpdate", nil)
	end)
	list.rows, list.ghost, list.Refresh = rows, ghost, refreshRows
	function list:SetRowWidth(width)
		self:SetWidth(width)
		for _, r in ipairs(rows) do r:SetWidth(width) end
		ghost:SetWidth(width)
		cutoff:SetWidth(width)
	end
	return list
end
