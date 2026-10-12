-- Composition root: startup and WoW event routing only.
local ADDON, ns = ...
local App = CreateFrame("Frame")
ns.App = App

ns.Events.On("PreferencesChanged", function()
	ns.Comm.Announce(true)
	ns.Assignments.Resolve()
end)

App:RegisterEvent("ADDON_LOADED")
App:RegisterEvent("PLAYER_LOGIN")
App:RegisterEvent("GROUP_ROSTER_UPDATE")
App:RegisterEvent("PLAYER_ENTERING_WORLD")
App:RegisterEvent("SPELLS_CHANGED")
App:RegisterEvent("PLAYER_ROLES_ASSIGNED")
App:RegisterEvent("ROLE_CHANGED_INFORM")
App:RegisterEvent("PLAYER_REGEN_ENABLED")
App:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		ns.Database.Init()
	elseif event == "PLAYER_LOGIN" then
		ns.Paladins.Init()
		ns.Comm.Init()
		ns.Tracker.Init()
		ns.Minimap.Init()
		ns.Options.RegisterSettings()
		ns.Assignments.Resolve()
		ns.WoW.Print("open for business. /buff to pick your buffs.")
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED"
		or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
		ns.Comm.Announce()
		ns.Assignments.Resolve()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Comm.Flush()
		ns.Tracker.Refresh()
	end
end)
