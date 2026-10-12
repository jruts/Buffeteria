-- Internal feature notifications; subscriptions last for the add-on session.
local _, ns = ...
local listeners = {}
ns.Events = {}

function ns.Events.On(event, callback)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], callback)
end

-- Extra arguments are passed to every listener.
function ns.Events.Emit(event, ...)
	for _, callback in ipairs(listeners[event] or {}) do callback(...) end
end
