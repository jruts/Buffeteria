-- Buffeteria: addon message transport. Features share their state on
-- "BroadcastRequested" and handle "Received:<kind>" (sender, fields...);
-- every client computes the assignments itself.
local _, ns = ...
local Comm = {}
ns.Comm = Comm

local Protocol = ns.Protocol
local PREFIX, VERSION = Protocol.PREFIX, Protocol.VERSION
local queued = {}           -- keep every class edit through lockdown/throttle
local lastSent, lastReq = 0, 0
local announcePending, replyPending = false, false
local sendWarned, versionWarned = false, false

local function channel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function send(msg)
	local chan = channel()
	if not chan then return true end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chan)
	-- A message the client rejects outright would never send; drop it so it
	-- cannot hold back every later edit in the queue.
	if not ok then
		if not sendWarned then sendWarned = true; ns.WoW.Print("could not send an addon message: " .. tostring(res)) end
		return true
	end
	-- Older clients return a bool, Mainline returns Enum.SendAddonMessageResult (0 = Success).
	return res == nil or res == true or res == 0
end

function Comm.Send(msg)
	if not channel() then return end
	if #queued == 0 and send(msg) then return end
	local key = Protocol.QueueKey(msg)
	for i, old in ipairs(queued) do
		if Protocol.QueueKey(old) == key then queued[i] = msg; return end
	end
	queued[#queued + 1] = msg
end

local function broadcast() ns.Events.Emit("BroadcastRequested") end

-- Broadcast my state. force = skip the anti-spam window (e.g. after a prefs change).
-- Calls inside the window collapse into one broadcast when it ends.
function Comm.Announce(force)
	if not channel() then return end
	local now = GetTime()
	if not force and now - lastSent < 2 then
		if not announcePending then
			announcePending = true
			C_Timer.After(2, function() announcePending = false; Comm.Announce(true) end)
		end
		return
	end
	lastSent = now
	broadcast()
	if now - lastReq > 10 then lastReq = now; Comm.Send(Protocol.Encode("R")) end
end

function Comm.Flush()
	if not channel() then queued = {}; return end
	while queued[1] do
		if not send(queued[1]) then return end
		table.remove(queued, 1)
	end
end

local function dispatch(sender, kind, ver, ...)
	if ver ~= VERSION then
		if not versionWarned then
			versionWarned = true
			ns.WoW.Print(ns.WoW.Short(sender) .. " runs a different Buffeteria version. Assignments may disagree.")
		end
		return
	end
	if kind == "R" then
		-- Everyone answers a state request, spread out to avoid a burst, and asks
		-- back (at most every 10 seconds): a client that just logged in may hold
		-- state it does not share on its own.
		if replyPending then return end
		replyPending = true
		C_Timer.After(0.5 + math.random() * 2, function() replyPending = false; Comm.Announce(true) end)
	else
		ns.Events.Emit("Received:" .. tostring(kind), sender, ...)
	end
end

function Comm.OnMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX or not msg then return end
	local full = ns.WoW.NormalizeName(sender)
	if not full or full == ns.WoW.Me() then return end
	dispatch(full, Protocol.Decode(msg))
end

function Comm.Init()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	local f = CreateFrame("Frame")
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:SetScript("OnEvent", function(_, _, ...) Comm.OnMessage(...) end)
	-- Retry anything that got held back (lockdown in instances/combat, throttles).
	C_Timer.NewTicker(5, function() if not InCombatLockdown() then Comm.Flush() end end)
	Comm.Announce(true)
end
