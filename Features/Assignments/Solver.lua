-- Buffeteria: the assignment solver.
-- Pure Lua, no WoW API: every client runs it on the same roster and gets the same answer.
local _, ns = ...
local Buffs, EMPTY, sortedKeys = ns.Buffs, ns.Util.EMPTY, ns.Util.SortedKeys

local Solver = {}
ns.Solver = Solver

--[[ Input roster:
	members = { [fullName] = {
		name, class, group (1-8),
		wants = { FORT=bool, ... },
		ranking = { "KINGS", "MIGHT", ... },
		blessingsOverride = bool, -- explicitly use my ranking over the class plan
		caps = { KINGS=true, gKINGS=true, FORT=true, gFORT=true, DEVO=true, ... },
	} }
	paladinAssignments = { [class] = { [paladin] = blessingKey | "NONE" } }
	paladinAuras = { [paladin] = auraKey | "NONE" }
Output:
	pally[class][paladin] = blessingKey
	home[paladin] = blessingKey
	auras[paladin] = auraKey
	overrides[member][paladin] = blessingKey | false  (false = nothing suitable)
	groups[buffKey][groupNum] = caster
	raidGroupCasters[buffKey] = caster for the raid-wide version
	expected[member][buffKey] = caster   (what the tracker checks)
]]

local NB = #Buffs.BLESSING_KEYS
local globalIndex = {}
for i, k in ipairs(Buffs.BLESSING_KEYS) do globalIndex[k] = i end

local function can(member, key) return (member.caps or EMPTY)[key] end
local function canAny(member, key) return Buffs.CanCast(member.caps, key) end

local function countKnown(p, keys, knows)
	local count = 0
	for _, key in ipairs(keys) do if knows(p, key) then count = count + 1 end end
	return count
end

-- Weighted Borda points: rank 1 = NB points, rank 2 = NB-1 ...
-- Majority rules for the Greater Blessing.
local function blessingPoints(member, key)
	for i, k in ipairs(member.ranking or EMPTY) do
		if k == key then return NB - i + 1 end
	end
	return 0
end

-- Blessings by the voters' total points, best first, ties in catalog order.
local function rankBlessings(voters, scoredOnly)
	local score, order = {}, {}
	for _, b in ipairs(Buffs.BLESSING_KEYS) do
		score[b] = 0
		for _, m in ipairs(voters) do score[b] = score[b] + blessingPoints(m, b) end
		if not scoredOnly or score[b] > 0 then order[#order + 1] = b end
	end
	table.sort(order, function(a, b)
		if score[a] ~= score[b] then return score[a] > score[b] end
		return globalIndex[a] < globalIndex[b]
	end)
	return order
end

-- Bipartite matching (Kuhn): give `item` to the first free candidate, or move a
-- candidate's current item to someone else to free them. held = { [holder] = item }.
local function augment(item, candidates, held, visited)
	for _, p in ipairs(candidates(item)) do
		if not visited[p] then
			visited[p] = true
			if not held[p] or augment(held[p], candidates, held, visited) then
				held[p] = item
				return true
			end
		end
	end
	return false
end

-- Manual cells: a castable pick holds its key; it and None take the paladin out of Auto.
local function manualPicks(paladins, manual, knows)
	local held, taken, fixed = {}, {}, {}
	for _, p in ipairs(paladins) do
		local key = manual[p]
		if key == "NONE" then fixed[p] = true
		elseif key and knows(p, key) and not taken[key] then
			fixed[p], held[p], taken[key] = true, key, true
		end
	end
	return held, taken, fixed
end

local function setOverride(out, member, paladin, key)
	out.overrides[member] = out.overrides[member] or {}
	out.overrides[member][paladin] = key
end

-- Top-N class blessings matched to paladins, home paladin first. Classes not in
-- the group are planned from their defaults, so whoever joins is already covered.
local function planClass(ctx, class, voters)
	if #voters == 0 then
		voters = { { ranking = Buffs.DefaultRanking(class) } }
	end
	local paladins, knows, home, homeOf = ctx.paladins, ctx.knows, ctx.home, ctx.homeOf
	local order = rankBlessings(voters, true)
	local estimate = {}
	for i = 1, math.min(#paladins, #order) do estimate[order[i]] = true end
	local p2b, taken, fixed = manualPicks(paladins, (ctx.roster.paladinAssignments or EMPTY)[class] or EMPTY, knows)
	local function candidates(b)
		local c = {}
		for _, p in ipairs(paladins) do if not fixed[p] and knows(p, b) then c[#c + 1] = p end end
		table.sort(c, function(x, y)
			local hx, hy = (homeOf[b] == x) and 0 or 1, (homeOf[b] == y) and 0 or 1
			if hx ~= hy then return hx < hy end
			local fx = (home[x] and estimate[home[x]]) and 1 or 0
			local fy = (home[y] and estimate[home[y]]) and 1 or 0
			if fx ~= fy then return fx < fy end
			return x < y
		end)
		return c
	end
	local matched = 0
	for _, b in ipairs(order) do
		if matched >= #paladins then break end
		if not taken[b] and augment(b, candidates, p2b, {}) then matched = matched + 1 end
	end
	return p2b
end

-- Explicit personal rankings ignore the manual plan completely. Keep matching
-- class assignments where possible, then use single blessings for differences
-- (including a paladin whose class cell says None).
local function personalBlessings(ctx, n, m, p2b, out)
	local members, knows, personal, wanted = ctx.roster.members, ctx.knows, {}, {}
	local function candidates(b)
		local c = {}
		for _, p in ipairs(ctx.paladins) do
			if (p2b[p] == b and knows(p, b)) or can(members[p], b) then c[#c + 1] = p end
		end
		table.sort(c, function(x, y)
			if (p2b[x] == b) ~= (p2b[y] == b) then return p2b[x] == b end
			return x < y
		end)
		return c
	end
	for _, b in ipairs(m.ranking or EMPTY) do
		if not wanted[b] then
			wanted[b] = true
			augment(b, candidates, personal, {})
		end
	end
	for _, p in ipairs(ctx.paladins) do
		local b = personal[p]
		if b then out.expected[n][b] = p end
		if b ~= p2b[p] then setOverride(out, n, p, b or false) end
	end
end

-- Members without a personal ranking receive their class plan.
local function planBlessings(n, p2b, out)
	for p, b in pairs(p2b) do out.expected[n][b] = p end
end

local function solvePaladins(roster, names, paladins, out)
	if #paladins == 0 then return end
	local members = roster.members
	local function knows(p, b) return canAny(members[p], b) end
	local known, everyone, byClass = {}, {}, {}
	for _, p in ipairs(paladins) do known[p] = countKnown(p, Buffs.BLESSING_KEYS, knows) end
	for _, n in ipairs(names) do
		local class = members[n].class
		everyone[#everyone + 1] = members[n]
		byClass[class] = byClass[class] or {}
		table.insert(byClass[class], n)
	end

	-- Home blessing per paladin, in group order: scarce casters (e.g. the only
	-- Kings paladin) claim first.
	local home, homeOf = {}, {}
	for _, b in ipairs(rankBlessings(everyone)) do
		local best
		for _, p in ipairs(paladins) do
			if not home[p] and knows(p, b) and (not best or known[p] < known[best]) then best = p end
		end
		if best then home[best] = b; homeOf[b] = best end
	end
	out.home = home

	local ctx = { roster = roster, paladins = paladins, knows = knows, home = home, homeOf = homeOf }
	local classes, planned = {}, {}
	for _, class in ipairs(Buffs.CLASS_KEYS) do classes[#classes + 1] = class; planned[class] = true end
	for _, class in ipairs(sortedKeys(byClass)) do
		if not planned[class] then classes[#classes + 1] = class end
	end
	for _, class in ipairs(classes) do
		local classNames, voters = byClass[class] or EMPTY, {}
		for _, n in ipairs(classNames) do voters[#voters + 1] = members[n] end
		local p2b = planClass(ctx, class, voters)
		out.pally[class] = p2b
		for _, n in ipairs(classNames) do
			local m = members[n]
			if m.blessingsOverride then personalBlessings(ctx, n, m, p2b, out)
			else planBlessings(n, p2b, out) end
		end
	end
end

-- One aura per paladin, no aura twice. Manual picks stay; the rest follow the
-- catalog's priority, with paladins who know the fewest auras served first so
-- each aura can go to a paladin who knows it.
local function solveAuras(roster, paladins, out)
	local function knows(p, a) return can(roster.members[p], a) end
	local order, known = {}, {}
	for i, p in ipairs(paladins) do order[i] = p; known[p] = countKnown(p, Buffs.AURA_KEYS, knows) end
	table.sort(order, function(x, y)
		if known[x] ~= known[y] then return known[x] < known[y] end
		return x < y
	end)
	local p2a, taken, fixed = manualPicks(order, roster.paladinAuras or EMPTY, knows)
	local function candidates(a)
		local c = {}
		for _, p in ipairs(order) do if not fixed[p] and knows(p, a) then c[#c + 1] = p end end
		return c
	end
	for _, a in ipairs(Buffs.AURA_KEYS) do
		if not taken[a] then augment(a, candidates, p2a, {}) end
	end
	out.auras = p2a
end

-- For single-target casts, split subgroups by the number of players to buff.
-- Biggest groups go first. On equal work, prefer a caster in the group.
local function splitGroups(roster, casters, wanting)
	local groups, load, assign = sortedKeys(wanting), {}, {}
	table.sort(groups, function(a, b)
		if wanting[a] ~= wanting[b] then return wanting[a] > wanting[b] end
		return a < b
	end)
	for _, c in ipairs(casters) do load[c] = 0 end
	for _, g in ipairs(groups) do
		local best, bestLoad, bestHome
		for _, c in ipairs(casters) do
			local m = roster.members[c]
			local total = load[c] + wanting[g]
			local home = (m.group or 1) == g
			if not best or total < bestLoad or (total == bestLoad and home and not bestHome) then
				best, bestLoad, bestHome = c, total, home
			end
		end
		assign[g], load[best] = best, bestLoad
	end
	return assign
end

local function solveGroupBuffs(roster, names, out)
	local raidWork = {}
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local casters, wanting, raidCaster = {}, {}, nil
		local bestWork
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if m.class == buff.class and not m.dead then
				if can(m, buff.key) then casters[#casters + 1] = n end
				local work = raidWork[n] or 0
				if can(m, "g" .. buff.key) and (not bestWork or work < bestWork) then
					raidCaster, bestWork = n, work
				end
			end
			if (m.wants or EMPTY)[buff.key] then
				local g = m.group or 1
				wanting[g] = (wanting[g] or 0) + 1
			end
		end
		if next(wanting) and (raidCaster or #casters > 0) then
			local assign = {}
			if raidCaster then
				raidWork[raidCaster] = bestWork + 1
				out.raidGroupCasters[buff.key] = raidCaster
				for g in pairs(wanting) do assign[g] = raidCaster end
			else
				assign = splitGroups(roster, casters, wanting)
			end
			out.groups[buff.key] = assign
			for _, n in ipairs(names) do
				local m = roster.members[n]
				if (m.wants or EMPTY)[buff.key] then out.expected[n][buff.key] = assign[m.group or 1] end
			end
		end
	end
end

-- Choose one living warrior who has Battle Shout enabled for the whole raid.
local function solveBattleShout(roster, names, out)
	local caster
	for _, name in ipairs(names) do
		local member = roster.members[name]
		if member.class == "WARRIOR" and not member.dead and can(member, "BSHOUT") and (member.wants or EMPTY).BSHOUT then
			caster = name
			break
		end
	end
	if not caster then return end
	out.raidShout = caster
	for _, name in ipairs(names) do out.expected[name].BSHOUT = caster end
end

-- Tank and self buffs are single-target: self-only ones are cast by the member
-- who wants them, the rest rotate through the class's casters.
local function solveSingleBuffs(roster, names, out)
	for _, buff in ipairs(Buffs.SINGLE_BUFFS) do
		local casters, nextCaster = {}, 1
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if m.class == buff.class and can(m, buff.key) then casters[#casters + 1] = n end
		end
		for _, n in ipairs(names) do
			local m, caster = roster.members[n], nil
			local wanted = (m.wants or EMPTY)[buff.key]
			if buff.kind == "imbue" then wanted = m.weaponImbue == buff.key end
			if wanted then
				if buff.selfOnly then
					if m.class == buff.class and can(m, buff.key) then caster = n end
				elseif #casters > 0 then
					caster = casters[nextCaster]
					nextCaster = nextCaster % #casters + 1
				end
				out.expected[n][buff.key] = caster
			end
		end
	end
end

-- One volunteer maintains each raid support buff. Match by elemental slot so
-- two shamans can supply both air effects without one shaman replacing their own.
local function solveRaidSupport(roster, names, out)
	local slots = {}
	local function candidates(key)
		local buff, eligible = Buffs.byKey[key], {}
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if not m.dead and m.class == buff.class and (m.wants or EMPTY)[key] and can(m, key) then
				eligible[#eligible + 1] = n
			end
		end
		return eligible
	end
	for _, buff in ipairs(Buffs.RAID_SUPPORT) do
		local slot = buff.totemSlot or buff.key
		slots[slot] = slots[slot] or {}
		augment(buff.key, candidates, slots[slot], {})
	end
	out.raidSupport = {}
	for _, held in pairs(slots) do
		for caster, key in pairs(held) do
			out.raidSupport[key] = caster
			for _, n in ipairs(names) do out.expected[n][key] = caster end
		end
	end
end

function Solver.Solve(roster)
	local out = { pally = {}, home = {}, auras = {}, overrides = {}, groups = {}, raidGroupCasters = {}, expected = {} }
	local names, paladins = sortedKeys(roster.members), {}
	for _, n in ipairs(names) do
		out.expected[n] = {}
		if roster.members[n].class == "PALADIN" then paladins[#paladins + 1] = n end
	end
	solvePaladins(roster, names, paladins, out)
	solveAuras(roster, paladins, out)
	solveGroupBuffs(roster, names, out)
	solveSingleBuffs(roster, names, out)
	solveRaidSupport(roster, names, out)
	solveBattleShout(roster, names, out)
	return out
end
