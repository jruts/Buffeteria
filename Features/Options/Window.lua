-- Host the feature panels in /buff and Blizzard Settings.
local _, ns = ...
local Options = {}
ns.Options = Options
local win, content, panel
-- More room for named controls and five paladins; scale to either native host.
local WIDTH, HEIGHT, CONTENT_H = 900, 714, 646
local HEADER_H, TAB_BAR_H = 30, 40
local FOOTER_H = 38
local footer, channel
-- Tabs in order; Paladins only exists for paladins. Each view fills a panel below the tab bar.
local TABS = {
	{ key = "PERSONAL", label = "My preferences", view = ns.Preferences.View },
	{ key = "PALADIN", label = "Paladins", view = ns.Paladins.View, paladinOnly = true },
	{ key = "SETTINGS", label = "Settings", view = ns.Tracker.View },
	{ key = "EXTRA", label = "Extra", view = ns.Extra.View },
}

local function visibleTabs()
	local out, paladin = {}, ns.WoW.IsPaladin()
	for _, tab in ipairs(TABS) do
		if paladin or not tab.paladinOnly then out[#out + 1] = tab end
	end
	return out
end

local function layout()
	local inWindow = content:GetParent() == win
	local width = inWindow and WIDTH or math.max(820, panel:GetWidth() - 32)
	for _, tab in ipairs(TABS) do tab.view.Layout(width) end
	local height = CONTENT_H
	content:SetSize(width, height)
	if inWindow then
		content:SetScale(1)
		win:SetHeight(height + HEADER_H + 12)
		win:SetScale(math.min(1, (UIParent:GetWidth() - 24) / WIDTH, (UIParent:GetHeight() - 24) / win:GetHeight()))
	else
		content:SetScale(math.max(0.05, math.min(1, (panel:GetWidth() - 32) / width,
			(panel:GetHeight() - 72) / height)))
	end
	-- Leave room for the window's portrait; Settings has none.
	local previous
	for _, tab in ipairs(visibleTabs()) do
		tab.button:ClearAllPoints()
		if previous then tab.button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		else tab.button:SetPoint("BOTTOMLEFT", content, "TOPLEFT", inWindow and 64 or 16, -32) end
		previous = tab.button
	end
end

local function showTab(selected)
	local known
	for _, tab in ipairs(TABS) do known = known or tab.key == selected end
	if not known then selected = "PERSONAL" end
	if selected == "PALADIN" and not ns.WoW.IsPaladin() then selected = "PERSONAL" end
	ns.db.optionsTab = selected
	for _, tab in ipairs(TABS) do
		local on = tab.key == selected
		tab.panel:SetShown(on)
		tab.button:SetChecked(on)
		tab.button:SetEnabled(not on)
	end
end

function Options.Refresh()
	if not content then return end
	-- Position navigation and size the preview before any feature paints it.
	layout()
	for _, tab in ipairs(TABS) do tab.view.Refresh() end
	channel:SetText("Channel: " .. (IsInRaid() and "Raid" or IsInGroup() and "Party" or "Local chat"))
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
	content:SetFrameLevel(win:GetFrameLevel() + 5)
	content:SetPoint("TOPLEFT", 0, -HEADER_H)
	local paladin = ns.WoW.IsPaladin()
	for _, tab in ipairs(TABS) do
		tab.button = ns.UI.Tab(content, tab.label, 140, function() showTab(tab.key); Options.Refresh() end)
		tab.button:SetFrameLevel(content:GetFrameLevel() + 10)
		tab.button:SetShown(paladin or not tab.paladinOnly)
	end
	-- The gold baseline the tabs stand on; the active tab opens through it.
	local baseline = ns.UI.Line(content, 0.75, 0.6, 0.3, 0.6, false, "BORDER")
	baseline:SetPoint("TOPLEFT", 12, -32); baseline:SetPoint("TOPRIGHT", -12, -32)
	for _, tab in ipairs(TABS) do
		tab.panel = CreateFrame("Frame", nil, content)
		tab.panel:SetPoint("TOPLEFT", 0, -TAB_BAR_H); tab.panel:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)
		tab.view.Create(tab.panel)
	end
	footer = ns.UI.Panel(content)
	footer:SetPoint("BOTTOMLEFT", 12, 2); footer:SetPoint("BOTTOMRIGHT", -12, 2); footer:SetHeight(FOOTER_H - 2)
	local announce = ns.UI.Button(footer, "Announce to group", 170, ns.Assignments.Announce)
	announce:SetPoint("LEFT", 8, 0)
	announce:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Announce to group")
		local chan = IsInRaid() and "Raid" or IsInGroup() and "Party" or "Local chat (only you)"
		GameTooltip:AddLine("Channel: " .. chan, 1, 0.82, 0)
		for _, line in ipairs(ns.Assignments.Lines(false)) do
			local prefix = IsInGroup() and ("[" .. ns.title .. "] ") or (ns.title .. ": ")
			GameTooltip:AddLine(prefix .. line, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	announce:SetScript("OnLeave", GameTooltip_Hide)
	channel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	channel:SetPoint("RIGHT", -14, 0); channel:SetTextColor(0.75, 0.75, 0.75)
	showTab(ns.db.optionsTab or (ns.WoW.IsPaladin() and IsInRaid() and "PALADIN" or "PERSONAL"))
	win:SetScript("OnShow", function() attach(win, -HEADER_H) end)
	win:Hide()

	local function refreshVisible()
		if content:IsVisible() then Options.Refresh() end
	end
	for _, event in ipairs({ "AssignmentsChanged", "PaladinPlanChanged", "PreferencesChanged", "PreviewChanged", "SettingsChanged" }) do
		ns.Events.On(event, refreshVisible)
	end
	win:RegisterEvent("DISPLAY_SIZE_CHANGED")
	win:RegisterEvent("UI_SCALE_CHANGED")
	win:RegisterEvent("PLAYER_REGEN_DISABLED")
	win:RegisterEvent("PLAYER_REGEN_ENABLED")
	win:SetScript("OnEvent", refreshVisible)
end

function Options.Toggle()
	if not win then build() end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then HideUIPanel(SettingsPanel) end
	win:SetShown(not win:IsShown())
end

-- Direct navigation also works when the window is already open on another tab.
function Options.OpenTab(selected)
	if not win then build() end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then HideUIPanel(SettingsPanel) end
	showTab(selected)
	if win:IsShown() then attach(win, -HEADER_H) else win:Show() end
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
	if not win then build() end
	showTab("SETTINGS")
	if Options.category and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.category:GetID())
	else
		Options.OpenTab("SETTINGS")
	end
end
