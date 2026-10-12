-- User entry points; feature logic lives in Features/.
local _, ns = ...

local COMMANDS = {
	announce = function() ns.Assignments.Announce() end,
	show = function() ns.Database.Set("showTracker", true) end,
	hide = function() ns.Database.Set("showTracker", false) end,
	lock = function()
		ns.Database.Set("locked", not ns.db.locked)
		ns.WoW.Print(ns.db.locked and "tracker locked" or "tracker unlocked")
	end,
	who = function()
		for _, l in ipairs(ns.Assignments.Lines(true)) do ns.WoW.Print(l) end
	end,
	sync = function()
		for _, l in ipairs(ns.Comm.Report()) do ns.WoW.Print(l) end
	end,
	reset = function()
		ns.Preferences.Reset()
		ns.WoW.Print("preferences reset to class defaults")
	end,
	settings = function() ns.Options.OpenSettings() end,
	preferences = function() ns.Options.OpenTab("PERSONAL") end,
	paladins = function()
		if not ns.WoW.IsPaladin() then ns.WoW.Print("The Paladins assignment editor is available to paladins.") end
		ns.Options.OpenTab("PALADIN")
	end,
	extra = function() ns.Options.OpenTab("EXTRA") end,
	preview = function() ns.Tracker.Preview.Toggle() end,
	minimap = function() ns.Minimap.Toggle() end,
	help = function()
		local c = ns.command
		ns.WoW.Print(("%s (options), %s preferences, %s paladins, %s settings, %s extra, %s who, %s announce, %s sync, %s show|hide, %s lock, %s minimap, %s preview, %s reset")
			:format(c, c, c, c, c, c, c, c, c, c, c, c, c))
	end,
}
COMMANDS.config, COMMANDS.test = COMMANDS.settings, COMMANDS.preview

_G["SLASH_" .. ns.commandKey .. "1"] = ns.isDev and "/buffeteriadev" or "/buffeteria"
_G["SLASH_" .. ns.commandKey .. "2"] = ns.command
SlashCmdList[ns.commandKey] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local command = COMMANDS[msg] or function() ns.Options.Toggle() end
	command()
end

-- Key binding labels
_G["BINDING_HEADER_" .. ns.commandKey] = ns.title
_G["BINDING_NAME_CLICK " .. ns.globalPrefix .. "_CastButton:LeftButton"] = "Cast next buff"

-- Addon compartment (the puzzle-piece menu by the minimap)
_G[ns.globalPrefix .. "_OnAddonCompartmentClick"] = function(_, button)
	if button == "RightButton" then ns.Options.OpenSettings() else ns.Options.Toggle() end
end
