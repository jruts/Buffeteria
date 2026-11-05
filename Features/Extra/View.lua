-- The Extra tab: conveniences beyond buffs.
local _, ns = ...
local UI, Buffs = ns.UI, ns.Buffs
local View = {}
ns.Extra.View = View
local panel, card, rez, spellText
local support, supportHelp, supportChoices

local function hint(parent, x, y, width, label)
	local text = UI.Text(parent, "GameFontHighlightSmall", x, y, width, label)
	text:SetTextColor(0.65, 0.65, 0.65)
	return text
end

function View.Refresh()
	if not panel then return end
	local preview = ns.Options.ClassPreview()
	rez:SetChecked(preview ~= nil or ns.db.resurrect and true or false)
	rez:SetEnabled(not preview)
	local name = ns.Extra.Resurrect.SpellName(preview)
	if not name then
		spellText:SetText(UI.COLOR.GREY .. "Your class can't resurrect.|r")
	else
		spellText:SetText("Your spell: |cffffffff" .. name .. "|r")
	end
	local mine = ns.Assignments.Served(ns.WoW.Me())
	for _, choice in ipairs(supportChoices) do
		local wanted = not preview and ns.db.wants[choice.key]
		choice.button:SetChecked(wanted == true)
		choice.button:SetEnabled(not preview)
		local caster = wanted and mine[choice.key]
		choice.status:SetText(caster and ("Assigned to " .. ns.Roster.Name(caster))
			or (wanted and "No caster assigned" or ""))
	end
end

function View.Layout(width)
	if not panel then return end
	card:ClearAllPoints(); card:SetPoint("TOPLEFT", 12, -56); card:SetSize(width - 24, 132)
	panel.rezHelp:SetWidth(width - 100)
	local class, count = ns.Options.DisplayClass(), 0
	for _, choice in ipairs(supportChoices) do
		local shown = not choice.class or choice.class == class
		choice.button:SetShown(shown); choice.status:SetShown(shown)
		if shown then
			local y = -34 - count * 28
			choice.button:ClearAllPoints(); choice.button:SetPoint("TOPLEFT", 16, y)
			choice.status:ClearAllPoints(); choice.status:SetPoint("TOPLEFT", 330, y - 6)
			count = count + 1
		end
	end
	support:ClearAllPoints(); support:SetPoint("TOPLEFT", 12, -198); support:SetSize(width - 24, 90 + count * 28)
	supportHelp:ClearAllPoints(); supportHelp:SetPoint("TOPLEFT", 46, -40 - count * 28)
	supportHelp:SetWidth(width - 100)
	local detail = "Fear Ward is useful for encounters with fear effects."
	if class == "SHAMAN" then
		detail = detail .. " Each shaman provides one air totem at a time. A different active totem keeps its slot."
	elseif class == "DRUID" then
		detail = detail .. " Druid crit auras are observed without changing your form."
	end
	supportHelp:SetText(detail)
end

function View.Create(host)
	panel = host
	UI.PageHeader(panel, "Extra", "Resurrection and optional group buffs.")
	card = UI.Panel(panel)
	UI.Section(card, "Resurrect", 16, -14)
	rez = UI.Checkbox(card, "Resurrect with the head", 16, -34, function(v)
		if not ns.Options.ClassPreview() then ns.Database.Set("resurrect", v) end
	end)
	panel.rezHelp = hint(card, 46, -62, 600,
		"Out of combat, clicking the head resurrects a dead group member before any buff. Players who can resurrect go first.")
	spellText = UI.Text(card, "GameFontNormal", 46, -96, nil, "")
	panel.resurrect = rez

	support, supportChoices = UI.Panel(panel), {}
	UI.Section(support, "Optional group buffs", 16, -14)
	local function addChoice(key, label, class)
		local button = UI.Checkbox(support, label, 16, 0, function()
			if not ns.Options.ClassPreview() then ns.Preferences.Toggle("wants", key) end
		end)
		local status = hint(support, 330, 0, 340, "")
		supportChoices[#supportChoices + 1] = { key = key, button = button, status = status, class = class }
	end
	addChoice("FWARD", "Request Fear Ward")
	local class = ns.WoW.PlayerClass()
	for _, buff in ipairs(Buffs.RAID_SUPPORT) do
		if buff.class == class or ns.isDev then
			addChoice(buff.key, buff.passive and "Track Moonkin Aura or Leader of the Pack" or ("Provide " .. buff.label), buff.class)
		end
	end
	supportHelp = hint(support, 46, 0, 600)
end
