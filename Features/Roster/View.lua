-- Who in the current group has been heard from, and a way to share the add-on.
local _, ns = ...
local UI = ns.UI
local View = {}
ns.Roster.View = View

local INSTALL_URL = "https://www.curseforge.com/wow/addons/buffeteria"
local INSTALL_MESSAGE = "Want to coordinate buffs? Search for Buffeteria in CurseForge or visit " .. INSTALL_URL
local STATUS = {
	detected = { "Detected", 0.46, 0.85, 0.44 },
	waiting = { "Not detected", 0.95, 0.76, 0.36 },
	offline = { "Offline", 0.66, 0.66, 0.66 },
}
local ROW_H, ROW_GAP = 20, 3
local panel, card, share, help, summary, rows, rowWidth

local function shareInstallLink()
	if ns.Options.ClassPreview() then return end
	local channel = ns.Comm.Channel()
	if channel and not ns.WoW.SendChat(INSTALL_MESSAGE, channel) then
		ns.WoW.Print("Could not post the install link. " .. INSTALL_URL)
	end
end

local function placeRow(row, index)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 12 + ((index - 1) % 2) * (rowWidth + 8),
		-42 - math.floor((index - 1) / 2) * (ROW_H + ROW_GAP))
	row:SetSize(rowWidth, ROW_H)
end

local function createRow(index)
	local row = CreateFrame("Frame", nil, card)
	placeRow(row, index)
	local background = row:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 0.92, 0.75, 0.06)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 5, 0)
	row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.status:SetPoint("RIGHT", -8, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.status, "LEFT", -12, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	rows[index] = row
	return row
end

function View.Refresh()
	if not panel:IsShown() then return end
	local preview = ns.Options.ClassPreview()
	local canShare = not preview and ns.Comm.Channel() ~= nil
	local members = not preview and ns.Roster.GroupMembers() or {}
	share:SetEnabled(canShare)
	help:SetText(preview and "Return to Current character to see your group and share the link."
		or (canShare and "Detected means Buffeteria has heard from that player this session."
			or "Join a party or raid to see other players and share the install link."))

	local detected = 0
	for index, member in ipairs(members) do
		local row = rows[index] or createRow(index)
		local heard = member.isPlayer or ns.Comm.stats.heard[member.name]
		local state = not member.online and STATUS.offline or (heard and STATUS.detected or STATUS.waiting)
		if state == STATUS.detected then detected = detected + 1 end
		if member.class then UI.ClassIcon(row.icon, member.class) end
		row.icon:SetShown(member.class ~= nil)
		row.name:SetText(member.name .. (member.isPlayer and " (you)" or ""))
		row.name:SetTextColor(unpack(member.class and ns.WoW.ClassColor(member.class) or UI.TEXT))
		row.status:SetText(state[1])
		row.status:SetTextColor(unpack(state, 2))
		row:Show()
	end
	for index = #members + 1, #rows do rows[index]:Hide() end
	summary:SetText(("%d of %d detected"):format(detected, #members))
	card:SetHeight(48 + math.ceil(#members / 2) * (ROW_H + ROW_GAP))
	card:SetShown(#members > 0)
end

function View.Layout(width)
	rowWidth = math.floor((width - 56) / 2)
	for index, row in ipairs(rows) do placeRow(row, index) end
end

function View.Create(host)
	panel, rows = host, {}
	local _, note = UI.PageHeader(panel, "Buffeteria in your group", "")
	help = note
	share = UI.Button(panel, "Share install link", 154, shareInstallLink,
		"Post the Buffeteria CurseForge link in your group chat.")
	share:SetPoint("TOPRIGHT", -16, -12)
	card = UI.Card(panel, "Group members")
	card:SetPoint("TOPLEFT", 12, -54)
	card:SetPoint("TOPRIGHT", -12, -54)
	summary = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	summary:SetPoint("TOPRIGHT", -14, -12)
end
