-- An isolated, unprotected tracker sample. Never reparents or changes the cast button.
local _, ns = ...
local UI, Tracker = ns.UI, ns.Tracker
local Sample = {}
Tracker.SettingsPreview = Sample
local KEYS = { "KINGS", "FORT", "MOTW", "INT" }
local CAST = { PALADIN = "KINGS", PRIEST = "FORT", DRUID = "MOTW", MAGE = "INT",
	WARRIOR = "BSHOUT" }

function Sample.Create(parent)
	local preview = CreateFrame("Frame", nil, parent)
	preview.mood = "grumpy"
	preview:SetClipsChildren(true)
	preview.head = CreateFrame("Frame", nil, preview)
	preview.head.icon = preview.head:CreateTexture(nil, "ARTWORK")
	preview.head.icon:SetAllPoints()
	-- The clean style's status border.
	preview.head.edge = CreateFrame("Frame", nil, preview.head, "BackdropTemplate")
	preview.head.edge:SetAllPoints()
	preview.head.edge:SetBackdrop({ edgeFile = UI.WHITE, edgeSize = 2 })
	preview.head.edge:Hide()
	preview.gief = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	preview.icons = {}
	for i, key in ipairs(KEYS) do
		local icon = CreateFrame("Frame", nil, preview, "BackdropTemplate")
		icon:SetBackdrop({ edgeFile = UI.WHITE, edgeSize = 1 })
		icon.tex = icon:CreateTexture(nil, "ARTWORK")
		icon.tex:SetPoint("TOPLEFT", 1, -1); icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
		icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		icon.count:SetPoint("BOTTOMRIGHT", 1, 0)
		icon.key = key
		preview.icons[i] = icon
	end
	return preview
end

function Sample.Refresh(preview)
	-- Native frames start at zero size until their first layout. Hidden settings
	-- can also be refreshed before the host is measured; wait for usable bounds.
	local width, height = preview:GetWidth(), preview:GetHeight()
	if width <= 20 or height <= 20 then return end
	local clean = ns.db.trackerStyle == "CLEAN"
	local size, headSize = ns.db.statusIconSize, ns.db.iconSize
	local keys, states, counts = {}, {}, {}
	for i, key in ipairs(KEYS) do
		local remaining = i == 2 and 120 or 240
		local state = preview.mood == "happy" and "ok" or preview.mood == "angry" and "bad"
			or (i % 2 == 1 and "bad" or remaining < ns.db.warnMinutes * 60 and "warn" or "ok")
		local show = ns.db.buffDisplay == "ALL" or ns.db.buffDisplay == "MISSING" and state == "bad"
			or ns.db.buffDisplay == "EXPIRING" and state == "warn"
			or ns.db.buffDisplay == "PROBLEMS" and state ~= "ok"
		if show then keys[#keys + 1] = key; states[key] = state; counts[key] = state == "ok" and 0 or i * 3 end
	end
	table.sort(keys, function(a, b)
		if states[a] ~= states[b] then return Tracker.Status.PRIORITY[states[a]] < Tracker.Status.PRIORITY[states[b]] end
		return a < b
	end)
	preview.head:SetSize(headSize, headSize)
	local cast = preview.mood ~= "happy" and CAST[ns.WoW.PlayerClass()]
	-- The clean style's button is the next cast's icon, shown only with something to cast.
	preview.head:SetShown(not clean or cast and true or false)
	if clean and cast then
		preview.head.icon:SetTexture(UI.BuffIcon(cast))
		preview.head.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local status = preview.mood == "angry" and "bad" or "warn"
		preview.head.edge:SetBackdropBorderColor(unpack(Tracker.Status.Color(status)))
	else
		preview.head.icon:SetTexture(Tracker.Art.Texture(preview.mood))
		preview.head.icon:SetTexCoord(0, 1, 0, 1)
	end
	preview.head.edge:SetShown(clean and cast and true or false)
	preview.gief:SetText(cast and not clean and ("GIEF " .. ns.Buffs.byKey[cast].label .. "!") or "")
	local font = preview.gief:GetFont()
	preview.gief:SetFont(font, ns.db.shoutSize, "OUTLINE")
	local aboveGap = clean and 0 or ns.db.shoutSize + 8
	local options = { columns = ns.db.iconsPerRow, side = ns.db.iconPosition, iconSize = size,
		sideGap = 4, belowGap = 4, aboveGap = aboveGap }
	-- Auto previews the same placement routine against the inset's screen bounds.
	if options.side == "AUTO" then
		local w, h = preview:GetWidth(), preview:GetHeight()
		options.head = { left = (w - headSize) / 2, bottom = (h - headSize) / 2,
			top = (h + headSize) / 2, width = headSize }
		options.screen = { left = 8, bottom = 8, right = w - 8, top = h - 8 }
	end
	local grid = Tracker.Layout.Grid(#keys, options)
	local placements, minX, maxX = {}, -headSize / 2, headSize / 2
	local minY, maxY = -headSize / 2, headSize / 2 + aboveGap
	for i, key in ipairs(keys) do
		local x, y = Tracker.Layout.Offset(i, #keys, size, grid)
		if grid.side == "LEFT" then x = x - headSize / 2
		elseif grid.side == "RIGHT" then x = x + headSize / 2
		elseif grid.side == "TOP" then y = y + headSize / 2
		else y = y - headSize / 2 end
		placements[i] = { x, y }
		minX, maxX = math.min(minX, x), math.max(maxX, x + size)
		minY, maxY = math.min(minY, y - size), math.max(maxY, y)
	end
	-- Fit large icon/head combinations without clipping or affecting the real tracker.
	local scale = math.min(1, (preview:GetWidth() - 20) / (maxX - minX),
		(preview:GetHeight() - 20) / (maxY - minY))
	local cx, cy = -(minX + maxX) / 2 * scale, -(minY + maxY) / 2 * scale
	preview.head:ClearAllPoints(); preview.head:SetPoint("CENTER", cx, cy)
	preview.head:SetSize(headSize * scale, headSize * scale)
	preview.gief:ClearAllPoints(); preview.gief:SetPoint("BOTTOM", preview.head, "TOP", 0, 4)
	preview.gief:SetFont(font, ns.db.shoutSize * scale, "OUTLINE")
	for i, icon in ipairs(preview.icons) do
		local key = keys[i]
		icon:SetShown(key ~= nil)
		if key then
			icon.key, icon.state = key, states[key]
			icon:SetSize(size * scale, size * scale)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", preview, "CENTER", cx + placements[i][1] * scale, cy + placements[i][2] * scale)
			icon.tex:SetTexture(UI.BuffIcon(key))
			icon:SetBackdropBorderColor(unpack(Tracker.Status.Color(states[key])))
			icon.count:SetText(counts[key] > 0 and counts[key] or "")
		end
	end
	preview.visibleCount, preview.fitScale = #keys, scale
end
