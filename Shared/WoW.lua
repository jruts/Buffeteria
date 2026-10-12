-- WoW API compatibility used across features.
local _, ns = ...
ns.WoW = {}

function ns.WoW.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ns.title .. "|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Small API helpers (work on Mainline and Classic-style clients)
------------------------------------------------------------------------
function ns.WoW.SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

function ns.WoW.SpellIcon(id)
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

function ns.WoW.KnowsAny(ids)
	for i = #ids, 1, -1 do if isKnown(ids[i]) then return true, ids[i] end end
	return false
end

-- False only when the client reports too little power (e.g. rage) for the spell.
function ns.WoW.SpellUsable(spell)
	local check = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
	if not check then return true end
	local ok, usable, noPower = pcall(check, spell)
	return not ok or usable or not noPower
end

function ns.WoW.ItemCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
	return GetItemCount and GetItemCount(id) or 0
end

local function homeRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if (not realm or realm == "") and GetRealmName then realm = GetRealmName() end
	return realm or ""
end

-- "Name-Realm" with the realm in normalized form (no spaces or hyphens), so the
-- roster, addon-message senders and saved plans always use the same key.
function ns.WoW.NormalizeName(full)
	if type(full) ~= "string" or full == "" then return nil end
	local name, realm = full:match("^([^-]+)-(.*)$")
	name = name or full
	if not realm or realm == "" then realm = homeRealm() end
	realm = realm:gsub("[%s%-]", "")
	if realm == "" then return name end
	return name .. "-" .. realm
end

function ns.WoW.FullName(unit)
	local name, realm = UnitFullName(unit)
	-- Units that haven't loaded yet report a placeholder name; skip them until they do.
	if not name or name == "" or name == (UNKNOWNOBJECT or "Unknown") then return nil end
	return ns.WoW.NormalizeName(realm and realm ~= "" and (name .. "-" .. realm) or name)
end

function ns.WoW.Me() return ns.WoW.FullName("player") end

function ns.WoW.PlayerClass()
	local _, class = UnitClass("player")
	return class
end

function ns.WoW.IsPaladin() return ns.WoW.PlayerClass() == "PALADIN" end

function ns.WoW.Short(full) return (full and full:match("^[^-]+")) or full or "?" end

-- Assigned combat roles, with the Classic raid main-tank assignment as fallback.
function ns.WoW.IsTank(unit)
	if UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "TANK" then return true end
	if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return true end
	local index = unit:match("^raid(%d+)$")
	if not index and UnitInRaid then index = UnitInRaid(unit) end
	if index and GetRaidRosterInfo then
		local _, _, _, _, _, _, _, _, _, role, _, combatRole = GetRaidRosterInfo(tonumber(index))
		return role == "MAINTANK" or role == "maintank" or combatRole == "TANK"
	end
	return false
end

function ns.WoW.ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- A class color as { r, g, b }, gold when the client has none for the class.
function ns.WoW.ClassColor(class)
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if c then return { c.r, c.g, c.b } end
	return { 1, 0.82, 0 }
end

function ns.WoW.ClassColorName(full, class)
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
	local short = ns.WoW.Short(full)
	if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(short) end
	return short
end
