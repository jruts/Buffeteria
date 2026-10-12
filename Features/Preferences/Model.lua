local _, ns = ...
local Buffs = ns.Buffs
ns.Preferences = {}

function ns.Preferences.IsTank()
	if ns.db.tankRole == "TANK" then return true end
	if ns.db.tankRole == "OFF" then return false end
	return ns.WoW.IsTank("player")
end

-- My own preferences in the shape the solver wants.
function ns.Preferences.Get()
	local ranking, excluded = Buffs.SplitOrder(ns.db.order)
	local class, tank = ns.WoW.PlayerClass(), ns.Preferences.IsTank()
	local wants = {}
	for key, value in pairs(ns.db.wants) do wants[key] = value end
	for _, buff in ipairs(Buffs.TANK_BUFFS) do
		wants[buff.key] = tank and ns.db.tankBuffs[buff.key] and Buffs.OfferedTo(buff, class) or false
	end
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		wants[buff.key] = wants[buff.key] and Buffs.OfferedTo(buff, class) or false
	end
	return { wants = wants, ranking = ranking, excluded = excluded, blessingsOverride = ns.db.blessingsOverride }
end

function ns.Preferences.Changed()
	ns.Events.Emit("PreferencesChanged")
end

function ns.Preferences.Reset()
	ns.Database.ResetPreferences()
	ns.Preferences.Changed()
end
