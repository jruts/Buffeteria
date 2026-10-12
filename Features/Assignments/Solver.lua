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
		ranking = { "KINGS", "MIGHT", ... }, excluded = { SALV=true },
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

-- Weighted Borda points: rank 1 = NB points, rank 2 = NB-1 ...; excluded = 0.
-- Majority rules for the Greater Blessing; anyone who excluded it gets a personal override.
local function blessingPoints(member, key)
	if member.excluded and member.excluded[key] then return 0 end
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
		local ranking, excluded = Buffs.DefaultRanking(class)
		voters = { { ranking = ranking, excluded = excluded } }
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
	return p2b, fixed
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
		if not wanted[b] and not (m.excluded or EMPTY)[b] then
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

-- Members on the class plan get it, except blessings they excluded, which are
-- swapped for the next ranked blessing that paladin can give.
local function planBlessings(ctx, n, m, p2b, fixed, out)
	local provided = {}
	for _, b in pairs(p2b) do provided[b] = true end
	for _, p in ipairs(sortedKeys(p2b)) do
		local b = p2b[p]
		-- A manually chosen class blessing is the source of truth for
		-- default users, even if class defaults would exclude it.
		if not fixed[p] and m.excluded and m.excluded[b] then
			local pick = false
			for _, r in ipairs(m.ranking or EMPTY) do
				if not provided[r] and can(ctx.roster.members[p], r) then pick = r; break end
			end
			setOverride(out, n, p, pick)
			if pick then provided[pick] = true; out.expected[n][pick] = p end
		else
			out.expected[n][b] = p
		end
	end
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
		local p2b, fixed = planClass(ctx, class, voters)
		out.pally[class] = p2b
		for _, n in ipairs(classNames) do
			local m = members[n]
			if m.blessingsOverride then personalBlessings(ctx, n, m, p2b, out)
			else planBlessings(ctx, n, m, p2b, fixed, out) end
		end
	end
end

-- One aura per paladin, no aura twice. Manual picks stay; the rest follow the
-- catalog's priority, with paladins who know the fewest auras served first so
-- talented auras (Concentration, Sanctity) land on the paladins who have them.
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

-- Each class splits the groups that want its buff between its casters.
local function solveGroupBuffs(roster, names, out)
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local casters, groupsWanting = {}, {}
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if m.class == buff.class and canAny(m, buff.key) then casters[#casters + 1] = n end
			if (m.wants or EMPTY)[buff.key] then groupsWanting[m.group or 1] = true end
		end
		if #casters > 0 then
			local assign = {}
			for i, g in ipairs(sortedKeys(groupsWanting)) do assign[g] = casters[((i - 1) % #casters) + 1] end
			out.groups[buff.key] = assign
			for _, n in ipairs(names) do
				local m = roster.members[n]
				if (m.wants or EMPTY)[buff.key] then out.expected[n][buff.key] = assign[m.group or 1] end
			end
		end
	end
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
			if (m.wants or EMPTY)[buff.key] then
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

function Solver.Solve(roster)
	local out = { pally = {}, home = {}, auras = {}, overrides = {}, groups = {}, expected = {} }
	local names, paladins = sortedKeys(roster.members), {}
	for _, n in ipairs(names) do
		out.expected[n] = {}
		if roster.members[n].class == "PALADIN" then paladins[#paladins + 1] = n end
	end
	solvePaladins(roster, names, paladins, out)
	solveAuras(roster, paladins, out)
	solveGroupBuffs(roster, names, out)
	solveSingleBuffs(roster, names, out)
	return out
end
