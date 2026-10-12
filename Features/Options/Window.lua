-- Host the feature panels in /buff and Blizzard Settings.
local _, ns = ...
local Options = {}
ns.Options = Options
local win, content, panel, personal, paladinPanel, personalTab, paladinTab
-- The /buff window matches the native talent panel: three trees side by side.
local WIDTH, HEIGHT, CONTENT_H = 652, 528, 498

local function layout()
	local inWindow = content:GetParent() == win
	local width = inWindow and WIDTH or math.max(WIDTH - 40, panel:GetWidth() - 32)
	content:SetWidth(width)
	-- Leave room for the window's portrait; Settings has none.
	personalTab:ClearAllPoints(); personalTab:SetPoint("TOPLEFT", inWindow and 64 or 16, -4)
	ns.Preferences.View.Layout(width)
	ns.Paladins.View.Layout(width)
end

local function styleTab(tab, selected)
	tab:SetEnabled(not selected)
	if selected then
		tab:SetBackdropColor(0.32, 0.22, 0.04, 0.95); tab:SetBackdropBorderColor(1, 0.82, 0, 1)
		tab.caption:SetTextColor(1, 0.82, 0)
	else
		tab:SetBackdropColor(0, 0, 0, 0.75); tab:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
		tab.caption:SetTextColor(0.6, 0.6, 0.6)
	end
end

-- Talent-panel style top tab ("Primary" / "Secondary").
local function createTab(label)
	local tab = CreateFrame("Button", nil, content, "BackdropTemplate")
	tab:SetSize(150, 24)
	tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	tab.caption = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.caption:SetPoint("CENTER", 0, 0)
	tab:SetFontString(tab.caption)
	tab:SetText(label)
	tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	return tab
end

local function selectTab(isPaladin)
	local _, class = UnitClass("player")
	isPaladin = isPaladin and class == "PALADIN"
	personal:SetShown(not isPaladin)
	paladinPanel:SetShown(isPaladin)
	styleTab(personalTab, not isPaladin)
	styleTab(paladinTab, isPaladin)
	Options.Refresh()
end

function Options.Refresh()
	if not content then return end
	ns.Preferences.View.Refresh()
	ns.Paladins.View.Refresh()
	layout()
end

local function build()
	win = CreateFrame("Frame", "Buffeteria_Prefs", UIParent, "PortraitFrameTemplate")
	win:SetSize(WIDTH, HEIGHT)
	win:SetPoint("CENTER")
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "Buffeteria_Prefs")
	win:SetTitle("Buffeteria")
	win:SetPortraitToAsset(ns.UI.ICON)
	win.CloseButton = win.CloseButton or CreateFrame("Button", nil, win, "UIPanelCloseButton")
	win.CloseButton:SetScript("OnClick", function() win:Hide() end)

	-- All controls live on "content", which moves between this window and the
	-- Settings > AddOns page (whichever is showing).
	content = CreateFrame("Frame", nil, win)
	content:SetSize(WIDTH, CONTENT_H)
	content:SetPoint("TOPLEFT", 0, -26)
	personalTab = createTab("My preferences")
	paladinTab = createTab("Paladins")
	paladinTab:SetPoint("LEFT", personalTab, "RIGHT", 6, 0)
	local _, playerClass = UnitClass("player")
	paladinTab:SetShown(playerClass == "PALADIN")
	personal = ns.Preferences.View.Create(content)
	paladinPanel = ns.Paladins.View.Create(content)
	personalTab:SetScript("OnClick", function() selectTab(false) end)
	paladinTab:SetScript("OnClick", function() selectTab(true) end)

	paladinPanel:Hide()
	styleTab(personalTab, true); styleTab(paladinTab, false)
	win:SetScript("OnShow", function()
		content:SetParent(win); content:ClearAllPoints(); content:SetPoint("TOPLEFT", 0, -26); content:Show()
		Options.Refresh()
	end)
	win:Hide()

	local function refreshVisible()
		if content:IsVisible() then Options.Refresh() end
	end
	ns.Events.On("AssignmentsChanged", refreshVisible)
	ns.Events.On("PaladinPlanChanged", refreshVisible)
	ns.Events.On("PreviewChanged", refreshVisible)
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
	panel.name = "Buffeteria"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Buffeteria")
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("The raid buff buffet. Unlimited refills.")
	panel:SetScript("OnShow", function()
		if not win then build() end
		win:Hide()
		content:SetParent(panel); content:ClearAllPoints(); content:SetPoint("TOPLEFT", 0, -56); content:Show()
		Options.Refresh()
	end)
	panel:SetScript("OnSizeChanged", function()
		if content and content:GetParent() == panel then layout() end
	end)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Buffeteria")
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
