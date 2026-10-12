-- Buffeteria: reads buffs on the group, rates them and picks my next cast.
local _, ns = ...
local D = ns.Data

local Scan = {}
ns.Scan = Scan

local isSecret = issecretvalue or function() return false end
local nameToKey = {}
local cache = {}          -- [fullName] = { [key] = { exp = number, name = string } }
local pendingUntil = {}   -- ["name:key"] = time; stops double-casting before the aura shows up

local function buildNameMap()
	for _, b in pairs(D.byKey) do
		for _, id in ipairs(b.ids) do local n = ns.SpellName(id); if n then nameToKey[n] = b.key end end
		for _, id in ipairs(b.groupIds) do local n = ns.SpellName(id); if n then nameToKey[n] = b.key end end
	end
end

local function auraAt(unit, i)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		return C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
	end
	local name, _, _, _, duration, exp = UnitBuff(unit, i)
	if name then return { name = name, duration = duration, expirationTime = exp } end
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

local RANK = { unknown = 0, ok = 1, warn = 2, bad = 3 }

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
				if RANK[st] > RANK[summary.overall] then summary.overall = st end
			end
			-- Blessings the member does not want at all (e.g. Salvation on a tank).
			for key in pairs(m.excluded or {}) do
				if cache[full] and cache[full][key] then
					table.insert(summary.problems, { who = full, key = key, status = "unwanted" })
					if RANK.warn > RANK[summary.overall] then summary.overall = "warn" end
				end
			end
		end
	end
	if not summary.any then summary.overall = "idle" end
	table.sort(summary.problems, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.who ~= b.who then return a.who < b.who end
		return a.key < b.key
	end)
	summary.next = Scan.NextAction(now, warnSec)
	summary.cancel = Scan.UnwantedOnMe()
	return summary
end

local function inRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
		if ok and r == false then return false end
		return true
	end
	if IsSpellInRange then return IsSpellInRange(spell, unit) ~= 0 end
	return true
end

local function hasReagent(list)
	for _, id in ipairs(list or {}) do if ns.ItemCount(id) > 0 then return true end end
	return false
end

-- Highest known rank -> castable spell name + icon.
local function spellFor(ids)
	local ok, id = ns.KnowsAny(ids)
	if not ok then return nil end
	return ns.SpellName(id), ns.SpellIcon(id)
end

function Scan.MarkCast(full, key)
	pendingUntil[full .. ":" .. key] = GetTime() + 3
end

-- My next cast: { spell, unit, icon, label, who, key, status }
function Scan.NextAction(now, warnSec)
	local me, roster, res = ns.FullName("player"), ns.roster, ns.result
	local cands = {}
	local function needs(full, key)
		if (pendingUntil[full .. ":" .. key] or 0) > now then return nil end
		local st = rate(full, key, now, warnSec)
		if st == "bad" or st == "warn" then return st end
	end
	local function add(c) cands[#cands + 1] = c end

	-- Group buffs (Fort, Spirit, Shadow Prot, Mark, Intellect)
	for _, buff in ipairs(D.GROUP_BUFFS) do
		for g, caster in pairs((res.groups or {})[buff.key] or {}) do
			if caster == me then
				local needy, wanters, worst = {}, 0, "warn"
				for full, m in pairs(roster.members) do
					if m.group == g and not m.dead and (res.expected[full] or {})[buff.key] == me then
						wanters = wanters + 1
						local st = needs(full, buff.key)
						if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
					end
				end
				if #needy > 0 then
					table.sort(needy)
					local gName, gIcon = spellFor(buff.groupIds)
					local sName, sIcon = spellFor(buff.ids)
					local useGroup = gName and hasReagent(buff.reagents) and wanters >= 2 and #needy >= math.min(3, wanters)
					local spell, icon = (useGroup and gName or sName), (useGroup and gIcon or sIcon)
					if spell then
						for _, full in ipairs(needy) do
							local unit = roster.units[full]
							if unit and inRange(spell, unit) then
								add({ spell = spell, icon = icon, unit = unit, who = full, key = buff.key, status = worst,
									big = useGroup, label = useGroup and ("Group " .. g) or ns.Short(full) })
								break
							end
						end
					end
				end
			end
		end
	end

	-- Blessings: Greater per class, then personal overrides.
	local bless = (D.byKey)
	for class, map in pairs(res.pally or {}) do
		local key = map[me]
		if key then
			local b = bless[key]
			local needy, worst = {}, "warn"
			for full, m in pairs(roster.members) do
				if m.class == class and not m.dead and (res.expected[full] or {})[key] == me then
					local st = needs(full, key)
					if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
				end
			end
			if #needy > 0 then
				table.sort(needy)
				local gName, gIcon = spellFor(b.groupIds)
				local useGreater = gName and ns.ItemCount(D.BLESSING_REAGENT) > 0
				local sName, sIcon = spellFor(b.ids)
				local spell, icon = (useGreater and gName or sName), (useGreater and gIcon or sIcon)
				if spell then
					for _, full in ipairs(needy) do
						local unit = roster.units[full]
						if unit and inRange(spell, unit) then
							add({ spell = spell, icon = icon, unit = unit, who = full, key = key, status = worst, big = useGreater,
								label = useGreater and ns.ClassName(class) or ns.Short(full) })
							break
						end
					end
				end
			end
		end
	end
	for full, map in pairs(res.overrides or {}) do
		local key = map[me]
		local m = roster.members[full]
		if key and m and not m.dead then
			local st = needs(full, key)
			local spell, icon = spellFor(bless[key].ids)
			local unit = roster.units[full]
			if st and spell and unit and inRange(spell, unit) then
				add({ spell = spell, icon = icon, unit = unit, who = full, key = key, status = st, big = false, label = ns.Short(full) })
			end
		end
	end

	table.sort(cands, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.big ~= b.big then return a.big end
		if a.key ~= b.key then return a.key < b.key end
		return a.who < b.who
	end)
	return cands[1]
end

-- An excluded blessing sitting on me -> the aura name to cancel.
function Scan.UnwantedOnMe()
	local me = ns.FullName("player")
	local m = ns.roster.members[me]
	local auras = cache[me]
	if not m or not auras then return nil end
	for key in pairs(m.excluded or {}) do
		if auras[key] then return auras[key].name, key end
	end
end
