-- Host the feature panels in /buff and Blizzard Settings.
local _, ns = ...
local Options = {}
ns.Options = Options
local win, content, panel, personal, paladinPanel, personalTab, paladinTab

local function selectTab(isPaladin)
	local _, class = UnitClass("player")
	isPaladin = isPaladin and class == "PALADIN"
	personal:SetShown(not isPaladin)
	paladinPanel:SetShown(isPaladin)
	personalTab:SetEnabled(isPaladin)
	paladinTab:SetEnabled(not isPaladin)
	Options.Refresh()
end

function Options.Refresh()
	if not content then return end
	ns.Preferences.View.Refresh()
	ns.Paladins.View.Refresh()
end

local function build()
	win = CreateFrame("Frame", "Buffeteria_Prefs", UIParent, "BasicFrameTemplateWithInset")
	win:SetSize(340, 686)
	win:SetPoint("CENTER")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "Buffeteria_Prefs")
	if not win.TitleText then
		win.TitleText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		win.TitleText:SetPoint("TOP", 0, -6)
	end
	win.TitleText:SetText("Buffeteria")

	-- All controls live on "content", which moves between this window and the
	-- Settings > AddOns page (whichever is showing).
	content = CreateFrame("Frame", nil, win)
	content:SetSize(340, 658)
	content:SetPoint("TOPLEFT", 0, -26)
	personalTab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	personalTab:SetSize(148, 24); personalTab:SetPoint("TOPLEFT", 16, -4); personalTab:SetText("My preferences")
	paladinTab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	paladinTab:SetSize(148, 24); paladinTab:SetPoint("LEFT", personalTab, "RIGHT", 8, 0); paladinTab:SetText("Paladins")
	local _, playerClass = UnitClass("player")
	paladinTab:SetShown(playerClass == "PALADIN")
	personal = ns.Preferences.View.Create(content)
	paladinPanel = ns.Paladins.View.Create(content)
	personalTab:SetScript("OnClick", function() selectTab(false) end)
	paladinTab:SetScript("OnClick", function() selectTab(true) end)

	paladinPanel:Hide(); personalTab:Disable()
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
