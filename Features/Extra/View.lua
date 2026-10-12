-- The Extra tab: conveniences beyond buffs.
local _, ns = ...
local UI = ns.UI
local View = {}
ns.Extra.View = View
local panel, card, rez, spellText

local function hint(parent, x, y, width, label)
	local text = UI.Text(parent, "GameFontHighlightSmall", x, y, width, label)
	text:SetTextColor(0.65, 0.65, 0.65)
	return text
end

function View.Refresh()
	if not panel then return end
	rez:SetChecked(ns.db.resurrect and true or false)
	local name = ns.Extra.Resurrect.SpellName()
	if not name then
		spellText:SetText(UI.COLOR.GREY .. "Your class can't resurrect.|r")
	else
		spellText:SetText("Your spell: |cffffffff" .. name .. "|r")
	end
end

function View.Layout(width)
	if not panel then return end
	card:ClearAllPoints(); card:SetPoint("TOPLEFT", 12, -56); card:SetSize(width - 24, 132)
	panel.rezHelp:SetWidth(width - 100)
end

function View.Create(host)
	panel = host
	UI.PageHeader(panel, "Extra", "Small conveniences beyond buffs.")
	card = UI.Panel(panel)
	UI.Section(card, "Resurrect", 16, -14)
	rez = UI.Checkbox(card, "Resurrect with the head", 16, -34, function(v) ns.Database.Set("resurrect", v) end)
	panel.rezHelp = hint(card, 46, -62, 600,
		"Out of combat, clicking the head resurrects a dead group member before any buff. Players who can resurrect go first.")
	spellText = UI.Text(card, "GameFontNormal", 46, -96, nil, "")
	panel.resurrect = rez
end
