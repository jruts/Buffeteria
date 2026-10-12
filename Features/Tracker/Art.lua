-- Matching portraits and cast glows for each selectable tracker mascot.
local _, ns = ...
local Art = {}
ns.Tracker.Art = Art

Art.CHOICES = {
	{ key = "ORC", label = "Orc", prefix = "Orc" },
	{ key = "GNOME", label = "Gnome", prefix = "Gnome" },
	{ key = "NIGHTELF", label = "Night Elf", prefix = "NightElf" },
	{ key = "TAUREN", label = "Tauren", prefix = "Tauren" },
	{ key = "HUMAN", label = "Human", prefix = "Human" },
	{ key = "TROLL", label = "Troll", prefix = "Troll" },
	{ key = "UNDEAD", label = "Undead", prefix = "Undead" },
	{ key = "XARYU", label = "Xaru", prefix = "Xaryu" },
}
local byKey = {}
for _, choice in ipairs(Art.CHOICES) do byKey[choice.key] = choice end
local SUFFIX = { happy = "Happy", grumpy = "Grumpy", angry = "Angry" }

local function choice(style)
	return byKey[style or ns.db.headStyle] or Art.CHOICES[1]
end

local function prefix(style)
	return ns.mediaPath .. choice(style).prefix .. (ns.db.coloredHair and "Colored" or "")
end

function Art.Label(style)
	return choice(style).label
end

function Art.Texture(mood, style)
	return prefix(style) .. (SUFFIX[mood] or "Grumpy")
end

function Art.Glow(style)
	return prefix(style) .. "Glow"
end
