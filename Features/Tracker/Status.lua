local _, ns = ...
local Status = {
	COLORS = { ok = { 0.25, 0.85, 0.35 }, warn = { 1.0, 0.6, 0.1 }, bad = { 0.95, 0.2, 0.2 }, idle = { 0.5, 0.5, 0.5 } },
	PRIORITY = { bad = 1, warn = 2, unwanted = 3, ok = 4, unknown = 5, idle = 6 },
}
ns.Status = Status

function Status.Color(status) return Status.COLORS[status] or Status.COLORS.idle end

-- Count expected buff/recipient pairs, rather than treating any missing buff
-- as an empty menu. Unknown observations must never count as fully buffed.
function Status.Mood(summary)
	if not summary or not summary.any then return "idle" end
	local total, missing, unknown = 0, 0, 0
	for _, counts in pairs(summary.perKey or {}) do
		total = total + counts.total
		missing = missing + counts.bad
		unknown = unknown + (counts.unknown or 0)
	end
	if total > 0 and missing == total then return "angry" end
	if summary.overall == "ok" and total > 0 and unknown == 0 then return "happy" end
	return "grumpy"
end

function Status.CompareProblems(a, b)
	if a.status ~= b.status then return Status.PRIORITY[a.status] < Status.PRIORITY[b.status] end
	if a.who ~= b.who then return a.who < b.who end
	return a.key < b.key
end
