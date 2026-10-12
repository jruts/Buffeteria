-- Persisted character settings; preserve existing keys and migrations.
local _, ns = ...
local Buffs = ns.Buffs
ns.Database = {}

-- Numeric settings: { minimum, maximum, step, default }. Controls read their range here.
ns.Database.RANGES = {
	iconSize = { 32, 128, 4, 64 },
	statusIconSize = { 16, 64, 1, 21 },
	shoutSize = { 10, 24, 1, 16 },
	warnMinutes = { 1, 15, 1, 5 },
}
local CHOICES = {
	buffDisplay = { "PROBLEMS", "ALL", "MISSING", "EXPIRING" },
	iconsPerRow = { 2, 3, 4 },
	iconPosition = { "BOTTOM", "LEFT", "TOP", "RIGHT", "AUTO" },
	tankRole = { "AUTO", "TANK", "OFF" },
}
-- Preferences that Preferences.Reset returns to their class defaults.
local PREFERENCE_KEYS = { "order", "wants", "blessingsOverride", "tankRole", "tankBuffs" }

-- Version 1 defaults (Kings first for everyone), only used to migrate untouched rankings.
local LEGACY_ORDER = {
	WARRIOR = { "KINGS", "MIGHT", "SALV", "LIGHT", "SANCT", "|", "WISDOM" },
	ROGUE   = { "KINGS", "MIGHT", "SALV", "LIGHT", "SANCT", "|", "WISDOM" },
	HUNTER  = { "KINGS", "MIGHT", "SALV", "WISDOM", "LIGHT", "SANCT", "|" },
	MAGE    = { "KINGS", "SALV", "WISDOM", "LIGHT", "SANCT", "|", "MIGHT" },
	WARLOCK = { "KINGS", "SALV", "WISDOM", "LIGHT", "SANCT", "|", "MIGHT" },
	PRIEST  = { "KINGS", "WISDOM", "SALV", "LIGHT", "SANCT", "|", "MIGHT" },
	DRUID   = { "KINGS", "WISDOM", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
	PALADIN = { "KINGS", "WISDOM", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
	SHAMAN  = { "KINGS", "WISDOM", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
}

local function sameOrder(a, b) return table.concat(a, ",") == table.concat(b, ",") end

-- A stored choice, or the first allowed value when it is missing or unknown.
local function choice(key, value)
	for _, allowed in ipairs(CHOICES[key]) do if allowed == value then return value end end
	return CHOICES[key][1]
end

local function inRange(key, value)
	local minimum, maximum, step, default = unpack(ns.Database.RANGES[key])
	return math.max(minimum, math.min(maximum, math.floor((tonumber(value) or default) / step + 0.5) * step))
end

local function initPreferences(db, class)
	db.order = Buffs.NormalizeOrder(db.order or Buffs.DefaultOrder(class), class)
	-- Untouched rankings from before the class-specific defaults move to the new ones.
	if (db.defaultOrderVersion or 1) < Buffs.DEFAULT_ORDER_VERSION
		and not db.blessingsOverride and sameOrder(db.order, LEGACY_ORDER[class] or LEGACY_ORDER.WARRIOR) then
		db.order = Buffs.NormalizeOrder(Buffs.DefaultOrder(class), class)
	end
	db.defaultOrderVersion = Buffs.DEFAULT_ORDER_VERSION
	-- Preserve deliberate rankings from before the explicit override toggle existed.
	if db.blessingsOverride == nil then db.blessingsOverride = not sameOrder(db.order, Buffs.DefaultOrder(class)) end
	-- Self buffs added after a character's wants were saved start enabled for their class.
	local defaults = Buffs.DefaultWants(class)
	db.wants = db.wants or defaults
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		if db.wants[buff.key] == nil then db.wants[buff.key] = defaults[buff.key] end
	end
	db.tankRole = choice("tankRole", db.tankRole)
	db.tankBuffs = db.tankBuffs or {}
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		if db.tankBuffs[buff.key] == nil then db.tankBuffs[buff.key] = true end
	end
end

function ns.Database.Init()
	_G[ns.savedVariable] = _G[ns.savedVariable] or {}
	local db = _G[ns.savedVariable]
	initPreferences(db, ns.WoW.PlayerClass())
	db.paladinBlessings = db.paladinBlessings or {}
	if db.showTracker == nil then db.showTracker = true end
	db.locked = db.locked or false
	db.minimap = db.minimap or { angle = 200, hide = false }
	-- onlyProblems is the setting's pre-buffDisplay form.
	if db.onlyProblems == false and db.buffDisplay == nil then db.buffDisplay = "ALL" end
	for key in pairs(CHOICES) do db[key] = choice(key, key == "iconsPerRow" and tonumber(db[key]) or db[key]) end
	for key in pairs(ns.Database.RANGES) do db[key] = inRange(key, db[key]) end
	ns.db = db
end

-- Return my preferences to their class defaults; other settings stay.
function ns.Database.ResetPreferences()
	for _, key in ipairs(PREFERENCE_KEYS) do ns.db[key] = nil end
	initPreferences(ns.db, ns.WoW.PlayerClass())
end

-- Change a display setting and let every view follow.
function ns.Database.Set(key, value)
	ns.db[key] = value
	ns.Events.Emit("SettingsChanged")
end
