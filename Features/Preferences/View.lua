-- Personal preferences: explicit blessing modes, wanted buffs and tank role.
local _, ns = ...
local UI, Buffs = ns.UI, ns.Buffs
local View = {}
ns.Preferences.View = View
local panel, cards, list, modes, roles, wants, tankButtons, roleText, tankTip, note
local GREY = UI.COLOR.GREY
local CARD_Y, CARD_H = -4, 560
local cachedRoster, cachedOrder, outcomes
local function served() return ns.Assignments.Served(ns.WoW.Me()) end

local function hint(parent, x, y, width, label)
	local text = UI.Text(parent, "GameFontHighlightSmall", x, y, width, label)
	text:SetTextColor(0.65, 0.65, 0.65)
	return text
end

local function casterText(buff, wanted, caster)
	if not wanted then return GREY .. "Skipped|r" end
	if caster then return buff.selfOnly and "Self" or ns.Roster.Name(caster) end
	if buff.selfOnly then return GREY .. "Not learned|r" end
	for _, member in pairs(ns.Assignments.roster.members) do
		if member.class == buff.class then return GREY .. "No available caster|r" end
	end
	local class = buff.class and ns.WoW.ClassName(buff.class):lower() or "caster"
	return GREY .. "No " .. class .. " in group|r"
end

local function modeResult(result)
	local names = {}
	for _, buff in ipairs(Buffs.BLESSINGS) do
		if result[buff.key] then names[#names + 1] = buff.label end
	end
	if #names == 0 then return "No blessings available" end
	local extra = #names > 2 and (" (+" .. (#names - 2) .. ")") or ""
	return table.concat(names, " + ", 1, math.min(2, #names)) .. extra
end

local function buffTooltip(row, tank)
	local buff = Buffs.byKey[row.key]
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(buff.label)
	GameTooltip:AddLine(tank and "Wanted only while tanking." or "Click to include or skip this buff.", 1, 1, 1, true)
	local wanted = tank and ns.db.tankBuffs[row.key] or (not tank and ns.db.wants[row.key])
	GameTooltip:AddLine(casterText(buff, wanted, served()[row.key]), 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function visibleWant(buff, class)
	return Buffs.OfferedTo(buff, class) and (not buff.selfOnly or ns.WoW.KnowsAny(buff.ids))
end

function View.Refresh()
	if not panel then return end
	local mine, class, tank = served(), ns.WoW.PlayerClass(), ns.Preferences.IsTank()
	local signature = table.concat(ns.db.order, ",")
	if cachedRoster ~= ns.Assignments.roster or cachedOrder ~= signature then
		cachedRoster, cachedOrder = ns.Assignments.roster, signature
		outcomes = { ns.Preferences.BlessingOutcome(false), ns.Preferences.BlessingOutcome(true) }
	end
	for i, mode in ipairs(modes) do
		mode:SetChecked((i == 2) == ns.db.blessingsOverride)
		mode.selection:SetShown(mode:GetChecked())
		mode.result:SetText(modeResult(outcomes[i]))
	end
	list.Refresh()
	note:SetText(ns.db.blessingsOverride and "Personal differences use single blessings."
		or "Drag a blessing to switch to your own ranking.")
	for _, row in pairs(wants) do
		local buff = Buffs.byKey[row.key]
		row:SetShown(visibleWant(buff, class))
		row:SetState(ns.db.wants[row.key] and "gold" or "grey", UI.BuffIcon(row.key))
		row.caster:SetText(casterText(buff, ns.db.wants[row.key], mine[row.key]))
	end
	for _, role in ipairs(roles) do role:SetChecked(ns.db.tankRole == role.role) end
	roleText:SetText(ns.db.tankRole == "AUTO" and ("Auto: " .. (tank and "tank buffs active" or "tank buffs inactive"))
		or (tank and "Tank buffs active" or "Tank buffs inactive"))
	if tank then roleText:SetTextColor(0.25, 1, 0.25) else roleText:SetTextColor(0.6, 0.6, 0.6) end
	for _, row in pairs(tankButtons) do
		row:SetShown(Buffs.OfferedTo(Buffs.byKey[row.key], class))
		row:SetState(tank and ns.db.tankBuffs[row.key] and "gold" or "grey", UI.BuffIcon(row.key))
		row.caster:SetText(tank and casterText(Buffs.byKey[row.key], ns.db.tankBuffs[row.key], mine[row.key])
			or GREY .. "Tank only|r")
	end
	tankTip:SetShown(tank)
	View.Layout(panel.layoutWidth or 900)
end

function View.Layout(width)
	if not panel then return end
	panel.layoutWidth = width
	local usable, gap = width - 24, 8
	local first = math.floor((usable - gap * 2) * 0.40)
	local second = math.floor((usable - gap * 2) * 0.31)
	local third = usable - gap * 2 - first - second
	for i, size in ipairs({ first, second, third }) do
		local x = i == 1 and 12 or (i == 2 and 12 + first + gap or 12 + first + second + gap * 2)
		cards[i]:ClearAllPoints(); cards[i]:SetPoint("TOPLEFT", x, CARD_Y); cards[i]:SetSize(size, CARD_H)
	end
	local modeWidth = math.floor((first - 28) / 2)
	for i, mode in ipairs(modes) do
		mode:ClearAllPoints(); mode:SetPoint("TOPLEFT", 10 + (i - 1) * (modeWidth + 8), -44)
		mode:SetSize(modeWidth, 46); mode.result:SetWidth(modeWidth - 40)
	end
	list:SetRowWidth(first - 20); note:SetWidth(first - 24)
	local row = 0
	for _, buff in ipairs(Buffs.Wantable(ns.WoW.PlayerClass())) do
		if not buff.selfOnly or ns.WoW.KnowsAny(buff.ids) then
			local button = wants[buff.key]
			button:ClearAllPoints(); button:SetPoint("TOPLEFT", 10, -44 - row * 54); button:SetWidth(second - 20)
			row = row + 1
		end
	end
	local roleWidth = math.floor((third - 20) / 3)
	for i, role in ipairs(roles) do
		role:ClearAllPoints(); role:SetPoint("TOPLEFT", 10 + (i - 1) * roleWidth, -44)
		role:SetWidth(roleWidth + 1)
	end
	local tankRow = 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		if Buffs.OfferedTo(buff, ns.WoW.PlayerClass()) then
			local button = tankButtons[buff.key]
			button:ClearAllPoints(); button:SetPoint("TOPLEFT", 10, -106 - tankRow * 54); button:SetWidth(third - 20)
			tankRow = tankRow + 1
		end
	end
	tankTip:ClearAllPoints(); tankTip:SetPoint("TOPLEFT", 12, -118 - tankRow * 54); tankTip:SetWidth(third - 24)
	panel.roleHelp:SetWidth(third - 24)
end

function View.Create(host)
	panel = host
	cards = { UI.Card(panel, "Blessings"), UI.Card(panel, "Buffs"), UI.Card(panel, "Tank role") }
	modes = {}
	for i, label in ipairs({ "Follow class plan", "Use my ranking" }) do
		local index, override = i, i == 2
		local mode = UI.Chip(cards[1], label, 170, function() ns.Preferences.Set("blessingsOverride", override) end, "GameFontHighlight")
		mode.caption:ClearAllPoints(); mode.caption:SetPoint("TOPLEFT", 30, -8)
		local ring
		ring, mode.selection = UI.RadioMark(mode, 16)
		ring:SetPoint("TOPLEFT", 8, -8)
		mode.result = hint(mode, 30, -26); mode.result:SetWordWrap(false)
		mode:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(label)
			for _, buff in ipairs(Buffs.BLESSINGS) do
				local caster = outcomes and outcomes[index][buff.key]
				if caster then GameTooltip:AddDoubleLine(buff.label, ns.WoW.Short(caster), 1, 1, 1, 1, 0.82, 0) end
			end
			GameTooltip:AddLine(override and "Your ranking takes priority; differences use single blessings."
				or "Use the Paladins class plan. Your saved ranking is kept.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		mode:SetScript("OnLeave", GameTooltip_Hide); modes[i] = mode
	end
	hint(cards[1], 12, -102, nil, "Drag to reorder")
	list = ns.Preferences.RankList.Create(cards[1], served, function() ns.Preferences.Set("blessingsOverride", true) end)
	list:SetPoint("TOPLEFT", 10, -120)
	note = hint(cards[1], 12, -408)
	wants, tankButtons = {}, {}
	for _, collection in ipairs({ Buffs.GROUP_BUFFS, Buffs.SELF_BUFFS }) do
		for _, buff in ipairs(collection) do
			local key = buff.key
			local row = UI.BuffRow(cards[2], key, function() ns.Preferences.Toggle("wants", key) end)
			row:SetScript("OnEnter", function(self) buffTooltip(self, false) end)
			row:SetScript("OnLeave", GameTooltip_Hide); wants[key] = row
		end
	end
	roles = {}
	for _, choice in ipairs({ { "AUTO", "Auto" }, { "TANK", "Tank" }, { "OFF", "Not tank" } }) do
		local key = choice[1]
		local role = UI.Chip(cards[3], choice[2], 64, function() ns.Preferences.Set("tankRole", key) end, "GameFontHighlight")
		role:SetHeight(26); role.role = key; roles[#roles + 1] = role
	end
	roleText = UI.Text(cards[3], "GameFontNormal", 12, -82)
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local key = buff.key
		local row = UI.BuffRow(cards[3], key, function() ns.Preferences.Toggle("tankBuffs", key) end)
		row:SetScript("OnEnter", function(self) buffTooltip(self, true) end)
		row:SetScript("OnLeave", GameTooltip_Hide); tankButtons[key] = row
	end
	tankTip = UI.Text(cards[3], "GameFontNormalSmall", 12, -230, nil, "Keep Salvation excluded from your ranking while tanking.")
	panel.roleHelp = hint(cards[3], 12, -CARD_H + 44, 180, "Auto follows your assigned Tank role or raid main-tank assignment.")
	panel.wants, panel.tankButtons, panel.roles = wants, tankButtons, roles
	panel.rankList, panel.rankRows, panel.rankGhost = list, list.rows, list.ghost
	panel.modes = modes
end
