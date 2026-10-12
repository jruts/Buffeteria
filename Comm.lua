-- Buffeteria: addon messages. Only preferences and capabilities travel;
-- every client computes the assignments itself.
local _, ns = ...
local D = ns.Data

local Comm = {}
ns.Comm = Comm

local PREFIX = "BUFFETERIA"
local VERSION = "1"
local queued = nil          -- a message held back by lockdown/throttle
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

-- S|version|wants|ranking|excluded|caps
local function stateMessage()
	local p = ns.MyPrefs()
	return table.concat({ "S", VERSION, keyList(p.wants), table.concat(p.ranking, ","), keyList(p.excluded), keyList(ns.MyCaps()) }, "|")
end

local function send(msg)
	local chan = channel()
	if not chan then return true end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chan)
	-- Older clients return a bool, Mainline returns Enum.SendAddonMessageResult (0 = Success).
	if ok and (res == nil or res == true or res == 0) then return true end
	queued = msg
	return false
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
	send(stateMessage())
	if now - lastReq > 10 then lastReq = now; send("R|" .. VERSION) end
end

function Comm.Flush()
	if queued then
		local m = queued; queued = nil
		send(m)
	end
end

local replyPending = false
local function onMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX or not msg then return end
	local full = sender
	if full and not full:find("-") then
		full = full .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or "")
	end
	if full == ns.FullName("player") then return end

	local kind, ver, a, b, c, d = strsplit("|", msg)
	if kind == "S" then
		if ver ~= VERSION then
			if not Comm.warned then Comm.warned = true; ns.Print(ns.Short(full) .. " runs a different Buffeteria version. Assignments may disagree.") end
			return
		end
		ns.peers[full] = { wants = toSet(a), ranking = toList(b), excluded = toSet(c), caps = toSet(d), time = GetTime() }
		ns.Resolve()
	elseif kind == "R" and not replyPending then
		replyPending = true
		C_Timer.After(0.5 + math.random() * 2, function()
			replyPending = false
			send(stateMessage())
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
