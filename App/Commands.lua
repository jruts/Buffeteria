-- User entry points; feature logic lives in Features/.
local _, ns = ...

SLASH_BUFFETERIA1 = "/buffeteria"
SLASH_BUFFETERIA2 = "/buff"
SlashCmdList.BUFFETERIA = function(msg)
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
		ns.WoW.Print("/buff (options), /buff settings, /buff who, /buff announce, /buff show|hide, /buff lock, /buff minimap, /buff preview, /buff reset")
	else
		ns.Options.Toggle()
	end
end

-- Key binding labels
BINDING_HEADER_BUFFETERIA = "Buffeteria"
_G["BINDING_NAME_CLICK Buffeteria_CastButton:LeftButton"] = "Cast next buff"

-- Addon compartment (the puzzle-piece menu by the minimap)
function Buffeteria_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then ns.Options.OpenSettings() else ns.Options.Toggle() end
end
