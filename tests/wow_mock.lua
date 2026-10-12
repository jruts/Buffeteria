-- Minimal UI/roster host for integration checks; no rendering or protected casting.
local W = {}
W.__index = W
widgets = {}
local function widget(kind, name, parent)
	local w = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {} }, W)
	widgets[#widgets + 1] = w
	if name then _G[name] = w end
	return w
end
for _, method in ipairs({ "SetSize", "SetWidth", "SetPoint", "ClearAllPoints", "SetMovable", "EnableMouse", "RegisterForDrag",
	"SetFrameStrata", "SetAllPoints", "SetTexCoord", "SetTexture", "SetDesaturated", "SetColorTexture", "SetJustifyH",
	"SetJustifyV", "RegisterForClicks", "RegisterEvent", "StartMoving", "StopMovingOrSizing" }) do W[method] = function() end end
function W:SetScript(event, callback) self.scripts[event] = callback end
function W:GetScript(event) return self.scripts[event] end
function W:SetText(text) self.label = text end
function W:SetParent(parent) self.parent = parent end
function W:SetChecked(value) self.checked = value end
function W:GetChecked() return self.checked end
function W:SetEnabled(value) self.enabled = value end
function W:Disable() self.enabled = false end
function W:IsShown() return self.shown end
function W:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function W:SetShown(value)
	if self.shown == value then return end
	self.shown = value
	local callback = self.scripts[value and "OnShow" or "OnHide"]
	if callback then callback(self) end
end
function W:Show() self:SetShown(true) end
function W:Hide() self:SetShown(false) end
function W:CreateFontString() return widget("FontString", nil, self) end
function W:CreateTexture() return widget("Texture", nil, self) end
function CreateFrame(kind, name, parent) return widget(kind, name, parent) end
UIParent = widget("Frame")
UISpecialFrames = {}; SlashCmdList = {}; tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
PLAYER_CLASS = "PALADIN"
function UnitClass(unit) local class = unit == "player" and PLAYER_CLASS or "PALADIN"; return class, class end
function UnitFullName(unit) return unit == "player" and "A" or "B", "Realm" end
function GetNormalizedRealmName() return "Realm" end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function IsInRaid() return false end
function GetNumSubgroupMembers() return 1 end
function GetTime() return 100 end
function time() return 1000 end
timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
function runTimers()
	while #timers > 0 do local todo = timers; timers = {}; for _, callback in ipairs(todo) do callback() end end
end
function findWidget(label)
	for _, w in ipairs(widgets) do if w.label == label then return w end end
	error("Widget not found: " .. label)
end
Settings = {
	RegisterCanvasLayoutCategory = function(panel) settingsPage = panel; return {GetID = function() return 1 end} end,
	RegisterAddOnCategory = function() end,
}
