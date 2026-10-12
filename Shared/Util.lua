-- Plain Lua table helpers used across features.
local _, ns = ...
ns.Util = { EMPTY = {} } -- read-only stand-in for a missing table

function ns.Util.SortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end
