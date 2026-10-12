-- Buffeteria: the on-screen mascot + one-click cast button.
local _, ns = ...
local Buffs = ns.Buffs
local Tracker = ns.Tracker
local Status, Layout, Tooltip = Tracker.Status, Tracker.Layout, Tracker.Tooltip
local Art = Tracker.Art

local frame, castBtn, cancelBtn, lastSummary, pulse, shadeTicker, cursorTicker
local statusIcons = {}
local MAIN = 64                                  -- current clickable head size
local GAP = Layout.GAP
local BORDER = 2
local SCREEN_MARGIN = 4
local GLOW_SCALE = 0.625  -- silhouette size within each glow; see tools/make_orc_glow.py
-- Halo tint and strength by mood: a soft orange when annoyed, full red when angry.
local HALO = {
	angry = { 1, 0.12, 0.08, 1 },
	default = { 1, 0.6, 0.12, 0.6 },
}
local OTHERS_ALPHA = 0.5  -- small icons for buffs that are someone else's job
local BADGE_SCALE = 0.18  -- "your part" count size relative to the head
local DONE_SCALE = 0.16   -- the "done" check is a quiet confirmation, not a call to act
local DONE_ALPHA = 0.6
local DONE_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GCD = 1.5           -- assumed global cooldown when the client hides cooldowns
local lastCastAt = -math.huge
-- Per display mode: whether a buff's icon shows, and the count on it.
local DISPLAY = {
	ALL = function(pk) return true, pk.bad + pk.warn end,
	MISSING = function(pk) return pk.bad > 0, pk.bad end,
	EXPIRING = function(pk) return pk.warn > 0, pk.warn end,
	PROBLEMS = function(pk) return pk.bad + pk.warn > 0, pk.bad + pk.warn end,
}

local function editing() return Tracker.EditMode.active end

-- The cooldown holding up the head's cast, as start time and duration (0, 0 when
-- ready). With nothing left to cast, the last cast's cooldown still runs out on
-- the face. Hidden cooldowns in combat fall back to the time since my last cast.
local function cooldown()
	local n = castBtn.pending or castBtn.lastCast
	if not n then return 0, 0 end
	local start, duration = ns.WoW.SpellCooldown(n.spellID or n.spell)
	if start then return start, duration end
	if InCombatLockdown() then return lastCastAt, GCD end
	return 0, 0
end

-- Over the head, show the spell-cast cursor while a press would cast something.
-- Reapplied every frame while hovered, like Blizzard's item buttons do. Only
-- reset the cursor this set, never one another frame asked for.
local function updateCursor()
	local want = castBtn.hovered and not castBtn.inert and not castBtn.dragging
	cursorTicker:SetShown(castBtn.hovered or false)
	if want and SetCursor then
		SetCursor("CAST_CURSOR")
		castBtn.cursorSet = true
	elseif not want and castBtn.cursorSet then
		castBtn.cursorSet = nil
		if ResetCursor then ResetCursor() end
	end
end

-- While the cooldown runs, a shadow drains off the face from the top down, the
-- way action buttons sweep theirs. Pressing the head gives no feedback then, nor
-- when there's nothing to cast.
local function updateShade()
	local start, duration = cooldown()
	local left = duration > 0 and start + duration - GetTime() or 0
	castBtn.inert = (left > 0 or not castBtn.pending) or nil
	updateCursor()
	shadeTicker:SetShown(left > 0)
	castBtn.shade:SetShown(left > 0)
	if left <= 0 then return end
	local covered = math.min(1, left / duration)
	castBtn.shade:SetHeight(castBtn:GetHeight() * covered)
	castBtn.shade:SetTexCoord(0, 1, 1 - covered, 1)
	castBtn.icon:SetVertexColor(1, 1, 1)
end

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
	castBtn.icon:SetTexture(Art.Texture("grumpy"))
	-- "Your turn" cue stays behind the head so facial detail remains crisp.
	castBtn.halo = castBtn:CreateTexture(nil, "BACKGROUND", nil, -8)
	castBtn.halo:SetPoint("CENTER", castBtn, "CENTER", 0, 0)
	castBtn.halo:SetTexture(Art.Glow())
	castBtn.halo:Hide()
	-- Same silhouette as the face, cropped to the part still on cooldown.
	castBtn.shade = castBtn:CreateTexture(nil, "ARTWORK", nil, 1)
	castBtn.shade:SetPoint("BOTTOMLEFT")
	castBtn.shade:SetPoint("BOTTOMRIGHT")
	castBtn.shade:SetVertexColor(0, 0, 0)
	castBtn.shade:SetAlpha(0.65)
	castBtn.shade:Hide()
	-- "Your part" badge in the top-right corner: casts I still owe, or a check
	-- once I've served everyone assigned to me. Separate from the group's mood.
	castBtn.done = castBtn:CreateTexture(nil, "OVERLAY")
	castBtn.done:SetTexture(DONE_TEXTURE)
	castBtn.done:SetAlpha(DONE_ALPHA)
	castBtn.done:Hide()
	castBtn.owed = castBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
	castBtn.owed:SetTextColor(1, 0.82, 0)
	castBtn.owedFont = castBtn.owed.GetFont and castBtn.owed:GetFont()
	castBtn.owed:Hide()
	-- Press feedback belongs to the actual icon, without unrelated slot artwork.
	ns.UI.PressFeedback(castBtn, castBtn.icon, function(self)
		if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
	end)
	castBtn:SetScript("OnEnter", function(self)
		-- After the tooltip: showing it resets the cursor.
		Tooltip.Head(self, lastSummary)
		self.hovered = true
		updateCursor()
	end)
	local leave = castBtn:GetScript("OnLeave")
	castBtn:SetScript("OnLeave", function(self)
		self.hovered = nil
		updateCursor()
		leave(self)
	end)
	-- Hold presses during the global cooldown instead of letting the client
	-- answer each one with "Spell is not ready yet". Combat locks the attributes,
	-- so there the press goes through with its error muted.
	castBtn:SetScript("PreClick", function(self, button, down)
		self.held = nil
		if button ~= "LeftButton" or down or self.dragged or not self.pending then return end
		local start, duration = cooldown()
		if duration == 0 or start + duration <= GetTime() then return end
		if not InCombatLockdown() then
			self:SetAttribute("*type1", "")
			self.held = "masked"
		elseif UIErrorsFrame then
			UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
			self.held = "muted"
		end
	end)
	castBtn:SetScript("PostClick", function(self, button, down)
		local held = self.held
		self.held = nil
		if held == "muted" then UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
		if held == "masked" then
			if not InCombatLockdown() then self:SetAttribute("*type1", nil) end
			return
		end
		if down or self.dragged then return end
		if button == "RightButton" then
			if not InCombatLockdown() then ns.Options.Toggle() end
			return
		end
		-- The cast is marked when it succeeds, so presses lost to the global
		-- cooldown don't skip ahead to the next target.
		self.clickedAt = GetTime()
	end)
	castBtn:RegisterForDrag("LeftButton")
	castBtn:SetScript("OnDragStart", function(self)
		if ns.db.locked or InCombatLockdown() then return end
		self.dragged, self.dragging = true, true
		updateCursor()
		-- Mask the secure action too: PostClick alone cannot prevent a cast.
		self:SetAttribute("*type1", "")
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
		Tracker.StartMoving()
	end)
	castBtn:SetScript("OnDragStop", function(self)
		if not self.dragging then return end
		self.dragging = false
		updateCursor()
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

	-- The mascot's demand on your turn, above the face.
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
		castBtn.halo:SetAlpha(math.min(1, 0.45 + 0.3 * wave + 0.35 * flare) * (pulse.strength or 1))
		local aura = MAIN / GLOW_SCALE * (1 + 0.04 * wave + 0.1 * flare)
		castBtn.halo:SetSize(aura, aura)
	end)
	pulse:Hide()
	shadeTicker = CreateFrame("Frame", nil, frame)
	shadeTicker:SetScript("OnUpdate", updateShade)
	shadeTicker:Hide()
	cursorTicker = CreateFrame("Frame", nil, frame)
	cursorTicker:SetScript("OnUpdate", updateCursor)
	cursorTicker:Hide()
	frame:Hide()
end

-- The "your part" badge: what I still owe, a check once I've served everyone,
-- or nothing when I have no buffs to give. It sits in the head's top-right
-- corner, beside the remove-unwanted-buff button when that is showing.
local function showBadge(s)
	local pending = s.mine and s.mine.pending or 0
	for _, badge in ipairs({ castBtn.done, castBtn.owed }) do
		badge:ClearAllPoints()
		if cancelBtn:IsShown() then
			badge:SetPoint("RIGHT", cancelBtn, "LEFT", -1, 0)
		else
			badge:SetPoint("TOPRIGHT", castBtn, "TOPRIGHT", -2, -2)
		end
	end
	local size = math.max(9, math.floor(MAIN * BADGE_SCALE + 0.5))
	local check = math.max(8, math.floor(MAIN * DONE_SCALE + 0.5))
	castBtn.done:SetSize(check, check)
	castBtn.done:SetShown(Status.MineDone(s))
	if castBtn.owedFont and castBtn.owedSize ~= size then
		castBtn.owed:SetFont(castBtn.owedFont, size, "OUTLINE")
		castBtn.owedSize = size
	end
	castBtn.owed:SetText(pending > 0 and pending or "")
	castBtn.owed:SetShown(pending > 0)
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

-- Show whether clicking does anything for you: a halo and demand on your turn.
-- The head itself is never brightened or faded.
local function showRole(s, mood)
	local n = s.next
	local turn = n ~= nil
	castBtn.icon:SetAlpha(1)
	castBtn.halo:SetTexture(Art.Glow())
	local tint = HALO[mood] or HALO.default
	castBtn.halo:SetVertexColor(tint[1], tint[2], tint[3])
	pulse.strength = tint[4]
	castBtn.halo:SetShown(turn)
	castBtn.halo:SetSize(MAIN / GLOW_SCALE, MAIN / GLOW_SCALE)
	if turn and (not pulse:IsShown() or n.spell ~= pulse.spell or n.label ~= pulse.target) then pulse.popAt = GetTime() end
	if n then pulse.spell, pulse.target = n.spell, n.label end
	pulse:SetShown(turn)
	showShout(turn, n)
end

-- Secure attributes can only change out of combat. The target goes in the
-- left-click "*unit1", never plain "unit": that would make the client treat the
-- head as a unit frame, setting mouseover and fighting the cast cursor.
local function applySecure(s)
	if InCombatLockdown() then return end
	castBtn:SetAttribute("*type1", castBtn.dragged and "" or nil)
	local n = s.next or {}
	castBtn:SetAttribute("spell", n.spell)
	castBtn:SetAttribute("*unit1", n.unit)
	castBtn.pending = s.next
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
	castBtn:SetAttribute("*unit1", n.unit)
	castBtn.pending = n
	updateShade()
end

-- One of my casts succeeded. The button's cast (its spell right after a click;
-- a hidden spell ID counts) covers its recipients at once, and combat self buffs
-- stay current while the client hides auras. Then move on to the next cast.
local function onCast(spellID)
	local now, n = GetTime(), castBtn.pending
	lastCastAt = now
	local hidden = issecretvalue and issecretvalue(spellID)
	local fromButton = n and now - (castBtn.clickedAt or 0) < 1 and (hidden or spellID == n.spellID)
	if fromButton then
		Tracker.Actions.MarkCast(n)
		castBtn.lastCast = n
	end
	local key = Tracker.Scan.SelfBuffKey(spellID)
	if not key and fromButton and hidden and Buffs.byKey[n.key].combat then key = n.key end
	if key then Tracker.Scan.SelfCast(key, now) end
	if fromButton or key then Tracker.Refresh() end
	updateShade()
end

-- Coalesce bursts of aura changes into one refresh shortly after.
local refreshQueued = false
function Tracker.RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.2, function() refreshQueued = false; Tracker.Refresh() end)
end

local function groupUnit(unit)
	if type(unit) ~= "string" then return false end
	return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

-- The full summary: the observed group, my next cast, and what to cancel on me.
function Tracker.Compute()
	if Tracker.Preview.active then return Tracker.Preview.Summary() end
	local now, warnSec = GetTime(), ns.db.warnMinutes * 60
	local s = Tracker.Scan.Update(now, warnSec)
	local combat = InCombatLockdown()
	s.next = Tracker.Actions.Next(now, warnSec, Tracker.Scan.MissingAura(), combat, ns.db.helpOthers)
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
	local face = Art.Texture(mood)
	castBtn.icon:SetTexture(face)
	castBtn.shade:SetTexture(face)
	castBtn.icon:SetDesaturated(mood == "idle")
	showRole(s, mood)
	layoutStatusIcons(s)
	-- In preview the button never casts anything.
	applySecure(preview and {} or s)
	showBadge(s)
	updateShade()
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
	frame:RegisterEvent("UNIT_AURA")
	frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if unit == "player" then onCast(spellID) end
			return
		end
		if event == "SPELL_UPDATE_COOLDOWN" then updateShade(); return end
		-- React when someone gains or loses a buff, e.g. another caster served
		-- my group. Combat hides the auras, so the ticker covers it then.
		if event == "UNIT_AURA" then
			if not InCombatLockdown() and groupUnit(unit) then Tracker.RequestRefresh() end
			return
		end
		Tracker.Refresh()
		-- After the refresh, which would otherwise reset the button's attributes.
		if event == "PLAYER_REGEN_DISABLED" then armForCombat() end
	end)
	C_Timer.NewTicker(1, Tracker.Refresh)
end
