-- Buffeteria: static buff data (Classic/vanilla spell set).
local _, ns = ...

local Buffs = {}
ns.Buffs = Buffs

-- Single-source "group" buffs. Each class splits the raid groups between its casters.
-- ids = every rank of the single-target spell, groupIds = every rank of the party version.
Buffs.GROUP_BUFFS = {
	{ key = "FORT",   class = "PRIEST", label = "Fortitude",         ids = {1243,1244,1245,2791,10937,10938}, groupIds = {21562,21564}, reagents = {17028,17029} },
	{ key = "SPIRIT", class = "PRIEST", label = "Divine Spirit",     ids = {14752,14818,14819,27841},         groupIds = {27681},       reagents = {17029} },
	{ key = "SHADOW", class = "PRIEST", label = "Shadow Protection", ids = {976,10957,10958},                 groupIds = {27683},       reagents = {17029} },
	{ key = "MOTW",   class = "DRUID",  label = "Mark of the Wild",  ids = {1126,5232,6756,5234,8907,9884,9885}, groupIds = {21849,21850}, reagents = {17021,17026} },
	{ key = "INT",    class = "MAGE",   label = "Arcane Intellect",  ids = {1459,1460,1461,10156,10157},      groupIds = {23028},       reagents = {17020} },
}

-- Paladin blessings. Greater versions hit every member of the target's class.
Buffs.BLESSINGS = {
	{ key = "KINGS",  label = "Kings",     ids = {20217},                                   groupIds = {25898} },
	{ key = "MIGHT",  label = "Might",     ids = {19740,19834,19835,19836,19837,19838,25291}, groupIds = {25782,25916} },
	{ key = "WISDOM", label = "Wisdom",    ids = {19742,19850,19852,19853,19854,25290},     groupIds = {25894,25918} },
	{ key = "SALV",   label = "Salvation", ids = {1038},                                    groupIds = {25895} },
	{ key = "LIGHT",  label = "Light",     ids = {19977,19978,19979},                       groupIds = {25890} },
	{ key = "SANCT",  label = "Sanctuary", ids = {20911,20912,20913,20914},                 groupIds = {25899} },
}
Buffs.BLESSING_REAGENT = 21177 -- Symbol of Kings

Buffs.byKey = {}
for _, b in ipairs(Buffs.GROUP_BUFFS) do b.kind = "group"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.BLESSINGS) do b.kind = "blessing"; Buffs.byKey[b.key] = b end

Buffs.BLESSING_KEYS = {}
for _, b in ipairs(Buffs.BLESSINGS) do Buffs.BLESSING_KEYS[#Buffs.BLESSING_KEYS + 1] = b.key end

Buffs.CLASS_KEYS = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN" }

Buffs.MANA_CLASSES = { PALADIN = true, PRIEST = true, DRUID = true, MAGE = true, WARLOCK = true, SHAMAN = true, HUNTER = true }

-- Default blessing order per class. Everything after "|" is "don't want".
Buffs.DEFAULT_ORDER = {
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

function Buffs.DefaultWants(class)
	local mana = Buffs.MANA_CLASSES[class] or false
	return { FORT = true, SPIRIT = mana, SHADOW = false, MOTW = true, INT = mana }
end

-- What we assume a player WITHOUT the add-on can cast (talents unknown, so be conservative).
Buffs.ASSUMED_CAPS = {
	PALADIN = { MIGHT = true, WISDOM = true, SALV = true, LIGHT = true },
	PRIEST  = { FORT = true, SHADOW = true },
	DRUID   = { MOTW = true },
	MAGE    = { INT = true },
}

-- Split "order" (with the "|" divider) into ranking + excluded set.
function Buffs.SplitOrder(order)
	local ranking, excluded, below = {}, {}, false
	for _, k in ipairs(order or {}) do
		if k == "|" then below = true
		elseif below then excluded[k] = true
		else ranking[#ranking + 1] = k end
	end
	return ranking, excluded
end

-- Make sure an order list contains every blessing exactly once plus the divider.
function Buffs.NormalizeOrder(order, class)
	local seen, out, hasBar = {}, {}, false
	for _, k in ipairs(order or {}) do
		if k == "|" and not hasBar then hasBar = true; out[#out + 1] = k
		elseif Buffs.byKey[k] and Buffs.byKey[k].kind == "blessing" and not seen[k] then seen[k] = true; out[#out + 1] = k end
	end
	if not hasBar then out[#out + 1] = "|" end
	for _, k in ipairs((Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR)) do
		if k ~= "|" and not seen[k] then seen[k] = true; table.insert(out, k) end
	end
	return out
end
