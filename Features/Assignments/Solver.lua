-- Buffeteria: the assignment solver.
-- Pure Lua, no WoW API: every client runs it on the same roster and gets the same answer.
local _, ns = ...
local Buffs = ns.Buffs

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

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

local NB = #Buffs.BLESSING_KEYS

-- Weighted Borda points: rank 1 = NB points, rank 2 = NB-1 ...; excluded = 0.
-- Majority rules for the Greater Blessing; anyone who excluded it gets a personal override.
local function blessingPoints(member, key)
	if member.excluded and member.excluded[key] then return 0 end
	for i, k in ipairs(member.ranking or {}) do
		if k == key then return NB - i + 1 end
	end
	return 0
end

local globalIndex = {}
for i, k in ipairs(Buffs.BLESSING_KEYS) do globalIndex[k] = i end

local function solvePaladins(roster, names, out)
	local paladins, byClass = {}, {}
	for _, n in ipairs(names) do
		local m = roster.members[n]
		if m.class == "PALADIN" then paladins[#paladins + 1] = n end
		byClass[m.class] = byClass[m.class] or {}
		table.insert(byClass[m.class], n)
	end
	if #paladins == 0 then return end

	local function knows(p, b) local c = roster.members[p].caps or {}; return c[b] or c["g" .. b] end
	local function knownCount(p)
		local c = 0
		for _, b in ipairs(Buffs.BLESSING_KEYS) do if knows(p, b) then c = c + 1 end end
		return c
	end

	-- 1) Global order: total points over everyone.
	local total = {}
	for _, b in ipairs(Buffs.BLESSING_KEYS) do
		total[b] = 0
		for _, n in ipairs(names) do total[b] = total[b] + blessingPoints(roster.members[n], b) end
	end
	local globalOrder = {}
	for i, b in ipairs(Buffs.BLESSING_KEYS) do globalOrder[i] = b end
	table.sort(globalOrder, function(a, b)
		if total[a] ~= total[b] then return total[a] > total[b] end
		return globalIndex[a] < globalIndex[b]
	end)

	-- 2) Home blessing per paladin: scarce casters (e.g. the only Kings paladin) claim first.
	local home, homeOf = {}, {}
	for _, b in ipairs(globalOrder) do
		local best
		for _, p in ipairs(paladins) do
			if not home[p] and knows(p, b) then
				if not best or knownCount(p) < knownCount(best) then best = p end
			end
		end
		if best then home[best] = b; homeOf[b] = best end
	end
	out.home = home

	-- 3) Per class: top-N blessings, matched to paladins (Kuhn's algorithm, home paladin first).
	-- Every class gets a plan, like PallyPower: classes not in the group are planned
	-- from their defaults, so whoever joins is already covered.
	local classes, planned = {}, {}
	for _, class in ipairs(Buffs.CLASS_KEYS) do classes[#classes + 1] = class; planned[class] = true end
	for _, class in ipairs(sortedKeys(byClass)) do
		if not planned[class] then classes[#classes + 1] = class end
	end
	for _, class in ipairs(classes) do
		local members = byClass[class] or {}
		local voters = {}
		for _, n in ipairs(members) do voters[#voters + 1] = roster.members[n] end
		if #voters == 0 then
			local ranking, excluded = Buffs.SplitOrder(Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR)
			voters[1] = { ranking = ranking, excluded = excluded }
		end
		local score = {}
		for _, b in ipairs(Buffs.BLESSING_KEYS) do
			score[b] = 0
			for _, m in ipairs(voters) do score[b] = score[b] + blessingPoints(m, b) end
		end
		local order = {}
		for _, b in ipairs(Buffs.BLESSING_KEYS) do if score[b] > 0 then order[#order + 1] = b end end
		table.sort(order, function(a, b)
			if score[a] ~= score[b] then return score[a] > score[b] end
			return globalIndex[a] < globalIndex[b]
		end)

		local estimate = {}
		for i = 1, math.min(#paladins, #order) do estimate[order[i]] = true end

		local b2p, p2b, fixed = {}, {}, {}
		local manual = (roster.paladinAssignments or {})[class] or {}
		for _, p in ipairs(paladins) do
			local b = manual[p]
			if b == "NONE" then fixed[p] = true
			elseif b and knows(p, b) and not b2p[b] then
				fixed[p] = true; p2b[p] = b; b2p[b] = p
			end
		end
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
		local function augment(b, visited)
			for _, p in ipairs(candidates(b)) do
				if not visited[p] then
					visited[p] = true
					if not p2b[p] or augment(p2b[p], visited) then
						p2b[p] = b; b2p[b] = p
						return true
					end
				end
			end
			return false
		end
		local matched = 0
		for _, b in ipairs(order) do
			if matched >= #paladins then break end
			if not b2p[b] and augment(b, {}) then matched = matched + 1 end
		end
		out.pally[class] = p2b

		-- 4) Explicit personal rankings ignore the manual plan completely. Keep
		-- matching class assignments where possible, then use single blessings
		-- for differences (including a paladin whose class cell says None).
		for _, n in ipairs(members) do
			local m = roster.members[n]
			out.expected[n] = out.expected[n] or {}
			if m.blessingsOverride then
				local personal, wanted = {}, {}
				local function personalCandidates(b)
					local candidates = {}
					for _, p in ipairs(paladins) do
						local caps = roster.members[p].caps or {}
						if (p2b[p] == b and knows(p, b)) or caps[b] then candidates[#candidates + 1] = p end
					end
					table.sort(candidates, function(x, y)
						if (p2b[x] == b) ~= (p2b[y] == b) then return p2b[x] == b end
						return x < y
					end)
					return candidates
				end
				local function assignPersonal(b, visited)
					for _, p in ipairs(personalCandidates(b)) do
						if not visited[p] then
							visited[p] = true
							if not personal[p] or assignPersonal(personal[p], visited) then personal[p] = b; return true end
						end
					end
					return false
				end
				for _, b in ipairs(m.ranking or {}) do
					if not wanted[b] and not (m.excluded or {})[b] then
						wanted[b] = true
						assignPersonal(b, {})
					end
				end
				for _, p in ipairs(paladins) do
					local b = personal[p]
					if b then out.expected[n][b] = p end
					if b ~= p2b[p] then
						out.overrides[n] = out.overrides[n] or {}
						out.overrides[n][p] = b or false
					end
				end
			else
				local provided = {}
				for _, b in pairs(p2b) do provided[b] = true end
				for _, p in ipairs(sortedKeys(p2b)) do
					local b = p2b[p]
					-- A manually chosen class blessing is the source of truth for
					-- default users, even if class defaults would exclude it.
					if not fixed[p] and m.excluded and m.excluded[b] then
						local pick = false
						for _, r in ipairs(m.ranking or {}) do
							if not provided[r] and (roster.members[p].caps or {})[r] then pick = r; break end
						end
						out.overrides[n] = out.overrides[n] or {}
						out.overrides[n][p] = pick
						if pick then provided[pick] = true; out.expected[n][pick] = p end
					else
						out.expected[n][b] = p
					end
				end
			end
		end
	end
end

-- One aura per paladin, no aura twice. Manual picks stay; the rest follow the
-- catalog's priority, with paladins who know the fewest auras served first so
-- talented auras (Concentration, Sanctity) land on the paladins who have them.
local function solveAuras(roster, names, out)
	local paladins = {}
	for _, n in ipairs(names) do
		if roster.members[n].class == "PALADIN" then paladins[#paladins + 1] = n end
	end
	local function knows(p, a) return (roster.members[p].caps or {})[a] end
	local known = {}
	for _, p in ipairs(paladins) do
		known[p] = 0
		for _, a in ipairs(Buffs.AURA_KEYS) do if knows(p, a) then known[p] = known[p] + 1 end end
	end
	table.sort(paladins, function(x, y)
		if known[x] ~= known[y] then return known[x] < known[y] end
		return x < y
	end)
	local manual, a2p, p2a, fixed = roster.paladinAuras or {}, {}, {}, {}
	for _, p in ipairs(paladins) do
		local a = manual[p]
		if a == "NONE" then fixed[p] = true
		elseif a and knows(p, a) and not a2p[a] then
			fixed[p] = true; p2a[p] = a; a2p[a] = p
		end
	end
	local function augment(a, visited)
		for _, p in ipairs(paladins) do
			if not fixed[p] and not visited[p] and knows(p, a) then
				visited[p] = true
				if not p2a[p] or augment(p2a[p], visited) then
					p2a[p] = a; a2p[a] = p
					return true
				end
			end
		end
		return false
	end
	for _, a in ipairs(Buffs.AURA_KEYS) do
		if not a2p[a] then augment(a, {}) end
	end
	out.auras = p2a
end

local function solveGroupBuffs(roster, names, out)
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local casters, groupsWanting = {}, {}
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if m.class == buff.class and m.caps and (m.caps[buff.key] or m.caps["g" .. buff.key]) then
				casters[#casters + 1] = n
			end
			if m.wants and m.wants[buff.key] then groupsWanting[m.group or 1] = true end
		end
		if #casters > 0 then
			local groups = sortedKeys(groupsWanting)
			local assign = {}
			for i, g in ipairs(groups) do assign[g] = casters[((i - 1) % #casters) + 1] end
			out.groups[buff.key] = assign
			for _, n in ipairs(names) do
				local m = roster.members[n]
				if m.wants and m.wants[buff.key] and assign[m.group or 1] then
					out.expected[n] = out.expected[n] or {}
					out.expected[n][buff.key] = assign[m.group or 1]
				end
			end
		end
	end
end

local function solveTankBuffs(roster, names, out)
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local casters, nextCaster = {}, 1
		for _, n in ipairs(names) do
			local m = roster.members[n]
			if m.class == buff.class and (m.caps or {})[buff.key] then casters[#casters + 1] = n end
		end
		for _, n in ipairs(names) do
			local m, caster = roster.members[n]
			if (m.wants or {})[buff.key] then
				if buff.selfOnly then
					if m.class == buff.class and (m.caps or {})[buff.key] then caster = n end
				elseif #casters > 0 then
					caster = casters[nextCaster]
					nextCaster = nextCaster % #casters + 1
				end
				if caster then out.expected[n][buff.key] = caster end
			end
		end
	end
end

function Solver.Solve(roster)
	local out = { pally = {}, home = {}, auras = {}, overrides = {}, groups = {}, expected = {} }
	local names = sortedKeys(roster.members)
	for _, n in ipairs(names) do out.expected[n] = {} end
	solvePaladins(roster, names, out)
	solveAuras(roster, names, out)
	solveGroupBuffs(roster, names, out)
	solveTankBuffs(roster, names, out)
	return out
end
