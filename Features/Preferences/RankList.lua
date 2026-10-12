-- The blessing ranking: one row per entry of the saved order, including the "not
-- wanted" divider. Dragging lifts a row that follows the cursor while the others
-- slide aside; the order is saved as it changes.
local _, ns = ...
local Buffs, GOLD = ns.Buffs, ns.UI.GOLD
local RankList = {}
ns.Preferences.RankList = RankList
local ROW_H, ICON = 30, 22
local GREY, RED = ns.UI.COLOR.GREY, ns.UI.COLOR.RED
-- Drag state: the slot being moved, where the cursor grabbed it, and the lifted copy.
local list, rows, ghost, served, onMoved
local dragging, grabY, ghostY, dropping, moved

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
	r.icon:SetTexture(ns.UI.BuffIcon(key))
	r.icon:SetDesaturated(below)
	if below then
		r.border:SetVertexColor(0.5, 0.5, 0.5)
		r.rank:SetText(""); r.served:SetText("")
		r.text:SetText(GREY .. Buffs.byKey[key].label .. "|r")
		r.accent:SetColorTexture(0.35, 0.35, 0.35, 1)
		r.bg:SetColorTexture(0, 0, 0, 0.35)
	else
		r.border:SetVertexColor(unpack(GOLD))
		r.rank:SetText(tostring(rank))
		r.text:SetText(Buffs.byKey[key].label)
		-- The paladin actually serving this blessing to you.
		r.served:SetText(mine[key] and ns.Roster.Name(mine[key]) or (GREY .. "-|r"))
		r.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		r.bg:SetColorTexture(0, 0, 0, 0.6)
	end
end

local function showContent(r, shown)
	for _, region in ipairs(r.content) do region:SetShown(shown) end
	for _, edge in ipairs(r.outline) do edge:SetShown(not shown) end
end

local function setGrip(r, lit)
	for _, dot in ipairs(r.dots) do
		if lit then dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) else dot:SetColorTexture(0.65, 0.65, 0.65, 0.7) end
	end
end

-- Repaint every row; returns how many blessings are ranked above the divider.
local function refreshRows()
	local rank, below, mine = 0, false, served()
	for i, key in ipairs(ns.Preferences.Order()) do
		local r = rows[i]
		if key == "|" then below = true elseif not below then rank = rank + 1 end
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
	end
	return list
end
