-- Observe group auras and summarize assigned buffs for the tracker.
local _, ns = ...
local Buffs, Status = ns.Buffs, ns.Tracker.Status

local Scan = {}
ns.Tracker.Scan = Scan

local EMPTY = {}
local isSecret = issecretvalue or function() return false end
local nameToKey = {}
local cache = {}          -- [fullName] = { [key] = { exp = number, name = string } }

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
		end
	end)
	return readable and out or nil
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

-- Scans the group and returns a summary used by the tracker.
function Scan.Update()
	local now, warnSec = GetTime(), ns.db.warnMinutes * 60
	local roster, res, me = ns.roster, ns.result, ns.WoW.Me()
	readGroup(roster)
	-- yours: keys I have to cast; needs: what I'm missing and who should cast it.
	local summary = { overall = "ok", perKey = {}, problems = {}, unreadable = {}, any = false, yours = {}, needs = {} }
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
				local pk = summary.perKey[key] or { bad = 0, warn = 0, total = 0, unknown = 0, casters = {} }
				summary.perKey[key] = pk
				pk.total = pk.total + 1
				summary.overall = Status.Worst(summary.overall, st)
				if st == "unknown" then
					pk.unknown = pk.unknown + 1
					if summary.unreadable[#summary.unreadable] ~= full then table.insert(summary.unreadable, full) end
				elseif st == "bad" or st == "warn" then
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
		summary.perKey[aura] = { bad = missingAura and 1 or 0, warn = 0, total = 1, casters = { [me] = true } }
		if missingAura then
			summary.yours[aura] = true
			problem(me, aura, "bad", nil, me)
		end
	end
	if not summary.any then summary.overall = "idle" end
	table.sort(summary.problems, Status.CompareProblems)
	table.sort(summary.unreadable)
	table.sort(summary.needs, Status.CompareProblems)
	summary.next = ns.Tracker.Actions.Next(now, warnSec, missingAura)
	summary.cancel = Scan.UnwantedOnMe()
	return summary
end

-- My assigned aura when I am not running it, or nil (none assigned, or auras hidden).
function Scan.MissingAura()
	local key = ns.result.auras[ns.WoW.Me()]
	if not key then return nil end
	local running = false
	local readable = eachAura("player", function(a)
		if isSecret(a.name) or isSecret(a.sourceUnit) then return false end
		-- Another paladin's copy of the same aura doesn't count as mine.
		if keyOf(a.name) == key and (a.sourceUnit == nil or a.sourceUnit == "player") then running = true end
	end)
	if readable and not running then return key end
end

-- An excluded blessing sitting on me -> the aura name to cancel.
function Scan.UnwantedOnMe()
	local me = ns.WoW.Me()
	local m, auras = ns.roster.members[me], cache[me]
	if not m or not auras then return nil end
	for key in pairs(m.excluded or EMPTY) do
		if not (ns.result.expected[me] or EMPTY)[key] and auras[key] then return auras[key].name, key end
	end
end
