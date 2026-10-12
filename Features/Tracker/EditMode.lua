-- Blizzard Edit Mode: show and highlight the tracker so it can be moved
-- together with the rest of the HUD.
local _, ns = ...
local Tracker = ns.Tracker
local EditMode = { active = false }
Tracker.EditMode = EditMode

-- Same atlas layout as Blizzard's EditModeSystemSelectionBaseMixin. Use only
-- its artwork; the system mixin requires a registered Blizzard HUD system.
local SELECTION_LAYOUT = {
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

local function buildOverlay(frame)
	local o = CreateFrame("Button", nil, frame)
	o:SetAllPoints()
	o:SetFrameLevel(frame:GetFrameLevel() + 20)
	o.Selection = CreateFrame("Frame", nil, o)
	o.Selection:SetAllPoints()
	o.Selection:SetFrameLevel(o:GetFrameLevel())
	local function selectArtwork(selected)
		NineSliceUtil.ApplyLayout(o.Selection, SELECTION_LAYOUT,
			selected and "editmode-actionbar-selected" or "editmode-actionbar-highlight")
	end
	o:SetScript("OnShow", function() selectArtwork(false) end)
	o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	-- The tracker is too narrow for the system name inside the selection.
	o.label:SetPoint("BOTTOM", o, "TOP", 0, 10)
	o.label:SetText(ns.title)
	o:RegisterForDrag("LeftButton")
	o:RegisterForClicks("LeftButtonUp")
	ns.UI.PressFeedback(o)
	o:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self.dragged = true
		selectArtwork(true)
		Tracker.StartMoving()
	end)
	o:SetScript("OnDragStop", function() Tracker.StopMoving() end)
	o:SetScript("OnClick", function(self)
		if self.dragged or InCombatLockdown() then return end
		selectArtwork(true)
		ns.Options.Toggle()
	end)
	o:Hide()
	return o
end

function EditMode.Attach(frame)
	if not (EventRegistry and EventRegistry.RegisterCallback) then return end
	local overlay = buildOverlay(frame)
	frame.editOverlay = overlay
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		if InCombatLockdown() then return end
		EditMode.active = true
		Tracker.Refresh()
		overlay:Show()
	end, EditMode)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		EditMode.active = false
		overlay:Hide()
		Tracker.Refresh()
	end, EditMode)
end
