--!strict
-- Theme — the single source of truth for every colour, size, and spacing
-- value in the UI.
--
-- Before this existed, HOT_PINK was declared in nine separate controllers and
-- TEXT_DARK in five. Changing the palette meant nine edits and missing one
-- was invisible until someone opened that panel. Nothing in src/client should
-- call Color3.fromRGB for chrome any more — add a token here instead.
--
-- Data only, no behaviour: builders live in Components.luau.

local Theme = {}

-- ---------------------------------------------------------------------------
-- Palette
--
-- Pink Panic reads LIGHT: blush surfaces, dark plum text, hot pink for
-- anything interactive. Dark values exist only for scrims and viewports.
-- ---------------------------------------------------------------------------

Theme.color = {
	-- Brand
	primary = Color3.fromRGB(255, 92, 168), -- hot pink: buttons, selection, focus
	primaryDeep = Color3.fromRGB(214, 66, 143), -- pressed / borders / headings
	primarySoft = Color3.fromRGB(255, 150, 200), -- tracers, glows, subtle accents

	-- Surfaces, lightest to heaviest
	surface = Color3.fromRGB(255, 227, 240), -- blush: panel backgrounds
	surfaceRaised = Color3.fromRGB(255, 245, 250), -- cards and rows on top of surface
	surfaceSunken = Color3.fromRGB(246, 208, 226), -- wells, tracks, empty slots

	-- Text
	text = Color3.fromRGB(96, 56, 78), -- plum: body copy on light surfaces
	textMuted = Color3.fromRGB(150, 116, 134), -- secondary lines, stat rows
	textOnPrimary = Color3.fromRGB(255, 245, 250), -- text sitting on hot pink

	-- Semantic
	coin = Color3.fromRGB(255, 196, 88),
	danger = Color3.fromRGB(235, 90, 90),
	kill = Color3.fromRGB(255, 64, 96),
	success = Color3.fromRGB(120, 200, 150),

	-- Overlays: locked cards, modal dimming, viewport backdrops
	scrim = Color3.fromRGB(52, 28, 44),
	viewportBackdrop = Color3.fromRGB(66, 40, 58),
}

-- Rarity drives border colour on gun cards and the rarity line.
Theme.rarity = {
	Common = Color3.fromRGB(168, 150, 162),
	Rare = Color3.fromRGB(96, 168, 236),
	Epic = Color3.fromRGB(186, 108, 240),
	Legendary = Color3.fromRGB(240, 172, 60),
}

function Theme.rarityColor(name: string?): Color3
	return (name and Theme.rarity[name]) or Theme.color.textMuted
end

-- ---------------------------------------------------------------------------
-- Type scale. FredokaOne everywhere — it IS the brand.
-- ---------------------------------------------------------------------------

Theme.font = Enum.Font.FredokaOne

Theme.text = {
	display = 34, -- round results, big moments
	title = 26, -- panel titles
	heading = 19, -- section headers
	body = 15, -- default
	label = 13, -- buttons, chips
	caption = 11, -- stat lines, hints
}

-- ---------------------------------------------------------------------------
-- Spacing — a 4pt scale. Use these instead of arbitrary offsets so panels
-- line up with each other without anyone measuring.
-- ---------------------------------------------------------------------------

Theme.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 20,
	xl = 32,
}

Theme.radius = {
	chip = 10,
	card = 14,
	panel = 20,
	pill = 999,
}

-- Locked content: how far unowned items are pushed back visually. Kept here
-- so "locked" looks identical in the loadout, the shop, and the armory.
Theme.locked = {
	scrimTransparency = 0.45,
	contentTransparency = 0.35,
	icon = "🔒",
}

return Theme
