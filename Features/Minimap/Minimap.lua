-- Buffeteria: minimap button (no libraries needed).
local _, ns = ...

local MinimapButton = {}
ns.Minimap = MinimapButton

local btn
local RADIUS_PAD = 10
local MOOD_TEXT = { ok = "Your buffs are served.", warn = "Your buffs are running low.", bad = "Your buffs need attention!", idle = "Nothing to track." }

local function place()
	local angle = math.rad(ns.db.minimap.angle or 200)
	local w, h = Minimap:GetWidth() / 2 + RADIUS_PAD, Minimap:GetHeight() / 2 + RADIUS_PAD
	local x, y = math.cos(angle), math.sin(angle)
	-- Square minimaps: push the button out to the corners.
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m, y / m
	end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	ns.db.minimap.angle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx)) % 360
	place()
end

-- The tracker's overall status, its color, and the summary.
local function status()
	local s = ns.Tracker.Summary()
	local overall = s and s.overall or "idle"
	return overall, ns.Tracker.Status.Color(overall), s
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.title)
	local overall, c, s = status()
	GameTooltip:AddLine(MOOD_TEXT[overall] or MOOD_TEXT.idle, c[1], c[2], c[3])
	if s and s.next then GameTooltip:AddLine(("Next: %s on %s"):format(s.next.spell, s.next.label), 0.4, 0.8, 1) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffffffLeft-click|r: options", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffffffRight-click|r: show/hide tracker", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffffffShift-click|r: announce assignments", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("|cffffffffDrag|r: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function MinimapButton.Refresh()
	if not btn then return end
	btn:SetShown(not ns.db.minimap.hide)
	local _, c = status()
	btn.ring:SetVertexColor(c[1], c[2], c[3])
end

function MinimapButton.SetShown(shown)
	local minimap = ns.db.minimap
	minimap.hide = not shown
	ns.Database.Set("minimap", minimap)
end

function MinimapButton.Toggle() MinimapButton.SetShown(ns.db.minimap.hide) end

function MinimapButton.Init()
	btn = CreateFrame("Button", ns.globalPrefix .. "_MinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(17, 17)
	btn.icon:SetTexture(ns.UI.ICON)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon:SetPoint("TOPLEFT", 7, -6)

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	-- Small status dot (green/orange/red) on the lower-right of the button.
	local dotBorder = btn:CreateTexture(nil, "OVERLAY", nil, 2)
	dotBorder:SetSize(11, 11)
	dotBorder:SetPoint("CENTER", btn, "BOTTOMRIGHT", -8, 8)
	dotBorder:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	dotBorder:SetVertexColor(0, 0, 0, 1)
	btn.ring = btn:CreateTexture(nil, "OVERLAY", nil, 3)
	btn.ring:SetSize(8, 8)
	btn.ring:SetPoint("CENTER", dotBorder, "CENTER")
	btn.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")

	ns.UI.PressFeedback(btn, btn.icon)
	btn:SetScript("OnClick", function(self, button)
		if self.dragged then return end
		if IsShiftKeyDown() then ns.Assignments.Announce()
		elseif button == "RightButton" then ns.Database.Set("showTracker", not ns.db.showTracker)
		else ns.Options.Toggle() end
	end)
	btn:SetScript("OnDragStart", function(self)
		self.dragged = true
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self.icon:SetVertexColor(1, 1, 1)
	end)
	btn:SetScript("OnEnter", showTooltip)

	place()
	MinimapButton.Refresh()
	-- The tracker announces each new summary; no polling needed.
	ns.Events.On("SummaryChanged", MinimapButton.Refresh)
	ns.Events.On("SettingsChanged", MinimapButton.Refresh)
end
