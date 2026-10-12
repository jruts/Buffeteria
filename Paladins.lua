-- Built-in class blessing assignments. Each cell is a last-write-wins register;
-- revision + author makes simultaneous edits converge regardless of delivery order.
local _, ns = ...
local D = ns.Data
local A = { cells = {}, revision = 0 }
ns.Paladins = A

local classes = {}
for i, class in ipairs(D.CLASS_KEYS) do classes[class] = i end

local function validKey(key)
	return key == "AUTO" or key == "NONE" or (D.byKey[key] and D.byKey[key].kind == "blessing")
end

local function remember(paladin, class, key, revision, author)
	local row = A.cells[paladin] or {}
	local old = row[class]
	A.revision = math.max(A.revision, revision)
	ns.db.paladinRevision = A.revision
	if old and (old.revision > revision or (old.revision == revision and old.author >= author)) then return false end
	A.cells[paladin] = row
	row[class] = { key = key, revision = revision, author = author }
	if paladin == ns.FullName("player") then ns.db.paladinBlessings[class] = key end
	return true
end

function A.Init()
	A.revision = math.max(A.revision, tonumber(ns.db.paladinRevision) or 0, time())
	local _, class = UnitClass("player")
	if class ~= "PALADIN" then return end
	local me = ns.FullName("player")
	for targetClass, key in pairs(ns.db.paladinBlessings) do
		if classes[targetClass] and validKey(key) then
			A.revision = math.max(A.revision + 1, time())
			remember(me, targetClass, key, A.revision, me)
		end
	end
end

function A.Prune(roster)
	for paladin, row in pairs(A.cells) do
		if not roster.members[paladin] then
			A.cells[paladin] = nil
		end
	end
end

function A.Get(paladin, class)
	local cell = (A.cells[paladin] or {})[class]
	return cell and cell.key or "AUTO"
end

function A.Assignments(roster)
	local out, winners = {}, {}
	for paladin, row in pairs(A.cells) do
		local m = roster.members[paladin]
		if m and m.class == "PALADIN" then
			for class, cell in pairs(row) do
				if cell.key ~= "AUTO" then
					out[class] = out[class] or {}
					out[class][paladin] = cell.key
					if D.byKey[cell.key] then
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
					if not m.hasAddon and D.byKey[cell.key] then m.caps[cell.key] = true end
				end
			end
		end
	end
	return out
end

local function message(paladin, class, cell)
	return table.concat({ "P", "2", paladin, classes[class], cell.key, cell.revision, cell.author }, "|")
end

local function edit(paladin, class, key)
	A.revision = math.max(A.revision + 1, time())
	local me = ns.FullName("player")
	remember(paladin, class, key, A.revision, me)
	if ns.Comm then ns.Comm.Send(message(paladin, class, A.cells[paladin][class])) end
end

function A.Set(paladin, class, key)
	local _, myClass = UnitClass("player")
	local m = ns.roster.members[paladin]
	if myClass ~= "PALADIN" or not m or m.class ~= "PALADIN" or not classes[class] or not validKey(key) then return end
	if D.byKey[key] then
		if m.hasAddon and not (m.caps[key] or m.caps["g" .. key]) then return end
		-- One caster per blessing/class. An explicit selection replaces another
		-- manual selection of that blessing instead of silently duplicating it.
		for other in pairs(A.cells) do
			if other ~= paladin and A.Get(other, class) == key then edit(other, class, "NONE") end
		end
	end
	edit(paladin, class, key)
	ns.Resolve()
	if ns.Prefs then ns.Prefs.Refresh() end
end

function A.Broadcast()
	local _, class = UnitClass("player")
	if class ~= "PALADIN" or not ns.Comm then return end
	for paladin, row in pairs(A.cells) do
		for targetClass, cell in pairs(row) do ns.Comm.Send(message(paladin, targetClass, cell)) end
	end
end

function A.Receive(sender, paladin, classIndex, key, revision, author)
	local roster = ns.BuildRoster()
	local from, target, editor = roster.members[sender], roster.members[paladin], roster.members[author]
	local class = D.CLASS_KEYS[tonumber(classIndex) or 0]
	revision = tonumber(revision)
	if not from or from.class ~= "PALADIN" or not target or target.class ~= "PALADIN"
		or type(author) ~= "string" or author == "" or (editor and editor.class ~= "PALADIN") or not class or not validKey(key)
		or not revision or revision < 0 or revision > 9007199254740000 or revision ~= math.floor(revision) then return end
	if remember(paladin, class, key, revision, author) then ns.Resolve() end
end
