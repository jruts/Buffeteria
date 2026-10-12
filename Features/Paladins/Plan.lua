-- Built-in class blessing assignments. Each cell is a last-write-wins register;
-- revision + author makes simultaneous edits converge regardless of delivery order.
local _, ns = ...
local Buffs = ns.Buffs
local Plan = { cells = {}, revision = 0 }
ns.Paladins = Plan

local classes = {}
for i, class in ipairs(Buffs.CLASS_KEYS) do classes[class] = i end

local function validKey(key)
	return key == "AUTO" or key == "NONE" or (Buffs.byKey[key] and Buffs.byKey[key].kind == "blessing")
end

local function remember(paladin, class, key, revision, author)
	local row = Plan.cells[paladin] or {}
	local old = row[class]
	Plan.revision = math.max(Plan.revision, revision)
	ns.db.paladinRevision = Plan.revision
	if old and (old.revision > revision or (old.revision == revision and old.author >= author)) then return false end
	Plan.cells[paladin] = row
	row[class] = { key = key, revision = revision, author = author }
	if paladin == ns.WoW.FullName("player") then ns.db.paladinBlessings[class] = key end
	return true
end

function Plan.Init()
	Plan.revision = math.max(Plan.revision, tonumber(ns.db.paladinRevision) or 0, time())
	local _, class = UnitClass("player")
	if class ~= "PALADIN" then return end
	local me = ns.WoW.FullName("player")
	for targetClass, key in pairs(ns.db.paladinBlessings) do
		if classes[targetClass] and validKey(key) then
			Plan.revision = math.max(Plan.revision + 1, time())
			remember(me, targetClass, key, Plan.revision, me)
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

function Plan.Get(paladin, class)
	local cell = (Plan.cells[paladin] or {})[class]
	return cell and cell.key or "AUTO"
end

function Plan.Assignments(roster)
	local out, winners = {}, {}
	for paladin, row in pairs(Plan.cells) do
		local m = roster.members[paladin]
		if m and m.class == "PALADIN" then
			for class, cell in pairs(row) do
				if cell.key ~= "AUTO" then
					out[class] = out[class] or {}
					out[class][paladin] = cell.key
					if Buffs.byKey[cell.key] then
						winners[class] = winners[class] or {}
						local old = winners[class][cell.key]
						if not old or cell.revision > old.cell.revision
							or (cell.revision == old.cell.revision and (cell.author > old.cell.author
								or (cell.author == old.cell.author and paladin > old.paladin))) then
							if old then out[class][old.paladin] = "NONE" end
							winners[class][cell.key] = { paladin = paladin, cell = cell }
						else out[class][paladin] = "NONE" end
					end
					-- A manual assignment supplies the missing spell information for
					-- a paladin who cannot broadcast their spellbook.
					if not m.hasAddon and Buffs.byKey[cell.key] then m.caps[cell.key] = true end
				end
			end
		end
	end
	return out
end

local function message(paladin, class, cell)
	return table.concat({ "P", ns.Protocol.VERSION, paladin, classes[class], cell.key, cell.revision, cell.author }, "|")
end

local function edit(paladin, class, key)
	Plan.revision = math.max(Plan.revision + 1, time())
	local me = ns.WoW.FullName("player")
	remember(paladin, class, key, Plan.revision, me)
	ns.Comm.Send(message(paladin, class, Plan.cells[paladin][class]))
end

function Plan.Set(paladin, class, key)
	local _, myClass = UnitClass("player")
	local m = ns.roster.members[paladin]
	if myClass ~= "PALADIN" or not m or m.class ~= "PALADIN" or not classes[class] or not validKey(key) then return end
	if Buffs.byKey[key] then
		if m.hasAddon and not (m.caps[key] or m.caps["g" .. key]) then return end
		-- One caster per blessing/class. An explicit selection replaces another
		-- manual selection of that blessing instead of silently duplicating it.
		for other in pairs(Plan.cells) do
			if other ~= paladin and Plan.Get(other, class) == key then edit(other, class, "NONE") end
		end
	end
	edit(paladin, class, key)
	ns.Assignments.Resolve()
	ns.Events.Emit("PaladinPlanChanged")
end

function Plan.Broadcast()
	local _, class = UnitClass("player")
	if class ~= "PALADIN" then return end
	for paladin, row in pairs(Plan.cells) do
		for targetClass, cell in pairs(row) do ns.Comm.Send(message(paladin, targetClass, cell)) end
	end
end

function Plan.Receive(sender, paladin, classIndex, key, revision, author)
	local roster = ns.Roster.Build()
	local from, target, editor = roster.members[sender], roster.members[paladin], roster.members[author]
	local class = Buffs.CLASS_KEYS[tonumber(classIndex) or 0]
	revision = tonumber(revision)
	if not from or from.class ~= "PALADIN" or not target or target.class ~= "PALADIN"
		or type(author) ~= "string" or author == "" or (editor and editor.class ~= "PALADIN") or not class or not validKey(key)
		or not revision or revision < 0 or revision > 9007199254740000 or revision ~= math.floor(revision) then return end
	if remember(paladin, class, key, revision, author) then ns.Assignments.Resolve() end
end
