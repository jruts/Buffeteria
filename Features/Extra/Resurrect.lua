-- Resurrect dead group members with the head, for every class that can.
local _, ns = ...
local Resurrect = {}
ns.Extra = { Resurrect = Resurrect }
-- Each class's resurrection, ranks lowest first.
local SPELLS = {
	PRIEST = { 2006, 2010, 10880, 10881, 20770 },   -- Resurrection
	PALADIN = { 7328, 10322, 10324, 20772, 20773 }, -- Redemption
	SHAMAN = { 2008, 20609, 20610, 20776, 20777 },  -- Ancestral Spirit
	DRUID = { 20484, 20739, 20742, 20747, 20748 },  -- Rebirth
}
local GCD = 1.5
local OFFER = 60    -- how long a resurrection waits for its answer
local offered = {}  -- [full] = when my offer to them lapses

function Resurrect.CanClass(class) return SPELLS[class] ~= nil end

-- My class's resurrection by name, learned or not; nil when my class has none.
function Resurrect.SpellName()
	local ids = SPELLS[ns.WoW.PlayerClass()]
	return ids and ns.WoW.SpellName(ids[1])
end

-- The highest rank I know: castable name, icon and ID.
local function known()
	local ok, id = ns.WoW.KnowsAny(SPELLS[ns.WoW.PlayerClass()] or {})
	if not ok then return nil end
	return ns.WoW.SpellName(id), ns.WoW.SpellIcon(id), id
end

-- Enough mana and reagents, and no cooldown beyond the global one: a Rebirth
-- on cooldown would otherwise hold the head up for half an hour.
local function ready(spell)
	local check = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
	if check then
		local ok, usable = pcall(check, spell)
		if ok and not usable then return false end
	end
	local start, duration = ns.WoW.SpellCooldown(spell)
	return not (start and duration > GCD and start + duration > GetTime())
end

-- A player waiting for a resurrection: dead or released (a ghost can accept it
-- too), not feigning, online, and not already being resurrected by someone else.
local function corpse(unit)
	return UnitIsDeadOrGhost(unit)
		and not (UnitIsFeignDeath and UnitIsFeignDeath(unit)) and UnitIsConnected(unit)
		and not (UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit))
end

-- My resurrection landed: leave them alone while they decide.
function Resurrect.Offered(full) offered[full] = GetTime() + OFFER end

-- The resurrection the head should cast, shaped like Actions.Next's casts, or
-- nil. Members who can resurrect go first so they can help with the rest.
function Resurrect.Next(roster, now)
	if UnitIsDeadOrGhost("player") then return nil end
	local me, dead = ns.WoW.Me(), {}
	for full, unit in pairs(roster.units) do
		if full ~= me and corpse(unit) then
			if (offered[full] or 0) <= now then dead[#dead + 1] = full end
		elseif not UnitIsDeadOrGhost(unit) then
			offered[full] = nil
		end
	end
	if #dead == 0 then return nil end
	local spell, icon, id = known()
	if not spell or not ready(spell) then return nil end
	local function healer(full) return Resurrect.CanClass((roster.members[full] or {}).class) end
	table.sort(dead, function(a, b)
		if healer(a) ~= healer(b) then return healer(a) end
		return a < b
	end)
	for _, full in ipairs(dead) do
		local unit = roster.units[full]
		if ns.WoW.SpellInRange(spell, unit) then
			return { spell = spell, icon = icon, spellID = id, unit = unit, who = full, key = "RESURRECT",
				status = "bad", big = false, label = ns.WoW.Short(full), covers = { full }, resurrect = true }
		end
	end
end
