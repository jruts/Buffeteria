-- Buffeteria: the on-screen tracker (status colour + one-click cast button).
local _, ns = ...
local Buffs = ns.Buffs

local Tracker = {}
ns.Tracker = Tracker

local frame, ring, castBtn, cancelBtn, statusIcons, lastSummary
local editing = false
local MAIN = 44                                  -- the big cast button
local GAP = 2
local COLS = 2                                   -- small icons per row under the big one
local ICON_SIZE = (MAIN - GAP * (COLS - 1)) / COLS -- half size, so two fill the width exactly
local BORDER = 2
local ICON_FILE = ns.UI.ICON
local colorOf = ns.Status.Color
local keyIcon = ns.UI.BuffIcon

local function fmtTime(sec)
	if not sec then return "" end
	return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function showTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:AddLine("Buffeteria" .. (ns.Preview.active and " |cffff9900(preview)|r" or ""))
	local s = lastSummary
	if not s or not s.any then
		GameTooltip:AddLine("Nothing on the menu yet.", 0.7, 0.7, 0.7)
	elseif #s.problems == 0 then
		GameTooltip:AddLine("Everyone is stuffed. All buffs up.", unpack(ns.Status.COLORS.ok))
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
	if s and s.next then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Click: %s on %s"):format(s.next.spell, s.next.label), 0.4, 0.8, 1)
	end
	GameTooltip:AddLine("Right-click: options. Move it in Edit Mode, or unlock it in options and drag.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function savePos()
	frame:StopMovingOrSizing()
	local p, _, rp, x, y = frame:GetPoint()
	ns.db.pos = { p, rp, x, y }
end

local function build()
	frame = CreateFrame("Frame", "Buffeteria_Tracker", UIParent)
	frame:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- Coloured ring around the big button = overall status.
	ring = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	ring:SetPoint("TOPLEFT")
	ring:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2)
	ring:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = BORDER })
	ring:SetBackdropColor(0, 0, 0, 0.8)

	-- The big secure cast button.
	castBtn = CreateFrame("Button", "Buffeteria_CastButton", frame, "SecureActionButtonTemplate")
	castBtn:SetSize(MAIN, MAIN)
	castBtn:SetPoint("TOPLEFT", BORDER, -BORDER)
	castBtn:SetFrameLevel(ring:GetFrameLevel() + 2)
	castBtn:RegisterForClicks("AnyUp", "AnyDown")
	castBtn:SetAttribute("type", "spell")
	-- Right-click must never cast: give it an empty macro, open options in PostClick.
	castBtn:SetAttribute("type2", "macro")
	castBtn:SetAttribute("macrotext2", "")
	castBtn.icon = castBtn:CreateTexture(nil, "ARTWORK")
	castBtn.icon:SetAllPoints()
	castBtn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	castBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	castBtn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	castBtn:SetScript("OnEnter", showTooltip)
	castBtn:SetScript("OnLeave", GameTooltip_Hide)
	castBtn:SetScript("PostClick", function(self, button, down)
		if button == "RightButton" then
			if not down and not InCombatLockdown() then ns.Options.Toggle() end
			return
		end
		if self.pendingWho and self.pendingKey then ns.Actions.MarkCast(self.pendingWho, self.pendingKey) end
		C_Timer.After(0.2, Tracker.Refresh)
	end)
	castBtn:RegisterForDrag("LeftButton")
	castBtn:SetScript("OnDragStart", function()
		if not ns.db.locked and not InCombatLockdown() then frame:StartMoving() end
	end)
	castBtn:SetScript("OnDragStop", savePos)

	-- Who it's for, written over the bottom of the big icon (like a macro name).
	castBtn.label = castBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	castBtn.label:SetPoint("BOTTOMLEFT", 1, 2)
	castBtn.label:SetPoint("BOTTOMRIGHT", -1, 2)
	castBtn.label:SetJustifyH("CENTER")
	castBtn.label:SetWordWrap(false)

	-- "PREVIEW" tag above the tracker.
	frame.tag = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
	frame.tag:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	frame.tag:SetText("|cffff9900PREVIEW|r")
	frame.tag:Hide()

	-- Secure "remove unwanted buff from me" button (e.g. Salvation on a tank), top-right corner.
	cancelBtn = CreateFrame("Button", "Buffeteria_CancelButton", frame, "SecureActionButtonTemplate")
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
local function layoutStatusIcons(s)
	local keys, state = {}, {}
	for key, pk in pairs(s.perKey) do
		local st = (pk.bad > 0 and "bad") or (pk.warn > 0 and "warn") or "ok"
		if st ~= "ok" or not ns.db.onlyProblems then
			keys[#keys + 1] = key
			state[key] = st
		end
	end
	-- Worst first, then blessings before the other buffs.
	table.sort(keys, function(a, b)
		if state[a] ~= state[b] then return PRIORITY[state[a]] < PRIORITY[state[b]] end
		local ka, kb = Buffs.byKey[a].kind, Buffs.byKey[b].kind
		if ka ~= kb then return ka == "blessing" end
		return a < b
	end)
	for i, key in ipairs(keys) do
		local ic = statusIcons[i]
		if not ic then
			ic = CreateFrame("Frame", nil, frame, "BackdropTemplate")
			ic:SetSize(ICON_SIZE, ICON_SIZE)
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
		ic:ClearAllPoints()
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		ic:SetPoint("TOPLEFT", frame, "TOPLEFT", BORDER + col * (ICON_SIZE + GAP), -(MAIN + BORDER * 2 + GAP + row * (ICON_SIZE + GAP)))
		local st = state[key]
		local pk = s.perKey[key]
		ic.tex:SetTexture(keyIcon(key))
		ic.tex:SetDesaturated(st == "ok")
		ic:SetBackdropBorderColor(unpack(colorOf(st)))
		local n = pk.bad + pk.warn
		ic.count:SetText(n > 0 and n or "")
		ic:Show()
	end
	for i = #keys + 1, #statusIcons do statusIcons[i]:Hide() end
	-- The frame holds secure buttons, so it can only be resized out of combat.
	if not InCombatLockdown() then
		local rows = math.ceil(#keys / COLS)
		frame:SetHeight(MAIN + BORDER * 2 + (rows > 0 and (GAP + rows * (ICON_SIZE + GAP) - GAP) or 0))
	end
end

-- Secure attributes can only change out of combat.
local function applySecure(s)
	if InCombatLockdown() then return end
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
	ring:SetBackdropBorderColor(unpack(colorOf(s.overall)))
	layoutStatusIcons(s)

	if InCombatLockdown() then
		castBtn.icon:SetDesaturated(true)
		castBtn.label:SetText("")
		return
	end
	-- In preview the button never casts anything.
	applySecure(preview and {} or s)
	local n = s.next
	if n then
		castBtn.icon:SetTexture(n.icon)
		castBtn.icon:SetDesaturated(false)
		castBtn.label:SetText(n.label)
	else
		castBtn.icon:SetTexture(ICON_FILE)
		castBtn.icon:SetDesaturated(false)
		castBtn.label:SetText("")
	end
end

function Tracker.Summary() return lastSummary end

------------------------------------------------------------------------
-- Blizzard Edit Mode: show + highlight the tracker so it can be moved
-- together with the rest of the HUBuffs.
------------------------------------------------------------------------
local function buildEditOverlay()
	local o = CreateFrame("Button", nil, frame)
	o:SetAllPoints()
	o:SetFrameLevel(frame:GetFrameLevel() + 20)
	o.tex = o:CreateTexture(nil, "OVERLAY")
	o.tex:SetAllPoints()
	o.tex:SetColorTexture(0.25, 0.55, 1, 0.35)
	o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	o.label:SetPoint("CENTER")
	o.label:SetText("Buffeteria")
	o:RegisterForDrag("LeftButton")
	o:SetScript("OnDragStart", function() frame:StartMoving() end)
	o:SetScript("OnDragStop", savePos)
	o:SetScript("OnClick", function() ns.Options.Toggle() end)
	o:Hide()
	frame.editOverlay = o
end

local function hookEditMode()
	if not (EventRegistry and EventRegistry.RegisterCallback) then return end
	buildEditOverlay()
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editing = true
		frame:Show()
		frame.editOverlay:Show()
	end, Tracker)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editing = false
		frame.editOverlay:Hide()
		Tracker.Refresh()
	end, Tracker)
end

function Tracker.Init()
	build()
	hookEditMode()
	if ns.db.pos then
		frame:ClearAllPoints()
		frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
	end
	ns.Events.On("AssignmentsChanged", Tracker.Refresh)
	ns.Events.On("PreviewChanged", Tracker.Refresh)
	C_Timer.NewTicker(1, Tracker.Refresh)
end
