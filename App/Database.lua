-- Persisted character settings; preserve existing keys and migrations.
local _, ns = ...
local Buffs = ns.Buffs
ns.Database = {}

function ns.Database.Init()
	BuffeteriaCharDB = BuffeteriaCharDB or {}
	local db = BuffeteriaCharDB
	local _, class = UnitClass("player")
	db.order = Buffs.NormalizeOrder(db.order or Buffs.DEFAULT_ORDER[class], class)
	-- Preserve deliberate rankings from before the explicit override toggle existed.
	if db.blessingsOverride == nil then
		db.blessingsOverride = table.concat(db.order, ",") ~= table.concat(Buffs.DEFAULT_ORDER[class] or Buffs.DEFAULT_ORDER.WARRIOR, ",")
	end
	db.paladinBlessings = db.paladinBlessings or {}
	if not db.wants then db.wants = Buffs.DefaultWants(class) end
	db.warnMinutes = db.warnMinutes or 5
	if db.showTracker == nil then db.showTracker = true end
	db.locked = db.locked or false
	db.minimap = db.minimap or { angle = 200, hide = false }
	if db.onlyProblems == nil then db.onlyProblems = true end
	ns.db = db
end
