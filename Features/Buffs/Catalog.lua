-- Buffeteria: static buff data (Classic/vanilla spell set).
local _, ns = ...

local Buffs = {}
ns.Buffs = Buffs

-- Single-source "group" buffs. Each class splits the raid groups between its casters.
-- ids = every rank of the single-target spell, groupIds = every rank of the party version.
-- want = class default: true for everyone, "mana" for mana users, false for nobody.
Buffs.GROUP_BUFFS = {
	{ key = "FORT",   class = "PRIEST", label = "Fortitude",         ids = {1243,1244,1245,2791,10937,10938}, groupIds = {21562,21564}, reagents = {17028,17029}, want = true },
	{ key = "SPIRIT", class = "PRIEST", label = "Divine Spirit",     ids = {14752,14818,14819,27841},         groupIds = {27681},       reagents = {17029}, want = "mana" },
	{ key = "SHADOW", class = "PRIEST", label = "Shadow Protection", ids = {976,10957,10958},                 groupIds = {27683},       reagents = {17029}, want = false },
	{ key = "MOTW",   class = "DRUID",  label = "Mark of the Wild",  ids = {1126,5232,6756,5234,8907,9884,9885}, groupIds = {21849,21850}, reagents = {17021,17026}, want = true },
	{ key = "INT",    class = "MAGE",   label = "Arcane Intellect",  ids = {1459,1460,1461,10156,10157},      groupIds = {23028},       reagents = {17020}, want = "mana" },
}

-- Tank requests are single-target buffs; Righteous Fury can only be self-cast.
Buffs.TANK_BUFFS = {
	{ key = "RFURY", class = "PALADIN", label = "Righteous Fury", ids = {25780}, groupIds = {}, selfOnly = true },
	{ key = "THORNS", class = "DRUID", label = "Thorns", ids = {467,782,1075,8914,9756,9910}, groupIds = {} },
}

-- Personal self buffs, offered only to their class. Battle Shout (two minutes) and
-- Inner Fire (ten minutes) warn shortly before expiring instead of at the global
-- threshold. combat = the tracker keeps offering them during combat, when the client
-- hides auras; duration (seconds) dates a recast until the aura is readable again.
Buffs.SELF_BUFFS = {
	{ key = "BSHOUT", class = "WARRIOR", label = "Battle Shout", ids = {6673,5242,6192,11549,11550,11551,25289}, groupIds = {}, selfOnly = true, warnSeconds = 30, combat = true, duration = 120 },
	{ key = "IFIRE", class = "PRIEST", label = "Inner Fire", ids = {588,7128,602,1006,10951,10952}, groupIds = {}, selfOnly = true, warnSeconds = 60, combat = true, duration = 600 },
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
Buffs.BLESSING_REAGENT = 21177 -- Symbol of Kings, for every Greater Blessing

-- Paladin auras, in auto-assignment priority. Each paladin runs one; no two share one.
Buffs.AURAS = {
	{ key = "DEVO",      label = "Devotion Aura",          ids = {465,10290,643,10291,1032,10292,10293} },
	{ key = "CONC",      label = "Concentration Aura",     ids = {19746} },
	{ key = "SANCTITY",  label = "Sanctity Aura",          ids = {20218} },
	{ key = "RETRI",     label = "Retribution Aura",       ids = {7294,10298,10299,10300,10301} },
	{ key = "FIRERES",   label = "Fire Resistance Aura",   ids = {19891,19899,19900} },
	{ key = "FROSTRES",  label = "Frost Resistance Aura",  ids = {19888,19897,19898} },
	{ key = "SHADOWRES", label = "Shadow Resistance Aura", ids = {19876,19895,19896} },
}

Buffs.byKey = {}
for _, b in ipairs(Buffs.GROUP_BUFFS) do b.kind = "group"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.TANK_BUFFS) do b.kind = "tank"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.SELF_BUFFS) do b.kind = "self"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.BLESSINGS) do b.kind = "blessing"; b.reagents = { Buffs.BLESSING_REAGENT }; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.AURAS) do b.kind = "aura"; b.groupIds = {}; Buffs.byKey[b.key] = b end

-- Single-target buffs the tracker casts one player at a time.
Buffs.SINGLE_BUFFS = {}
for _, b in ipairs(Buffs.TANK_BUFFS) do Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end
for _, b in ipairs(Buffs.SELF_BUFFS) do Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end

Buffs.BLESSING_KEYS = {}
for _, b in ipairs(Buffs.BLESSINGS) do Buffs.BLESSING_KEYS[#Buffs.BLESSING_KEYS + 1] = b.key end
Buffs.AURA_KEYS = {}
for _, b in ipairs(Buffs.AURAS) do Buffs.AURA_KEYS[#Buffs.AURA_KEYS + 1] = b.key end

Buffs.CLASS_KEYS = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN" }

Buffs.MANA_CLASSES = { PALADIN = true, PRIEST = true, DRUID = true, MAGE = true, WARLOCK = true, SHAMAN = true, HUNTER = true }

-- Default blessing order per class. Everything after "|" is "don't want".
-- Melee lead with Might, mana users with Wisdom, hunters with Kings (agility;
-- Might has no effect on ranged attack power). Kings and Salvation follow for everyone.
Buffs.DEFAULT_ORDER_VERSION = 2
Buffs.DEFAULT_ORDER = {
	WARRIOR = { "MIGHT", "KINGS", "SALV", "LIGHT", "SANCT", "|", "WISDOM" },
	ROGUE   = { "MIGHT", "KINGS", "SALV", "LIGHT", "SANCT", "|", "WISDOM" },
	HUNTER  = { "KINGS", "WISDOM", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
	MAGE    = { "WISDOM", "KINGS", "SALV", "LIGHT", "SANCT", "|", "MIGHT" },
	WARLOCK = { "WISDOM", "KINGS", "SALV", "LIGHT", "SANCT", "|", "MIGHT" },
	PRIEST  = { "WISDOM", "KINGS", "SALV", "LIGHT", "SANCT", "|", "MIGHT" },
	DRUID   = { "WISDOM", "KINGS", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
	PALADIN = { "WISDOM", "KINGS", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
	SHAMAN  = { "WISDOM", "KINGS", "SALV", "MIGHT", "LIGHT", "SANCT", "|" },
}

function Buffs.DefaultOrder(class) return Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR end

-- Whether a buff is offered to a class: self-only buffs belong to their own class.
function Buffs.OfferedTo(buff, class) return not buff.selfOnly or buff.class == class end

-- Buffs a class can ask for in the Buffs tree: group buffs, then its own self buffs.
function Buffs.Wantable(class)
	local out = {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do out[#out + 1] = buff end
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		if Buffs.OfferedTo(buff, class) then out[#out + 1] = buff end
	end
	return out
end

function Buffs.DefaultWants(class)
	local mana, wants = Buffs.MANA_CLASSES[class] or false, {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do wants[buff.key] = buff.want == true or (buff.want == "mana" and mana) end
	for _, buff in ipairs(Buffs.SELF_BUFFS) do wants[buff.key] = buff.class == class end
	return wants
end

-- Whether capabilities include the single or the group/Greater version of a spell.
function Buffs.CanCast(caps, key) return caps ~= nil and (caps[key] or caps["g" .. key]) or false end

-- What we assume a player WITHOUT the add-on can cast (talents unknown, so be conservative).
Buffs.ASSUMED_CAPS = {
	PALADIN = { MIGHT = true, WISDOM = true, SALV = true, LIGHT = true,
		DEVO = true, RETRI = true, FIRERES = true, FROSTRES = true, SHADOWRES = true },
	PRIEST  = { FORT = true, SHADOW = true },
	DRUID   = { MOTW = true, THORNS = true },
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

function Buffs.DefaultRanking(class) return Buffs.SplitOrder(Buffs.DefaultOrder(class)) end

-- Make sure an order list contains every blessing exactly once plus the divider.
function Buffs.NormalizeOrder(order, class)
	local seen, out, hasBar = {}, {}, false
	for _, k in ipairs(order or {}) do
		if k == "|" and not hasBar then hasBar = true; out[#out + 1] = k
		elseif Buffs.byKey[k] and Buffs.byKey[k].kind == "blessing" and not seen[k] then seen[k] = true; out[#out + 1] = k end
	end
	if not hasBar then out[#out + 1] = "|" end
	for _, k in ipairs(Buffs.DefaultOrder(class)) do
		if k ~= "|" and not seen[k] then seen[k] = true; table.insert(out, k) end
	end
	return out
end
