-- My buff preferences: saved choices, their defaults and migrations, and the
-- shape the solver and other group members receive.
local _, ns = ...
local Buffs = ns.Buffs
ns.Preferences = {}

-- Preferences that Reset returns to their class defaults.
local KEYS = { "order", "wants", "blessingsOverride", "tankRole", "tankBuffs", "weaponImbue", "personalBuff" }

-- Version 1 defaults (Kings first for everyone), only used to migrate untouched rankings.
local LEGACY_ORDER = {
	WARRIOR = { "KINGS", "MIGHT", "WISDOM" },
	ROGUE   = { "KINGS", "MIGHT", "WISDOM" },
	HUNTER  = { "KINGS", "MIGHT", "WISDOM" },
	MAGE    = { "KINGS", "WISDOM", "MIGHT" },
	WARLOCK = { "KINGS", "WISDOM", "MIGHT" },
	PRIEST  = { "KINGS", "WISDOM", "MIGHT" },
	DRUID   = { "KINGS", "WISDOM", "MIGHT" },
	PALADIN = { "KINGS", "WISDOM", "MIGHT" },
	SHAMAN  = { "KINGS", "WISDOM", "MIGHT" },
}

local function sameOrder(a, b) return table.concat(a, ",") == table.concat(b, ",") end

local function weaponChoice(key, class)
	if key == false and (class == "SHAMAN" or ns.isDev) then return false end
	local buff = Buffs.byKey[key]
	if buff and buff.kind == "imbue" and (buff.class == class or ns.isDev) then return key end
end

local function personalChoice(key, class)
	if key == false and Buffs.PERSONAL_BUFFS[class] then return false end
	local buff = Buffs.byKey[key]
	if buff and buff.kind == "personal" and buff.class == class then return key end
end

-- Auto follows learned upgrades. Keep explicit choices across talent changes,
-- and only request their spell while it is available.
function ns.Preferences.PersonalBuff()
	local selected = ns.db.personalBuff
	if selected ~= nil then
		local buff = Buffs.byKey[selected]
		if buff and ns.WoW.KnowsAny(buff.ids) then return buff end
		return
	end
	for _, buff in ipairs(Buffs.PERSONAL_BUFFS[ns.WoW.PlayerClass()] or ns.Util.EMPTY) do
		if ns.WoW.KnowsAny(buff.ids) then return buff end
	end
end

-- Leave an unset choice open until the character learns an imbue. An explicit
-- None is saved as false, and learning more imbues leaves the first pick in place.
function ns.Preferences.SetDefaultWeaponImbue()
	if ns.db.weaponImbue ~= nil or ns.WoW.PlayerClass() ~= "SHAMAN" then return end
	for _, buff in ipairs(Buffs.WEAPON_IMBUES) do
		if ns.WoW.KnowsAny(buff.ids) then
			ns.db.weaponImbue = buff.key
			return
		end
	end
end

-- Fill in and migrate my saved preferences; runs after Database.Init.
function ns.Preferences.Init()
	local db, class = ns.db, ns.WoW.PlayerClass()
	db.order = Buffs.NormalizeOrder(db.order or Buffs.DefaultOrder(class), class)
	-- Untouched rankings from before the class-specific defaults move to the new ones.
	if (db.defaultOrderVersion or 1) < Buffs.DEFAULT_ORDER_VERSION
		and not db.blessingsOverride and sameOrder(db.order, LEGACY_ORDER[class] or LEGACY_ORDER.WARRIOR) then
		db.order = Buffs.NormalizeOrder(Buffs.DefaultOrder(class), class)
	end
	db.defaultOrderVersion = Buffs.DEFAULT_ORDER_VERSION
	-- Personal rankings are the default; keep an explicitly saved choice to follow the class plan.
	if db.blessingsOverride == nil then db.blessingsOverride = true end
	-- Self buffs added after a character's wants were saved start enabled for their class.
	local defaults = Buffs.DefaultWants(class)
	db.wants = db.wants or defaults
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		if db.wants[buff.key] == nil then db.wants[buff.key] = defaults[buff.key] end
	end
	db.tankRole = ns.Database.Normalize("tankRole", db.tankRole)
	db.weaponImbue = weaponChoice(db.weaponImbue, class)
	db.personalBuff = personalChoice(db.personalBuff, class)
	db.tankBuffs = db.tankBuffs or {}
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		if db.tankBuffs[buff.key] == nil then db.tankBuffs[buff.key] = true end
	end
end

function ns.Preferences.IsTank()
	if ns.db.tankRole == "TANK" then return true end
	if ns.db.tankRole == "OFF" then return false end
	return ns.WoW.IsTank("player")
end

-- The saved blessing ranking; the ranking view reorders it in place.
function ns.Preferences.Order() return ns.db.order end

-- Preview either blessing mode without changing saved preferences or broadcasting.
function ns.Preferences.BlessingOutcome(override)
	local source, me = ns.Assignments.roster, ns.WoW.Me()
	if not source.members[me] then return {} end
	local roster, mine = {}, {}
	for key, value in pairs(source) do roster[key] = value end
	roster.members = {}
	for name, member in pairs(source.members) do roster.members[name] = member end
	for key, value in pairs(source.members[me]) do mine[key] = value end
	mine.blessingsOverride = override
	mine.ranking = Buffs.NormalizeOrder(override and ns.db.order or Buffs.DefaultOrder(mine.class), mine.class)
	roster.members[me] = mine
	return ns.Solver.Solve(roster).expected[me] or {}
end

-- My own preferences in the shape the solver wants.
function ns.Preferences.Get(includePersonal)
	local class, tank = ns.WoW.PlayerClass(), ns.Preferences.IsTank()
	local ranking = Buffs.NormalizeOrder(ns.db.order, class)
	local wants = {}
	for key, value in pairs(ns.db.wants) do wants[key] = value end
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		wants[buff.key] = tank and ns.db.tankBuffs[buff.key] and Buffs.OfferedTo(buff, class) or false
	end
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		wants[buff.key] = wants[buff.key] and Buffs.OfferedTo(buff, class) or false
	end
	local personal = includePersonal and ns.Preferences.PersonalBuff()
	if personal then wants[personal.key] = true end
	return { wants = wants, ranking = ranking, blessingsOverride = ns.db.blessingsOverride }
end

function ns.Preferences.Changed()
	ns.Events.Emit("PreferencesChanged")
end

-- Change one preference and share it.
function ns.Preferences.Set(key, value)
	if key == "weaponImbue" then value = weaponChoice(value, ns.WoW.PlayerClass()) end
	if key == "personalBuff" then value = personalChoice(value, ns.WoW.PlayerClass()) end
	ns.db[key] = ns.Database.Normalize(key, value)
	ns.Preferences.Changed()
end

-- Flip one buff in a saved set ("wants" or "tankBuffs").
function ns.Preferences.Toggle(set, key)
	ns.db[set][key] = not ns.db[set][key]
	ns.Preferences.Changed()
end

-- Return my preferences to their class defaults; other settings stay.
function ns.Preferences.Reset()
	for _, key in ipairs(KEYS) do ns.db[key] = nil end
	ns.Preferences.Init()
	ns.Preferences.SetDefaultWeaponImbue()
	ns.Preferences.Changed()
end
