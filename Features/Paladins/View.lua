-- Class plan editor; independent of the options window hosting it.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Paladins.View = View
local paladinPanel, paladinName, paladinNote, paladinRows, paladinSummary, selectedPaladin

local function paladinNames()
	local out = {}
	for full, m in pairs(ns.roster.members) do if m.class == "PALADIN" then out[#out + 1] = full end end
	table.sort(out)
	return out
end

local function refreshPaladins()
	if not paladinPanel then return end
	local pals = paladinNames()
	if not selectedPaladin or not ns.roster.members[selectedPaladin] then
		local me = ns.roster.members[ns.WoW.FullName("player")]
		selectedPaladin = me and me.class == "PALADIN" and ns.WoW.FullName("player") or pals[1]
	end
	local m = selectedPaladin and ns.roster.members[selectedPaladin]
	paladinName:SetText(m and ns.WoW.ClassColorName(selectedPaladin, "PALADIN") or "No paladins in the group")
	paladinNote:SetText(m and (m.hasAddon and "Spellbook shared by Buffeteria" or "Without Buffeteria: assignments confirm known blessings") or "")
	for class, button in pairs(paladinRows) do
		local key = selectedPaladin and ns.Paladins.Get(selectedPaladin, class) or "AUTO"
		local resolved = ((ns.result.pally or {})[class] or {})[selectedPaladin]
		local label = key == "AUTO" and ("Auto: " .. (resolved and Buffs.byKey[resolved].label or "none"))
			or (key == "NONE" and "None" or Buffs.byKey[key].label)
		if Buffs.byKey[key] and (((ns.roster.paladinAssignments or {})[class] or {})[selectedPaladin] == "NONE") then
			label = Buffs.byKey[key].label .. " (duplicate)"
		end
		button:SetText(label)
		button:SetEnabled(m ~= nil)
	end
	paladinSummary:SetText(table.concat(ns.Assignments.Lines(true), "\n"))
end

View.Refresh = refreshPaladins

function View.Create(parent)
	paladinPanel = CreateFrame("Frame", nil, parent)
	paladinPanel:SetPoint("TOPLEFT", 0, -32); paladinPanel:SetPoint("BOTTOMRIGHT")
	local title = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -8); title:SetText("Class blessing assignments")
	local help = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 16, -30); help:SetWidth(300); help:SetJustifyH("LEFT")
	help:SetText("Choose a paladin, then click a class blessing to cycle it (right-click reverses). Auto uses the solver; None leaves the class unassigned.")
	local prevPaladin = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
	prevPaladin:SetSize(26, 24); prevPaladin:SetPoint("TOPLEFT", 16, -84); prevPaladin:SetText("<")
	local nextPaladin = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
	nextPaladin:SetSize(26, 24); nextPaladin:SetPoint("TOPRIGHT", -16, -84); nextPaladin:SetText(">")
	paladinName = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	paladinName:SetPoint("LEFT", prevPaladin, "RIGHT", 8, 0); paladinName:SetPoint("RIGHT", nextPaladin, "LEFT", -8, 0)
	local function movePaladin(delta)
		local pals = paladinNames()
		for i, name in ipairs(pals) do
			if name == selectedPaladin then selectedPaladin = pals[((i - 1 + delta) % #pals) + 1]; break end
		end
		refreshPaladins()
	end
	prevPaladin:SetScript("OnClick", function() movePaladin(-1) end)
	nextPaladin:SetScript("OnClick", function() movePaladin(1) end)
	paladinNote = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	paladinNote:SetPoint("TOPLEFT", 16, -114); paladinNote:SetWidth(300); paladinNote:SetJustifyH("LEFT")
	paladinRows = {}
	for i, class in ipairs(Buffs.CLASS_KEYS) do
		local label = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 20, -146 - (i - 1) * 30); label:SetText(ns.WoW.ClassName(class))
		local button = CreateFrame("Button", nil, paladinPanel, "UIPanelButtonTemplate")
		button:SetSize(152, 24); button:SetPoint("TOPLEFT", 168, -140 - (i - 1) * 30)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(_, mouseButton)
			local m = selectedPaladin and ns.roster.members[selectedPaladin]
			if not m then return end
			local choices = { "AUTO" }
			for _, key in ipairs(Buffs.BLESSING_KEYS) do
				if not m.hasAddon or m.caps[key] or m.caps["g" .. key] then choices[#choices + 1] = key end
			end
			choices[#choices + 1] = "NONE"
			local current, index = ns.Paladins.Get(selectedPaladin, class), 1
			for j, key in ipairs(choices) do if key == current then index = j; break end end
			local delta = mouseButton == "RightButton" and -1 or 1
			ns.Paladins.Set(selectedPaladin, class, choices[((index - 1 + delta) % #choices) + 1])
		end)
		paladinRows[class] = button
	end
	local priority = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	priority:SetPoint("TOPLEFT", 16, -418); priority:SetWidth(300); priority:SetJustifyH("LEFT")
	priority:SetText("Shared with the group's Buffeteria users. Personal overrides take priority; everyone else follows this plan. Your own row is saved between sessions.")
	paladinSummary = paladinPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	paladinSummary:SetPoint("TOPLEFT", 16, -470); paladinSummary:SetPoint("BOTTOMRIGHT", -16, 44)
	paladinSummary:SetJustifyH("LEFT"); paladinSummary:SetJustifyV("TOP")
	ns.UI.AnnounceButton(paladinPanel)
	return paladinPanel
end
