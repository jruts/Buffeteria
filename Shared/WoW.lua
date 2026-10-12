-- WoW API compatibility used across features.
local _, ns = ...
ns.WoW = {}

function ns.WoW.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuffeteria|r: " .. tostring(msg))
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

function ns.WoW.ItemCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
	return GetItemCount and GetItemCount(id) or 0
end

function ns.WoW.FullName(unit)
	local name, realm = UnitFullName(unit)
	if not name then return nil end
	if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() or "" end
	if realm == "" then return name end
	return name .. "-" .. realm
end

function ns.WoW.Short(full) return (full and full:match("^[^-]+")) or full or "?" end

function ns.WoW.ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

function ns.WoW.ClassColorName(full, class)
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
	local short = ns.WoW.Short(full)
	if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(short) end
	return short
end
