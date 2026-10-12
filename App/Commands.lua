-- User entry points; feature logic lives in Features/.
local _, ns = ...

_G["SLASH_" .. ns.commandKey .. "1"] = ns.isDev and "/buffeteriadev" or "/buffeteria"
_G["SLASH_" .. ns.commandKey .. "2"] = ns.command
SlashCmdList[ns.commandKey] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "announce" then ns.Assignments.Announce()
	elseif msg == "show" then ns.db.showTracker = true; ns.Tracker.Refresh()
	elseif msg == "hide" then ns.db.showTracker = false; ns.Tracker.Refresh()
	elseif msg == "lock" then ns.db.locked = not ns.db.locked; ns.WoW.Print(ns.db.locked and "tracker locked" or "tracker unlocked")
	elseif msg == "who" then
		for _, l in ipairs(ns.Assignments.Lines(true)) do ns.WoW.Print(l) end
	elseif msg == "reset" then
		ns.Preferences.Reset(); ns.Options.Refresh()
		ns.WoW.Print("preferences reset to class defaults")
	elseif msg == "config" or msg == "settings" then
		ns.Options.OpenSettings()
	elseif msg == "preview" or msg == "test" then
		ns.Preview.Toggle()
	elseif msg == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide; ns.Minimap.Refresh()
	elseif msg == "help" then
		ns.WoW.Print(ns.command .. " (options), " .. ns.command .. " settings, " .. ns.command .. " who, " .. ns.command .. " announce, " .. ns.command .. " show|hide, " .. ns.command .. " lock, " .. ns.command .. " minimap, " .. ns.command .. " preview, " .. ns.command .. " reset")
	else
		ns.Options.Toggle()
	end
end

-- Key binding labels
_G["BINDING_HEADER_" .. ns.commandKey] = ns.title
_G["BINDING_NAME_CLICK " .. ns.globalPrefix .. "_CastButton:LeftButton"] = "Cast next buff"

-- Addon compartment (the puzzle-piece menu by the minimap)
_G[ns.globalPrefix .. "_OnAddonCompartmentClick"] = function(_, button)
	if button == "RightButton" then ns.Options.OpenSettings() else ns.Options.Toggle() end
end
