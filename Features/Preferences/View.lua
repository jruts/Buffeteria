-- Personal buff preferences, laid out as three talent trees: blessing ranking,
-- wanted buffs, and tank buffs.
local _, ns = ...
local Buffs = ns.Buffs
local View = {}
ns.Preferences.View = View
local personal, band, trees, list, wants, overrideCheck, tip, tankButtons, roleButton, roleText, tankTip
local EDGE, GAP, BOARD_H = 8, 2, 360
local GREY, RED = ns.UI.COLOR.GREY, ns.UI.COLOR.RED
local ROLE_LABELS = { AUTO = "Auto", TANK = "Tank", OFF = "Not tank" }
local NEXT_ROLE = { AUTO = "TANK", TANK = "OFF", OFF = "AUTO" }

-- What the solver expects you to receive: buff key -> caster.
local function served() return ns.Assignments.Served(ns.WoW.Me()) end

-- A wanted buff's caption: who casts it, or why nobody does.
local function casterText(buff, on, caster, missing)
	if not on then return GREY .. "Skipped|r" end
	if caster then return buff.selfOnly and "Self" or ns.Roster.Name(caster) end
	return RED .. (buff.selfOnly and "Not learned" or missing) .. "|r"
end

-- Tank requests follow the role without changing the saved per-buff choices.
local function refreshTanks()
	local tank, mine, class = ns.Preferences.IsTank(), served(), ns.WoW.PlayerClass()
	roleButton:SetText("Role: " .. ROLE_LABELS[ns.db.tankRole])
	roleText:SetText(tank and "|cff40ff40Tank buffs active|r" or GREY .. "Tank buffs inactive|r")
	local wanted = 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button, offered = tankButtons[buff.key], Buffs.OfferedTo(buff, class)
		local on = tank and ns.db.tankBuffs[buff.key]
		button:SetShown(offered)
		if offered and on then wanted = wanted + 1 end
		button:SetState(on and "gold" or "grey", ns.UI.BuffIcon(buff.key))
		button.caster:SetText(tank and casterText(buff, on, mine[buff.key], "No druid") or GREY .. "Tank only|r")
	end
	return wanted
end

local function refreshWants()
	local wanted, mine = 0, served()
	for _, button in pairs(wants) do button:Hide() end
	for _, buff in ipairs(Buffs.Wantable(ns.WoW.PlayerClass())) do
		local button, on = wants[buff.key], ns.db.wants[buff.key] and true or false
		if on then wanted = wanted + 1 end
		button:Show()
		button:SetState(on and "gold" or "grey", ns.UI.BuffIcon(buff.key))
		button.caster:SetText(casterText(buff, on, mine[buff.key], "No caster"))
	end
	return wanted
end

function View.Refresh()
	if not personal then return end
	local wanted = refreshWants()
	overrideCheck:SetChecked(ns.db.blessingsOverride and true or false)
	local art = ns.UI.TREE_ART[ns.WoW.PlayerClass()] or ns.UI.TREE_ART.PALADIN
	for i, tree in ipairs(trees) do tree:SetArt(art[i]) end
	trees[1]:SetHeader(ns.UI.BuffIcon("KINGS"), "Blessings", "Best first, drag to reorder", list.Refresh())
	trees[2]:SetHeader(ns.UI.BuffIcon("FORT"), "Buffs", "Click the buffs you want", wanted)
	trees[3]:SetHeader(ns.UI.BuffIcon("THORNS"), "Tanks", "Buffs for your tank role", refreshTanks())
	band:SetCount("Paladins", #ns.Roster.Paladins())
end

function View.Layout(width)
	if not personal then return end
	local column = math.floor((width - EDGE * 2 - GAP * 2) / 3)
	for i, tree in ipairs(trees) do
		tree:ClearAllPoints(); tree:SetPoint("TOPLEFT", EDGE + (i - 1) * (column + GAP), -48)
		tree:Resize(column, BOARD_H)
	end
	list:SetRowWidth(column - 20)
	for _, region in ipairs({ tip, roleButton, roleText, tankTip }) do region:SetWidth(column - 28) end
	overrideCheck.text:SetWidth(column - 44)
	local class, row = ns.WoW.PlayerClass(), 0
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button = tankButtons[buff.key]
		button:ClearAllPoints(); button:SetPoint("TOPLEFT", trees[3], "TOPLEFT", 20, -150 - row * 66)
		button.label:SetWidth(column - 80); button.caster:SetWidth(column - 80)
		if Buffs.OfferedTo(buff, class) then row = row + 1 end
	end
	local cell = column / 3
	local entries = Buffs.Wantable(class)
	for i, buff in ipairs(entries) do
		-- Talent tiers of three, a partial last tier centered.
		local tier = math.floor((i - 1) / 3)
		local inTier = math.min(3, #entries - tier * 3)
		local x = cell * ((i - 1) % 3 + 0.5 + (3 - inTier) / 2)
		local button = wants[buff.key]
		button:ClearAllPoints(); button:SetPoint("TOP", trees[2], "TOPLEFT", x, -84 - tier * 60)
		button.caster:SetWidth(cell - 2)
	end
end

local function wantTooltip(button)
	local buff, wanted = Buffs.byKey[button.key], ns.db.wants[button.key]
	local caster = served()[button.key]
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(buff.label)
	GameTooltip:AddLine(wanted and "Wanted" or "Not wanted", unpack(ns.UI.GOLD))
	if buff.selfOnly then
		GameTooltip:AddLine("You cast it yourself; the tracker reminds you when it is missing or about to expire.",
			0.8, 0.8, 0.8, true)
	elseif wanted then
		GameTooltip:AddLine(caster and ("Cast by " .. ns.Roster.Name(caster)) or "Nobody in the group casts it yet.",
			0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Click to toggle.", 1, 1, 1)
	GameTooltip:Show()
end

local function tankTooltip(button)
	local buff = Buffs.byKey[button.key]
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT"); GameTooltip:SetText(buff.label)
	GameTooltip:AddLine(ns.db.tankBuffs[button.key] and "Wanted when tanking" or "Not wanted", unpack(ns.UI.GOLD))
	GameTooltip:AddLine(buff.selfOnly and "Self-cast by paladin tanks." or "Assigned to a druid for tank recipients.", 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine("Click to toggle.", 1, 1, 1); GameTooltip:Show()
end

-- A talent button toggling one key of a saved set, captioned with its caster.
local function toggleButton(tree, buff, set, onEnter)
	local button = ns.UI.TalentButton(tree)
	button.key = buff.key
	button.caster = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.caster:SetWordWrap(false)
	button:SetScript("OnClick", function(self)
		ns.Preferences.Toggle(set, self.key)
		if GameTooltip:IsOwned(self) then onEnter(self) end
	end)
	button:SetScript("OnEnter", onEnter); button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

function View.Create(host)
	personal = host
	band = ns.UI.Band(personal, "Your buffet", "Rank your blessings and pick your buffs, including tank buffs.", true)
	trees = { ns.UI.Tree(personal), ns.UI.Tree(personal), ns.UI.Tree(personal) }

	-- 1) Blessing ranking, with the paladin serving each ranked blessing
	local blessings = trees[1]
	list = ns.Preferences.RankList.Create(blessings, served, function()
		ns.Preferences.Set("blessingsOverride", true)
	end)
	list:SetPoint("TOPLEFT", 10, -80)
	tip = ns.UI.Text(blessings, "GameFontDisableSmall", 14, -84 - list:GetHeight(), nil,
		"#1 with one paladin, #1 and #2 with two. Tanks: drag Salvation below the line.")
	overrideCheck = ns.UI.Checkbox(blessings, "Override the Paladins class plan", 10, -322, function(value)
		ns.Preferences.Set("blessingsOverride", value)
	end)
	overrideCheck.text:SetJustifyH("LEFT")

	-- 2) Buffs I want as talent buttons naming their caster; every class's self
	-- buffs get a button, shown only for their class.
	wants = {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do wants[buff.key] = toggleButton(trees[2], buff, "wants", wantTooltip) end
	for _, buff in ipairs(Buffs.SELF_BUFFS) do wants[buff.key] = toggleButton(trees[2], buff, "wants", wantTooltip) end
	for _, button in pairs(wants) do button.caster:SetPoint("TOP", button, "BOTTOM", 0, -4) end

	-- 3) Tank buffs, with an automatic role and an override for unassigned groups.
	local tanks = trees[3]
	roleButton = ns.UI.Button(tanks, "", 120, function()
		ns.Preferences.Set("tankRole", NEXT_ROLE[ns.db.tankRole])
	end)
	roleButton:SetPoint("TOPLEFT", 14, -84)
	roleText = ns.UI.Text(tanks, "GameFontHighlightSmall", 14, -114)
	tankButtons = {}
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local button = toggleButton(tanks, buff, "tankBuffs", tankTooltip)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.label:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, -3)
		button.label:SetJustifyH("LEFT"); button.label:SetWordWrap(false); button.label:SetText(buff.label)
		button.caster:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, -23)
		button.caster:SetJustifyH("LEFT")
		tankButtons[buff.key] = button
	end
	tankTip = ns.UI.Text(tanks, "GameFontDisableSmall", 14, -286, nil,
		"Auto follows your Tank role or raid main-tank assignment. Click Role to override it. Buff choices apply only while tanking.")

	ns.UI.Button(personal, "Announce to group", 160, function() ns.Assignments.Announce() end):SetPoint("BOTTOM", 0, 10)
	personal.wants, personal.tankButtons, personal.tankRole = wants, tankButtons, roleButton
	personal.rankList, personal.rankRows, personal.rankGhost = list, list.rows, list.ghost
end
