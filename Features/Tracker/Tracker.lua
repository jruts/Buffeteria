-- Buffeteria: the on-screen orc mascot + one-click cast button.
local _, ns = ...
local Buffs = ns.Buffs
local Tracker = ns.Tracker
local Status, Layout, Tooltip = Tracker.Status, Tracker.Layout, Tracker.Tooltip

local frame, castBtn, cancelBtn, lastSummary, pulse
local statusIcons = {}
local MAIN = 64                                  -- current clickable head size
local GAP = Layout.GAP
local BORDER = 2
local SCREEN_MARGIN = 4
local GLOW_SCALE = 0.625  -- silhouette size within OrcGlow; see tools/make_orc_glow.py
local OTHERS_ALPHA = 0.5  -- small icons for buffs that are someone else's job
local MOOD_TEXTURES = {
	happy = ns.mediaPath .. "OrcHappy",
	grumpy = ns.mediaPath .. "OrcGrumpy",
	angry = ns.mediaPath .. "OrcAngry",
}
-- Per display mode: whether a buff's icon shows, and the count on it.
local DISPLAY = {
	ALL = function(pk) return true, pk.bad + pk.warn end,
	MISSING = function(pk) return pk.bad > 0, pk.bad end,
	EXPIRING = function(pk) return pk.warn > 0, pk.warn end,
	PROBLEMS = function(pk) return pk.bad + pk.warn > 0, pk.bad + pk.warn end,
}

local function editing() return Tracker.EditMode.active end

-- Room above the face for the GIEF call-out, the DEV/preview tag and Edit Mode's label.
local function topGap()
	local gap = (ns.isDev or Tracker.Preview.active or editing()) and 24 or GAP
	if frame.gief:IsShown() then gap = gap + ns.db.shoutSize + 2 end
	return gap
end

-- Inputs for Layout.Grid, with bounds converted to the head's coordinate scale.
local function placement()
	local o = { columns = ns.db.iconsPerRow, side = ns.db.iconPosition, iconSize = ns.db.statusIconSize,
		sideGap = BORDER + GAP, belowGap = BORDER + GAP, aboveGap = topGap() }
	local left, bottom, top = castBtn:GetLeft(), castBtn:GetBottom(), castBtn:GetTop()
	if left and bottom and top then
		local scale = UIParent:GetEffectiveScale() / castBtn:GetEffectiveScale()
		local screenLeft = (UIParent:GetLeft() or 0) * scale + SCREEN_MARGIN
		local screenBottom = (UIParent:GetBottom() or 0) * scale + SCREEN_MARGIN
		o.head = { left = left, bottom = bottom, top = top, width = castBtn:GetWidth() }
		o.screen = { left = screenLeft, bottom = screenBottom,
			right = screenLeft + UIParent:GetWidth() * scale - SCREEN_MARGIN * 2,
			top = screenBottom + UIParent:GetHeight() * scale - SCREEN_MARGIN * 2 }
	end
	return o
end

local function statusIcon(i)
	local ic = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	ic:SetBackdrop({ edgeFile = ns.UI.WHITE, edgeSize = 1 })
	ic.tex = ic:CreateTexture(nil, "ARTWORK")
	ic.tex:SetPoint("TOPLEFT", 1, -1); ic.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ic.tex:SetDesaturated(false)
	ic.count = ic:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	ic.count:SetPoint("BOTTOMRIGHT", 1, 0)
	ic:EnableMouse(true)
	ic:SetScript("OnEnter", function(self) Tooltip.Icon(self, self.key, lastSummary) end)
	ic:SetScript("OnLeave", GameTooltip_Hide)
	statusIcons[i] = ic
	return ic
end

-- Keep the head's frame independent of the number of rows. A center- or
-- bottom-anchored frame otherwise moves its top whenever its height changes.
-- Secure descendants also mean size changes must wait until out of combat.
local function resizeHead()
	if InCombatLockdown() or MAIN == ns.db.iconSize then return end
	MAIN = ns.db.iconSize
	castBtn:SetSize(MAIN, MAIN)
	frame:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2)
end

local function layoutStatusIcons(s)
	resizeHead()
	local shows = DISPLAY[ns.db.buffDisplay]
	local keys, state = {}, {}
	for key, pk in pairs(s.perKey) do
		if shows(pk) then
			keys[#keys + 1] = key
			state[key] = (pk.bad > 0 and "bad") or (pk.warn > 0 and "warn") or "ok"
		end
	end
	-- Worst first, with the same ordering for every kind of icon.
	table.sort(keys, function(a, b)
		if state[a] ~= state[b] then return Status.PRIORITY[state[a]] < Status.PRIORITY[state[b]] end
		return a < b
	end)
	-- Full strength for buffs you cast or are missing yourself; others are dimmed.
	local relevant = {}
	for key in pairs(s.yours or {}) do relevant[key] = true end
	for _, need in ipairs(s.needs or {}) do relevant[need.key] = true end
	local size = ns.db.statusIconSize
	local grid = Layout.Grid(#keys, placement())
	for i, key in ipairs(keys) do
		local ic = statusIcons[i] or statusIcon(i)
		local _, count = shows(s.perKey[key])
		ic.key = key
		ic:SetSize(size, size)
		ic:ClearAllPoints()
		ic:SetPoint("TOPLEFT", castBtn, grid.side, Layout.Offset(i, #keys, size, grid))
		ic.tex:SetTexture(ns.UI.BuffIcon(key))
		ic:SetAlpha((relevant[key] or state[key] == "ok") and 1 or OTHERS_ALPHA)
		ic:SetBackdropBorderColor(unpack(Status.Color(state[key])))
		ic.count:SetText(count > 0 and count or "")
		ic:Show()
	end
	for i = #keys + 1, #statusIcons do statusIcons[i]:Hide() end
end

function Tracker.StartMoving()
	frame:StartMoving()
	-- Reposition Auto during dragging without rescanning or changing the head.
	frame:SetScript("OnUpdate", function()
		if ns.db.iconPosition == "AUTO" and lastSummary then layoutStatusIcons(lastSummary) end
	end)
end

-- Finish a drag and save where the tracker landed.
function Tracker.StopMoving()
	frame:StopMovingOrSizing()
	frame:SetScript("OnUpdate", nil)
	local p, _, rp, x, y = frame:GetPoint()
	ns.db.pos = { p, rp, x, y }
	Tracker.Refresh()
end

local function buildCastButton()
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
	-- The alpha silhouette supplies the shape; no square background or highlight.
	castBtn.icon = castBtn:CreateTexture(nil, "ARTWORK")
	castBtn.icon:SetAllPoints()
	castBtn.icon:SetTexture(MOOD_TEXTURES.grumpy)
	-- "Your turn" cue: a soft gold glow around the silhouette (Media/OrcGlow,
	-- built by tools/make_orc_glow.py) and a faint shimmer on the face.
	castBtn.halo = castBtn:CreateTexture(nil, "BACKGROUND", nil, -8)
	castBtn.halo:SetPoint("CENTER", castBtn, "CENTER", 0, 0)
	castBtn.halo:SetTexture(ns.mediaPath .. "OrcGlow")
	castBtn.halo:SetVertexColor(1, 0.78, 0.15)
	castBtn.halo:Hide()
	castBtn.glow = castBtn:CreateTexture(nil, "OVERLAY")
	castBtn.glow:SetAllPoints(castBtn.icon)
	castBtn.glow:SetTexture(MOOD_TEXTURES.grumpy)
	castBtn.glow:SetBlendMode("ADD")
	castBtn.glow:Hide()
	-- Press feedback belongs to the actual icon, without unrelated slot artwork.
	ns.UI.PressFeedback(castBtn, castBtn.icon, function(self)
		if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
	end)
	castBtn:SetScript("OnEnter", function(self) Tooltip.Head(self, lastSummary) end)
	castBtn:SetScript("PostClick", function(self, button, down)
		if down or self.dragged then return end
		if button == "RightButton" then
			if not InCombatLockdown() then ns.Options.Toggle() end
			return
		end
		if self.pendingWho and self.pendingKey then Tracker.Actions.MarkCast(self.pendingWho, self.pendingKey) end
		self.clickedAt = GetTime()
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
		Tracker.StartMoving()
	end)
	castBtn:SetScript("OnDragStop", function(self)
		if not self.dragging then return end
		self.dragging = false
		Tracker.StopMoving()
		self.icon:SetVertexColor(1, 1, 1)
		-- Keep the release suppressed through this input event. Restore on the
		-- next frame even if the client doesn't send a click after the drag.
		C_Timer.After(0, function()
			if self.dragging then return end
			self.dragged = false
			if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
		end)
	end)
end

-- Secure "remove unwanted buff from me" button (e.g. Salvation on a tank), top-right corner.
local function buildCancelButton()
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
end

local function build()
	frame = CreateFrame("Frame", ns.globalPrefix .. "_Tracker", UIParent)
	frame:SetSize(MAIN + BORDER * 2, MAIN + BORDER * 2)
	-- Keep a fresh Dev tracker distinct from the release's starting position.
	frame:SetPoint("CENTER", UIParent, "CENTER", ns.isDev and 140 or 0, -180)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	buildCastButton()
	buildCancelButton()

	-- Always identify the development copy, even when preview is off.
	frame.tag = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
	frame.tag:Hide()

	-- The orc's demand on your turn, above the face.
	frame.gief = frame:CreateFontString(nil, "OVERLAY",
		_G.GameFontNormalLargeOutline and "GameFontNormalLargeOutline" or "GameFontNormalLarge")
	frame.gief:SetPoint("BOTTOM", castBtn, "TOP", 0, 3)
	frame.gief:SetWordWrap(false)
	frame.giefFont = frame.gief.GetFont and frame.gief:GetFont()
	frame.gief:Hide()

	-- Separate from the tracker frame, whose OnUpdate is used while dragging.
	pulse = CreateFrame("Frame", nil, frame)
	pulse:SetScript("OnUpdate", function()
		local now = GetTime()
		local wave = 0.5 + 0.5 * math.sin(now * 4)
		-- Flare up when the spell or target changes, then settle into breathing.
		local flare = 1 - math.min(1, (now - (pulse.popAt or 0)) / 0.5)
		castBtn.glow:SetAlpha(0.03 + 0.1 * wave + 0.25 * flare)
		castBtn.halo:SetAlpha(math.min(1, 0.45 + 0.3 * wave + 0.35 * flare))
		local aura = MAIN / GLOW_SCALE * (1 + 0.04 * wave + 0.1 * flare)
		castBtn.halo:SetSize(aura, aura)
	end)
	pulse:Hide()
	frame:Hide()
end

-- The GIEF call-out on your turn, and the DEV/preview tag above it.
local function showShout(turn, n)
	if frame.giefFont and frame.giefSize ~= ns.db.shoutSize then
		frame.gief:SetFont(frame.giefFont, ns.db.shoutSize, "OUTLINE")
		frame.giefSize = ns.db.shoutSize
	end
	frame.gief:SetShown(turn and not editing())
	if n then
		local buff = n.key and Buffs.byKey[n.key]
		frame.gief:SetText("GIEF " .. (buff and buff.label or n.spell) .. "!")
	end
	local preview = Tracker.Preview.active
	frame.tag:SetText(ns.isDev and (preview and "|cffff9900DEV / PREVIEW|r" or "|cffff9900DEV|r") or "|cffff9900PREVIEW|r")
	-- Edit Mode already displays the full add-on name above this same head.
	frame.tag:SetShown((ns.isDev and not editing()) or (not ns.isDev and preview))
	frame.tag:ClearAllPoints()
	if frame.gief:IsShown() then
		frame.tag:SetPoint("BOTTOM", frame.gief, "TOP", 0, 1)
	else
		frame.tag:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	end
end

-- Show whether clicking does anything for you: a glowing head demanding the
-- buff on your turn. The head itself is never faded.
local function showRole(s, face)
	local n = s.next
	local turn = n ~= nil
	castBtn.icon:SetAlpha(1)
	castBtn.glow:SetTexture(face)
	castBtn.glow:SetShown(turn)
	castBtn.halo:SetShown(turn)
	castBtn.halo:SetSize(MAIN / GLOW_SCALE, MAIN / GLOW_SCALE)
	if turn and (not pulse:IsShown() or n.spell ~= pulse.spell or n.label ~= pulse.target) then pulse.popAt = GetTime() end
	if n then pulse.spell, pulse.target = n.spell, n.label end
	pulse:SetShown(turn)
	showShout(turn, n)
end

-- Secure attributes can only change out of combat.
local function applySecure(s)
	if InCombatLockdown() then return end
	castBtn:SetAttribute("*type1", castBtn.dragged and "" or nil)
	local n = s.next or {}
	castBtn:SetAttribute("spell", n.spell)
	castBtn:SetAttribute("unit", n.unit)
	castBtn.pendingWho, castBtn.pendingKey = n.who, n.key
	cancelBtn:SetAttribute("spell", s.cancel)
	cancelBtn:SetShown(s.cancel ~= nil)
end

-- PLAYER_REGEN_DISABLED arrives just before combat lockdown: hold my combat self
-- buff on the button so it can be recast if it falls off mid-fight.
local function armForCombat()
	if InCombatLockdown() or Tracker.Preview.active or castBtn.dragged then return end
	local n = Tracker.Actions.CombatBuff()
	if not n then return end
	castBtn:SetAttribute("*type1", nil)
	castBtn:SetAttribute("spell", n.spell)
	castBtn:SetAttribute("unit", n.unit)
	castBtn.pendingWho, castBtn.pendingKey = n.who, n.key
end

-- My own casts keep combat self buffs current while the client hides auras.
-- A hidden spell ID counts as the button's buff right after a click.
local function selfCast(spellID)
	local now = GetTime()
	local key = Tracker.Scan.SelfBuffKey(spellID)
	if not key and issecretvalue and issecretvalue(spellID) and now - (castBtn.clickedAt or 0) < 1 then
		key = castBtn.pendingKey and Buffs.byKey[castBtn.pendingKey].combat and castBtn.pendingKey
	end
	if not key then return end
	Tracker.Scan.SelfCast(key, now)
	Tracker.Refresh()
end

-- The full summary: the observed group, my next cast, and what to cancel on me.
function Tracker.Compute()
	if Tracker.Preview.active then return Tracker.Preview.Summary() end
	local now, warnSec = GetTime(), ns.db.warnMinutes * 60
	local s = Tracker.Scan.Update(now, warnSec)
	local combat = InCombatLockdown()
	s.next = Tracker.Actions.Next(now, warnSec, Tracker.Scan.MissingAura(), combat)
	-- In combat the button casts only what it was armed with as combat began.
	if combat and s.next and s.next.spell ~= castBtn:GetAttribute("spell") then s.next = nil end
	s.cancel = Tracker.Scan.UnwantedOnMe()
	return s
end

function Tracker.Refresh()
	if not frame then return end
	local preview = Tracker.Preview.active
	if not editing() and not preview and (not ns.db.showTracker or not next(ns.Assignments.roster.members)) then
		if not InCombatLockdown() then frame:Hide() end
		return
	end
	if editing() or not InCombatLockdown() then frame:Show() end
	local s = Tracker.Compute()
	lastSummary = s
	local mood = Status.Mood(s)
	local face = MOOD_TEXTURES[mood] or MOOD_TEXTURES.grumpy
	castBtn.icon:SetTexture(face)
	castBtn.icon:SetDesaturated(mood == "idle")
	showRole(s, face)
	layoutStatusIcons(s)
	-- In preview the button never casts anything.
	applySecure(preview and {} or s)
	ns.Events.Emit("SummaryChanged")
end

function Tracker.Summary() return lastSummary end

function Tracker.Init()
	MAIN = ns.db.iconSize
	build()
	Tracker.EditMode.Attach(frame)
	if ns.db.pos then
		frame:ClearAllPoints()
		frame:SetPoint(ns.db.pos[1], UIParent, ns.db.pos[2], ns.db.pos[3], ns.db.pos[4])
	end
	for _, event in ipairs({ "AssignmentsChanged", "PreviewChanged", "SettingsChanged" }) do
		ns.Events.On(event, Tracker.Refresh)
	end
	frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
	frame:RegisterEvent("UI_SCALE_CHANGED")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if unit == "player" then selfCast(spellID) end
			return
		end
		Tracker.Refresh()
		-- After the refresh, which would otherwise reset the button's attributes.
		if event == "PLAYER_REGEN_DISABLED" then armForCombat() end
	end)
	C_Timer.NewTicker(1, Tracker.Refresh)
end
