-- Observe group auras and summarize assigned buffs for the tracker.
local _, ns = ...
local Buffs, Status = ns.Buffs, ns.Tracker.Status

local Scan = {}
ns.Tracker.Scan = Scan

local EMPTY = ns.Util.EMPTY
local isSecret = issecretvalue or function() return false end
local nameToKey = {}
local cache = {}          -- [fullName] = { [key] = { exp = number, name = string } }
local durations = {}      -- [key] = seconds, from the last readable aura (talents can lengthen it)
local missingSince = {}   -- ["name:key"] = when an expected buff was first seen missing
local selfKeys = {}       -- [spellID] = key, for my combat self buffs
for _, b in ipairs(Buffs.SELF_BUFFS) do
	if b.combat then for _, id in ipairs(b.ids) do selfKeys[id] = b.key end end
end

-- Spell names are only known once the client has loaded them.
local function keyOf(name)
	if not next(nameToKey) then
		for _, b in pairs(Buffs.byKey) do
			for _, id in ipairs(b.ids) do local n = ns.WoW.SpellName(id); if n then nameToKey[n] = b.key end end
			for _, id in ipairs(b.groupIds) do local n = ns.WoW.SpellName(id); if n then nameToKey[n] = b.key end end
		end
	end
	return nameToKey[name]
end

local function auraAt(unit, i)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		return C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
	end
	local name, _, _, _, _, exp, source = UnitBuff(unit, i)
	if name then return { name = name, expirationTime = exp, sourceUnit = source } end
end

-- Calls visit(aura) for each helpful aura. False if the client hides them, or
-- visit returns false (it found a hidden value).
local function eachAura(unit, visit)
	for i = 1, 40 do
		local ok, a = pcall(auraAt, unit, i)
		if not ok then return false end
		if not a then return true end
		if visit(a) == false then return false end
	end
	return true
end

-- Returns a key -> {exp,name} map, or nil if the client hides aura data right now.
local function readAuras(unit)
	if not UnitIsVisible(unit) then return nil end
	local out = {}
	local readable = eachAura(unit, function(a)
		if isSecret(a.name) or isSecret(a.expirationTime) then return false end
		local key = keyOf(a.name)
		if key then
			local exp, prev = a.expirationTime or 0, out[key]
			if not prev or (prev.exp ~= 0 and (exp == 0 or exp > prev.exp)) then
				out[key] = { exp = exp, name = a.name }
			end
			local d = a.duration
			if not isSecret(d) and type(d) == "number" and d > 0 then durations[key] = d end
		end
	end)
	return readable and out or nil
end

-- Combat hides every aura detail, removals included, so the cache keeps the last
-- read: its expiry still dates the buff running out, and my recasts redate it.

-- The combat self buff a spell ID casts, or nil (also for hidden IDs).
function Scan.SelfBuffKey(spellID)
	if isSecret(spellID) then return nil end
	return selfKeys[spellID]
end

-- I just cast one of my combat self buffs.
function Scan.SelfCast(key, now)
	local buff, me = Buffs.byKey[key], ns.WoW.Me()
	local d = durations[key] or buff.duration
	if not d then return end
	cache[me] = cache[me] or {}
	cache[me][key] = { exp = now + d, name = buff.label }
end

-- status: "ok" | "warn" | "bad" | "unknown"
function Scan.Rate(full, key, now, warnSec)
	local auras = cache[full]
	if not auras then return "unknown" end
	local short = Buffs.byKey[key] and Buffs.byKey[key].warnSeconds
	if short then warnSec = math.min(warnSec, short) end
	local a = auras[key]
	if not a then return "bad" end
	if a.exp == 0 then return "ok" end
	local rem = a.exp - now
	if rem <= 0 then return "bad" end
	if rem <= warnSec then return "warn", rem end
	return "ok", rem
end

local function readGroup(roster)
	for full, m in pairs(roster.members) do
		if not m.dead then
			if not UnitIsVisible(m.unit) then
				cache[full] = nil -- out of range: an old read would be stale
			else
				cache[full] = readAuras(m.unit) or cache[full] -- keep the last good read when hidden
			end
		end
	end
end

-- Scans the group and returns the observed part of the tracker summary
-- (everything but next and cancel; see Status.NewSummary).
function Scan.Update(now, warnSec)
	local roster, res, me = ns.Assignments.roster, ns.Assignments.result, ns.WoW.Me()
	readGroup(roster)
	local summary, since = Status.NewSummary(), {}
	local function problem(full, key, status, rem, caster)
		table.insert(summary.problems, { who = full, key = key, status = status, rem = rem, caster = caster })
		summary.overall = Status.Worst(summary.overall, status == "unwanted" and "warn" or status)
	end
	for full, exp in pairs(res.expected) do
		local m = roster.members[full]
		if m and not m.dead then
			for key, caster in pairs(exp) do
				summary.any = true
				local st, rem = Scan.Rate(full, key, now, warnSec)
				if caster == me then
					summary.mine.total = summary.mine.total + 1
					if st == "bad" or st == "warn" then summary.mine.pending = summary.mine.pending + 1 end
				end
				local pk = summary.perKey[key] or Status.NewCounts()
				summary.perKey[key] = pk
				pk.total = pk.total + 1
				summary.overall = Status.Worst(summary.overall, st)
				if st == "unknown" then
					pk.unknown = pk.unknown + 1
					if summary.unreadable[#summary.unreadable] ~= full then table.insert(summary.unreadable, full) end
				elseif st == "bad" or st == "warn" then
					if st == "bad" then
						local id = full .. ":" .. key
						since[id] = missingSince[id] or now
					end
					pk[st] = pk[st] + 1
					pk.casters[caster] = true
					problem(full, key, st, rem, caster)
					if caster == me then summary.yours[key] = true end
					if full == me then table.insert(summary.needs, { key = key, status = st, caster = caster }) end
				end
			end
			-- Blessings the member does not want at all (e.g. Salvation on a tank).
			for key in pairs(m.excluded or EMPTY) do
				if not exp[key] and cache[full] and cache[full][key] then problem(full, key, "unwanted") end
			end
		end
	end
	-- My own assigned aura.
	local aura, missingAura = res.auras[me], Scan.MissingAura()
	if aura and roster.members[me] and not roster.members[me].dead then
		summary.any = true
		local pk = Status.NewCounts()
		pk.bad, pk.total, pk.casters[me] = missingAura and 1 or 0, 1, true
		summary.perKey[aura] = pk
		summary.mine.total = summary.mine.total + 1
		if missingAura then
			summary.mine.pending = summary.mine.pending + 1
			summary.yours[aura] = true
			problem(me, aura, "bad", nil, me)
		end
	end
	missingSince = since
	if not summary.any then summary.overall = "idle" end
	table.sort(summary.problems, Status.CompareProblems)
	table.sort(summary.unreadable)
	table.sort(summary.needs, Status.CompareProblems)
	return summary
end

-- Seconds an expected buff has been missing in a row, as of the last Update.
function Scan.MissingFor(full, key, now)
	local since = missingSince[full .. ":" .. key]
	return since and now - since or 0
end

-- My assigned aura when nobody's copy of it is on me, or nil (none assigned, or
-- auras hidden). The client shows one copy of an aura, so when another paladin
-- runs the same one, mine never appears; theirs covers the group either way.
function Scan.MissingAura()
	local key = ns.Assignments.Aura(ns.WoW.Me())
	if not key then return nil end
	local running = false
	local readable = eachAura("player", function(a)
		if isSecret(a.name) then return false end
		if keyOf(a.name) == key then running = true end
	end)
	if readable and not running then return key end
end

-- An excluded blessing sitting on me -> the aura name to cancel.
function Scan.UnwantedOnMe()
	local me = ns.WoW.Me()
	local m, auras = ns.Assignments.roster.members[me], cache[me]
	if not m or not auras then return nil end
	for key in pairs(m.excluded or EMPTY) do
		if not ns.Assignments.Served(me)[key] and auras[key] then return auras[key].name, key end
	end
end
