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

-- Edits for paladins or from senders not in the roster yet (just joined, zoning,
-- not loaded). They are applied as soon as the roster can validate them.
local pending, pendingCount, MAX_PENDING, PENDING_SECONDS = {}, 0, 200, 60

local function validKey(slot, key)
	if key == "AUTO" or key == "NONE" then return true end
	local buff = Buffs.byKey[key]
	return buff ~= nil and buff.kind == (slot == AURA and "aura" or "blessing")
end

-- The roster member when they are a paladin, else nil.
local function paladinMember(roster, name)
	local m = roster.members[name]
	return m and m.class == "PALADIN" and m or nil
end

-- Last write wins: the higher revision, then the higher author name.
local function newer(a, b)
	return a.revision > b.revision or (a.revision == b.revision and a.author > b.author)
end

local function remember(paladin, slot, key, revision, author)
	local row = Plan.cells[paladin] or {}
	local cell, old = { key = key, revision = revision, author = author }, row[slot]
	Plan.revision = math.max(Plan.revision, revision)
	ns.db.paladinRevision = Plan.revision
	if old and not newer(cell, old) then return false end
	Plan.cells[paladin] = row
	row[slot] = cell
	if paladin == ns.WoW.Me() then ns.db.paladinBlessings[slot] = key end
	return true
end

local function nextRevision()
	Plan.revision = math.max(Plan.revision + 1, time())
	return Plan.revision
end

function Plan.Init()
	ns.db.paladinBlessings = ns.db.paladinBlessings or {}
	Plan.revision = math.max(Plan.revision, tonumber(ns.db.paladinRevision) or 0, time())
	if not ns.WoW.IsPaladin() then return end
	local me = ns.WoW.Me()
	for slot, key in pairs(ns.db.paladinBlessings) do
		if slots[slot] and validKey(slot, key) then remember(me, slot, key, nextRevision(), me) end
	end
end

-- Assignments belong to the current group. A paladin missing from one roster read
-- (offline, loading screen, data not loaded) keeps their cells; leaving the group
-- clears everyone else's.
function Plan.Prune(roster)
	if IsInGroup and IsInGroup() then return end
	for paladin in pairs(Plan.cells) do
		if not roster.members[paladin] then Plan.cells[paladin] = nil end
	end
end

function Plan.Get(paladin, slot)
	local cell = (Plan.cells[paladin] or {})[slot]
	return cell and cell.key or "AUTO"
end

-- Manual cells for the solver: class -> paladin -> blessing, and paladin -> aura.
-- When two paladins claim the same key in a slot, the newest edit keeps it.
-- Also returns paladin -> { key = true } for keys assigned to paladins without
-- the add-on: the assignment supplies the spellbook they cannot broadcast.
function Plan.Assignments(roster)
	local out, winners, assumed = {}, {}, {}
	for paladin, row in pairs(Plan.cells) do
		local m = paladinMember(roster, paladin)
		if m then
			for slot, cell in pairs(row) do
				if cell.key ~= "AUTO" then
					out[slot] = out[slot] or {}
					out[slot][paladin] = cell.key
					if Buffs.byKey[cell.key] then
						winners[slot] = winners[slot] or {}
						local old = winners[slot][cell.key]
						if not old or newer(cell, old.cell) or (not newer(old.cell, cell) and paladin > old.paladin) then
							if old then out[slot][old.paladin] = "NONE" end
							winners[slot][cell.key] = { paladin = paladin, cell = cell }
						else
							out[slot][paladin] = "NONE"
						end
						if not m.hasAddon then
							assumed[paladin] = assumed[paladin] or {}
							assumed[paladin][cell.key] = true
						end
					end
				end
			end
		end
	end
	local auras = out[AURA] or {}
	out[AURA] = nil
	return out, auras, assumed
end

-- A manual pick that lost its key to another paladin's newer edit.
function Plan.Overruled(paladin, slot)
	if not Buffs.byKey[Plan.Get(paladin, slot)] then return false end
	local roster = ns.Assignments.roster
	local cells = slot == AURA and roster.paladinAuras or (roster.paladinAssignments or {})[slot]
	return (cells or {})[paladin] == "NONE"
end

-- nil = the roster cannot validate it yet, false = rejected or older, true = applied.
local function apply(roster, edit)
	local from, target, editor = roster.members[edit.sender], roster.members[edit.paladin], roster.members[edit.author]
	if not from or not target then return nil end
	if from.class ~= "PALADIN" or target.class ~= "PALADIN" or (editor and editor.class ~= "PALADIN") then return false end
	return remember(edit.paladin, edit.slot, edit.key, edit.revision, edit.author)
end

-- Retry edits that arrived before their sender or paladin was in the roster.
function Plan.Replay(roster)
	local changed, now = false, GetTime()
	for id, edit in pairs(pending) do
		local result = apply(roster, edit)
		if result == nil and now - edit.at > PENDING_SECONDS then result = false end
		if result ~= nil then
			pending[id] = nil; pendingCount = pendingCount - 1
			changed = changed or result
		end
	end
	return changed
end

-- Give a fresh roster read its plan: forget the old group's cells, apply waiting
-- edits, then hand the solver the manual cells and the spells they imply.
function Plan.Attach(roster)
	Plan.Prune(roster)
	Plan.Replay(roster)
	local assumed
	roster.paladinAssignments, roster.paladinAuras, assumed = Plan.Assignments(roster)
	for paladin, keys in pairs(assumed) do
		for key in pairs(keys) do roster.members[paladin].caps[key] = true end
	end
end

local function send(paladin, slot)
	local cell = Plan.cells[paladin][slot]
	ns.Comm.Send(ns.Protocol.Encode("P", paladin, slots[slot], cell.key, cell.revision, cell.author))
end

local function edit(paladin, slot, key)
	remember(paladin, slot, key, nextRevision(), ns.WoW.Me())
	send(paladin, slot)
end

local function changed() ns.Events.Emit("PaladinPlanChanged") end

-- Whether a paladin may be assigned a key: anything for paladins without the
-- add-on (their spellbook is unknown), else only what they can cast.
local function castable(m, key)
	return not m.hasAddon or Buffs.CanCast(m.caps, key)
end

-- A slot's choices for the editor, in cycling order; empty for non-paladins.
function Plan.Choices(paladin, slot)
	local m = paladinMember(ns.Assignments.roster, paladin)
	if not m then return {} end
	local choices = { "AUTO" }
	for _, key in ipairs(slot == AURA and Buffs.AURA_KEYS or Buffs.BLESSING_KEYS) do
		if castable(m, key) then choices[#choices + 1] = key end
	end
	choices[#choices + 1] = "NONE"
	return choices
end

function Plan.Set(paladin, slot, key)
	local m = paladinMember(ns.Assignments.roster, paladin)
	if not ns.WoW.IsPaladin() or not m or not slots[slot] or not validKey(slot, key) then return end
	if Buffs.byKey[key] then
		if not castable(m, key) then return end
		-- One caster per blessing/class and per aura. An explicit selection replaces
		-- another manual selection of that key instead of silently duplicating it.
		for other in pairs(Plan.cells) do
			if other ~= paladin and Plan.Get(other, slot) == key then edit(other, slot, "NONE") end
		end
	end
	edit(paladin, slot, key)
	changed()
end

-- Edit every group paladin's cell that matches; returns how many changed.
local function editAll(matches, pick)
	if not ns.WoW.IsPaladin() then return 0 end
	local count = 0
	for _, paladin in ipairs(ns.Roster.Paladins()) do
		for slot in pairs(slots) do
			local key = matches(Plan.Get(paladin, slot)) and pick(paladin, slot)
			if key then edit(paladin, slot, key); count = count + 1 end
		end
	end
	if count > 0 then changed() end
	return count
end

-- Like PallyPower's auto-assign: turn every Auto cell into the blessing or aura
-- the solver picks for it now, so the whole plan is filled in and shared.
-- Manual choices (including None) stay as they are.
function Plan.Fill()
	return editAll(function(key) return key == "AUTO" end, function(paladin, slot)
		if slot == AURA then return ns.Assignments.Aura(paladin) end
		return ns.Assignments.ClassBlessing(slot, paladin)
	end)
end

-- Return every cell of the group's paladins to Auto.
function Plan.Clear()
	return editAll(function(key) return key ~= "AUTO" end, function() return "AUTO" end)
end

function Plan.Broadcast()
	if not ns.WoW.IsPaladin() then return end
	-- Kept cells of paladins who are away right now go out again when they return.
	for paladin, row in pairs(Plan.cells) do
		if paladinMember(ns.Assignments.roster, paladin) then
			for slot in pairs(row) do send(paladin, slot) end
		end
	end
end

function Plan.Receive(sender, paladin, slotIndex, key, revision, author)
	sender, paladin, author = ns.WoW.NormalizeName(sender), ns.WoW.NormalizeName(paladin), ns.WoW.NormalizeName(author)
	local slot = slotAt[tonumber(slotIndex) or 0]
	revision = tonumber(revision)
	if not sender or not paladin or not author or not slot or not validKey(slot, key)
		or not revision or revision < 0 or revision > 9007199254740000 or revision ~= math.floor(revision) then return end
	local edit = { sender = sender, paladin = paladin, slot = slot, key = key, revision = revision, author = author, at = GetTime() }
	local result = apply(ns.Assignments.roster, edit)
	if result then
		changed()
	elseif result == nil then
		local id = paladin .. "|" .. slot
		local old = pending[id]
		if old then
			if newer(edit, old) then pending[id] = edit end
		elseif pendingCount < MAX_PENDING then
			pending[id] = edit; pendingCount = pendingCount + 1
		end
	end
end

ns.Events.On("BroadcastRequested", Plan.Broadcast)
ns.Events.On("Received:P", function(...) Plan.Receive(...) end)
