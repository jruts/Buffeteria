-- Buffeteria: minimap button (no libraries needed).
local _, ns = ...

local MinimapButton = {}
ns.Minimap = MinimapButton

local btn
local ICON = ns.UI.ICON
local RADIUS_PAD = 10

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

local function statusColor()
	local s = ns.Tracker.Summary()
	return ns.Status.Color(s and s.overall), s
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.title)
	local c, s = statusColor()
	local text = ({ ok = "Everyone is fed.", warn = "Buffs running low.", bad = "Buffs missing!", idle = "Nothing to track." })[(s and s.overall) or "idle"]
	GameTooltip:AddLine(text, c[1], c[2], c[3])
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
	local c = statusColor()
	btn.ring:SetVertexColor(c[1], c[2], c[3])
end

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
	btn.icon:SetTexture(ICON)
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

	btn:SetScript("OnMouseDown", function(self)
		self.dragged = false
		self.icon:SetVertexColor(0.75, 0.75, 0.75)
	end)
	btn:SetScript("OnMouseUp", function(self) self.icon:SetVertexColor(1, 1, 1) end)
	btn:SetScript("OnClick", function(self, button)
		if self.dragged then return end
		if IsShiftKeyDown() then ns.Assignments.Announce()
		elseif button == "RightButton" then
			ns.db.showTracker = not ns.db.showTracker
			ns.Tracker.Refresh()
		else
			ns.Options.Toggle()
		end
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
	btn:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip_Hide()
	end)

	place()
	MinimapButton.Refresh()
	ns.Events.On("PreviewChanged", MinimapButton.Refresh)
	C_Timer.NewTicker(2, MinimapButton.Refresh)
end
