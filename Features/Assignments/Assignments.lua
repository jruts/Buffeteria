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
		local ok, res = pcall(Solver.Solve, ns.roster)
		if ok then ns.result = res else ns.WoW.Print("solver error: " .. tostring(res)) end
		ns.Events.Emit("AssignmentsChanged")
	end)
end

-- Plain-text summary of the current assignments.
function ns.Assignments.Lines(withColor)
	local lines, r = {}, ns.result
	local function nm(full)
		local m = ns.roster.members[full]
		return (withColor and m) and ns.WoW.ClassColorName(full, m.class) or ns.WoW.Short(full)
	end
	-- Paladins: blessing -> classes, per paladin.
	local perPal = {}
	for class, map in pairs(r.pally or {}) do
		for p, b in pairs(map) do
			perPal[p] = perPal[p] or {}
			perPal[p][b] = perPal[p][b] or {}
			table.insert(perPal[p][b], ns.WoW.ClassName(class))
		end
	end
	for p in pairs(r.auras or {}) do perPal[p] = perPal[p] or {} end
	local pals = {}
	for p in pairs(perPal) do pals[#pals + 1] = p end
	table.sort(pals)
	for _, p in ipairs(pals) do
		local parts = {}
		local aura = (r.auras or {})[p]
		if aura then parts[1] = Buffs.byKey[aura].label end
		local bs = {}
		for b in pairs(perPal[p]) do bs[#bs + 1] = b end
		table.sort(bs)
		for _, b in ipairs(bs) do
			table.sort(perPal[p][b])
			parts[#parts + 1] = Buffs.byKey[b].label .. " (" .. table.concat(perPal[p][b], ", ") .. ")"
		end
		lines[#lines + 1] = nm(p) .. ": " .. table.concat(parts, "; ")
	end
	for member, map in pairs(r.overrides or {}) do
		for p, b in pairs(map) do
			lines[#lines + 1] = ("  %s -> %s: %s instead"):format(nm(p), nm(member), b and Buffs.byKey[b].label or "nothing")
		end
	end
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local g = r.groups and r.groups[buff.key]
		if g and next(g) then
			local byCaster = {}
			for grp, c in pairs(g) do byCaster[c] = byCaster[c] or {}; table.insert(byCaster[c], grp) end
			local parts = {}
			for c, grps in pairs(byCaster) do
				table.sort(grps)
				parts[#parts + 1] = nm(c) .. " (G" .. table.concat(grps, ",") .. ")"
			end
			table.sort(parts)
			lines[#lines + 1] = buff.label .. ": " .. table.concat(parts, ", ")
		end
	end
	if #lines == 0 then lines[1] = "Nothing to assign. Find a buffer!" end
	return lines
end

function ns.Assignments.Announce()
	local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
	local lines = ns.Assignments.Lines(false)
	for _, l in ipairs(lines) do
		if chan then pcall(SendChatMessage, "[Buffeteria] " .. l, chan) else ns.WoW.Print(l) end
	end
end
