--!strict
-- LightingConfig — the lobby's light sources. Data only (NOD-162).
--
-- Lamp posts are Titus's build; this file only says what colour they burn. The
-- system that reads it never creates, moves or deletes a lamp — it adds a light
-- to one that already exists and nothing else.

local LightingConfig = {}

-- ---------------------------------------------------------------------------
-- Lamp posts
-- ---------------------------------------------------------------------------

-- Pastel pink, and deliberately not the UI's hot pink: a light tints everything
-- it touches, so a saturated bulb turns white marble into bubblegum and every
-- other colour in the lobby into a version of itself. Soft and slightly warm
-- reads as "pink lighting"; saturated reads as "something is wrong with my
-- monitor".
LightingConfig.lampColor = Color3.fromRGB(255, 186, 214)

-- Brightness and range are a pair. A bright short light is a pool you walk
-- through; a dim long one is atmosphere with no source. 28 studs is ~30 ft,
-- so the pools overlap slightly at typical lamp spacing and the ground between
-- two posts is lit rather than black.
LightingConfig.lampBrightness = 2.4
LightingConfig.lampRange = 28

-- Off. Twelve shadow-casting point lights is twelve shadow maps for decoration
-- nobody looks at, and the cost lands on exactly the players with the worst
-- hardware. Turn on for one lamp if a screenshot needs it.
LightingConfig.lampShadows = false

-- Whether the lantern MESH itself glows, on top of casting light. This is what
-- makes a lamp read as ON from across the lobby rather than as a dark object
-- with a puddle under it.
--
-- Applied at runtime only — the saved place file is never touched, so if it
-- looks wrong the fix is this flag and not an undo in Studio.
LightingConfig.lampGlow = true
LightingConfig.lampGlowColor = Color3.fromRGB(255, 214, 232)

-- The part inside each lamp model that is the light source. Titus's models call
-- it `lantern`; anything tagged with the attribute below is also lit, so a lamp
-- built differently later does not need this file changed.
LightingConfig.lampPartName = "lantern"
LightingConfig.lampAttribute = "LampLight"

return LightingConfig
