-- Select a cast from assignments and observed aura status.
local _, ns = ...
local Buffs = ns.Buffs
local Actions = {}
ns.Actions = Actions
local pendingUntil = {} -- ["name:key"] = expiry; wait for a cast's aura to arrive

local function inRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
		if ok and r == false then return false end
		return true
	end
	if IsSpellInRange then return IsSpellInRange(spell, unit) ~= 0 end
	return true
end

local function hasReagent(list)
	for _, id in ipairs(list or {}) do if ns.WoW.ItemCount(id) > 0 then return true end end
	return false
end

-- Highest known rank -> castable spell name + icon.
local function spellFor(ids)
	local ok, id = ns.WoW.KnowsAny(ids)
	if not ok then return nil end
	return ns.WoW.SpellName(id), ns.WoW.SpellIcon(id)
end

function Actions.MarkCast(full, key)
	pendingUntil[full .. ":" .. key] = GetTime() + 3
end

-- My next cast: { spell, unit, icon, label, who, key, status }
function Actions.Next(now, warnSec)
	local me, roster, res = ns.WoW.FullName("player"), ns.roster, ns.result
	local cands = {}
	local function needs(full, key)
		if (pendingUntil[full .. ":" .. key] or 0) > now then return nil end
		local st = ns.Scan.Rate(full, key, now, warnSec)
		if st == "bad" or st == "warn" then return st end
	end
	local function add(c) cands[#cands + 1] = c end

	-- Group buffs (Fort, Spirit, Shadow Prot, Mark, Intellect)
	for _, buff in ipairs(Buffs.GROUP_BUFFS) do
		for g, caster in pairs((res.groups or {})[buff.key] or {}) do
			if caster == me then
				local needy, wanters, worst = {}, 0, "warn"
				for full, m in pairs(roster.members) do
					if m.group == g and not m.dead and (res.expected[full] or {})[buff.key] == me then
						wanters = wanters + 1
						local st = needs(full, buff.key)
						if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
					end
				end
				if #needy > 0 then
					table.sort(needy)
					local gName, gIcon = spellFor(buff.groupIds)
					local sName, sIcon = spellFor(buff.ids)
					local useGroup = gName and hasReagent(buff.reagents) and wanters >= 2 and #needy >= math.min(3, wanters)
					local spell, icon = (useGroup and gName or sName), (useGroup and gIcon or sIcon)
					if spell then
						for _, full in ipairs(needy) do
							local unit = roster.units[full]
							if unit and inRange(spell, unit) then
								add({ spell = spell, icon = icon, unit = unit, who = full, key = buff.key, status = worst,
									big = useGroup, label = useGroup and ("Group " .. g) or ns.WoW.Short(full) })
								break
							end
						end
					end
				end
			end
		end
	end

	-- Blessings: Greater per class, then personal overrides.
	local bless = Buffs.byKey
	for class, map in pairs(res.pally or {}) do
		local key = map[me]
		if key then
			local b = bless[key]
			local needy, worst = {}, "warn"
			for full, m in pairs(roster.members) do
				if m.class == class and not m.dead and (res.expected[full] or {})[key] == me then
					local st = needs(full, key)
					if st then needy[#needy + 1] = full; if st == "bad" then worst = "bad" end end
				end
			end
			if #needy > 0 then
				table.sort(needy)
				local gName, gIcon = spellFor(b.groupIds)
				local useGreater = gName and ns.WoW.ItemCount(Buffs.BLESSING_REAGENT) > 0
				-- Greater Blessings also hit players with a different personal
				-- assignment. Use singles so a class refresh cannot overwrite it.
				for full, member in pairs(roster.members) do
					if member.class == class and not member.dead and (res.overrides[full] or {})[me] ~= nil then
						useGreater = false; break
					end
				end
				local sName, sIcon = spellFor(b.ids)
				local spell, icon = (useGreater and gName or sName), (useGreater and gIcon or sIcon)
				if spell then
					for _, full in ipairs(needy) do
						local unit = roster.units[full]
						if unit and inRange(spell, unit) then
							add({ spell = spell, icon = icon, unit = unit, who = full, key = key, status = worst, big = useGreater,
								label = useGreater and ns.WoW.ClassName(class) or ns.WoW.Short(full) })
							break
						end
					end
				end
			end
		end
	end
	for full, map in pairs(res.overrides or {}) do
		local key = map[me]
		local m = roster.members[full]
		if key and m and not m.dead then
			local st = needs(full, key)
			local spell, icon = spellFor(bless[key].ids)
			local unit = roster.units[full]
			if st and spell and unit and inRange(spell, unit) then
				add({ spell = spell, icon = icon, unit = unit, who = full, key = key, status = st, big = false, label = ns.WoW.Short(full) })
			end
		end
	end

	table.sort(cands, function(a, b)
		if a.status ~= b.status then return a.status == "bad" end
		if a.big ~= b.big then return a.big end
		if a.key ~= b.key then return a.key < b.key end
		return a.who < b.who
	end)
	return cands[1]
end
