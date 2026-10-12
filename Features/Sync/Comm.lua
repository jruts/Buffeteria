-- Buffeteria: addon messages. Preferences, capabilities and class plans travel;
-- every client computes the assignments itself.
local _, ns = ...
local Comm = {}
ns.Comm = Comm

local PREFIX, VERSION = ns.Protocol.PREFIX, ns.Protocol.VERSION
local queued = {}           -- keep every class edit through lockdown/throttle
local lastSent, lastReq = 0, 0

local function channel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function keyList(set)
	local out = {}
	for k, v in pairs(set or {}) do if v then out[#out + 1] = k end end
	table.sort(out)
	return table.concat(out, ",")
end

local function toSet(str)
	local s = {}
	for k in (str or ""):gmatch("[^,]+") do s[k] = true end
	return s
end

local function toList(str)
	local l = {}
	for k in (str or ""):gmatch("[^,]+") do l[#l + 1] = k end
	return l
end

-- S|version|wants|ranking|excluded|caps|explicitBlessings
local function stateMessage()
	local p = ns.Preferences.Get()
	return table.concat({ "S", VERSION, keyList(p.wants), table.concat(p.ranking, ","), keyList(p.excluded), keyList(ns.Roster.Capabilities()), p.blessingsOverride and "1" or "0" }, "|")
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
	if res == nil or res == true or res == 0 then return true end
	return false
end

function Comm.Send(msg)
	if not channel() then return end
	if #queued == 0 and send(msg) then return end
	local kind, _, paladin, class = strsplit("|", msg)
	for i, old in ipairs(queued) do
		local oldKind, _, oldPaladin, oldClass = strsplit("|", old)
		if kind == oldKind and (kind ~= "P" or (paladin == oldPaladin and class == oldClass)) then
			queued[i] = msg; return
		end
	end
	queued[#queued + 1] = msg
end

local function broadcastState()
	Comm.Send(stateMessage())
	ns.Paladins.Broadcast(ns.Roster.Build())
end

-- Broadcast my state. force = skip the anti-spam window (e.g. after a prefs change).
function Comm.Announce(force)
	if not channel() then return end
	local now = GetTime()
	if not force and now - lastSent < 2 then
		C_Timer.After(2, function() Comm.Announce(true) end)
		return
	end
	lastSent = now
	broadcastState()
	if now - lastReq > 10 then lastReq = now; Comm.Send("R|" .. VERSION) end
end

function Comm.Flush()
	if not channel() then queued = {}; return end
	while queued[1] do
		if not send(queued[1]) then return end
		table.remove(queued, 1)
	end
end

local replyPending = false
local function onMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX or not msg then return end
	local full = ns.WoW.NormalizeName(sender)
	if not full or full == ns.WoW.FullName("player") then return end

	local kind, ver, a, b, c, d, e = strsplit("|", msg)
	if kind == "S" then
		if ver ~= VERSION then
			if not Comm.warned then Comm.warned = true; ns.WoW.Print(ns.WoW.Short(full) .. " runs a different Buffeteria version. Assignments may disagree.") end
			return
		end
		-- Keep state even if the sender isn't in our roster yet (they just joined or
		-- haven't loaded); Roster.Build only uses peers who are in the group.
		ns.Roster.peers[full] = { wants = toSet(a), ranking = toList(b), excluded = toSet(c), caps = toSet(d), blessingsOverride = e == "1" }
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

Comm.OnMessage = onMessage

function Comm.Init()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	local f = CreateFrame("Frame")
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:SetScript("OnEvent", function(_, _, ...) onMessage(...) end)
	-- Retry anything that got held back (lockdown in instances/combat, throttles).
	C_Timer.NewTicker(5, function() if not InCombatLockdown() then Comm.Flush() end end)
	Comm.Announce(true)
end
