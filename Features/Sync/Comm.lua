-- Buffeteria: addon messages. Preferences, capabilities and class plans travel;
-- every client computes the assignments itself.
local _, ns = ...
local Comm = {}
ns.Comm = Comm

local Protocol = ns.Protocol
local PREFIX, VERSION = Protocol.PREFIX, Protocol.VERSION
local queued = {}           -- keep every class edit through lockdown/throttle
local lastSent, lastReq = 0, 0
local announcePending, replyPending = false, false

local function channel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function stateMessage()
	local p = ns.Preferences.Get()
	return Protocol.Encode("S", Protocol.SetString(p.wants), table.concat(p.ranking, ","),
		Protocol.SetString(p.excluded), Protocol.SetString(ns.Roster.Capabilities()), p.blessingsOverride and "1" or "0")
end

local function send(msg)
	local chan = channel()
	if not chan then return true end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chan)
	-- A message the client rejects outright would never send; drop it so it
	-- cannot hold back every later edit in the queue.
	if not ok then
		if not Comm.sendWarned then Comm.sendWarned = true; ns.WoW.Print("could not send an addon message: " .. tostring(res)) end
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

local function broadcastState()
	Comm.Send(stateMessage())
	ns.Paladins.Broadcast()
end

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
	broadcastState()
	if now - lastReq > 10 then lastReq = now; Comm.Send(Protocol.Encode("R")) end
end

function Comm.Flush()
	if not channel() then queued = {}; return end
	while queued[1] do
		if not send(queued[1]) then return end
		table.remove(queued, 1)
	end
end

function Comm.OnMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX or not msg then return end
	local full = ns.WoW.NormalizeName(sender)
	if not full or full == ns.WoW.Me() then return end

	local kind, ver, a, b, c, d, e = Protocol.Decode(msg)
	if kind == "S" then
		if ver ~= VERSION then
			if not Comm.warned then Comm.warned = true; ns.WoW.Print(ns.WoW.Short(full) .. " runs a different Buffeteria version. Assignments may disagree.") end
			return
		end
		-- Keep state even if the sender isn't in our roster yet (they just joined or
		-- haven't loaded); Roster.Build only uses peers who are in the group.
		ns.Roster.peers[full] = { wants = Protocol.Set(a), ranking = Protocol.List(b), excluded = Protocol.Set(c),
			caps = Protocol.Set(d), blessingsOverride = e == "1" }
		ns.Assignments.Resolve()
	elseif kind == "P" and ver == VERSION then
		ns.Paladins.Receive(full, a, b, c, d, e)
	elseif kind == "R" and ver == VERSION and not replyPending then
		replyPending = true
		C_Timer.After(0.5 + math.random() * 2, function()
			replyPending = false
			broadcastState()
		end)
	end
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
