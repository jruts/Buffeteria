-- Persisted character settings; preserve existing keys and migrations.
local _, ns = ...
local Buffs = ns.Buffs
ns.Database = {}

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

function ns.Database.Init()
	_G[ns.savedVariable] = _G[ns.savedVariable] or {}
	local db = _G[ns.savedVariable]
	local _, class = UnitClass("player")
	db.order = Buffs.NormalizeOrder(db.order or Buffs.DEFAULT_ORDER[class], class)
	-- Untouched rankings from before the class-specific defaults move to the new ones.
	if (db.defaultOrderVersion or 1) < Buffs.DEFAULT_ORDER_VERSION then
		local legacy = LEGACY_ORDER[class] or LEGACY_ORDER.WARRIOR
		if not db.blessingsOverride and table.concat(db.order, ",") == table.concat(legacy, ",") then
			db.order = Buffs.NormalizeOrder(Buffs.DEFAULT_ORDER[class], class)
		end
	end
	db.defaultOrderVersion = Buffs.DEFAULT_ORDER_VERSION
	-- Preserve deliberate rankings from before the explicit override toggle existed.
	if db.blessingsOverride == nil then
		db.blessingsOverride = table.concat(db.order, ",") ~= table.concat(Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR, ",")
	end
	db.paladinBlessings = db.paladinBlessings or {}
	if not db.wants then db.wants = Buffs.DefaultWants(class) end
	if db.tankRole ~= "TANK" and db.tankRole ~= "OFF" then db.tankRole = "AUTO" end
	db.tankBuffs = db.tankBuffs or {}
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		if db.tankBuffs[buff.key] == nil then db.tankBuffs[buff.key] = true end
	end
	db.warnMinutes = db.warnMinutes or 5
	if db.showTracker == nil then db.showTracker = true end
	db.locked = db.locked or false
	db.minimap = db.minimap or { angle = 200, hide = false }
	if db.onlyProblems == nil then db.onlyProblems = true end
	if db.buffDisplay ~= "ALL" and db.buffDisplay ~= "MISSING" and db.buffDisplay ~= "EXPIRING" and db.buffDisplay ~= "PROBLEMS" then
		db.buffDisplay = db.onlyProblems and "PROBLEMS" or "ALL"
	end
	db.iconSize = math.max(32, math.min(128, tonumber(db.iconSize) or 64))
	db.shoutSize = math.max(10, math.min(24, math.floor((tonumber(db.shoutSize) or 16) + 0.5)))
	db.statusIconSize = math.max(16, math.min(64, math.floor((tonumber(db.statusIconSize) or 21) + 0.5)))
	db.iconsPerRow = tonumber(db.iconsPerRow)
	if db.iconsPerRow ~= 2 and db.iconsPerRow ~= 3 and db.iconsPerRow ~= 4 then db.iconsPerRow = 2 end
	if db.iconPosition ~= "LEFT" and db.iconPosition ~= "TOP" and db.iconPosition ~= "RIGHT" and db.iconPosition ~= "BOTTOM" and db.iconPosition ~= "AUTO" then
		db.iconPosition = "BOTTOM"
	end
	ns.db = db
end
