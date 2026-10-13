-- The tracker feature: Status, Scan, Actions, Preview, Layout, Tooltip, EditMode,
-- the head (Tracker.lua) and its settings View all live in ns.Tracker.
local _, ns = ...
ns.Tracker = {}
local Status = {
	COLORS = { ok = { 0.25, 0.85, 0.35 }, warn = { 1.0, 0.6, 0.1 }, bad = { 0.95, 0.2, 0.2 }, idle = { 0.5, 0.5, 0.5 } },
	PRIORITY = { bad = 1, warn = 2, ok = 3, unknown = 4, idle = 5 },
}
ns.Tracker.Status = Status

function Status.Color(status) return Status.COLORS[status] or Status.COLORS.idle end

-- The more urgent of two statuses.
function Status.Worst(a, b) return Status.PRIORITY[b] < Status.PRIORITY[a] and b or a end

-- The tracker summary read by the head, tooltips and minimap button:
--   overall   my worst status; perKey  buff key -> my recipient counts (see NewCounts)
--   problems  { who, key, status, rem, caster } worst first
--   unreadable  members whose buffs can't be read; any  something is tracked
--   yours     keys I have to cast; needs  { key, status, caster } I'm missing
--   mine      { total, pending } recipient pairs assigned to me, and those still missing or low
--   next      my next cast (Actions.Next)
function Status.NewSummary()
	return { overall = "ok", perKey = {}, problems = {}, unreadable = {}, any = false, yours = {}, needs = {},
		mine = { total = 0, pending = 0 } }
end

-- Whether I'm assigned buffs to give and have served every one I can see.
function Status.MineDone(summary)
	local mine = summary and summary.mine
	return mine ~= nil and mine.total > 0 and mine.pending == 0
end

-- Recipient counts for one buff, and who is supposed to cast it.
function Status.NewCounts()
	return { bad = 0, warn = 0, total = 0, unknown = 0, casters = {} }
end

-- Only my recipients affect the face. Any missing buff is angry; expiring buffs
-- are grumpy. Unreadable recipients neither upset nor satisfy him. A helper cast
-- or resurrection also demands attention, even when my assigned work is done.
function Status.Mood(summary)
	if not summary or not summary.any then return "idle" end
	local total, readable, missing, expiring = 0, 0, 0, 0
	for _, counts in pairs(summary.perKey or {}) do
		total = total + counts.total
		readable = readable + counts.total - (counts.unknown or 0)
		missing = missing + counts.bad
		expiring = expiring + counts.warn
	end
	local nextStatus = summary.next and summary.next.status
	if missing > 0 or nextStatus == "bad" then return "angry" end
	if expiring > 0 or nextStatus == "warn" then return "grumpy" end
	if total == 0 then return "happy" end
	if readable <= 0 then return "idle" end
	return "happy"
end

-- Worst first, then by player and buff (entries without a player sort by buff).
function Status.CompareProblems(a, b)
	if a.status ~= b.status then return Status.PRIORITY[a.status] < Status.PRIORITY[b.status] end
	if a.who ~= b.who then return a.who < b.who end
	return a.key < b.key
end
