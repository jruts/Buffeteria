-- Controls and textures used by more than one feature.
local _, ns = ...
local UI = { ICON = "Interface\\AddOns\\Buffeteria\\Media\\Icon" }
ns.UI = UI
local icons = {}

function UI.BuffIcon(key)
	if not icons[key] then
		local buff = ns.Buffs.byKey[key]
		icons[key] = ns.WoW.SpellIcon(buff.groupIds[1]) or ns.WoW.SpellIcon(buff.ids[1]) or 134400
	end
	return icons[key]
end

function UI.Checkbox(parent, label, x, y, onClick)
	local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	button:SetSize(24, 24)
	button:SetPoint("TOPLEFT", x, y)
	button.text = button.text or button.Text or button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", button, "RIGHT", 2, 0)
	button.text:SetText(label)
	button:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return button
end

function UI.AnnounceButton(parent)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(140, 22)
	button:SetPoint("BOTTOM", 0, 14)
	button:SetText("Announce to group")
	button:SetScript("OnClick", ns.Assignments.Announce)
end
