-- Select a cast from assignments and observed aura status.
local _, ns = ...
local Buffs, EMPTY = ns.Buffs, ns.Util.EMPTY
local Actions = {}
ns.Tracker.Actions = Actions
local pendingUntil = {} -- ["name:key"] = expiry; wait for a cast's aura to arrive

local function inRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
		return not (ok and r == false)
	end
	if IsSpellInRange then return IsSpellInRange(spell, unit) ~= 0 end
	return true
end

local function hasReagent(list)
	for _, id in ipairs(list or EMPTY) do if ns.WoW.ItemCount(id) > 0 then return true end end
	return false
end

-- Highest known rank -> castable spell name + icon.
local function spellFor(ids)
	local ok, id = ns.WoW.KnowsAny(ids)
	if not ok then return nil end
	return ns.WoW.SpellName(id), ns.WoW.SpellIcon(id)
end

local function groupVersion(buff) return ns.WoW.KnowsAny(buff.groupIds) and hasReagent(buff.reagents) end

function Actions.MarkCast(full, key)
	pendingUntil[full .. ":" .. key] = GetTime() + 3
end

-- One search for my next cast: the inputs, and the candidates found so far.
local function newSearch(now, warnSec)
	local ctx = { now = now, warnSec = warnSec, me = ns.WoW.Me(), cands = {},
		roster = ns.Assignments.roster, res = ns.Assignments.result }

	function ctx.casting(full, key) return (pendingUntil[full .. ":" .. key] or 0) > now end
	-- "bad" or "warn" when the member needs the buff and no cast of it is on the way.
	function ctx.needs(full, key)
		if ctx.casting(full, key) then return nil end
		local st = ns.Tracker.Scan.Rate(full, key, now, warnSec)
		if st == "bad" or st == "warn" then return st end
	end
	function ctx.mine(full, key) return (ctx.res.expected[full] or EMPTY)[key] == ctx.me end
	function ctx.add(buff, spell, icon, unit, who, status, big, label)
		ctx.cands[#ctx.cands + 1] = { spell = spell, icon = icon, unit = unit, who = who, key = buff.key,
			status = status, big = big, label = label or ns.WoW.Short(who) }
	end
	-- My living recipients of a buff that match, the needy ones sorted, and the worst status.
	function ctx.recipients(key, match)
		local needy, worst, count = {}, "warn", 0
		for full, m in pairs(ctx.roster.members) do
			if not m.dead and match(m) and ctx.mine(full, key) then
				count = count + 1
				local st = ctx.needs(full, key)
				if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
			end
		end
		table.sort(needy)
		return needy, worst, count
	end
	-- One cast covering the needy: the group version (labelled `label`) when big,
	-- else the single version, on the first needy player in range.
	function ctx.addCover(buff, needy, worst, big, label)
		local spell, icon = spellFor(big and buff.groupIds or buff.ids)
		if not spell then return end
		for _, full in ipairs(needy) do
			local unit = ctx.roster.units[full]
			if unit and inRange(spell, unit) then return ctx.add(buff, spell, icon, unit, full, worst, big, big and label or nil) end
		end
	end
	function ctx.addSingle(buff, full, status, onSelf)
		local spell, icon = spellFor(buff.ids)
		local unit = onSelf and "player" or ctx.roster.units[full]
		if spell and unit and (onSelf or inRange(spell, unit)) then ctx.add(buff, spell, icon, unit, full, status, false) end
	end
	return ctx
end

-- Group buffs (Fort, Spirit, Shadow Prot, Mark, Intellect), per raid group.
local function groupBuffs(ctx)
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		for g, caster in pairs(ctx.res.groups[buff.key] or EMPTY) do
			if caster == ctx.me then
				local needy, worst, wanters = ctx.recipients(buff.key, function(m) return m.group == g end)
				if #needy > 0 then
					local big = groupVersion(buff) and wanters >= 2 and #needy >= math.min(3, wanters)
					ctx.addCover(buff, needy, worst, big, "Group " .. g)
				end
			end
		end
	end
end

-- Blessings: Greater per class, unless it would overwrite someone's personal
-- assignment from me; then singles.
local function blessings(ctx)
	local roster, res, me = ctx.roster, ctx.res, ctx.me
	for class, map in pairs(res.pally) do
		local buff = map[me] and Buffs.byKey[map[me]]
		if buff then
			local needy, worst = ctx.recipients(buff.key, function(m) return m.class == class end)
			if #needy > 0 then
				local big = groupVersion(buff)
				for full, m in pairs(roster.members) do
					if big and m.class == class and not m.dead and (res.overrides[full] or EMPTY)[me] ~= nil then big = false end
				end
				ctx.addCover(buff, needy, worst, big, ns.WoW.ClassName(class))
			end
		end
	end
	for full, map in pairs(res.overrides) do
		local m = roster.members[full]
		if map[me] and m and not m.dead then
			local st = ctx.needs(full, map[me])
			if st then ctx.addSingle(Buffs.byKey[map[me]], full, st, false) end
		end
	end
end

-- Tank and self buffs: always singles, once I have the power to cast them.
-- Self-only ones (Righteous Fury, Battle Shout, Inner Fire) belong to the caster alone.
local function usable(buff)
	local spell = spellFor(buff.ids)
	return spell and ns.WoW.SpellUsable(spell)
end

local function singleBuffs(ctx, combatOnly)
	for _, buff in ipairs(Buffs.SINGLE_BUFFS) do
		for full, m in pairs(combatOnly and not buff.combat and EMPTY or ctx.roster.members) do
			if not m.dead and ctx.mine(full, buff.key) and (not buff.selfOnly or full == ctx.me) then
				local st = ctx.needs(full, buff.key)
				if st and usable(buff) then ctx.addSingle(buff, full, st, buff.selfOnly) end
			end
		end
	end
end

-- My assigned aura: a self-cast toggle, so it never needs a target.
local function aura(ctx, missingAura)
	if not missingAura or ctx.casting(ctx.me, missingAura) then return end
	local buff = Buffs.byKey[missingAura]
	local spell, icon = spellFor(buff.ids)
	if spell then ctx.add(buff, spell, icon, "player", ctx.me, "bad", true, "Aura") end
end

-- The combat self buff the cast button holds through combat, whatever its status:
-- secure attributes are locked once combat starts. Nil when I have none.
function Actions.CombatBuff()
	local me = ns.WoW.Me()
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		if buff.combat and (ns.Assignments.result.expected[me] or EMPTY)[buff.key] == me then
			local spell, icon = spellFor(buff.ids)
			if spell then return { spell = spell, icon = icon, unit = "player", who = me, key = buff.key } end
		end
	end
end

-- My next cast: { spell, unit, icon, label, who, key, status, big }.
-- missingAura is my assigned aura when it isn't running. In combat only
-- combat self buffs (Battle Shout, Inner Fire) are worth interrupting for.
function Actions.Next(now, warnSec, missingAura, combat)
	local ctx = newSearch(now, warnSec)
	if combat then
		singleBuffs(ctx, true)
	else
		groupBuffs(ctx)
		blessings(ctx)
		singleBuffs(ctx)
		aura(ctx, missingAura)
	end
	table.sort(ctx.cands, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.big ~= b.big then return a.big end
		if a.key ~= b.key then return a.key < b.key end
		return a.who < b.who
	end)
	return ctx.cands[1]
end
