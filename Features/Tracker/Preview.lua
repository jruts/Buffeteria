-- Buffeteria: preview mode. Fills the tracker with a fake raid
-- that cycles through "empty", "missing", "running low" and "all fed" so you can see
-- how it looks. Nothing is cast and nothing is sent to other players.
local _, ns = ...
local Buffs = ns.Buffs

local Preview = { active = false }
ns.Tracker.Preview = Preview

local PHASE_SECONDS = 5
local FAKE = {
	{ "Thrallbuster", "WARRIOR" }, { "Shieldwalla", "WARRIOR" }, { "Bonkmaster", "WARRIOR" },
	{ "Stabbity", "ROGUE" }, { "Sneakypete", "ROGUE" },
	{ "Pewpewlazor", "HUNTER" }, { "Arrowsmith", "HUNTER" },
	{ "Frostbyte", "MAGE" }, { "Pyromancy", "MAGE" }, { "Sheepish", "MAGE" },
	{ "Doomscroll", "WARLOCK" }, { "Felbrain", "WARLOCK" },
	{ "Holyhandgren", "PRIEST" }, { "Fortitudes", "PRIEST" },
	{ "Moonkinz", "DRUID" }, { "Barkskin", "DRUID" },
	{ "Bubblehearth", "PALADIN" }, { "Kingsley", "PALADIN" }, { "Mightymouse", "PALADIN" },
	{ "Chainheals", "SHAMAN" }, { "Totemtom", "SHAMAN" },
}
local KEYS = { "KINGS", "MIGHT", "WISDOM", "SALV", "LIGHT", "FORT", "SPIRIT", "SHADOW", "MOTW", "INT" }
local PHASES = { "empty", "bad", "warn", "ok" }
-- What the player's class would be asked to cast; other classes only receive.
local CLASS_CAST = { PALADIN = "KINGS", PRIEST = "FORT", DRUID = "MOTW", MAGE = "INT" }

-- Deterministic pseudo-random so each phase looks the same every cycle.
local function roll(i, j, phase) return ((i * 7 + j * 13 + phase * 31) % 17) end

function Preview.Summary()
	local phaseIndex = math.floor(GetTime() / PHASE_SECONDS) % #PHASES
	local empty = PHASES[phaseIndex + 1] == "empty"
	local phase = empty and "bad" or PHASES[phaseIndex + 1]
	local s = { overall = phase, perKey = {}, problems = {}, any = true, yours = {}, needs = {} }
	for _, key in ipairs(KEYS) do s.perKey[key] = { bad = 0, warn = 0, total = #FAKE } end

	if phase ~= "ok" then
		for i, who in ipairs(FAKE) do
			for j, key in ipairs(KEYS) do
				local r = roll(i, j, phaseIndex)
				local st
				if empty then st = "bad"
				elseif phase == "bad" then st = (r < 2 and "bad") or (r < 5 and "warn") or nil
				else st = (r < 4 and "warn") or nil end
				if st then
					s.perKey[key][st] = s.perKey[key][st] + 1
					table.insert(s.problems, { who = who[1], class = who[2], key = key, status = st,
						rem = st == "warn" and (30 + r * 15) or nil })
				end
			end
		end
		if phase == "bad" then
			table.insert(s.problems, { who = "Shieldwalla", class = "WARRIOR", key = "SALV", status = "unwanted" })
		end
		table.sort(s.problems, ns.Tracker.Status.CompareProblems)
		local key = CLASS_CAST[ns.WoW.PlayerClass()]
		if key then
			local b = Buffs.byKey[key]
			s.next = { spell = ns.WoW.SpellName(b.groupIds[1]) or b.label, icon = ns.WoW.SpellIcon(b.groupIds[1]),
				label = ns.WoW.ClassName("WARRIOR"), key = key, status = phase }
			s.yours[key] = true
		else
			s.needs[1] = { key = "KINGS", status = phase, caster = "Kingsley" }
		end
	end
	return s
end

function Preview.Set(on)
	Preview.active = on and true or false
	ns.WoW.Print(Preview.active and "preview on: a fake raid is on the menu (nothing will be cast)." or "preview off.")
	ns.Events.Emit("PreviewChanged")
end

function Preview.Toggle() Preview.Set(not Preview.active) end
