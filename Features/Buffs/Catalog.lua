-- Buffeteria: WoW Forever buff data.
local _, ns = ...

local Buffs = {}
ns.Buffs = Buffs

-- Group buffs have a single-target spell and a raid-wide version.
-- Reagents follow the rank order in groupIds, or use one common item.
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
	{ key = "THORNS", class = "DRUID", label = "Thorns", ids = {467,782,1075,8914,9756,9910}, groupIds = {}, duration = 600 },
}

-- Encounter buffs are explicitly requested by the recipient.
Buffs.ENCOUNTER_BUFFS = {
	{ key = "FWARD", class = "PRIEST", label = "Fear Ward", ids = {6346}, groupIds = {}, duration = 180, cooldown = true },
}

-- Raid support is enabled by its caster. The optional aura IDs are the effects
-- applied to players, separate from the spells used to summon a totem or shapeshift.
Buffs.RAID_SUPPORT = {
	{ key = "TRUESHOT", class = "HUNTER", label = "Trueshot Aura", ids = {1299346,1299348,19506,20905,20906}, duration = 1800, raidRadius = 45 },
	{ key = "STRENGTHEARTH", class = "SHAMAN", label = "Strength of Earth Totem", ids = {8075,8160,8161,10442,25361},
		auraIds = {8076,8162,8163,10441,25362}, totemSlot = 2 },
	{ key = "WINDFURYTOTEM", class = "SHAMAN", label = "Windfury Totem", ids = {8512,10613,10614},
		auraIds = {8515,10609,10612}, totemSlot = 4 },
	{ key = "GRACEOFAIR", class = "SHAMAN", label = "Grace of Air Totem", ids = {8835,10627,25359},
		auraIds = {8836,10626,25360}, totemSlot = 4 },
	{ key = "DRUIDCRIT", class = "DRUID", label = "Druid crit aura", ids = {17007,24858},
		auraIds = {24932,24907}, passive = true, raidRadius = 45 },
}

-- Personal self buffs, offered only to their class. combat = the tracker keeps
-- offering them during combat, when the client hides auras. Base duration (seconds)
-- dates a recast and supplies a fallback when the aura's duration is unavailable.
Buffs.SELF_BUFFS = {
	{ key = "BSHOUT", class = "WARRIOR", label = "Battle Shout", ids = {6673,5242,6192,11549,11550,11551,25289}, groupIds = {}, selfOnly = true, combat = true, duration = 180, raidRadius = 20 },
	{ key = "IFIRE", class = "PRIEST", label = "Inner Fire", ids = {588,7128,602,1006,10951,10952}, groupIds = {}, selfOnly = true, combat = true, duration = 600 },
}

-- One maintained armor or shield per class, in automatic selection priority.
Buffs.PERSONAL_BUFFS = {
	MAGE = {
		{ key = "ICEARMOR", label = "Ice Armor", ids = {7302,7320,10219,10220}, duration = 1800 },
		{ key = "FROSTARMOR", label = "Frost Armor", ids = {168,7300,7301}, duration = 1800 },
		{ key = "MAGEARMOR", label = "Mage Armor", ids = {6117,22782,22783}, duration = 1800 },
	},
	WARLOCK = {
		{ key = "DEMONARMOR", label = "Demon Armor", ids = {706,1086,11733,11734,11735}, duration = 1800 },
		{ key = "DEMONSKIN", label = "Demon Skin", ids = {687,696}, duration = 1800 },
	},
	SHAMAN = {
		{ key = "LIGHTNINGSHIELD", label = "Lightning Shield", ids = {324,325,905,945,8134,10431,10432}, duration = 600 },
		{ key = "WATERSHIELD", label = "Water Shield", ids = {408510}, duration = 600 },
	},
}

-- Forever main-hand imbues have their own enchant type, alongside oils and stones.
-- enchantIds covers every rank of the applied enchant, independently of spell IDs.
Buffs.WEAPON_IMBUES = {
	{ key = "ROCKBITER", label = "Rockbiter Weapon", ids = {8017,8018,8019,10399,16314,16315,16316}, enchantIds = {29,6,1,503,1663,683,1664} },
	{ key = "FLAMETONGUE", label = "Flametongue Weapon", ids = {8024,8027,8030,16339,16341,16342}, enchantIds = {5,4,3,523,1665,1666} },
	{ key = "FROSTBRAND", label = "Frostbrand Weapon", ids = {8033,8038,10456,16355,16356}, enchantIds = {2,12,524,1667,1668} },
	{ key = "WINDFURY", label = "Windfury Weapon", ids = {8232,8235,10486,16362}, enchantIds = {283,284,525,1669} },
}

-- Paladin blessings. Greater versions hit every member of the target's class.
Buffs.BLESSINGS = {
	{ key = "KINGS",  label = "Kings",     ids = {20217},                                   groupIds = {25898} },
	{ key = "MIGHT",  label = "Might",     ids = {19740,19834,19835,19836,19837,19838,25291}, groupIds = {25782,25916} },
	{ key = "WISDOM", label = "Wisdom",    ids = {19742,19850,19852,19853,19854,25290},     groupIds = {25894,25918} },
}
Buffs.BLESSING_REAGENT = 21177 -- Symbol of Kings, for every Greater Blessing

-- Paladin auras, in auto-assignment priority. Each paladin runs one; no two share one.
Buffs.AURAS = {
	{ key = "DEVO",      label = "Devotion Aura",          ids = {465,10290,643,10291,1032,10292,10293} },
	{ key = "CONC",      label = "Concentration Aura",     ids = {19746} },
	{ key = "RETRI",     label = "Retribution Aura",       ids = {7294,10298,10299,10300,10301} },
	{ key = "FIRERES",   label = "Fire Resistance Aura",   ids = {19891,19899,19900} },
	{ key = "FROSTRES",  label = "Frost Resistance Aura",  ids = {19888,19897,19898} },
	{ key = "SHADOWRES", label = "Shadow Resistance Aura", ids = {19876,19895,19896} },
}

Buffs.byKey = {}
for _, b in ipairs(Buffs.GROUP_BUFFS) do b.kind = "group"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.TANK_BUFFS) do b.kind = "tank"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.ENCOUNTER_BUFFS) do b.kind = "encounter"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.RAID_SUPPORT) do b.kind = "raidSupport"; b.groupIds = {}; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.SELF_BUFFS) do b.kind = "self"; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.WEAPON_IMBUES) do
	b.kind, b.class, b.selfOnly, b.groupIds, b.duration = "imbue", "SHAMAN", true, {}, 3600
	Buffs.byKey[b.key] = b
end
for _, b in ipairs(Buffs.BLESSINGS) do b.kind = "blessing"; b.reagents = { Buffs.BLESSING_REAGENT }; Buffs.byKey[b.key] = b end
for _, b in ipairs(Buffs.AURAS) do b.kind = "aura"; b.groupIds = {}; Buffs.byKey[b.key] = b end

-- Single-target buffs the tracker casts one player at a time.
Buffs.SINGLE_BUFFS = {}
for _, b in ipairs(Buffs.TANK_BUFFS) do Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end
for _, b in ipairs(Buffs.ENCOUNTER_BUFFS) do Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end
for _, b in ipairs(Buffs.SELF_BUFFS) do
	if not b.raidRadius then Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end
end
for _, b in ipairs(Buffs.WEAPON_IMBUES) do Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b end
for class, choices in pairs(Buffs.PERSONAL_BUFFS) do
	for _, b in ipairs(choices) do
		b.kind, b.class, b.selfOnly, b.groupIds = "personal", class, true, {}
		Buffs.byKey[b.key] = b
		Buffs.SINGLE_BUFFS[#Buffs.SINGLE_BUFFS + 1] = b
	end
end

Buffs.BLESSING_KEYS = {}
for _, b in ipairs(Buffs.BLESSINGS) do Buffs.BLESSING_KEYS[#Buffs.BLESSING_KEYS + 1] = b.key end
Buffs.AURA_KEYS = {}
for _, b in ipairs(Buffs.AURAS) do Buffs.AURA_KEYS[#Buffs.AURA_KEYS + 1] = b.key end

Buffs.CLASS_KEYS = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN" }

Buffs.MANA_CLASSES = { PALADIN = true, PRIEST = true, DRUID = true, MAGE = true, WARLOCK = true, SHAMAN = true, HUNTER = true }

-- Default blessing order per class, from highest to lowest priority.
-- Melee lead with Might, mana users with Wisdom, hunters with Kings (agility;
-- Might has no effect on ranged attack power).
Buffs.DEFAULT_ORDER_VERSION = 2
Buffs.DEFAULT_ORDER = {
	WARRIOR = { "MIGHT", "KINGS", "WISDOM" },
	ROGUE   = { "MIGHT", "KINGS", "WISDOM" },
	HUNTER  = { "KINGS", "WISDOM", "MIGHT" },
	MAGE    = { "WISDOM", "KINGS", "MIGHT" },
	WARLOCK = { "WISDOM", "KINGS", "MIGHT" },
	PRIEST  = { "WISDOM", "KINGS", "MIGHT" },
	DRUID   = { "WISDOM", "KINGS", "MIGHT" },
	PALADIN = { "WISDOM", "KINGS", "MIGHT" },
	SHAMAN  = { "WISDOM", "KINGS", "MIGHT" },
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

-- A bare spell name casts the highest learned rank. Use that rank's reagent.
function Buffs.CastableGroupRank(buff)
	local _, id = ns.WoW.KnowsAny(buff.groupIds)
	for rank, groupID in ipairs(buff.groupIds) do
		if groupID == id then
			local reagent = buff.reagents[rank] or buff.reagents[1]
			if ns.WoW.ItemCount(reagent) > 0 then return id end
		end
	end
end

-- Minimum levels for baseline spells we assume players without the add-on know.
Buffs.ASSUMED_CAPS = {
	PALADIN = { KINGS = 20, MIGHT = 4, WISDOM = 14,
		DEVO = 1, CONC = 22, RETRI = 16, FIRERES = 36, FROSTRES = 32, SHADOWRES = 28 },
	PRIEST  = { FORT = 1, SPIRIT = 30, SHADOW = 30, FWARD = 20 },
	DRUID   = { MOTW = 1, THORNS = 6 },
	MAGE    = { INT = 1 },
}

function Buffs.DefaultRanking(class) return Buffs.NormalizeOrder(Buffs.DefaultOrder(class), class) end

-- Keep every blessing exactly once. Old saved dividers and unknown entries are
-- discarded without changing the relative order of the blessings around them.
function Buffs.NormalizeOrder(order, class)
	local seen, out = {}, {}
	for _, k in ipairs(order or {}) do
		if Buffs.byKey[k] and Buffs.byKey[k].kind == "blessing" and not seen[k] then seen[k] = true; out[#out + 1] = k end
	end
	for _, k in ipairs(Buffs.DefaultOrder(class)) do
		if not seen[k] then seen[k] = true; table.insert(out, k) end
	end
	return out
end
