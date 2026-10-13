-- Persisted character settings; preserve existing keys and migrations.
local _, ns = ...
ns.Database = {}

-- Numeric settings: { minimum, maximum, step, default }. Controls read their range here.
ns.Database.RANGES = {
	iconSize = { 32, 128, 4, 96 },
	statusIconSize = { 16, 64, 1, 32 },
	shoutSize = { 10, 24, 1, 16 },
	warnPercent = { 1, 50, 1, 5 },
}
-- Allowed values, the first being the default.
local CHOICES = {
	coloredHair = { true, false },
	trackerStyle = { "HEAD", "CLEAN" },
	headStyle = { "ORC", "GNOME", "NIGHTELF", "TAUREN", "HUMAN", "TROLL", "UNDEAD", "XARYU" },
	buffDisplay = { "PROBLEMS", "ALL", "MISSING", "EXPIRING" },
	iconsPerRow = { 2, 3, 4 },
	iconPosition = { "BOTTOM", "LEFT", "TOP", "RIGHT", "AUTO" },
	tankRole = { "AUTO", "TANK", "OFF" },
}

-- A valid value for a ranged or choice setting: clamped to its range and step,
-- or the default choice when unknown. Other settings pass through.
function ns.Database.Normalize(key, value)
	local range, choices = ns.Database.RANGES[key], CHOICES[key]
	if range then
		local minimum, maximum, step, default = unpack(range)
		return math.max(minimum, math.min(maximum, math.floor((tonumber(value) or default) / step + 0.5) * step))
	end
	if choices then
		for _, allowed in ipairs(choices) do
			if allowed == value or (type(allowed) == "number" and allowed == tonumber(value)) then return allowed end
		end
		return choices[1]
	end
	return value
end

function ns.Database.Init()
	_G[ns.savedVariable] = _G[ns.savedVariable] or {}
	local db = _G[ns.savedVariable]
	if db.showTracker == nil then db.showTracker = true end
	db.locked = db.locked or false
	if db.helpOthers == nil then db.helpOthers = true end
	if db.resurrect == nil then db.resurrect = true end
	db.minimap = db.minimap or { angle = 200, hide = false }
	-- onlyProblems is the setting's pre-buffDisplay form.
	if db.onlyProblems == false and db.buffDisplay == nil then db.buffDisplay = "ALL" end
	-- A fixed number of minutes has no equivalent across different buff durations.
	-- Older characters start at the new 5% default; saved percentages are kept.
	db.warnMinutes = nil
	for key in pairs(CHOICES) do db[key] = ns.Database.Normalize(key, db[key]) end
	for key in pairs(ns.Database.RANGES) do db[key] = ns.Database.Normalize(key, db[key]) end
	ns.db = db
end

-- Change a display setting and let every view follow.
function ns.Database.Set(key, value)
	ns.db[key] = ns.Database.Normalize(key, value)
	ns.Events.Emit("SettingsChanged")
end
