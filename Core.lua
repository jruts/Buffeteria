-- Buffeteria: core (saved data, roster, solving, slash commands).
local ADDON, ns = ...
local D, S = ns.Data, ns.Solver

local Core = CreateFrame("Frame")
ns.Core = Core
ns.result = { pally = {}, home = {}, overrides = {}, groups = {}, expected = {} }
ns.roster = { members = {}, units = {} }
ns.peers = {} -- [fullName] = { wants, ranking, excluded, caps, time }

ns.COLOR = { ok = { 0.25, 0.85, 0.35 }, warn = { 1.0, 0.6, 0.1 }, bad = { 0.95, 0.2, 0.2 }, idle = { 0.5, 0.5, 0.5 } }

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuffeteria|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Small API helpers (work on Mainline and Classic-style clients)
------------------------------------------------------------------------
function ns.SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

function ns.SpellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
	return GetSpellTexture and GetSpellTexture(id) or nil
end

local function isKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
		local ok, r = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id)
		if ok and r then return true end
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, r = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and r then return true end
	end
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	if IsSpellKnown and IsSpellKnown(id) then return true end
	return false
end

function ns.KnowsAny(ids)
	for i = #ids, 1, -1 do if isKnown(ids[i]) then return true, ids[i] end end
	return false
end

function ns.ItemCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
	return GetItemCount and GetItemCount(id) or 0
end

function ns.FullName(unit)
	local name, realm = UnitFullName(unit)
	if not name then return nil end
	if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() or "" end
	if realm == "" then return name end
	return name .. "-" .. realm
end

function ns.Short(full) return (full and full:match("^[^-]+")) or full or "?" end

function ns.ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

function ns.ClassColorName(full, class)
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
	local short = ns.Short(full)
	if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(short) end
	return short
end

------------------------------------------------------------------------
-- Saved settings
------------------------------------------------------------------------
local function initDB()
	BuffeteriaCharDB = BuffeteriaCharDB or {}
	local db = BuffeteriaCharDB
	local _, class = UnitClass("player")
	db.order = D.NormalizeOrder(db.order or D.DEFAULT_ORDER[class], class)
	-- Preserve deliberate rankings from before the explicit override toggle existed.
	if db.blessingsOverride == nil then
		db.blessingsOverride = table.concat(db.order, ",") ~= table.concat(D.DEFAULT_ORDER[class] or D.DEFAULT_ORDER.WARRIOR, ",")
	end
	db.paladinBlessings = db.paladinBlessings or {}
	if not db.wants then db.wants = D.DefaultWants(class) end
	db.warnMinutes = db.warnMinutes or 5
	if db.showTracker == nil then db.showTracker = true end
	db.locked = db.locked or false
	db.minimap = db.minimap or { angle = 200, hide = false }
	if db.onlyProblems == nil then db.onlyProblems = true end
	ns.db = db
end

-- My own preferences in the shape the solver wants.
function ns.MyPrefs()
	local ranking, excluded = D.SplitOrder(ns.db.order)
	return { wants = ns.db.wants, ranking = ranking, excluded = excluded, blessingsOverride = ns.db.blessingsOverride }
end

-- What I can cast: plain key = single version, "g"..key = group/Greater version.
function ns.MyCaps()
	local caps = {}
	for _, b in ipairs(D.GROUP_BUFFS) do
		if ns.KnowsAny(b.ids) then caps[b.key] = true end
		if ns.KnowsAny(b.groupIds) then caps["g" .. b.key] = true end
	end
	local _, class = UnitClass("player")
	if class == "PALADIN" then
		for _, b in ipairs(D.BLESSINGS) do
			if ns.KnowsAny(b.ids) then caps[b.key] = true end
			if ns.KnowsAny(b.groupIds) then caps["g" .. b.key] = true end
		end
	end
	return caps
end

------------------------------------------------------------------------
-- Roster
------------------------------------------------------------------------
local function eachGroupUnit(fn)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
			fn("raid" .. i, subgroup or 1, class, online, isDead)
		end
	else
		local _, pc = UnitClass("player")
		fn("player", 1, pc, true, UnitIsDeadOrGhost("player"))
		for i = 1, GetNumSubgroupMembers() do
			local u = "party" .. i
			local _, c = UnitClass(u)
			fn(u, 1, c, UnitIsConnected(u), UnitIsDeadOrGhost(u))
		end
	end
end

function ns.BuildRoster()
	local roster = { members = {}, units = {} }
	local me = ns.FullName("player")
	eachGroupUnit(function(unit, group, class, online, dead)
		local full = ns.FullName(unit)
		if not full or not class or not online then return end
		local m = { name = full, class = class, group = group, unit = unit, dead = dead }
		local peer = (full == me) and ns.MyPrefs() or ns.peers[full]
		if full == me then
			m.caps = ns.MyCaps(); m.hasAddon = true
		elseif peer and peer.caps then
			m.caps = peer.caps; m.hasAddon = true
		else
			m.caps = {}
			for k, v in pairs(D.ASSUMED_CAPS[class] or {}) do m.caps[k] = v end
		end
		if peer and peer.ranking then
			m.wants, m.ranking, m.excluded = peer.wants, peer.ranking, peer.excluded
			m.blessingsOverride = peer.blessingsOverride and true or false
		else
			local r, e = D.SplitOrder(D.DEFAULT_ORDER[class] or D.DEFAULT_ORDER.WARRIOR)
			m.wants, m.ranking, m.excluded = D.DefaultWants(class), r, e
		end
		if not m.blessingsOverride then
			m.ranking, m.excluded = D.SplitOrder(D.DEFAULT_ORDER[class] or D.DEFAULT_ORDER.WARRIOR)
		end
		roster.members[full] = m
		roster.units[full] = unit
	end)
	if ns.Paladins then
		ns.Paladins.Prune(roster)
		roster.paladinAssignments = ns.Paladins.Assignments(roster)
	end
	return roster
end

------------------------------------------------------------------------
-- Solving (debounced)
------------------------------------------------------------------------
local pending = false
function ns.Resolve()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		ns.roster = ns.BuildRoster()
		local ok, res = pcall(S.Solve, ns.roster)
		if ok then ns.result = res else ns.Print("solver error: " .. tostring(res)) end
		if ns.OnSolved then ns.OnSolved() end
	end)
end

-- Plain-text summary of the current assignments.
function ns.AssignmentLines(withColor)
	local lines, r = {}, ns.result
	local function nm(full)
		local m = ns.roster.members[full]
		return (withColor and m) and ns.ClassColorName(full, m.class) or ns.Short(full)
	end
	-- Paladins: blessing -> classes, per paladin.
	local perPal = {}
	for class, map in pairs(r.pally or {}) do
		for p, b in pairs(map) do
			perPal[p] = perPal[p] or {}
			perPal[p][b] = perPal[p][b] or {}
			table.insert(perPal[p][b], ns.ClassName(class))
		end
	end
	local pals = {}
	for p in pairs(perPal) do pals[#pals + 1] = p end
	table.sort(pals)
	for _, p in ipairs(pals) do
		local parts = {}
		local bs = {}
		for b in pairs(perPal[p]) do bs[#bs + 1] = b end
		table.sort(bs)
		for _, b in ipairs(bs) do
			table.sort(perPal[p][b])
			parts[#parts + 1] = D.byKey[b].label .. " (" .. table.concat(perPal[p][b], ", ") .. ")"
		end
		lines[#lines + 1] = nm(p) .. ": " .. table.concat(parts, "; ")
	end
	for member, map in pairs(r.overrides or {}) do
		for p, b in pairs(map) do
			lines[#lines + 1] = ("  %s -> %s: %s instead"):format(nm(p), nm(member), b and D.byKey[b].label or "nothing")
		end
	end
	for _, buff in ipairs(D.GROUP_BUFFS) do
		local g = r.groups and r.groups[buff.key]
		if g and next(g) then
			local byCaster = {}
			for grp, c in pairs(g) do byCaster[c] = byCaster[c] or {}; table.insert(byCaster[c], grp) end
			local parts = {}
			for c, grps in pairs(byCaster) do
				table.sort(grps)
				parts[#parts + 1] = nm(c) .. " (G" .. table.concat(grps, ",") .. ")"
			end
			table.sort(parts)
			lines[#lines + 1] = buff.label .. ": " .. table.concat(parts, ", ")
		end
	end
	if #lines == 0 then lines[1] = "Nothing to assign. Find a buffer!" end
	return lines
end

function ns.Announce()
	local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
	local lines = ns.AssignmentLines(false)
	for _, l in ipairs(lines) do
		if chan then pcall(SendChatMessage, "[Buffeteria] " .. l, chan) else ns.Print(l) end
	end
end

------------------------------------------------------------------------
-- Events + slash
------------------------------------------------------------------------
Core:RegisterEvent("ADDON_LOADED")
Core:RegisterEvent("PLAYER_LOGIN")
Core:RegisterEvent("GROUP_ROSTER_UPDATE")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("SPELLS_CHANGED")
Core:RegisterEvent("PLAYER_REGEN_ENABLED")
Core:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		initDB()
	elseif event == "PLAYER_LOGIN" then
		if ns.Paladins then ns.Paladins.Init() end
		if ns.Comm then ns.Comm.Init() end
		if ns.Tracker then ns.Tracker.Init() end
		if ns.Minimap then ns.Minimap.Init() end
		if ns.Prefs then ns.Prefs.RegisterSettings() end
		ns.Resolve()
		ns.Print("open for business. /buff to pick your buffs.")
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		if ns.Comm then ns.Comm.Announce() end
		ns.Resolve()
	elseif event == "SPELLS_CHANGED" then
		if ns.Comm then ns.Comm.Announce() end
		ns.Resolve()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.Comm then ns.Comm.Flush() end
		if ns.Tracker then ns.Tracker.Refresh() end
	end
end)

-- Called by the prefs window whenever my preferences change.
function ns.PrefsChanged()
	if ns.Comm then ns.Comm.Announce(true) end
	ns.Resolve()
end

SLASH_BUFFETERIA1 = "/buffeteria"
SLASH_BUFFETERIA2 = "/buff"
SlashCmdList.BUFFETERIA = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "announce" then ns.Announce()
	elseif msg == "show" then ns.db.showTracker = true; ns.Tracker.Refresh()
	elseif msg == "hide" then ns.db.showTracker = false; ns.Tracker.Refresh()
	elseif msg == "lock" then ns.db.locked = not ns.db.locked; ns.Print(ns.db.locked and "tracker locked" or "tracker unlocked")
	elseif msg == "who" then
		for _, l in ipairs(ns.AssignmentLines(true)) do ns.Print(l) end
	elseif msg == "reset" then
		local _, class = UnitClass("player")
		ns.db.order = D.NormalizeOrder(D.DEFAULT_ORDER[class], class)
		ns.db.wants = D.DefaultWants(class)
		ns.db.blessingsOverride = false
		ns.PrefsChanged(); if ns.Prefs then ns.Prefs.Refresh() end
		ns.Print("preferences reset to class defaults")
	elseif msg == "config" or msg == "settings" then
		ns.Prefs.OpenSettings()
	elseif msg == "preview" or msg == "test" then
		ns.Preview.Toggle()
	elseif msg == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide; ns.Minimap.Refresh()
	elseif msg == "help" then
		ns.Print("/buff (options), /buff settings, /buff who, /buff announce, /buff show|hide, /buff lock, /buff minimap, /buff preview, /buff reset")
	else
		ns.Prefs.Toggle()
	end
end

-- Key binding labels
BINDING_HEADER_BUFFETERIA = "Buffeteria"
_G["BINDING_NAME_CLICK Buffeteria_CastButton:LeftButton"] = "Cast next buff"

-- Addon compartment (the puzzle-piece menu by the minimap)
function Buffeteria_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then ns.Prefs.OpenSettings() else ns.Prefs.Toggle() end
end
