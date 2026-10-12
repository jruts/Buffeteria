-- Live members, preferences and spell capabilities.
local _, ns = ...
local Buffs = ns.Buffs
ns.Roster = { peers = {} }

-- What I can cast: plain key = single version, "g"..key = group/Greater version.
function ns.Roster.Capabilities()
	local caps = {}
	local _, class = UnitClass("player")
	for _, b in pairs(Buffs.byKey) do
		if b.kind == "group" or class == "PALADIN" then
			if ns.WoW.KnowsAny(b.ids) then caps[b.key] = true end
			if ns.WoW.KnowsAny(b.groupIds) then caps["g" .. b.key] = true end
		end
	end
	return caps
end

------------------------------------------------------------------------
-- Roster
------------------------------------------------------------------------
local function eachGroupUnit(fn)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
			fn("raid" .. i, subgroup or 1, class, online, isDead)
		end
	else
		local _, pc = UnitClass("player")
		fn("player", 1, pc, true, UnitIsDeadOrGhost("player"))
		for i = 1, GetNumSubgroupMembers() do
			local u = "party" .. i
			local _, c = UnitClass(u)
			fn(u, 1, c, UnitIsConnected(u), UnitIsDeadOrGhost(u))
		end
	end
end

function ns.Roster.Build()
	local roster = { members = {}, units = {} }
	local me = ns.WoW.FullName("player")
	eachGroupUnit(function(unit, group, class, online, dead)
		local full = ns.WoW.FullName(unit)
		if not full or not class or not online then return end
		local m = { name = full, class = class, group = group, unit = unit, dead = dead }
		local peer = (full == me) and ns.Preferences.Get() or ns.Roster.peers[full]
		if full == me then
			m.caps = ns.Roster.Capabilities(); m.hasAddon = true
		elseif peer and peer.caps then
			m.caps = peer.caps; m.hasAddon = true
		else
			m.caps = {}
			for k, v in pairs(Buffs.ASSUMED_CAPS[class] or {}) do m.caps[k] = v end
		end
		if peer and peer.ranking then
			m.wants, m.ranking, m.excluded = peer.wants, peer.ranking, peer.excluded
			m.blessingsOverride = peer.blessingsOverride and true or false
		else
			local r, e = Buffs.SplitOrder(Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR)
			m.wants, m.ranking, m.excluded = Buffs.DefaultWants(class), r, e
		end
		if not m.blessingsOverride then
			m.ranking, m.excluded = Buffs.SplitOrder(Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR)
		end
		roster.members[full] = m
		roster.units[full] = unit
	end)
	ns.Paladins.Prune(roster)
	roster.paladinAssignments, roster.paladinAuras = ns.Paladins.Assignments(roster)
	return roster
end
