-- The tracker feature: Status, Scan, Actions, Preview, Layout, Tooltip, the head
-- (Tracker.lua) and its settings View all live in ns.Tracker.
local _, ns = ...
ns.Tracker = {}
local Status = {
	COLORS = { ok = { 0.25, 0.85, 0.35 }, warn = { 1.0, 0.6, 0.1 }, bad = { 0.95, 0.2, 0.2 }, idle = { 0.5, 0.5, 0.5 } },
	PRIORITY = { bad = 1, warn = 2, unwanted = 3, ok = 4, unknown = 5, idle = 6 },
}
ns.Tracker.Status = Status

function Status.Color(status) return Status.COLORS[status] or Status.COLORS.idle end

-- The more urgent of two statuses.
function Status.Worst(a, b) return Status.PRIORITY[b] < Status.PRIORITY[a] and b or a end

-- Count expected buff/recipient pairs, rather than treating any missing buff
-- as an empty menu. Unreadable pairs (e.g. players out of range) are left out:
-- they neither upset nor satisfy him. With nothing readable he stays idle.
function Status.Mood(summary)
	if not summary or not summary.any then return "idle" end
	local readable, missing = 0, 0
	for _, counts in pairs(summary.perKey or {}) do
		readable = readable + counts.total - (counts.unknown or 0)
		missing = missing + counts.bad
	end
	if readable <= 0 then return "idle" end
	if missing == readable then return "angry" end
	if summary.overall == "ok" then return "happy" end
	return "grumpy"
end

-- Worst first, then by player and buff (entries without a player sort by buff).
function Status.CompareProblems(a, b)
	if a.status ~= b.status then return Status.PRIORITY[a.status] < Status.PRIORITY[b.status] end
	if a.who ~= b.who then return a.who < b.who end
	return a.key < b.key
end
