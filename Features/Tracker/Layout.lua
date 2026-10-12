-- Where the small buff icons go around the head. Pure geometry: the caller passes
-- the head and screen bounds in the head's coordinate scale.
local _, ns = ...
local Layout = { GAP = 2 }
ns.Tracker.Layout = Layout
local GAP = Layout.GAP

local function rowsHeight(count, columns, size)
	return math.ceil(count / columns) * (size + GAP) - GAP
end

-- o = { columns, side, iconSize, sideGap, belowGap, aboveGap,
--       head = { left, bottom, top, width }, screen = { left, bottom, right, top } }
-- Returns { columns, side, left, top, minX, maxX }: rows anchor to the head's
-- `side`; minX/maxX keep centered rows on screen.
function Layout.Grid(count, o)
	local columns, size = o.columns, o.iconSize
	local height = rowsHeight(count, columns, size)
	-- Fixed choices retain their selected side and row width at screen edges.
	if o.side == "LEFT" then return { columns = columns, side = "LEFT", left = -o.sideGap - size, top = height / 2 } end
	if o.side == "RIGHT" then return { columns = columns, side = "RIGHT", left = o.sideGap, top = height / 2 } end
	if o.side == "TOP" then return { columns = columns, side = "TOP", left = 0, top = o.aboveGap + height } end
	if o.side ~= "AUTO" or count == 0 or not o.head then
		return { columns = columns, side = "BOTTOM", left = 0, top = -o.belowGap }
	end
	-- Auto: below the head, above it when there is more room there, wider when tight.
	local head, screen = o.head, o.screen
	local below = math.max(0, head.bottom - o.belowGap - screen.bottom)
	local above = math.max(0, screen.top - head.top - o.aboveGap)
	local upward = height > below and above > below
	local maxRows = math.max(1, math.floor(((upward and above or below) + GAP) / (size + GAP)))
	local maxColumns = math.max(1, math.floor((screen.right - screen.left + GAP) / (size + GAP)))
	columns = math.min(maxColumns, math.max(columns, math.ceil(count / maxRows)))
	local center = head.left + head.width / 2
	return { columns = columns, side = upward and "TOP" or "BOTTOM", left = 0,
		top = upward and (o.aboveGap + rowsHeight(count, columns, size)) or -o.belowGap,
		minX = screen.left - center, maxX = screen.right - center }
end

-- Offset of icon i (of count) from the grid's anchor.
function Layout.Offset(i, count, size, grid)
	local step = size + GAP
	local col, row = (i - 1) % grid.columns, math.floor((i - 1) / grid.columns)
	local x
	if grid.side == "LEFT" then
		x = grid.left - col * step -- fill outward from the face
	elseif grid.side == "RIGHT" then
		x = grid.left + col * step
	else
		-- Center each row independently, including a partially filled last row.
		local rowWidth = math.min(grid.columns, count - row * grid.columns) * step - GAP
		local rowLeft = -rowWidth / 2
		if grid.minX then rowLeft = math.max(grid.minX, math.min(rowLeft, grid.maxX - rowWidth)) end
		x = rowLeft + col * step
	end
	return x, grid.top - row * step
end
