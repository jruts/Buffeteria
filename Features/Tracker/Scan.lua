-- Observe group auras and summarize assigned buffs for the tracker.
local _, ns = ...
local Buffs = ns.Buffs

local Scan = {}
ns.Scan = Scan

local isSecret = issecretvalue or function() return false end
local nameToKey = {}
local cache = {}          -- [fullName] = { [key] = { exp = number, name = string } }

local function buildNameMap()
	for _, b in pairs(Buffs.byKey) do
		for _, id in ipairs(b.ids) do local n = ns.WoW.SpellName(id); if n then nameToKey[n] = b.key end end
		for _, id in ipairs(b.groupIds) do local n = ns.WoW.SpellName(id); if n then nameToKey[n] = b.key end end
	end
end

local function auraAt(unit, i)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		return C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
	end
	local name, _, _, _, _, exp = UnitBuff(unit, i)
	if name then return { name = name, expirationTime = exp } end
end

-- Returns a key -> {exp,name} map, or nil if the client hides aura data right now.
local function readAuras(unit)
	if not UnitIsVisible(unit) then return nil end
	local out = {}
	for i = 1, 40 do
		local ok, a = pcall(auraAt, unit, i)
		if not ok then return nil end
		if not a then break end
		if isSecret(a.name) or isSecret(a.expirationTime) then return nil end
		local key = nameToKey[a.name]
		if key then
			local exp = a.expirationTime or 0
			local prev = out[key]
			if not prev or (prev.exp ~= 0 and (exp == 0 or exp > prev.exp)) then
				out[key] = { exp = exp, name = a.name }
			end
		end
	end
	return out
end

-- status: "ok" | "warn" | "bad" | "unknown"
local function rate(full, key, now, warnSec)
	local auras = cache[full]
	if not auras then return "unknown" end
	local a = auras[key]
	if not a then return "bad" end
	if a.exp == 0 then return "ok" end
	local rem = a.exp - now
	if rem <= 0 then return "bad" end
	if rem <= warnSec then return "warn", rem end
	return "ok", rem
end
Scan.Rate = rate

local PRIORITY = ns.Status.PRIORITY

-- Scans the group and returns a summary used by the tracker.
function Scan.Update()
	if not next(nameToKey) then buildNameMap() end
	local now, warnSec = GetTime(), (ns.db.warnMinutes or 5) * 60
	local roster, res = ns.roster, ns.result
	for full, m in pairs(roster.members) do
		if not m.dead then
			local auras = readAuras(m.unit)
			if auras then cache[full] = auras end -- keep the last good read when hidden
		end
	end

	local summary = { overall = "ok", perKey = {}, problems = {}, any = false }
	for full, exp in pairs(res.expected or {}) do
		local m = roster.members[full]
		if m and not m.dead then
			for key in pairs(exp) do
				summary.any = true
				local st, rem = rate(full, key, now, warnSec)
				local pk = summary.perKey[key] or { bad = 0, warn = 0, total = 0 }
				summary.perKey[key] = pk
				pk.total = pk.total + 1
				if st == "bad" or st == "warn" then
					pk[st] = pk[st] + 1
					table.insert(summary.problems, { who = full, key = key, status = st, rem = rem })
				end
				if PRIORITY[st] < PRIORITY[summary.overall] then summary.overall = st end
			end
			-- Blessings the member does not want at all (e.g. Salvation on a tank).
			for key in pairs(m.excluded or {}) do
				if not exp[key] and cache[full] and cache[full][key] then
					table.insert(summary.problems, { who = full, key = key, status = "unwanted" })
					if PRIORITY.warn < PRIORITY[summary.overall] then summary.overall = "warn" end
				end
			end
		end
	end
	if not summary.any then summary.overall = "idle" end
	table.sort(summary.problems, ns.Status.CompareProblems)
	summary.next = ns.Actions.Next(now, warnSec)
	summary.cancel = Scan.UnwantedOnMe()
	return summary
end

-- An excluded blessing sitting on me -> the aura name to cancel.
function Scan.UnwantedOnMe()
	local me = ns.WoW.FullName("player")
	local m = ns.roster.members[me]
	local auras = cache[me]
	if not m or not auras then return nil end
	for key in pairs(m.excluded or {}) do
		if not (ns.result.expected[me] or {})[key] and auras[key] then return auras[key].name, key end
	end
end
