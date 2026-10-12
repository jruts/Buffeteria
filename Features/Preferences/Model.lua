local _, ns = ...
local Buffs = ns.Buffs
ns.Preferences = {}

-- My own preferences in the shape the solver wants.
function ns.Preferences.Get()
	local ranking, excluded = Buffs.SplitOrder(ns.db.order)
	return { wants = ns.db.wants, ranking = ranking, excluded = excluded, blessingsOverride = ns.db.blessingsOverride }
end

function ns.Preferences.Changed()
	ns.Events.Emit("PreferencesChanged")
end

function ns.Preferences.Reset()
	local _, class = UnitClass("player")
	ns.db.order = Buffs.NormalizeOrder(Buffs.DEFAULT_ORDER[class], class)
	ns.db.wants = Buffs.DefaultWants(class)
	ns.db.blessingsOverride = false
	ns.Preferences.Changed()
end
