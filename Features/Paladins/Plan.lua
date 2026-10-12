-- Built-in paladin assignments: a blessing per class and an aura per paladin. Each
-- cell is a last-write-wins register; revision + author makes simultaneous edits
-- converge regardless of delivery order.
local _, ns = ...
local Buffs = ns.Buffs
local Plan = { cells = {}, revision = 0, AURA = "AURA" }
ns.Paladins = Plan
local AURA = Plan.AURA

-- Slot -> wire index: the nine classes, then the paladin's own aura.
local slots, slotAt = {}, {}
for i, class in ipairs(Buffs.CLASS_KEYS) do slots[class] = i end
slots[AURA] = #Buffs.CLASS_KEYS + 1
for slot, i in pairs(slots) do slotAt[i] = slot end

local function validKey(slot, key)
	if key == "AUTO" or key == "NONE" then return true end
	local buff = Buffs.byKey[key]
	return buff ~= nil and buff.kind == (slot == AURA and "aura" or "blessing")
end

local function isPaladin()
	local _, class = UnitClass("player")
	return class == "PALADIN"
end

local function remember(paladin, slot, key, revision, author)
	local row = Plan.cells[paladin] or {}
	local old = row[slot]
	Plan.revision = math.max(Plan.revision, revision)
	ns.db.paladinRevision = Plan.revision
	if old and (old.revision > revision or (old.revision == revision and old.author >= author)) then return false end
	Plan.cells[paladin] = row
	row[slot] = { key = key, revision = revision, author = author }
	if paladin == ns.WoW.FullName("player") then ns.db.paladinBlessings[slot] = key end
	return true
end

function Plan.Init()
	Plan.revision = math.max(Plan.revision, tonumber(ns.db.paladinRevision) or 0, time())
	if not isPaladin() then return end
	local me = ns.WoW.FullName("player")
	for slot, key in pairs(ns.db.paladinBlessings) do
		if slots[slot] and validKey(slot, key) then
			Plan.revision = math.max(Plan.revision + 1, time())
			remember(me, slot, key, Plan.revision, me)
		end
	end
end

function Plan.Prune(roster)
	for paladin in pairs(Plan.cells) do
		if not roster.members[paladin] then
			Plan.cells[paladin] = nil
		end
	end
end

function Plan.Get(paladin, slot)
	local cell = (Plan.cells[paladin] or {})[slot]
	return cell and cell.key or "AUTO"
end

-- Manual cells for the solver: class -> paladin -> blessing, and paladin -> aura.
-- When two paladins claim the same key in a slot, the newest edit keeps it.
function Plan.Assignments(roster)
	local out, winners = {}, {}
	for paladin, row in pairs(Plan.cells) do
		local m = roster.members[paladin]
		if m and m.class == "PALADIN" then
			for slot, cell in pairs(row) do
				if cell.key ~= "AUTO" then
					out[slot] = out[slot] or {}
					out[slot][paladin] = cell.key
					if Buffs.byKey[cell.key] then
						winners[slot] = winners[slot] or {}
						local old = winners[slot][cell.key]
						if not old or cell.revision > old.cell.revision
							or (cell.revision == old.cell.revision and (cell.author > old.cell.author
								or (cell.author == old.cell.author and paladin > old.paladin))) then
							if old then out[slot][old.paladin] = "NONE" end
							winners[slot][cell.key] = { paladin = paladin, cell = cell }
						else out[slot][paladin] = "NONE" end
					end
					-- A manual assignment supplies the missing spell information for
					-- a paladin who cannot broadcast their spellbook.
					if not m.hasAddon and Buffs.byKey[cell.key] then m.caps[cell.key] = true end
				end
			end
		end
	end
	local auras = out[AURA] or {}
	out[AURA] = nil
	return out, auras
end

local function message(paladin, slot, cell)
	return table.concat({ "P", ns.Protocol.VERSION, paladin, slots[slot], cell.key, cell.revision, cell.author }, "|")
end

local function edit(paladin, slot, key)
	Plan.revision = math.max(Plan.revision + 1, time())
	local me = ns.WoW.FullName("player")
	remember(paladin, slot, key, Plan.revision, me)
	ns.Comm.Send(message(paladin, slot, Plan.cells[paladin][slot]))
end

local function changed()
	ns.Assignments.Resolve()
	ns.Events.Emit("PaladinPlanChanged")
end

function Plan.Set(paladin, slot, key)
	local m = ns.roster.members[paladin]
	if not isPaladin() or not m or m.class ~= "PALADIN" or not slots[slot] or not validKey(slot, key) then return end
	if Buffs.byKey[key] then
		if m.hasAddon and not (m.caps[key] or m.caps["g" .. key]) then return end
		-- One caster per blessing/class and per aura. An explicit selection replaces
		-- another manual selection of that key instead of silently duplicating it.
		for other in pairs(Plan.cells) do
			if other ~= paladin and Plan.Get(other, slot) == key then edit(other, slot, "NONE") end
		end
	end
	edit(paladin, slot, key)
	changed()
end

local function rosterPaladins(roster)
	local out = {}
	for name, m in pairs(roster.members) do
		if m.class == "PALADIN" then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

-- Like PallyPower's auto-assign: turn every Auto cell into the blessing or aura
-- the solver picks for it now, so the whole plan is filled in and shared.
-- Manual choices (including None) stay as they are.
function Plan.Fill()
	if not isPaladin() then return 0 end
	local roster = ns.Roster.Build()
	local result = ns.Solver.Solve(roster)
	local filled = 0
	for _, paladin in ipairs(rosterPaladins(roster)) do
		for _, slot in ipairs(Buffs.CLASS_KEYS) do
			local key = (result.pally[slot] or {})[paladin]
			if key and Plan.Get(paladin, slot) == "AUTO" then edit(paladin, slot, key); filled = filled + 1 end
		end
		local aura = result.auras[paladin]
		if aura and Plan.Get(paladin, AURA) == "AUTO" then edit(paladin, AURA, aura); filled = filled + 1 end
	end
	if filled > 0 then changed() end
	return filled
end

-- Return every cell of the group's paladins to Auto.
function Plan.Clear()
	if not isPaladin() then return 0 end
	local cleared = 0
	for _, paladin in ipairs(rosterPaladins(ns.roster)) do
		for slot in pairs(slots) do
			if Plan.Get(paladin, slot) ~= "AUTO" then edit(paladin, slot, "AUTO"); cleared = cleared + 1 end
		end
	end
	if cleared > 0 then changed() end
	return cleared
end

function Plan.Broadcast()
	if not isPaladin() then return end
	for paladin, row in pairs(Plan.cells) do
		for slot, cell in pairs(row) do ns.Comm.Send(message(paladin, slot, cell)) end
	end
end

function Plan.Receive(sender, paladin, slotIndex, key, revision, author)
	local roster = ns.Roster.Build()
	local from, target, editor = roster.members[sender], roster.members[paladin], roster.members[author]
	local slot = slotAt[tonumber(slotIndex) or 0]
	revision = tonumber(revision)
	if not from or from.class ~= "PALADIN" or not target or target.class ~= "PALADIN"
		or type(author) ~= "string" or author == "" or (editor and editor.class ~= "PALADIN") or not slot or not validKey(slot, key)
		or not revision or revision < 0 or revision > 9007199254740000 or revision ~= math.floor(revision) then return end
	if remember(paladin, slot, key, revision, author) then ns.Assignments.Resolve() end
end
