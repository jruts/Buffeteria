-- Tooltips for the head and the small buff icons.
local _, ns = ...
local Buffs, Status = ns.Buffs, ns.Tracker.Status
local Tooltip = {}
ns.Tracker.Tooltip = Tooltip
local MAX_PROBLEMS = 20
local GREY, BLUE = { 0.7, 0.7, 0.7 }, { 0.4, 0.8, 1 }

local function fmtTime(sec)
	if not sec then return "" end
	return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function label(key) return Buffs.byKey[key].label end

-- What the head's click does, then what I'm waiting for.
local function addTurn(s)
	if s and s.next then
		GameTooltip:AddLine(("Your turn! Click to cast %s on %s."):format(s.next.spell, s.next.label), BLUE[1], BLUE[2], BLUE[3], true)
		if s.next.helping then
			GameTooltip:AddLine("Covering for " .. ns.Roster.Name(s.next.helping) .. ".", BLUE[1], BLUE[2], BLUE[3], true)
		end
	elseif Status.MineDone(s) then
		GameTooltip:AddLine("Your part is done: everyone you buff is served.", unpack(Status.COLORS.ok))
	else
		GameTooltip:AddLine("Nothing for you to cast right now.", unpack(GREY))
	end
	local pending = s and s.mine and s.mine.pending or 0
	if s and s.next and pending > 0 then
		GameTooltip:AddLine(("%d of your buffs still to serve."):format(pending), GREY[1], GREY[2], GREY[3], true)
	end
	if not (s and s.needs and #s.needs > 0) then return end
	GameTooltip:AddLine("You're waiting for:", unpack(Status.COLORS.warn))
	local me = ns.WoW.Me()
	for _, need in ipairs(s.needs) do
		local from = (need.caster == me and "you") or (need.caster and ns.Roster.Name(need.caster)) or "nobody assigned"
		GameTooltip:AddDoubleLine("  " .. label(need.key), "from " .. from, 1, 1, 1, 1, 1, 1)
	end
end

local function addProblems(s)
	if not s or not s.any then return GameTooltip:AddLine("Nothing on the menu yet.", unpack(GREY)) end
	if #s.problems == 0 then
		local mood = Status.Mood(s)
		if mood == "happy" then
			GameTooltip:AddLine(#(s.unreadable or {}) > 0 and "Everyone in range has their buffs."
				or "Everyone is stuffed. All buffs up.", unpack(Status.COLORS.ok))
		elseif mood == "idle" then
			GameTooltip:AddLine("Nobody's buffs can be checked right now.", unpack(GREY))
		else
			GameTooltip:AddLine("Waiting for readable buff information.", unpack(Status.COLORS.warn))
		end
		return
	end
	for i, p in ipairs(s.problems) do
		if i > MAX_PROBLEMS then
			GameTooltip:AddLine(("...and %d more"):format(#s.problems - MAX_PROBLEMS), unpack(GREY))
			break
		end
		local text = (p.status == "bad" and label(p.key) .. " missing")
			or (p.status == "warn" and label(p.key) .. " " .. fmtTime(p.rem))
			or ("doesn't want " .. label(p.key))
		local color = p.status == "bad" and Status.COLORS.bad or Status.COLORS.warn
		GameTooltip:AddDoubleLine(ns.Roster.Name(p.who, p.class), text, 1, 1, 1, unpack(color))
	end
end

function Tooltip.Head(owner, s)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:AddLine(ns.title .. (ns.Tracker.Preview.active and " |cffff9900(preview)|r" or ""))
	addTurn(s)
	GameTooltip:AddLine(" ")
	addProblems(s)
	if s and s.unreadable and #s.unreadable > 0 then
		GameTooltip:AddLine(" ")
		for _, full in ipairs(s.unreadable) do
			GameTooltip:AddDoubleLine(ns.Roster.Name(full), "out of range", 1, 1, 1, 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Move: Edit Mode, or unlock and drag", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function Tooltip.Icon(owner, key, s)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(label(key))
	local pk = s and s.perKey[key]
	if pk then
		if pk.bad > 0 then GameTooltip:AddLine(pk.bad .. " missing", unpack(Status.COLORS.bad)) end
		if pk.warn > 0 then GameTooltip:AddLine(pk.warn .. " running low", unpack(Status.COLORS.warn)) end
		if pk.bad + pk.warn == 0 then GameTooltip:AddLine("everyone has it", unpack(Status.COLORS.ok)) end
		if s.yours and s.yours[key] then
			GameTooltip:AddLine("Your job: click the head to cast it.", unpack(BLUE))
		elseif pk.casters and next(pk.casters) then
			local names = {}
			for caster in pairs(pk.casters) do names[#names + 1] = ns.WoW.Short(caster) end
			table.sort(names)
			GameTooltip:AddLine("Cast by " .. table.concat(names, ", "), GREY[1], GREY[2], GREY[3], true)
		end
	end
	GameTooltip:Show()
end
