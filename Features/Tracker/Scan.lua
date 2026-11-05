-- Observe group auras and summarize assigned buffs for the tracker.
local _, ns = ...
local Buffs, Status = ns.Buffs, ns.Tracker.Status

local Scan = {}
ns.Tracker.Scan = Scan

local isSecret = issecretvalue or function() return false end
local nameToKey, idToKey = {}, {}
local cache = {}          -- [fullName] = { [key] = { exp, name, duration } }
local weaponAuras         -- my main-hand imbue, read independently of unit auras
local durations = {}      -- My combat self buffs' last readable durations (including talents)
local missingSince = {}   -- ["name:key"] = when an expected buff was first seen missing
local selfKeys = {}       -- [spellID] = key, for my combat self buffs
for _, b in ipairs(Buffs.SELF_BUFFS) do
	if b.combat then for _, id in ipairs(b.ids) do selfKeys[id] = b.key end end
end

-- Spell names are only known once the client has loaded them.
local function keyOf(name, spellID)
	if not next(nameToKey) then
		for _, b in pairs(Buffs.byKey) do
			if b.kind ~= "imbue" then
				for _, ids in ipairs({ b.auraIds or b.ids, b.groupIds }) do
					for _, id in ipairs(ids) do
						local n = ns.WoW.SpellName(id)
						idToKey[id] = b.key
						if n then nameToKey[n] = b.key end
					end
				end
			end
		end
	end
	local key = nameToKey[name]
	if not isSecret(spellID) and spellID and spellID > 0 then
		-- Windfury's short attack proc shares its name with the raid buff.
		if idToKey[spellID] then return idToKey[spellID] end
		if key and Buffs.byKey[key].auraIds then return nil end
	end
	return key
end

local function auraAt(unit, i)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		return C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
	end
	local name, _, _, _, duration, exp, source, _, _, spellID = UnitBuff(unit, i)
	if name then return { name = name, duration = duration, expirationTime = exp, sourceUnit = source, spellId = spellID } end
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

-- Returns a key -> {exp,name,duration} map, or nil if aura data is hidden.
local function readAuras(unit)
	if not UnitIsVisible(unit) then return nil end
	local out = {}
	local readable = eachAura(unit, function(a)
		if isSecret(a.name) or isSecret(a.expirationTime) then return false end
		local key = keyOf(a.name, a.spellId)
		if key then
			local exp, prev = a.expirationTime or 0, out[key]
			local d = a.duration
			if isSecret(d) or type(d) ~= "number" or d <= 0 then d = nil end
			if not prev or (prev.exp ~= 0 and (exp == 0 or exp > prev.exp)) then
				out[key] = { exp = exp, name = a.name, duration = d or Buffs.byKey[key].duration }
			end
		end
	end)
	if readable and unit == "player" then
		for key, aura in pairs(out) do
			if Buffs.byKey[key].combat and aura.duration then durations[key] = aura.duration end
		end
	end
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
	local observed = { exp = now + d, name = buff.label, duration = d }
	cache[me][key] = observed
	if buff.raidRadius then
		-- Estimate the refresh for nearby allies with cached readings. Leave
		-- unknown aura maps alone so other buffs still report unknown.
		for full, member in pairs(ns.Assignments.roster.members) do
			if full ~= me and cache[full] and not member.dead
				and ns.WoW.WithinRadius(member.unit, buff.raidRadius) then
				cache[full][key] = observed
			end
		end
	end
end

-- nil means unreadable, {} means the selected imbue is absent.
local function readWeaponImbue(buff, now)
	local slot, enchantType = Enum and Enum.WeaponSlot, Enum and Enum.ItemEnchantType
	if not (C_Item and C_Item.GetWeaponEnchantInfo and slot and enchantType) then return nil end
	local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, slot.MainHand)
	if not ok or isSecret(enchants) or type(enchants) ~= "table" then return nil end
	for _, enchant in ipairs(enchants) do
		if isSecret(enchant) or isSecret(enchant.enchantType) then return nil end
		if enchant.enchantType == enchantType.Imbue then
			if isSecret(enchant.hasEnchant) or isSecret(enchant.enchantID) or isSecret(enchant.timeLeft) then return nil end
			if enchant.hasEnchant then
				for _, id in ipairs(buff.enchantIds) do
					if enchant.enchantID == id then
						return { [buff.key] = { exp = now + enchant.timeLeft / 1000, duration = buff.duration } }
					end
				end
			end
		end
	end
	return {}
end

-- The slot may be unreadable or occupied by another totem. Only refresh an
-- identified totem of this type or fill a positively empty slot.
function Scan.TotemRate(buff, now, warnPercent)
	if not GetTotemInfo then return "unknown" end
	local ok, active, name, start, duration, _, _, id = pcall(GetTotemInfo, buff.totemSlot)
	if not ok or isSecret(active) or active == nil then return "unknown" end
	if not active then return "bad" end
	if isSecret(name) or isSecret(start) or isSecret(duration) or isSecret(id) then return "unknown" end
	local hasSpellID = id and id > 0
	local matched
	for _, rank in ipairs(buff.ids) do
		if (hasSpellID and id == rank) or (not hasSpellID and name and name ~= "" and name == ns.WoW.SpellName(rank)) then
			matched = true
			break
		end
	end
	if not matched then return "unknown" end
	if not duration or duration <= 0 or not start then return "ok" end
	local rem = start + duration - now
	if rem <= 0 then return "bad" end
	if rem <= duration * warnPercent / 100 then return "warn", rem end
	return "ok", rem
end

-- status: "ok" | "warn" | "bad" | "unknown"
function Scan.Rate(full, key, now, warnPercent, ignoreRadius)
	local auras = cache[full]
	local buff = Buffs.byKey[key]
	if buff.kind == "imbue" then auras = full == ns.WoW.Me() and weaponAuras or nil end
	if not auras then return "unknown" end
	local a = auras[key]
	if buff.raidRadius and not ignoreRadius then
		local assignments, me = ns.Assignments, ns.WoW.Me()
		local caster = assignments.Served(full)[key]
		local other = caster == me and full or (full == me and caster)
		if other and other ~= me and not ns.WoW.WithinRadius(assignments.roster.units[other], buff.raidRadius) then
			if a and (a.exp == 0 or a.exp > now) then return "ok" end
			return "unknown"
		end
	end
	if buff.totemSlot and full == ns.WoW.Me() and ns.Assignments.Served(full)[key] == full then
		local status, rem = Scan.TotemRate(buff, now, warnPercent)
		if status == "warn" then return status, rem end
	end
	if not a then return "bad" end
	if a.exp == 0 then return "ok" end
	local rem = a.exp - now
	if rem <= 0 then return "bad" end
	-- Each recipient can have a different duration (single/group spells or talents).
	-- Without a duration, keep tracking expiry without guessing a percentage.
	if a.duration and rem <= a.duration * warnPercent / 100 then return "warn", rem end
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
-- (everything but next; see Status.NewSummary).
function Scan.Update(now, warnPercent)
	local roster, res, me = ns.Assignments.roster, ns.Assignments.result, ns.WoW.Me()
	readGroup(roster)
	local member = roster.members[me]
	local imbue = member and not member.dead and member.weaponImbue
	weaponAuras = imbue and res.expected[me] and res.expected[me][imbue]
		and readWeaponImbue(Buffs.byKey[imbue], now) or nil
	local summary, since = Status.NewSummary(), {}
	local function problem(full, key, status, rem, caster)
		table.insert(summary.problems, { who = full, key = key, status = status, rem = rem, caster = caster })
	end
	for full, exp in pairs(res.expected) do
		local m = roster.members[full]
		if m and not m.dead then
			for key, caster in pairs(exp) do
				summary.any = true
				local st, rem = Scan.Rate(full, key, now, warnPercent)
				local pk
				if caster == me then
					summary.mine.total = summary.mine.total + 1
					if st == "bad" or st == "warn" then summary.mine.pending = summary.mine.pending + 1 end
					pk = summary.perKey[key] or Status.NewCounts()
					summary.perKey[key] = pk
					pk.total = pk.total + 1
					pk.casters[me] = true
					summary.overall = Status.Worst(summary.overall, st)
				end
				if st == "unknown" then
					if pk then pk.unknown = pk.unknown + 1 end
					if summary.unreadable[#summary.unreadable] ~= full then table.insert(summary.unreadable, full) end
				elseif st == "bad" or st == "warn" then
					if st == "bad" then
						local id = full .. ":" .. key
						since[id] = missingSince[id] or now
					end
					if pk then pk[st] = pk[st] + 1 end
					problem(full, key, st, rem, caster)
					if caster == me and not Buffs.byKey[key].passive then summary.yours[key] = true end
					if full == me then table.insert(summary.needs, { key = key, status = st, caster = caster }) end
				end
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
			summary.overall = Status.Worst(summary.overall, "bad")
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
		if keyOf(a.name, a.spellId) == key then running = true end
	end)
	if readable and not running then return key end
end
