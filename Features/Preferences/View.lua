-- Personal preferences: blessing order, wanted buffs and tank role.
local _, ns = ...
local UI, Buffs = ns.UI, ns.Buffs
local View = {}
ns.Preferences.View = View
local panel, cards, list, own, ownText, roles, wants, tankButtons, roleText, note
local pickers = {}
local GREY = UI.COLOR.GREY
local CARD_Y, CARD_H = -4, 560
local cachedRoster, cachedOrder, outcomes
local function previewing() return ns.Options.ClassPreview() ~= nil end
local function served() return previewing() and ns.Util.EMPTY or ns.Assignments.Served(ns.WoW.Me()) end
local function order() return previewing() and Buffs.DefaultOrder(ns.Options.DisplayClass()) or ns.Preferences.Order() end

local function write(fn, ...)
	if not previewing() then fn(...) end
end

local function hint(parent, x, y, width, label)
	local text = UI.Text(parent, "GameFontHighlightSmall", x, y, width, label)
	text:SetTextColor(0.65, 0.65, 0.65)
	return text
end

local function casterText(buff, wanted, caster)
	if not wanted then return GREY .. "Skipped|r" end
	if caster then
		if buff.selfOnly and caster == ns.WoW.Me() then return "Self" end
		return ns.Roster.Name(caster)
	end
	if previewing() then return buff.selfOnly and "Self" or GREY .. "Sample spellbook|r" end
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
	GameTooltip:AddLine(previewing() and "Class preview." or (tank and "Wanted only while tanking."
		or "Click to include or skip this buff."), 1, 1, 1, true)
	local wanted = previewing() and row:GetChecked()
	if not previewing() then wanted = tank and ns.db.tankBuffs[row.key] or (not tank and ns.db.wants[row.key]) end
	GameTooltip:AddLine(casterText(buff, wanted, served()[row.key]), 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function visibleWant(buff, class)
	return Buffs.OfferedTo(buff, class) and (not buff.selfOnly or previewing() or ns.WoW.KnowsAny(buff.ids))
end

local function refreshPicker(picker)
	local selected, menu = ns.db[picker.key], picker.menu
	local preview = previewing()
	if preview then selected = picker.key == "weaponImbue" and picker.buffs[1].key or "AUTO" end
	if selected == nil then selected = picker.default end
	local buff = Buffs.byKey[selected]
	local label = buff and buff.label or "None"
	if picker.key == "personalBuff" then
		local active = preview and picker.buffs[1] or ns.Preferences.PersonalBuff()
		if selected == "AUTO" then
			label = active and ("Auto (" .. active.label .. ")") or "Auto"
		elseif buff and not active then
			label = label .. " (not learned)"
		end
	end
	picker.caption:SetText(label)
	local row = 0
	for _, item in ipairs(menu.items) do
		local choice = Buffs.byKey[item.key]
		local shown = preview or not choice or ns.WoW.KnowsAny(choice.ids)
		item:SetShown(shown)
		item:SetChecked(item.key == selected)
		item:SetEnabled(not preview)
		if shown then
			item:ClearAllPoints(); item:SetPoint("TOPLEFT", 8, -8 - row * 24)
			row = row + 1
		end
	end
	menu:SetHeight(row * 24 + 16)
end

function View.Refresh()
	if not panel then return end
	local preview, class = previewing(), ns.Options.DisplayClass()
	local mine, tank = served(), not preview and ns.Preferences.IsTank()
	local sampleWants = preview and Buffs.DefaultWants(class) or ns.db.wants
	local signature = table.concat(order(), ",")
	if not preview and (cachedRoster ~= ns.Assignments.roster or cachedOrder ~= signature) then
		cachedRoster, cachedOrder = ns.Assignments.roster, signature
		outcomes = { ns.Preferences.BlessingOutcome(false), ns.Preferences.BlessingOutcome(true) }
	end
	local on = preview or ns.db.blessingsOverride
	own:SetChecked(on)
	own:SetEnabled(not preview)
	ownText:SetText(preview and ("Default order for " .. ns.WoW.ClassName(class)) or
		(on and ("On: you get " .. modeResult(outcomes[2]) .. " from your list.")
		or ("Off: you get your class's blessings, " .. modeResult(outcomes[1]) .. ".")))
	list.Refresh()
	-- Greyed out while unused; dragging still switches it on.
	list:SetAlpha(on and 1 or 0.45)
	note:SetText(preview and "Read-only preview of the class defaults." or (on
		and "You get the blessings above the gold line, cast by the paladin named under each; a check mark means it is on you now. Blessings that differ from your class's Greater Blessing are cast on you as single blessings."
		or "Your list is not used while Use my own order is off. Tick it, or drag a blessing, to use it."))
	for _, row in pairs(wants) do
		local buff = Buffs.byKey[row.key]
		row:SetShown(visibleWant(buff, class))
		row:SetEnabled(not preview)
		row:SetState(sampleWants[row.key] and "gold" or "grey", UI.BuffIcon(row.key))
		row.caster:SetText(casterText(buff, sampleWants[row.key], mine[row.key]))
	end
	for _, picker in ipairs(pickers) do
		local shown = picker.class == class
		picker:SetShown(shown); picker.label:SetShown(shown); picker.help:SetShown(shown)
		if shown then refreshPicker(picker) end
	end
	local tankRole = preview and "AUTO" or ns.db.tankRole
	for _, role in ipairs(roles) do role:SetChecked(tankRole == role.role); role:SetEnabled(not preview) end
	roleText:SetText(tankRole == "AUTO" and ("Auto: " .. (tank and "tank buffs active" or "tank buffs inactive"))
		or (tank and "Tank buffs active" or "Tank buffs inactive"))
	if tank then roleText:SetTextColor(0.25, 1, 0.25) else roleText:SetTextColor(0.6, 0.6, 0.6) end
	for _, row in pairs(tankButtons) do
		row:SetShown(Buffs.OfferedTo(Buffs.byKey[row.key], class))
		row:SetEnabled(not preview)
		row:SetState(tank and ns.db.tankBuffs[row.key] and "gold" or "grey", UI.BuffIcon(row.key))
		row.caster:SetText(tank and casterText(Buffs.byKey[row.key], ns.db.tankBuffs[row.key], mine[row.key])
			or GREY .. "Tank only|r")
	end
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
	ownText:SetWidth(first - 52)
	list:SetRowWidth(first - 20); note:SetWidth(first - 24)
	local row = 0
	local class = ns.Options.DisplayClass()
	for _, buff in ipairs(Buffs.Wantable(class)) do
		if visibleWant(buff, class) then
			local button = wants[buff.key]
			button:ClearAllPoints(); button:SetPoint("TOPLEFT", 10, -44 - row * 54); button:SetWidth(second - 20)
			row = row + 1
		end
	end
	local offset = 0
	for _, picker in ipairs(pickers) do
		if picker.class == class then
			local width = second - 24
			local y = -56 - row * 54 - offset
			picker.label:ClearAllPoints(); picker.label:SetPoint("TOPLEFT", 12, y)
			picker:ClearAllPoints(); picker:SetPoint("TOPLEFT", 12, y - 20); picker:SetWidth(width)
			picker.help:ClearAllPoints(); picker.help:SetPoint("TOPLEFT", 12, y - 54); picker.help:SetWidth(width)
			picker.menu:SetWidth(width)
			for _, item in ipairs(picker.menu.items) do item:SetWidth(width - 16) end
			offset = offset + 82
		end
	end
	local roleWidth = math.floor((third - 20) / 3)
	for i, role in ipairs(roles) do
		role:ClearAllPoints(); role:SetPoint("TOPLEFT", 10 + (i - 1) * roleWidth, -44)
		role:SetWidth(roleWidth + 1)
	end
	local tankRow = 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		if Buffs.OfferedTo(buff, class) then
			local button = tankButtons[buff.key]
			button:ClearAllPoints(); button:SetPoint("TOPLEFT", 10, -106 - tankRow * 54); button:SetWidth(third - 20)
			tankRow = tankRow + 1
		end
	end
	panel.roleHelp:SetWidth(third - 24)
end

local function createPicker(parent, spec)
	local picker = UI.Chip(parent, "", 200, function(self)
		local open = not self.menu:IsShown()
		for _, other in ipairs(pickers) do other.menu:Hide() end
		refreshPicker(self)
		self.menu:SetShown(open)
	end, "GameFontHighlight")
	picker.key, picker.default = spec.key, spec.default
	picker.class, picker.buffs = spec.class, spec.buffs
	picker.label = UI.Text(parent, "GameFontNormal", 12, -326, nil, spec.title)
	picker.help = hint(parent, 12, -380, 200, spec.help)
	picker.caption:ClearAllPoints(); picker.caption:SetPoint("LEFT", 10, 0)
	picker.caption:SetPoint("RIGHT", -26, 0); picker.caption:SetJustifyH("LEFT"); picker.caption:SetWordWrap(false)
	local arrow = picker:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	arrow:SetSize(22, 22); arrow:SetPoint("RIGHT", -4, 0)

	local name = ns.globalPrefix .. spec.suffix
	local menu = UI.Menu(picker, name)
	menu:SetPoint("BOTTOMLEFT", picker, "TOPLEFT", 0, 2)
	menu:SetFrameLevel(picker:GetFrameLevel() + 25)
	menu:Hide(); menu.items = {}; picker.menu = menu
	tinsert(UISpecialFrames, name)
	picker:SetScript("OnHide", function() menu:Hide() end)

	local function addChoice(key, label, icon)
		local item = UI.MenuItem(menu, 184, function()
			menu:Hide()
			write(ns.Preferences.Set, picker.key, key)
		end)
		item.key = key
		item.caption:SetText(label); item.icon:SetTexture(icon)
		menu.items[#menu.items + 1] = item
	end
	if spec.default == "AUTO" then addChoice("AUTO", "Auto") end
	addChoice(false, "None")
	for _, buff in ipairs(spec.buffs) do addChoice(buff.key, buff.label, UI.BuffIcon(buff.key)) end
	pickers[#pickers + 1] = picker
end

function View.Create(host)
	panel = host
	cards = { UI.Card(panel, "Blessings"), UI.Card(panel, "Buffs"), UI.Card(panel, "Tank role") }
	-- One checkbox: off follows your class's blessings, on uses the list below.
	own = UI.Checkbox(cards[1], "Use my own order", 8, -40, function(on) write(ns.Preferences.Set, "blessingsOverride", on) end)
	own:SetScript("OnEnter", function(self)
		if previewing() then return end
		local on = ns.db.blessingsOverride
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Use my own order")
		GameTooltip:AddLine("Off: you get the Greater Blessings the paladins planned for your class.", 1, 1, 1, true)
		GameTooltip:AddLine("On: you get the blessings at the top of your list. Where they differ from your class's, a paladin casts a single blessing on you.", 1, 1, 1, true)
		local result = outcomes and outcomes[on and 2 or 1] or {}
		for _, buff in ipairs(Buffs.BLESSINGS) do
			if result[buff.key] then GameTooltip:AddDoubleLine(buff.label, ns.WoW.Short(result[buff.key]), 1, 1, 1, 1, 0.82, 0) end
		end
		GameTooltip:Show()
	end)
	own:SetScript("OnLeave", GameTooltip_Hide)
	ownText = hint(cards[1], 40, -68)
	hint(cards[1], 12, -102, nil, "Most wanted at the top. Drag to reorder.")
	list = ns.Preferences.RankList.Create(cards[1], served, function() write(ns.Preferences.Set, "blessingsOverride", true) end,
		order, previewing)
	list:SetPoint("TOPLEFT", 10, -120)
	note = hint(cards[1], 12, -120 - list:GetHeight() - 8)
	wants, tankButtons = {}, {}
	for _, collection in ipairs({ Buffs.GROUP_BUFFS, Buffs.SELF_BUFFS }) do
		for _, buff in ipairs(collection) do
			local key = buff.key
			local row = UI.BuffRow(cards[2], key, function() write(ns.Preferences.Toggle, "wants", key) end)
			row:SetScript("OnEnter", function(self) buffTooltip(self, false) end)
			row:SetScript("OnLeave", GameTooltip_Hide); wants[key] = row
		end
	end
	local class = ns.WoW.PlayerClass()
	if class == "SHAMAN" or ns.isDev then
		createPicker(cards[2], {
			key = "weaponImbue", default = false, suffix = "_WeaponImbueMenu",
			title = "Weapon imbue", buffs = Buffs.WEAPON_IMBUES, class = "SHAMAN",
			help = "Track an imbue on your main-hand weapon.",
		})
	end
	for _, other in ipairs(Buffs.CLASS_KEYS) do
		if Buffs.PERSONAL_BUFFS[other] and (class == other or ns.isDev) then
			createPicker(cards[2], {
				key = "personalBuff", default = "AUTO",
				suffix = "_PersonalBuffMenu" .. (class == other and "" or "_" .. other),
				title = other == "SHAMAN" and "Elemental shield" or "Armor",
				buffs = Buffs.PERSONAL_BUFFS[other], class = other,
				help = "Choose one spell to maintain, or None to skip.",
			})
		end
	end
	roles = {}
	for _, choice in ipairs({ { "AUTO", "Auto" }, { "TANK", "Tank" }, { "OFF", "Not tank" } }) do
		local key = choice[1]
		local role = UI.Chip(cards[3], choice[2], 64, function() write(ns.Preferences.Set, "tankRole", key) end, "GameFontHighlight")
		role:SetHeight(26); role.role = key; roles[#roles + 1] = role
	end
	roleText = UI.Text(cards[3], "GameFontNormal", 12, -82)
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local key = buff.key
		local row = UI.BuffRow(cards[3], key, function() write(ns.Preferences.Toggle, "tankBuffs", key) end)
		row:SetScript("OnEnter", function(self) buffTooltip(self, true) end)
		row:SetScript("OnLeave", GameTooltip_Hide); tankButtons[key] = row
	end
	panel.roleHelp = hint(cards[3], 12, -CARD_H + 44, 180, "Auto follows your assigned Tank role or raid main-tank assignment.")
	panel.wants, panel.tankButtons, panel.roles = wants, tankButtons, roles
	panel.rankList, panel.rankRows, panel.rankGhost = list, list.rows, list.ghost
	panel.own = own
end
