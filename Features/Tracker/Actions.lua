-- Select a cast from assignments and observed aura status.
local _, ns = ...
local Buffs = ns.Buffs
local Actions = {}
ns.Tracker.Actions = Actions
local EMPTY = {}
local pendingUntil = {} -- ["name:key"] = expiry; wait for a cast's aura to arrive

local function inRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
		return not (ok and r == false)
	end
	if IsSpellInRange then return IsSpellInRange(spell, unit) ~= 0 end
	return true
end

local function hasReagent(list)
	for _, id in ipairs(list or EMPTY) do if ns.WoW.ItemCount(id) > 0 then return true end end
	return false
end

-- Highest known rank -> castable spell name + icon.
local function spellFor(ids)
	local ok, id = ns.WoW.KnowsAny(ids)
	if not ok then return nil end
	return ns.WoW.SpellName(id), ns.WoW.SpellIcon(id)
end

function Actions.MarkCast(full, key)
	pendingUntil[full .. ":" .. key] = GetTime() + 3
end

-- My next cast: { spell, unit, icon, label, who, key, status, big }.
-- missingAura is my assigned aura when it isn't running.
function Actions.Next(now, warnSec, missingAura)
	local me, roster, res = ns.WoW.Me(), ns.roster, ns.result
	local cands = {}
	local function casting(full, key) return (pendingUntil[full .. ":" .. key] or 0) > now end
	local function needs(full, key)
		if casting(full, key) then return nil end
		local st = ns.Tracker.Scan.Rate(full, key, now, warnSec)
		if st == "bad" or st == "warn" then return st end
	end
	local function mine(full, key) return (res.expected[full] or EMPTY)[key] == me end
	local function add(buff, spell, icon, unit, who, status, big, label)
		cands[#cands + 1] = { spell = spell, icon = icon, unit = unit, who = who, key = buff.key, status = status,
			big = big, label = label or ns.WoW.Short(who) }
	end

	-- My living recipients of a buff that match, the needy ones sorted, and the worst status.
	local function recipients(key, match)
		local needy, worst, count = {}, "warn", 0
		for full, m in pairs(roster.members) do
			if not m.dead and match(m) and mine(full, key) then
				count = count + 1
				local st = needs(full, key)
				if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
			end
		end
		table.sort(needy)
		return needy, worst, count
	end
	-- One cast covering the needy: the group version (labelled `label`) when big,
	-- else the single version, on the first needy player in range.
	local function addCover(buff, needy, worst, big, label)
		local spell, icon = spellFor(big and buff.groupIds or buff.ids)
		if not spell then return end
		for _, full in ipairs(needy) do
			local unit = roster.units[full]
			if unit and inRange(spell, unit) then return add(buff, spell, icon, unit, full, worst, big, big and label or nil) end
		end
	end
	local function addSingle(buff, full, status, onSelf)
		local spell, icon = spellFor(buff.ids)
		local unit = onSelf and "player" or roster.units[full]
		if spell and unit and (onSelf or inRange(spell, unit)) then add(buff, spell, icon, unit, full, status, false) end
	end
	local function groupVersion(buff) return ns.WoW.KnowsAny(buff.groupIds) and hasReagent(buff.reagents) end

	-- Group buffs (Fort, Spirit, Shadow Prot, Mark, Intellect), per raid group.
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		for g, caster in pairs(res.groups[buff.key] or EMPTY) do
			if caster == me then
				local needy, worst, wanters = recipients(buff.key, function(m) return m.group == g end)
				if #needy > 0 then
					local big = groupVersion(buff) and wanters >= 2 and #needy >= math.min(3, wanters)
					addCover(buff, needy, worst, big, "Group " .. g)
				end
			end
		end
	end

	-- Blessings: Greater per class, unless it would overwrite someone's personal
	-- assignment from me; then singles.
	for class, map in pairs(res.pally) do
		local buff = map[me] and Buffs.byKey[map[me]]
		if buff then
			local needy, worst = recipients(buff.key, function(m) return m.class == class end)
			if #needy > 0 then
				local big = groupVersion(buff)
				for full, m in pairs(roster.members) do
					if big and m.class == class and not m.dead and (res.overrides[full] or EMPTY)[me] ~= nil then big = false end
				end
				addCover(buff, needy, worst, big, ns.WoW.ClassName(class))
			end
		end
	end
	for full, map in pairs(res.overrides) do
		local m = roster.members[full]
		if map[me] and m and not m.dead then
			local st = needs(full, map[me])
			if st then addSingle(Buffs.byKey[map[me]], full, st, false) end
		end
	end

	-- Tank buffs always use singles; Righteous Fury belongs to the caster alone.
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		for full, m in pairs(roster.members) do
			if not m.dead and mine(full, buff.key) and (not buff.selfOnly or full == me) then
				local st = needs(full, buff.key)
				if st then addSingle(buff, full, st, buff.selfOnly) end
			end
		end
	end

	-- Self buffs (Battle Shout): only once there is enough rage to cast.
	local player = roster.members[me]
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		local spell = spellFor(buff.ids)
		if player and not player.dead and mine(me, buff.key) and spell and ns.WoW.SpellUsable(spell) then
			local st = needs(me, buff.key)
			if st then addSingle(buff, me, st, true) end
		end
	end

	-- My assigned aura: a self-cast toggle, so it never needs a target.
	if missingAura and not casting(me, missingAura) then
		local buff = Buffs.byKey[missingAura]
		local spell, icon = spellFor(buff.ids)
		if spell then add(buff, spell, icon, "player", me, "bad", true, "Aura") end
	end

	table.sort(cands, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.big ~= b.big then return a.big end
		if a.key ~= b.key then return a.key < b.key end
		return a.who < b.who
	end)
	return cands[1]
end
