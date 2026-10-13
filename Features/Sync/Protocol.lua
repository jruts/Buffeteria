-- Wire format. Keep version 2 compatible with existing group members:
--   S|2|wants|ranking|reserved|caps|override   preferences and spellbook
-- The reserved field is empty; retain its position for older clients.
--   P|2|paladin|slot|key|revision|author       one paladin plan cell
--   R|2                                        request everyone's state
local _, ns = ...
local Protocol = { PREFIX = "BUFFETERIA", VERSION = "2" }
ns.Protocol = Protocol

function Protocol.Encode(kind, ...)
	return table.concat({ kind, Protocol.VERSION, ... }, "|")
end

-- kind, version, fields...
function Protocol.Decode(msg) return strsplit("|", msg) end

-- Queued messages with the same key supersede each other: one state, one per plan cell.
function Protocol.QueueKey(msg)
	local kind, _, paladin, slot = Protocol.Decode(msg)
	return kind == "P" and table.concat({ kind, paladin, slot }, "|") or kind
end

-- Sorted keys of a set's true entries, comma separated.
function Protocol.SetString(set)
	local out = {}
	for k, v in pairs(set or {}) do if v then out[#out + 1] = k end end
	table.sort(out)
	return table.concat(out, ",")
end

function Protocol.List(str)
	local out = {}
	for k in (str or ""):gmatch("[^,]+") do out[#out + 1] = k end
	return out
end

function Protocol.Set(str)
	local out = {}
	for _, k in ipairs(Protocol.List(str)) do out[k] = true end
	return out
end
