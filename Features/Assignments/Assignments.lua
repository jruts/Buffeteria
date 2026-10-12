-- Recompute and present the current buff plan.
local _, ns = ...
local Buffs, Solver = ns.Buffs, ns.Solver
ns.Assignments = {}

local pending = false
function ns.Assignments.Resolve()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		ns.roster = ns.Roster.Build()
		ns.Paladins.Attach(ns.roster)
		local ok, res = pcall(Solver.Solve, ns.roster)
		if ok then ns.result = res else ns.WoW.Print("solver error: " .. tostring(res)) end
		ns.Events.Emit("AssignmentsChanged")
	end)
end

-- What a member should receive: buff key -> caster.
function ns.Assignments.Served(member) return ns.result.expected[member] or {} end

-- The blessing a paladin gives a class, and a paladin's aura, as solved now.
function ns.Assignments.ClassBlessing(class, paladin) return (ns.result.pally[class] or {})[paladin] end
function ns.Assignments.Aura(paladin) return ns.result.auras[paladin] end

local function sorted(list) table.sort(list); return list end

-- Plain-text summary of the current assignments.
function ns.Assignments.Lines(withColor)
	local lines, r = {}, ns.result
	local nm = withColor and ns.Roster.Name or ns.WoW.Short
	-- Paladins: aura, then blessing -> classes, per paladin.
	local perPal = {}
	for class, map in pairs(r.pally) do
		for p, b in pairs(map) do
			perPal[p] = perPal[p] or {}
			perPal[p][b] = perPal[p][b] or {}
			table.insert(perPal[p][b], ns.WoW.ClassName(class))
		end
	end
	for p in pairs(r.auras) do perPal[p] = perPal[p] or {} end
	for _, p in ipairs(Solver.SortedKeys(perPal)) do
		local parts = {}
		if r.auras[p] then parts[1] = Buffs.byKey[r.auras[p]].label end
		for _, b in ipairs(Solver.SortedKeys(perPal[p])) do
			parts[#parts + 1] = Buffs.byKey[b].label .. " (" .. table.concat(sorted(perPal[p][b]), ", ") .. ")"
		end
		lines[#lines + 1] = nm(p) .. ": " .. table.concat(parts, "; ")
	end
	for _, member in ipairs(Solver.SortedKeys(r.overrides)) do
		for _, p in ipairs(Solver.SortedKeys(r.overrides[member])) do
			local b = r.overrides[member][p]
			lines[#lines + 1] = ("  %s -> %s: %s instead"):format(nm(p), nm(member), b and Buffs.byKey[b].label or "nothing")
		end
	end
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local byCaster = {}
		for grp, c in pairs(r.groups[buff.key] or {}) do byCaster[c] = byCaster[c] or {}; table.insert(byCaster[c], grp) end
		local parts = {}
		for c, grps in pairs(byCaster) do parts[#parts + 1] = nm(c) .. " (G" .. table.concat(sorted(grps), ",") .. ")" end
		if #parts > 0 then lines[#lines + 1] = buff.label .. ": " .. table.concat(sorted(parts), ", ") end
	end
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		local parts = {}
		for member, expected in pairs(r.expected) do
			local caster = expected[buff.key]
			if caster then parts[#parts + 1] = nm(caster) .. " -> " .. nm(member) end
		end
		for _, part in ipairs(sorted(parts)) do lines[#lines + 1] = buff.label .. ": " .. part end
	end
	if #lines == 0 then lines[1] = "Nothing to assign. Find a buffer!" end
	return lines
end

function ns.Assignments.Announce()
	local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
	for _, l in ipairs(ns.Assignments.Lines(false)) do
		if chan then pcall(SendChatMessage, "[" .. ns.title .. "] " .. l, chan) else ns.WoW.Print(l) end
	end
end
