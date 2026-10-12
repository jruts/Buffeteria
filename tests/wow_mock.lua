-- Minimal UI/roster host for integration checks; no rendering or protected casting.
local W = {}
W.__index = W
widgets = {}
local function widget(kind, name, parent, template)
	local w = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, attributes = {},
		secure = template and template:find("SecureActionButtonTemplate") ~= nil }, W)
	widgets[#widgets + 1] = w
	if name then _G[name] = w end
	return w
end
for _, method in ipairs({ "ClearAllPoints", "SetMovable", "EnableMouse", "RegisterForDrag",
	"SetFrameStrata", "SetAllPoints", "SetTexCoord", "SetTexture", "SetDesaturated", "SetColorTexture", "SetJustifyH",
	"SetJustifyV", "RegisterForClicks", "RegisterEvent", "StartMoving", "StopMovingOrSizing", "SetClampedToScreen",
	"SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHighlightTexture", "SetPushedTexture",
	"SetWordWrap", "SetNormalTexture", "SetVertexColor", "SetOwner", "AddLine", "AddDoubleLine",
	"SetOrientation", "SetValueStep", "EnableMouseWheel", "SetClipsChildren", "AddMaskTexture", "SetAtlas",
	"SetTitle", "SetPortraitToAsset", "SetFontString", "SetTextColor", "SetFontObject" }) do W[method] = function() end end
function W:SetSize(width, height) self.width, self.height = width, height end
function W:SetWidth(width) self.width = width end
function W:SetHeight(height) self.height = height end
function W:GetWidth() return self.width or 140 end
function W:GetHeight() return self.height or 140 end
function W:SetPoint(...) self.point = {...} end
function W:GetPoint() return unpack(self.point or {"CENTER", UIParent, "CENTER", 0, 0}) end
function W:GetCenter() return 100, 100 end
function W:GetLeft() return self.left end
function W:GetBottom() return self.bottom end
function W:GetTop() return self.top end
function W:GetEffectiveScale() return 1 end
function W:GetFrameLevel() return self.level or 0 end
function W:SetFrameLevel(level) self.level = level end
function W:SetAttribute(key, value)
	assert(not (self.secure and InCombatLockdown()), "secure attribute changed during combat")
	self.attributes[key] = value
end
function W:GetAttribute(key) return self.attributes[key] end
function W:RegisterForClicks(...) self.clicks = {...} end
function W:SetPushedTexture(texture) self.pushedTexture = texture end
function W:SetTexture(texture) self.texture = texture end
function W:SetDesaturated(value) self.desaturated = value end
function W:SetVertexColor(...) self.vertexColor = {...} end
function W:SetScript(event, callback) self.scripts[event] = callback end
function W:GetScript(event) return self.scripts[event] end
function W:StartMoving()
	assert(not InCombatLockdown(), "tracker moved during combat")
	self.moving = true
end
function W:StopMovingOrSizing() self.moving = false end
function W:SetText(text) self.label = text end
function W:GetText() return self.label end
function W:SetParent(parent) self.parent = parent end
function W:GetParent() return self.parent end
function W:SetScrollChild(child) self.scrollChild = child end
function W:SetHorizontalScroll(value) self.horizontalScroll = value end
function W:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function W:SetValue(value)
	self.value = math.max(self.minimum, math.min(value, self.maximum))
	if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, self.value) end
end
function W:SetThumbTexture() self.thumb = widget("Texture", nil, self) end
function W:GetThumbTexture() return self.thumb end
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
function W:CreateMaskTexture() return widget("MaskTexture", nil, self) end
function W:IsOwned(owner) return self.shown and self.owner == owner end
function CreateFrame(kind, name, parent, template) return widget(kind, name, parent, template) end
UIParent = widget("Frame")
UIParent:SetSize(1920, 1080)
Minimap = widget("Frame")
GameTooltip = widget("Frame")
function GameTooltip_Hide() GameTooltip:Hide() end
UISpecialFrames = {}; SlashCmdList = {}; tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
PLAYER_CLASS = "PALADIN"
function UnitClass(unit) local class = unit == "player" and PLAYER_CLASS or "PALADIN"; return class, class end
function UnitFullName(unit) return unit == "player" and "A" or "B", "Realm" end
function GetNormalizedRealmName() return "Realm" end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function IsInRaid() return false end
GROUP_SIZE = 1
LE_PARTY_CATEGORY_INSTANCE = 2
function GetNumSubgroupMembers() return GROUP_SIZE end
function IsInGroup(category) return category == nil and GROUP_SIZE > 0 end
function UnitIsVisible() return true end
COMBAT = false
function InCombatLockdown() return COMBAT end
function IsShiftKeyDown() return false end
function IsPlayerSpell() return true end
WOW_TIME = 100
function GetTime() return WOW_TIME end
function time() return 1000 end
timers = {}
tickers = {}
C_Timer = {
	After = function(_, callback) timers[#timers + 1] = callback end,
	NewTicker = function(_, callback) tickers[#tickers + 1] = callback end,
}
C_Spell = { GetSpellName = function(id) return tostring(id) end, GetSpellTexture = function(id) return id end }
C_Item = { GetItemCount = function() return 10 end }
C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
delivered = {}
C_ChatInfo = {
	RegisterAddonMessagePrefix = function() end,
	SendAddonMessage = function(_, message) delivered[#delivered + 1] = message; return 0 end,
}
function strsplit(separator, text)
	local parts = {}
	for part in (text .. separator):gmatch("(.-)" .. separator) do parts[#parts + 1] = part end
	return unpack(parts)
end
function SendChatMessage() end
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
	OpenToCategory = function(id) openedCategory = id end,
}
EventRegistry = {
	callbacks = {},
	RegisterCallback = function(self, event, callback) self.callbacks[event] = callback end,
	TriggerEvent = function(self, event) self.callbacks[event]() end,
}
NineSliceUtil = { ApplyLayout = function(frame, layout, kit) frame.textureKit = kit end }
