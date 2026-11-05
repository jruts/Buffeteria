-- Live members, preferences and spell capabilities, including the state
-- message that shares mine and records everyone else's.
local _, ns = ...
local Buffs, Protocol = ns.Buffs, ns.Protocol
ns.Roster = { peers = {} }
local lastSharedCaps

-- Only advertise the druid crit effect while an eligible form is active.
local function druidCritActive()
	if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return false end
	local form = GetShapeshiftForm()
	if (issecretvalue and issecretvalue(form)) or not form or form == 0 then return false end
	local _, _, _, spellID = GetShapeshiftFormInfo(form)
	if issecretvalue and issecretvalue(spellID) then return false end
	if spellID == 24858 then return true end -- Moonkin Form
	local feral = spellID == 768 or spellID == 5487 or spellID == 9634 -- Cat, Bear, Dire Bear
	return feral and ns.WoW.KnowsAny({17007}) -- Leader of the Pack
end

-- What I can cast: plain key = single version, "g"..key = group/Greater version.
function ns.Roster.Capabilities(shared)
	local caps = {}
	local class = ns.WoW.PlayerClass()
	for _, b in pairs(Buffs.byKey) do
		local paladinSpell = b.kind == "blessing" or b.kind == "aura"
		local myClass = (paladinSpell and class == "PALADIN") or (not paladinSpell and class == b.class)
		if myClass and not (shared and (b.kind == "imbue" or b.kind == "personal")) then
			local known = b.passive and druidCritActive() or (not b.passive and ns.WoW.KnowsAny(b.ids))
			if known then caps[b.key] = true end
			if b.kind == "group" then
				if Buffs.CastableGroupRank(b) then caps["g" .. b.key] = true end
			elseif ns.WoW.KnowsAny(b.groupIds) then
				caps["g" .. b.key] = true
			end
		end
	end
	return caps
end

-- Bag events only matter to assignments when a raid spell gains or loses its reagent.
function ns.Roster.GroupCastAvailabilityChanged()
	local member = ns.Assignments.roster.members[ns.WoW.Me()]
	local class = ns.WoW.PlayerClass()
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		if buff.class == class then
			local key = "g" .. buff.key
			local ready = Buffs.CastableGroupRank(buff) ~= nil
			if (member and ready ~= (member.caps[key] == true))
				or (lastSharedCaps and IsInGroup() and ready ~= (lastSharedCaps[key] == true)) then return true end
		end
	end
	return false
end

-- S|2|wants|ranking|reserved|caps|override: my preferences and spellbook.
-- The reserved field stays empty so older clients can still read version 2.
ns.Events.On("BroadcastRequested", function()
	local p = ns.Preferences.Get()
	lastSharedCaps = ns.Roster.Capabilities(true)
	ns.Comm.Send(Protocol.Encode("S", Protocol.SetString(p.wants), table.concat(p.ranking, ","),
		"", Protocol.SetString(lastSharedCaps), p.blessingsOverride and "1" or "0"))
end)

-- Keep state even if the sender isn't in our roster yet (they just joined or
-- haven't loaded); Build only uses peers who are in the group.
ns.Events.On("Received:S", function(sender, wants, ranking, reserved, caps, override)
	ns.Roster.peers[sender] = { wants = Protocol.Set(wants), ranking = Protocol.List(ranking),
		caps = Protocol.Set(caps), blessingsOverride = override == "1" }
	ns.Events.Emit("PeersChanged")
end)

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

-- Include offline members in the status view. The assignment roster below
-- excludes them so they are never given work.
function ns.Roster.GroupMembers()
	local members = {}
	local me = ns.WoW.Me()
	eachGroupUnit(function(unit, _, class, online)
		local name = ns.WoW.FullName(unit)
		if name then
			members[#members + 1] = { name = name, class = class, online = online, isPlayer = name == me }
		end
	end)
	table.sort(members, function(a, b)
		if a.isPlayer ~= b.isPlayer then return a.isPlayer end
		return a.name < b.name
	end)
	return members
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
	local roster = { members = {}, units = {}, isRaid = IsInRaid() }
	local me = ns.WoW.Me()
	eachGroupUnit(function(unit, group, class, online, dead)
		local full = ns.WoW.FullName(unit)
		if not full or not class or not online then return end
		local m = { name = full, class = class, group = group, unit = unit, dead = dead }
		local peer = (full == me) and ns.Preferences.Get(true) or ns.Roster.peers[full]
		if full == me then
			m.caps, m.hasAddon = ns.Roster.Capabilities(), true
			if class == "SHAMAN" then m.weaponImbue = ns.db.weaponImbue or nil end
		elseif peer and peer.caps then
			m.caps, m.hasAddon = peer.caps, true
		else
			m.caps = {}
			local level = UnitLevel and UnitLevel(unit)
			if issecretvalue and issecretvalue(level) then level = nil end
			for key, minimum in pairs(Buffs.ASSUMED_CAPS[class] or {}) do
				if not level or level <= 0 or level >= minimum then m.caps[key] = true end
			end
		end
		if peer and peer.ranking then
			m.wants, m.ranking = peer.wants, Buffs.NormalizeOrder(peer.ranking, class)
			m.blessingsOverride = peer.blessingsOverride and true or false
		else
			m.wants = defaultWants(class, unit)
		end
		-- Without an explicit override, members follow their class plan.
		if not m.blessingsOverride then m.ranking = Buffs.DefaultRanking(class) end
		roster.members[full] = m
		roster.units[full] = unit
	end)
	return roster
end

-- Sorted full names of the roster's paladins.
function ns.Roster.Paladins(roster)
	local out = {}
	for full, member in pairs((roster or ns.Assignments.roster).members) do
		if member.class == "PALADIN" then out[#out + 1] = full end
	end
	table.sort(out)
	return out
end

-- A short name in class color (the given class, else the member's), or plain.
function ns.Roster.Name(full, class)
	class = class or (ns.Assignments.roster.members[full] or {}).class
	return class and ns.WoW.ClassColorName(full, class) or ns.WoW.Short(full)
end
