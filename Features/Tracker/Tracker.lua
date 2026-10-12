-- Buffeteria: the on-screen orc mascot + one-click cast button.
local _, ns = ...
local Buffs = ns.Buffs

local Tracker = {}
ns.Tracker = Tracker

local frame, castBtn, cancelBtn, statusIcons, lastSummary
local layoutStatusIcons
local editing = false
local MAIN = 64                                  -- current clickable head size
local GAP = 2
local BORDER = 2
local LABEL_HEIGHT = 12
local SCREEN_MARGIN = 4
local MOOD_TEXTURES = {
	happy = ns.mediaPath .. "OrcHappy",
	grumpy = ns.mediaPath .. "OrcGrumpy",
	angry = ns.mediaPath .. "OrcAngry",
}
local colorOf = ns.Status.Color
local keyIcon = ns.UI.BuffIcon

local function fmtTime(sec)
	if not sec then return "" end
	return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function showTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:AddLine(ns.title .. (ns.Preview.active and " |cffff9900(preview)|r" or ""))
	local s = lastSummary
	if not s or not s.any then
		GameTooltip:AddLine("Nothing on the menu yet.", 0.7, 0.7, 0.7)
	elseif #s.problems == 0 then
		local mood = ns.Status.Mood(s)
		if mood == "happy" then
			local unread = #(s.unreadable or {}) > 0
			GameTooltip:AddLine(unread and "Everyone in range has their buffs." or "Everyone is stuffed. All buffs up.",
				unpack(ns.Status.COLORS.ok))
		elseif mood == "idle" then
			GameTooltip:AddLine("Nobody's buffs can be checked right now.", 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Waiting for readable buff information.", unpack(ns.Status.COLORS.warn))
		end
	else
		local shown = 0
		for _, p in ipairs(s.problems) do
			shown = shown + 1
			if shown > 20 then GameTooltip:AddLine(("...and %d more"):format(#s.problems - 20), 0.7, 0.7, 0.7); break end
			local m = ns.roster.members[p.who]
			local cls = p.class or (m and m.class)
			local who = cls and ns.WoW.ClassColorName(p.who, cls) or ns.WoW.Short(p.who)
			local label = Buffs.byKey[p.key].label
			if p.status == "bad" then
				GameTooltip:AddDoubleLine(who, label .. " missing", 1, 1, 1, unpack(ns.Status.COLORS.bad))
			elseif p.status == "warn" then
				GameTooltip:AddDoubleLine(who, label .. " " .. fmtTime(p.rem), 1, 1, 1, unpack(ns.Status.COLORS.warn))
			else
				GameTooltip:AddDoubleLine(who, "doesn't want " .. label, 1, 1, 1, unpack(ns.Status.COLORS.warn))
			end
		end
	end
	if s and s.unreadable and #s.unreadable > 0 then
		GameTooltip:AddLine(" ")
		for _, full in ipairs(s.unreadable) do
			local m = ns.roster.members[full]
			local who = m and ns.WoW.ClassColorName(full, m.class) or ns.WoW.Short(full)
			GameTooltip:AddDoubleLine(who, "out of range", 1, 1, 1, 0.6, 0.6, 0.6)
		end
	end
	if s and s.next then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Click: %s on %s"):format(s.next.spell, s.next.label), 0.4, 0.8, 1)
	end
	GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Move: Edit Mode, or unlock and drag", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function savePos()
	frame:StopMovingOrSizing()
	frame:SetScript("OnUpdate", nil)
	local p, _, rp, x, y = frame:GetPoint()
	ns.db.pos = { p, rp, x, y }
	Tracker.Refresh()
end

local function startMoving()
	frame:StartMoving()
	-- Reposition Auto during dragging without rescanning or changing the head.
	frame:SetScript("OnUpdate", function()
		if ns.db.iconPosition == "AUTO" and lastSummary then layoutStatusIcons(lastSummary) end
	end)
end

local function build()
	frame = CreateFrame("Frame", ns.globalPrefix .. "_Tracker", UIParent)
	frame:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2 + LABEL_HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- The big secure cast button.
	castBtn = CreateFrame("Button", ns.globalPrefix .. "_CastButton", frame, "SecureActionButtonTemplate")
	castBtn:SetSize(MAIN, MAIN)
	castBtn:SetPoint("TOPLEFT", BORDER, -BORDER)
	castBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
	castBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	castBtn:SetAttribute("useOnKeyDown", false)
	castBtn:SetAttribute("type", "spell")
	-- Right-click must never cast: give it an empty macro, open options in PostClick.
	castBtn:SetAttribute("type2", "macro")
	castBtn:SetAttribute("macrotext2", "")
	castBtn.icon = castBtn:CreateTexture(nil, "ARTWORK")
	castBtn.icon:SetAllPoints()
	-- The alpha silhouette supplies the shape; no square background or highlight.
	castBtn.icon:SetTexCoord(0, 1, 0, 1)
	castBtn.icon:SetTexture(MOOD_TEXTURES.grumpy)
	-- Press feedback belongs to the actual icon, without unrelated slot artwork.
	castBtn:SetScript("OnMouseDown", function(self)
		self.dragged = false
		if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
		self.icon:SetVertexColor(0.75, 0.75, 0.75)
	end)
	castBtn:SetScript("OnMouseUp", function(self) self.icon:SetVertexColor(1, 1, 1) end)
	castBtn:SetScript("OnEnter", showTooltip)
	castBtn:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
	end)
	castBtn:SetScript("PostClick", function(self, button, down)
		if down or self.dragged then return end
		if button == "RightButton" then
			if not down and not InCombatLockdown() then ns.Options.Toggle() end
			return
		end
		if self.pendingWho and self.pendingKey then ns.Actions.MarkCast(self.pendingWho, self.pendingKey) end
		C_Timer.After(0.2, Tracker.Refresh)
	end)
	castBtn:RegisterForDrag("LeftButton")
	castBtn:SetScript("OnDragStart", function(self)
		if ns.db.locked or InCombatLockdown() then return end
		self.dragged, self.dragging = true, true
		-- Mask the secure action too: PostClick alone cannot prevent a cast.
		self:SetAttribute("*type1", "")
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
		startMoving()
	end)
	castBtn:SetScript("OnDragStop", function(self)
		if not self.dragging then return end
		self.dragging = false
		savePos()
		self.icon:SetVertexColor(1, 1, 1)
		-- Keep the release suppressed through this input event. Restore on the
		-- next frame even if the client doesn't send a click after the drag.
		C_Timer.After(0, function()
			if self.dragging then return end
			self.dragged = false
			if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
		end)
	end)

	-- Keep the next recipient below the face, leaving the expression unobscured.
	castBtn.label = castBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	castBtn.label:SetPoint("TOPLEFT", castBtn, "BOTTOMLEFT", 1, -1)
	castBtn.label:SetPoint("TOPRIGHT", castBtn, "BOTTOMRIGHT", -1, -1)
	castBtn.label:SetJustifyH("CENTER")
	castBtn.label:SetWordWrap(false)

	-- "PREVIEW" tag above the tracker.
	frame.tag = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
	frame.tag:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	frame.tag:SetText("|cffff9900PREVIEW|r")
	frame.tag:Hide()

	-- Secure "remove unwanted buff from me" button (e.g. Salvation on a tank), top-right corner.
	cancelBtn = CreateFrame("Button", ns.globalPrefix .. "_CancelButton", frame, "SecureActionButtonTemplate")
	cancelBtn:SetSize(14, 14)
	cancelBtn:SetPoint("CENTER", castBtn, "TOPRIGHT", -2, -2)
	cancelBtn:SetFrameLevel(castBtn:GetFrameLevel() + 3)
	cancelBtn:RegisterForClicks("AnyUp", "AnyDown")
	cancelBtn:SetAttribute("type", "cancelaura")
	cancelBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	cancelBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Remove " .. tostring(self:GetAttribute("spell")) .. " from yourself")
		GameTooltip:Show()
	end)
	cancelBtn:SetScript("OnLeave", GameTooltip_Hide)
	cancelBtn:Hide()

	statusIcons = {}
	frame:Hide()
end

local PRIORITY = ns.Status.PRIORITY
local function iconPlacement(count, iconSize)
	local columns = ns.db.iconsPerRow
	local height = math.ceil(count / columns) * (iconSize + GAP) - GAP
	local side = ns.db.iconPosition
	if side == "AUTO" then
		local belowGap = BORDER + LABEL_HEIGHT + GAP
		local aboveGap = (ns.Preview.active or editing) and 24 or GAP
		local headLeft, headBottom, headTop = castBtn:GetLeft(), castBtn:GetBottom(), castBtn:GetTop()
		if count == 0 or not headLeft or not headBottom or not headTop then
			return columns, "BOTTOM", 0, -belowGap
		end
		-- Convert screen bounds to the head's coordinate scale.
		local scale = UIParent:GetEffectiveScale() / castBtn:GetEffectiveScale()
		local screenLeft = (UIParent:GetLeft() or 0) * scale + SCREEN_MARGIN
		local screenBottom = (UIParent:GetBottom() or 0) * scale + SCREEN_MARGIN
		local screenRight = screenLeft + UIParent:GetWidth() * scale - SCREEN_MARGIN * 2
		local screenTop = screenBottom + UIParent:GetHeight() * scale - SCREEN_MARGIN * 2
		local below = math.max(0, headBottom - belowGap - screenBottom)
		local above = math.max(0, screenTop - headTop - aboveGap)
		local upward = height > below and above > below
		local available = upward and above or below
		-- Start with the chosen row width, widening only when height is tight.
		local maxRows = math.max(1, math.floor((available + GAP) / (iconSize + GAP)))
		local maxColumns = math.max(1, math.floor((screenRight - screenLeft + GAP) / (iconSize + GAP)))
		columns = math.min(maxColumns, math.max(columns, math.ceil(count / maxRows)))
		height = math.ceil(count / columns) * (iconSize + GAP) - GAP
		local center = headLeft + castBtn:GetWidth() / 2
		return columns, upward and "TOP" or "BOTTOM", 0, upward and (aboveGap + height) or -belowGap,
			screenLeft - center, screenRight - center
	end
	-- Fixed choices retain their selected side and row width at screen edges.
	if side == "LEFT" then
		return columns, side, -BORDER - GAP - iconSize, height / 2
	elseif side == "RIGHT" then
		return columns, side, BORDER + GAP, height / 2
	elseif side == "TOP" then
		-- Keep the preview tag and Edit Mode label clear above the face.
		local gap = (ns.Preview.active or editing) and 24 or GAP
		return columns, side, 0, gap + height
	end
	return columns, "BOTTOM", 0, -BORDER - LABEL_HEIGHT - GAP
end

layoutStatusIcons = function(s)
	-- Keep the head's frame independent of the number of rows. A center- or
	-- bottom-anchored frame otherwise moves its top whenever its height changes.
	-- Secure descendants also mean size changes must wait until out of combat.
	if not InCombatLockdown() and MAIN ~= ns.db.iconSize then
		MAIN = ns.db.iconSize
		castBtn:SetSize(MAIN, MAIN)
		frame:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2 + LABEL_HEIGHT)
	end
	local keys, state = {}, {}
	for key, pk in pairs(s.perKey) do
		local st = (pk.bad > 0 and "bad") or (pk.warn > 0 and "warn") or "ok"
		local mode = ns.db.buffDisplay
		if mode == "ALL" or (mode == "MISSING" and pk.bad > 0)
			or (mode == "EXPIRING" and pk.warn > 0) or (mode == "PROBLEMS" and st ~= "ok") then
			keys[#keys + 1] = key
			state[key] = st
		end
	end
	-- Worst first, with the same ordering for every kind of icon.
	table.sort(keys, function(a, b)
		if state[a] ~= state[b] then return PRIORITY[state[a]] < PRIORITY[state[b]] end
		return a < b
	end)
	local iconSize = ns.db.statusIconSize
	local columns, side, left, top, minX, maxX = iconPlacement(#keys, iconSize)
	for i, key in ipairs(keys) do
		local ic = statusIcons[i]
		if not ic then
			ic = CreateFrame("Frame", nil, frame, "BackdropTemplate")
			ic:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			ic.tex = ic:CreateTexture(nil, "ARTWORK")
			ic.tex:SetPoint("TOPLEFT", 1, -1); ic.tex:SetPoint("BOTTOMRIGHT", -1, 1)
			ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			ic.count = ic:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			ic.count:SetPoint("BOTTOMRIGHT", 1, 0)
			ic:EnableMouse(true)
			ic:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(Buffs.byKey[self.key].label)
				local pk = lastSummary and lastSummary.perKey[self.key]
				if pk then
					if pk.bad > 0 then GameTooltip:AddLine(pk.bad .. " missing", unpack(ns.Status.COLORS.bad)) end
					if pk.warn > 0 then GameTooltip:AddLine(pk.warn .. " running low", unpack(ns.Status.COLORS.warn)) end
					if pk.bad + pk.warn == 0 then GameTooltip:AddLine("everyone has it", unpack(ns.Status.COLORS.ok)) end
				end
				GameTooltip:Show()
			end)
			ic:SetScript("OnLeave", GameTooltip_Hide)
			statusIcons[i] = ic
		end
		ic.key = key
		ic:SetSize(iconSize, iconSize)
		ic:ClearAllPoints()
		local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
		local x
		if side == "LEFT" then
			-- Fill outward from the face, including partially filled rows.
			x = left - col * (iconSize + GAP)
		elseif side == "RIGHT" then
			x = left + col * (iconSize + GAP)
		else
			-- Center each row independently as icons appear or disappear.
			local rowCount = math.min(columns, #keys - row * columns)
			local rowWidth = rowCount * (iconSize + GAP) - GAP
			local rowLeft = -rowWidth / 2
			if minX then rowLeft = math.max(minX, math.min(rowLeft, maxX - rowWidth)) end
			x = rowLeft + col * (iconSize + GAP)
		end
		ic:SetPoint("TOPLEFT", castBtn, side,
			x, top - row * (iconSize + GAP))
		local st = state[key]
		local pk = s.perKey[key]
		ic.tex:SetTexture(keyIcon(key))
		ic.tex:SetDesaturated(false)
		ic:SetBackdropBorderColor(unpack(colorOf(st)))
		local n = (ns.db.buffDisplay == "MISSING" and pk.bad)
			or (ns.db.buffDisplay == "EXPIRING" and pk.warn) or (pk.bad + pk.warn)
		ic.count:SetText(n > 0 and n or "")
		ic:Show()
	end
	for i = #keys + 1, #statusIcons do statusIcons[i]:Hide() end
end

-- Secure attributes can only change out of combat.
local function applySecure(s)
	if InCombatLockdown() then return end
	castBtn:SetAttribute("*type1", castBtn.dragged and "" or nil)
	local n = s.next
	if n then
		castBtn:SetAttribute("spell", n.spell)
		castBtn:SetAttribute("unit", n.unit)
		castBtn.pendingWho, castBtn.pendingKey = n.who, n.key
	else
		castBtn:SetAttribute("spell", nil)
		castBtn:SetAttribute("unit", nil)
		castBtn.pendingWho, castBtn.pendingKey = nil, nil
	end
	if s.cancel then
		cancelBtn:SetAttribute("spell", s.cancel)
		cancelBtn:Show()
	else
		cancelBtn:SetAttribute("spell", nil)
		cancelBtn:Hide()
	end
end

function Tracker.Refresh()
	if not frame then return end
	local preview = ns.Preview.active
	if editing then frame:Show() end
	if not editing and not preview and (not ns.db.showTracker or not next(ns.roster.members)) then
		if not InCombatLockdown() then frame:Hide() end
		return
	end
	if not InCombatLockdown() then frame:Show() end
	frame.tag:SetShown(preview and true or false)
	local s = preview and ns.Preview.Summary() or ns.Scan.Update()
	lastSummary = s
	local mood = ns.Status.Mood(s)
	castBtn.icon:SetTexture(MOOD_TEXTURES[mood] or MOOD_TEXTURES.grumpy)
	castBtn.icon:SetDesaturated(mood == "idle")
	layoutStatusIcons(s)

	if InCombatLockdown() then
		castBtn.label:SetText("")
		return
	end
	-- In preview the button never casts anything.
	applySecure(preview and {} or s)
	local n = s.next
	if n then
		castBtn.label:SetText(n.label)
	else
		castBtn.label:SetText("")
	end
end

function Tracker.Summary() return lastSummary end

------------------------------------------------------------------------
-- Blizzard Edit Mode: show + highlight the tracker so it can be moved
-- together with the rest of the HUD.
------------------------------------------------------------------------
-- Same atlas layout as Blizzard's EditModeSystemSelectionBaseMixin. Use only
-- its artwork; the system mixin requires a registered Blizzard HUD system.
local EDIT_SELECTION_LAYOUT = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local function buildEditOverlay()
	local o = CreateFrame("Button", nil, frame)
	o:SetAllPoints()
	o:SetFrameLevel(frame:GetFrameLevel() + 20)
	o.Selection = CreateFrame("Frame", nil, o)
	o.Selection:SetAllPoints()
	o.Selection:SetFrameLevel(o:GetFrameLevel())
	local function selectArtwork(selected)
		NineSliceUtil.ApplyLayout(o.Selection, EDIT_SELECTION_LAYOUT,
			selected and "editmode-actionbar-selected" or "editmode-actionbar-highlight")
	end
	o:SetScript("OnShow", function() selectArtwork(false) end)
	o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	-- The tracker is too narrow for the system name inside the selection.
	o.label:SetPoint("BOTTOM", o, "TOP", 0, 10)
	o.label:SetText(ns.title)
	o:RegisterForDrag("LeftButton")
	o:RegisterForClicks("LeftButtonUp")
	o:SetScript("OnMouseDown", function(self) self.dragged = false end)
	o:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self.dragged = true
		selectArtwork(true)
		startMoving()
	end)
	o:SetScript("OnDragStop", savePos)
	o:SetScript("OnClick", function(self)
		if self.dragged or InCombatLockdown() then return end
		selectArtwork(true)
		ns.Options.Toggle()
	end)
	o:Hide()
	frame.editOverlay = o
end

local function hookEditMode()
	if not (EventRegistry and EventRegistry.RegisterCallback) then return end
	buildEditOverlay()
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		if InCombatLockdown() then return end
		editing = true
		Tracker.Refresh()
		frame.editOverlay:Show()
	end, Tracker)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editing = false
		frame.editOverlay:Hide()
		Tracker.Refresh()
	end, Tracker)
end

function Tracker.Init()
	MAIN = ns.db.iconSize
	build()
	hookEditMode()
	if ns.db.pos then
		frame:ClearAllPoints()
		frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
	end
	ns.Events.On("AssignmentsChanged", Tracker.Refresh)
	ns.Events.On("PreviewChanged", Tracker.Refresh)
	ns.Events.On("TrackerSettingsChanged", Tracker.Refresh)
	frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
	frame:RegisterEvent("UI_SCALE_CHANGED")
	frame:SetScript("OnEvent", Tracker.Refresh)
	C_Timer.NewTicker(1, Tracker.Refresh)
end
