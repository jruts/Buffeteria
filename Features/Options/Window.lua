-- Host the feature panels in /buff and Blizzard Settings.
local _, ns = ...
local Options = {}
ns.Options = Options
local win, content, panel
-- The /buff window matches the native talent panel: three trees side by side.
local WIDTH, HEIGHT, CONTENT_H = 652, 528, 498
-- Tabs in order; Paladins only exists for paladins.
local TABS = {
	{ key = "PERSONAL", label = "My preferences", view = function() return ns.Preferences.View end },
	{ key = "PALADIN", label = "Paladins", view = function() return ns.Paladins.View end, paladinOnly = true },
	{ key = "SETTINGS", label = "Settings", view = function() return ns.Tracker.View end },
}

local function visibleTabs()
	local out, paladin = {}, ns.WoW.PlayerClass() == "PALADIN"
	for _, tab in ipairs(TABS) do
		if paladin or not tab.paladinOnly then out[#out + 1] = tab end
	end
	return out
end

local function layout()
	local inWindow = content:GetParent() == win
	local width = inWindow and WIDTH or math.max(WIDTH - 40, panel:GetWidth() - 32)
	content:SetWidth(width)
	-- Leave room for the window's portrait; Settings has none.
	local previous
	for _, tab in ipairs(visibleTabs()) do
		tab.button:ClearAllPoints()
		if previous then tab.button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		else tab.button:SetPoint("TOPLEFT", inWindow and 64 or 16, -4) end
		previous = tab.button
	end
	for _, tab in ipairs(TABS) do tab.view().Layout(width) end
end

local function showTab(selected)
	if selected == "PALADIN" and ns.WoW.PlayerClass() ~= "PALADIN" then selected = "PERSONAL" end
	for _, tab in ipairs(TABS) do
		local on = tab.key == selected
		tab.panel:SetShown(on)
		tab.button:SetChecked(on)
		tab.button:SetEnabled(not on)
	end
end

function Options.Refresh()
	if not content then return end
	for _, tab in ipairs(TABS) do tab.view().Refresh() end
	layout()
end

-- Show the shared controls in a host: this window or the Settings page.
local function attach(host, top)
	content:SetParent(host); content:ClearAllPoints(); content:SetPoint("TOPLEFT", 0, top); content:Show()
	Options.Refresh()
end

local function build()
	win = CreateFrame("Frame", ns.globalPrefix .. "_Prefs", UIParent, "PortraitFrameTemplate")
	win:SetSize(WIDTH, HEIGHT)
	win:SetPoint("CENTER")
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, ns.globalPrefix .. "_Prefs")
	win:SetTitle(ns.title)
	win:SetPortraitToAsset(ns.UI.ICON)
	win.CloseButton = win.CloseButton or CreateFrame("Button", nil, win, "UIPanelCloseButton")
	win.CloseButton:SetScript("OnClick", function() win:Hide() end)

	-- All controls live on "content", which moves between this window and the
	-- Settings > AddOns page (whichever is showing).
	content = CreateFrame("Frame", nil, win)
	content:SetSize(WIDTH, CONTENT_H)
	content:SetPoint("TOPLEFT", 0, -26)
	local paladin = ns.WoW.PlayerClass() == "PALADIN"
	for _, tab in ipairs(TABS) do
		-- Talent-panel style top tab ("Primary" / "Secondary").
		tab.button = ns.UI.Chip(content, tab.label, 150, function() showTab(tab.key); Options.Refresh() end, "GameFontNormal")
		tab.button:SetShown(paladin or not tab.paladinOnly)
	end
	for _, tab in ipairs(TABS) do tab.panel = tab.view().Create(content) end
	showTab("PERSONAL")
	win:SetScript("OnShow", function() attach(win, -26) end)
	win:Hide()

	local function refreshVisible()
		if content:IsVisible() then Options.Refresh() end
	end
	for _, event in ipairs({ "AssignmentsChanged", "PaladinPlanChanged", "PreviewChanged", "SettingsChanged" }) do
		ns.Events.On(event, refreshVisible)
	end
	win:RegisterEvent("DISPLAY_SIZE_CHANGED")
	win:RegisterEvent("UI_SCALE_CHANGED")
	win:SetScript("OnEvent", refreshVisible)
end

function Options.Toggle()
	if not win then build() end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then HideUIPanel(SettingsPanel) end
	win:SetShown(not win:IsShown())
end

-- Esc > Options > AddOns > Buffeteria (same controls as the /buff window).
function Options.RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	panel = CreateFrame("Frame")
	panel.name = ns.title
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.title)
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("The raid buff buffet. Unlimited refills.")
	panel:SetScript("OnShow", function()
		if not win then build() end
		win:Hide()
		attach(panel, -56)
	end)
	panel:SetScript("OnSizeChanged", function()
		if content and content:GetParent() == panel then layout() end
	end)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, ns.title)
	if ok and category then
		Settings.RegisterAddOnCategory(category)
		Options.category = category
	end
end

function Options.OpenSettings()
	if Options.category and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.category:GetID())
	else
		Options.Toggle()
	end
end
