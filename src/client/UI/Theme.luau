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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Shared.Config.Rarity)

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
	primaryLight = Color3.fromRGB(255, 130, 190), -- secondary actions, trial buttons
	primarySoft = Color3.fromRGB(255, 150, 200), -- tracers, glows, subtle accents

	-- Surfaces, lightest to heaviest
	surface = Color3.fromRGB(255, 227, 240), -- blush: panel backgrounds
	surfaceRaised = Color3.fromRGB(255, 245, 250), -- cards and rows on top of surface
	surfaceSunken = Color3.fromRGB(246, 208, 226), -- wells, tracks, empty slots

	-- Lines
	border = Color3.fromRGB(240, 200, 220), -- resting card stroke; primary when selected
	neutral = Color3.fromRGB(180, 150, 165), -- cancel / dismiss, deliberately unexciting

	-- Text
	text = Color3.fromRGB(96, 56, 78), -- plum: body copy on light surfaces
	textMuted = Color3.fromRGB(150, 116, 134), -- secondary lines, stat rows
	textOnPrimary = Color3.fromRGB(255, 245, 250), -- text sitting on hot pink

	-- Semantic
	coin = Color3.fromRGB(255, 196, 88),
	danger = Color3.fromRGB(235, 90, 90),
	kill = Color3.fromRGB(255, 64, 96),
	success = Color3.fromRGB(120, 200, 150),
	brass = Color3.fromRGB(255, 208, 130), -- ejected shells

	-- Overlays: locked cards, modal dimming, viewport backdrops
	scrim = Color3.fromRGB(52, 28, 44),
	viewportBackdrop = Color3.fromRGB(66, 40, 58),
	viewportAmbient = Color3.fromRGB(220, 210, 218),
}

-- Rarity is NOT defined here. It lives in shared/Config/Rarity.luau because it
-- is game data before it is presentation — the crate roller weights by it and
-- refunds scale with it, and the server needs all of that. A second copy of the
-- palette here is how a Legendary ends up gold in the shop and orange in the
-- killfeed.
function Theme.rarityColor(name: string?): Color3
	return RarityConfig.color(name)
end

-- Full tier definition, for anything that wants the loudness too: glow,
-- particles, frame treatment, reveal sound.
function Theme.rarity(name: string?): RarityConfig.TierDef
	return RarityConfig.get(name)
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
-- Glyphs.
--
-- Roblox renders a character FredokaOne cannot supply as NOTHING — no box, no
-- fallback, no warning. The coin readout said "100" with a gap where the coin
-- should be, and every close button in the game was a blank pink circle,
-- because 🪙 (U+1FA99) and ✕ (U+2715) are both missing. Nobody notices a
-- symbol that was never there.
--
-- So symbols live here, checked once, instead of being typed inline in nine
-- places. Verify a new one in Studio before using it: put it in a TextLabel at
-- TextSize 24 and read TextBounds.X. Emoji that render measure 23. A missing
-- glyph measures exactly 10.
-- ---------------------------------------------------------------------------

Theme.glyph = {
	coin = "💰", -- 🪙 does not exist in this font
	close = "X", -- ✕ and ✗ do not either
	equipped = "✓",
	locked = "🔒",
	bow = "🎀",
	heart = "💗",
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
	icon = Theme.glyph.locked,
}

-- ---------------------------------------------------------------------------
-- Motion. Tokens rather than per-call TweenInfo, because timing is as much a
-- brand as colour is — Pink Panic should feel bouncy and quick everywhere, not
-- bouncy on one screen and linear on the next.
-- ---------------------------------------------------------------------------

Theme.duration = {
	instant = 0.08, -- hover, press
	quick = 0.16, -- most state changes
	normal = 0.28, -- panel open/close
	slow = 0.5, -- celebratory moments
	reveal = 1.6, -- crate opening; the one place slowness is the product
}

Theme.easing = {
	-- Default for anything appearing: overshoots slightly, which is where the
	-- cuteness lives.
	enter = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	exit = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	hover = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	-- Values that should read as data rather than motion (bars, counters).
	value = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- How far a surface sits above the one behind it. Drives shadow strength and
-- stroke weight so depth is consistent rather than per-panel guesswork.
Theme.elevation = {
	flat = { shadow = 0, stroke = 1 },
	card = { shadow = 0.35, stroke = 1 },
	panel = { shadow = 0.5, stroke = 2 },
	modal = { shadow = 0.7, stroke = 2 },
}

-- Press bounce, per Leah's "cutesy click effects". A component that scales by
-- this on press feels alive; one that doesn't feels like a web form.
Theme.juice = {
	pressScale = 0.96,
	hoverScale = 1.03,
	hoverLift = 2, -- pixels
}

return Theme
