-- Select a cast from assignments and observed aura status.
local _, ns = ...
local Buffs, EMPTY = ns.Buffs, ns.Util.EMPTY
local Actions = {}
ns.Tracker.Actions = Actions
local pendingUntil = {} -- ["name:key"] = expiry; wait for a cast's aura to arrive
-- Covering for another caster of my class: wait this long after a buff goes
-- missing (no wait when its caster is dead or out of sight), plus a turn for
-- each helper ahead of me, so two helpers don't cast the same buff at once.
local HELP_GRACE, HELP_STAGGER = 30, 10

-- Highest known rank -> castable spell name, icon and ID.
local function spellFor(ids)
	local ok, id = ns.WoW.KnowsAny(ids)
	if not ok then return nil end
	return ns.WoW.SpellName(id), ns.WoW.SpellIcon(id), id
end

-- A cast landed: everyone it covers stops counting as needy until the auras arrive.
function Actions.MarkCast(cast)
	if cast.resurrect then return ns.Extra.Resurrect.Offered(cast.who) end
	local untilTime = GetTime() + 3
	for _, full in ipairs(cast.covers or { cast.who }) do pendingUntil[full .. ":" .. cast.key] = untilTime end
end

-- One search for my next cast: the inputs, and the candidates found so far.
-- While ctx.helping, the search serves other casters' recipients instead of mine.
local function newSearch(now, warnPercent)
	local ctx = { now = now, warnPercent = warnPercent, me = ns.WoW.Me(), cands = {},
		roster = ns.Assignments.roster, res = ns.Assignments.result }

	function ctx.casting(full, key) return (pendingUntil[full .. ":" .. key] or 0) > now end
	-- "bad" or "warn" when the member needs the buff and no cast of it is on the way.
	function ctx.needs(full, key)
		if ctx.casting(full, key) then return nil end
		local st = ns.Tracker.Scan.Rate(full, key, now, warnPercent)
		if st == "bad" or st == "warn" then return st end
	end
	function ctx.caster(full, key) return (ctx.res.expected[full] or EMPTY)[key] end

	-- My place in line among the other living casters of `key` able to cover for `caster`.
	local ranks = {}
	local function helperRank(key, caster)
		local id = key .. ":" .. caster
		if not ranks[id] then
			local rank = 0
			for full, m in pairs(ctx.roster.members) do
				if full < ctx.me and full ~= caster and not m.dead and Buffs.CanCast(m.caps, key) then rank = rank + 1 end
			end
			ranks[id] = rank
		end
		return ranks[id]
	end
	-- Someone else's recipient I should cover now: missing long enough, or at
	-- once when the assigned caster is dead or out of sight.
	local function helpable(full, key)
		local caster = ctx.caster(full, key)
		if not caster or caster == ctx.me or ns.Tracker.Scan.Rate(full, key, now, warnPercent) ~= "bad" then return false end
		local unit = ctx.roster.units[caster]
		local away = not unit or UnitIsDeadOrGhost(unit) or not UnitIsVisible(unit)
		local wait = (away and 0 or HELP_GRACE) + helperRank(key, caster) * HELP_STAGGER
		return ns.Tracker.Scan.MissingFor(full, key, now) >= wait
	end
	-- Whether this search serves the member: mine, or helpable while helping.
	function ctx.serves(full, key)
		if ctx.helping then return helpable(full, key) end
		return ctx.caster(full, key) == ctx.me
	end

	function ctx.add(buff, spell, icon, id, unit, who, status, big, label, covers)
		local cast = { spell = spell, icon = icon, spellID = id, unit = unit, who = who, key = buff.key,
			status = status, big = big, label = label or ns.WoW.Short(who), covers = covers or { who },
			helping = ctx.helping and ctx.caster(who, buff.key) or nil }
		ctx.cands[#ctx.cands + 1] = cast
		return cast
	end
	-- Living recipients of a buff that match and that this search is about, the
	-- needy ones I serve sorted, and the worst status.
	function ctx.recipients(key, match)
		local needy, worst, count = {}, "warn", 0
		for full, m in pairs(ctx.roster.members) do
			local caster = ctx.caster(full, key)
			if not m.dead and (not match or match(m)) and caster and (ctx.helping or caster == ctx.me) then
				count = count + 1
				local st = ctx.serves(full, key) and ctx.needs(full, key)
				if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
			end
		end
		table.sort(needy)
		return needy, worst, count
	end
	-- One cast covering the needy: the group version (labelled `label`) when big,
	-- else the single version, on the first needy player in range.
	function ctx.addCover(buff, needy, worst, big, label)
		local spell, icon, id = spellFor(big and buff.groupIds or buff.ids)
		if not spell then return end
		for _, full in ipairs(needy) do
			local unit = ctx.roster.units[full]
			if unit and ns.WoW.SpellInRange(spell, unit) then
				return ctx.add(buff, spell, icon, id, unit, full, worst, big, big and label or nil, big and needy or nil)
			end
		end
	end
	function ctx.addSingle(buff, full, status, onSelf)
		local spell, icon, id = spellFor(buff.ids)
		local unit = onSelf and "player" or ctx.roster.units[full]
		if spell and unit and (onSelf or ns.WoW.SpellInRange(spell, unit)) then
			-- Imbues apply to the main-hand weapon through the spell's default targeting.
			ctx.add(buff, spell, icon, id, buff.kind ~= "imbue" and unit or nil, full, status, false)
		end
	end
	return ctx
end

-- Prayer, Gift and Brilliance are centered on the caster, up to 100 yards.
local function raidGroupCast(ctx, buff, needy, wanters)
	local id = Buffs.CastableGroupRank(buff)
	local spell = id and ns.WoW.SpellName(id)
	if not spell then return end
	local covers, worst = {}, "warn"
	for _, full in ipairs(needy) do
		local unit = ctx.roster.units[full]
		local within = unit and ns.WoW.WithinRadius(unit, 100)
		if within == true or (within == nil and unit and UnitIsVisible(unit)) then
			covers[#covers + 1] = full
			if ctx.needs(full, buff.key) == "bad" then worst = "bad" end
		end
	end
	if #covers == 0 or (#covers < math.max(2, math.min(3, wanters)) and ns.WoW.KnowsAny(buff.ids)) then return end
	local label = ctx.roster.isRaid and "Raid" or "Group"
	ctx.add(buff, spell, ns.WoW.SpellIcon(id), id, "player", covers[1], worst, true, label, covers)
	return true
end

-- A raid-wide cast serves everyone reachable across subgroups. Use singles for
-- a few recipients or when the raid version cannot cover them.
local function groupBuffs(ctx)
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		local needy, worst, wanters = ctx.recipients(buff.key)
		if #needy > 0 and not raidGroupCast(ctx, buff, needy, wanters) then
			ctx.addCover(buff, needy, worst, false)
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
				local big = Buffs.CastableGroupRank(buff) ~= nil
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

-- An opted-in warrior separated from the assigned caster can keep their own
-- shout up. Everyone nearby will still benefit from that cast.
local function shoutBackup(me, caster)
	if not caster or caster == me then return false end
	local roster = ns.Assignments.roster
	local member, unit = roster.members[me], roster.units[caster]
	return member and member.class == "WARRIOR" and (member.wants or EMPTY).BSHOUT and unit
		and (not UnitIsVisible(unit) or ns.WoW.WithinRadius(unit, Buffs.byKey.BSHOUT.raidRadius) == false)
end

-- Battle Shout is cast on the warrior and covers needy allies across subgroups.
local function battleShout(ctx)
	local buff, me = Buffs.byKey.BSHOUT, ctx.me
	local caster = ctx.caster(me, buff.key)
	if not caster or UnitIsDeadOrGhost("player") then return end
	local needy, worst
	if caster == me then
		needy, worst = ctx.recipients(buff.key)
		if #needy == 0 then return end
	elseif shoutBackup(me, caster) and not ctx.casting(me, buff.key) then
		worst = ns.Tracker.Scan.Rate(me, buff.key, ctx.now, ctx.warnPercent, true)
		if worst ~= "bad" and worst ~= "warn" then return end
		needy = { me }
	else
		return
	end
	local spell, icon, id = spellFor(buff.ids)
	if spell and ns.WoW.SpellUsable(spell) then
		local label = ctx.roster.isRaid and "Raid" or "Group"
		local cast = ctx.add(buff, spell, icon, id, "player", me, worst, #needy > 1, label, needy)
		if caster ~= me then cast.helping = caster end
	end
end

-- Tank and self buffs: always singles, once I have the power to cast them.
local function usable(buff)
	local spell = spellFor(buff.ids)
	if spell and buff.cooldown then
		local start, duration = ns.WoW.SpellCooldown(spell)
		if start and duration > 1.5 and start + duration > GetTime() then return false end
	end
	return spell and ns.WoW.SpellUsable(spell)
end

local function singleBuffs(ctx, combatOnly)
	for _, buff in ipairs(Buffs.SINGLE_BUFFS) do
		for full, m in pairs(combatOnly and not buff.combat and EMPTY or ctx.roster.members) do
			if not m.dead and ctx.serves(full, buff.key) and (not buff.selfOnly or full == ctx.me) then
				local st = ctx.needs(full, buff.key)
				if st and usable(buff) then ctx.addSingle(buff, full, st, buff.selfOnly) end
			end
		end
	end
end

-- Raid support is cast at the provider. Missing distant recipients can show
-- in the scan, but won't repeatedly refresh a running aura or deployed totem.
local function raidSupport(ctx)
	local me = ctx.me
	local member = ctx.roster.members[me]
	if not member or member.dead or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return end
	for _, buff in ipairs(Buffs.RAID_SUPPORT) do
		if not buff.passive and ctx.caster(me, buff.key) == me then
			local status = ctx.needs(me, buff.key)
			if status and buff.totemSlot then
				local slot = ns.Tracker.Scan.TotemRate(buff, ctx.now, ctx.warnPercent)
				if slot ~= "bad" and slot ~= "warn" then status = nil end
			end
			if status then
				local spell, icon, id = spellFor(buff.ids)
				if spell and ns.WoW.SpellUsable(spell) then
					local needy, worst = ctx.recipients(buff.key)
					local label = ctx.roster.isRaid and "Raid" or "Group"
					ctx.add(buff, spell, icon, id, not buff.totemSlot and "player" or nil, me, worst, #needy > 1, label, needy)
				end
			end
		end
	end
end

-- My assigned aura: a self-cast toggle, so it never needs a target.
local function aura(ctx, missingAura)
	if not missingAura or ctx.casting(ctx.me, missingAura) then return end
	local buff = Buffs.byKey[missingAura]
	local spell, icon, id = spellFor(buff.ids)
	if spell then ctx.add(buff, spell, icon, id, "player", ctx.me, "bad", true, "Aura") end
end

-- The combat self buff the cast button holds through combat, whatever its status:
-- secure attributes are locked once combat starts. Nil when I have none.
function Actions.CombatBuff()
	local me = ns.WoW.Me()
	for _, buff in ipairs(Buffs.SELF_BUFFS) do
		local caster = (ns.Assignments.result.expected[me] or EMPTY)[buff.key]
		if buff.combat and (caster == me or (buff.raidRadius and shoutBackup(me, caster))) then
			local spell, icon, id = spellFor(buff.ids)
			if spell then return { spell = spell, icon = icon, spellID = id, unit = "player", who = me, key = buff.key } end
		end
	end
end

-- My next cast: { spell, spellID, unit, icon, label, who, key, status, big,
-- covers = everyone the cast serves, helping = the caster I cover for }.
-- missingAura is my assigned aura when it isn't running. In combat only
-- combat self buffs (Battle Shout, Inner Fire) are worth interrupting for.
-- With help and nothing of my own to cast, I cover group buffs and Thorns for
-- another caster (never blessings: a paladin's new blessing replaces their last).
-- With resurrect, a dead group member comes before any buff.
function Actions.Next(now, warnPercent, missingAura, combat, help, resurrect)
	local ctx = newSearch(now, warnPercent)
	if resurrect and not combat then
		local rez = ns.Extra.Resurrect.Next(ctx.roster, now)
		if rez then return rez end
	end
	battleShout(ctx)
	if combat then
		singleBuffs(ctx, true)
	else
		groupBuffs(ctx)
		blessings(ctx)
		singleBuffs(ctx)
		raidSupport(ctx)
		aura(ctx, missingAura)
		if #ctx.cands == 0 and help then
			ctx.helping = true
			groupBuffs(ctx)
			singleBuffs(ctx)
		end
	end
	table.sort(ctx.cands, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.big ~= b.big then return a.big end
		if a.key ~= b.key then return a.key < b.key end
		return a.who < b.who
	end)
	return ctx.cands[1]
end
