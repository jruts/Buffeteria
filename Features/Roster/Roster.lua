-- Live members, preferences and spell capabilities.
local _, ns = ...
local Buffs = ns.Buffs
ns.Roster = { peers = {} }

-- What I can cast: plain key = single version, "g"..key = group/Greater version.
function ns.Roster.Capabilities()
	local caps = {}
	local class = ns.WoW.PlayerClass()
	for _, b in pairs(Buffs.byKey) do
		local paladinSpell = b.kind == "blessing" or b.kind == "aura"
		if (paladinSpell and class == "PALADIN") or (not paladinSpell and class == b.class) then
			if ns.WoW.KnowsAny(b.ids) then caps[b.key] = true end
			if ns.WoW.KnowsAny(b.groupIds) then caps["g" .. b.key] = true end
		end
	end
	return caps
end

local function eachGroupUnit(fn)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
			fn("raid" .. i, subgroup or 1, class, online, isDead)
		end
	else
		fn("player", 1, ns.WoW.PlayerClass(), true, UnitIsDeadOrGhost("player"))
		for i = 1, GetNumSubgroupMembers() do
			local u = "party" .. i
			local _, c = UnitClass(u)
			fn(u, 1, c, UnitIsConnected(u), UnitIsDeadOrGhost(u))
		end
	end
end

-- Players without the add-on get class defaults; assigned tanks also want tank buffs.
local function defaultWants(class, unit)
	local wants = Buffs.DefaultWants(class)
	if ns.WoW.IsTank(unit) then
		for _, buff in ipairs(Buffs.TANK_BUFFS) do wants[buff.key] = Buffs.OfferedTo(buff, class) end
	end
	return wants
end

function ns.Roster.Build()
	local roster = { members = {}, units = {} }
	local me = ns.WoW.Me()
	eachGroupUnit(function(unit, group, class, online, dead)
		local full = ns.WoW.FullName(unit)
		if not full or not class or not online then return end
		local m = { name = full, class = class, group = group, unit = unit, dead = dead }
		local peer = (full == me) and ns.Preferences.Get() or ns.Roster.peers[full]
		if full == me then
			m.caps, m.hasAddon = ns.Roster.Capabilities(), true
		elseif peer and peer.caps then
			m.caps, m.hasAddon = peer.caps, true
		else
			m.caps = {}
			for k, v in pairs(Buffs.ASSUMED_CAPS[class] or {}) do m.caps[k] = v end
		end
		if peer and peer.ranking then
			m.wants, m.ranking, m.excluded = peer.wants, peer.ranking, peer.excluded
			m.blessingsOverride = peer.blessingsOverride and true or false
		else
			m.wants = defaultWants(class, unit)
		end
		-- Without an explicit override, members follow their class plan.
		if not m.blessingsOverride then m.ranking, m.excluded = Buffs.DefaultRanking(class) end
		roster.members[full] = m
		roster.units[full] = unit
	end)
	return roster
end

-- Sorted full names of the roster's paladins.
function ns.Roster.Paladins(roster)
	local out = {}
	for full, member in pairs((roster or ns.roster).members) do
		if member.class == "PALADIN" then out[#out + 1] = full end
	end
	table.sort(out)
	return out
end

-- A short name in class color (the given class, else the member's), or plain.
function ns.Roster.Name(full, class)
	class = class or (ns.roster.members[full] or {}).class
	return class and ns.WoW.ClassColorName(full, class) or ns.WoW.Short(full)
end
