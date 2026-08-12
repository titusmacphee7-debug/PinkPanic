--!strict
-- CombatHUD — everything the screen says while you are fighting (NOD-138).
--
-- Leah drew the line and it is the right one: **hitmarkers stay crisp and
-- readable, kills get the hearts and sparkles.** Clarity while you are
-- fighting, celebration when you have a second to enjoy it. So there is not a
-- single particle in this file. Four sharp ticks, a number, a name — the things
-- you read without looking at them.
--
-- Three shapes, deliberately different at a glance rather than different by
-- colour alone. Colour is the first thing a small screen loses and the first
-- thing a colourblind player never had:
--
--   HIT       four diagonal ticks, an X
--   HEADSHOT  the X plus four axis ticks — eight points, visibly denser
--   KILL      the X inside a diamond, which is a silhouette nothing else has
--
-- **Nothing here decides anything.** Every number arrives from the server
-- already awarded. The HUD cannot mint score, cannot credit a kill, and cannot
-- tell you a shot landed that the server did not resolve — which is precisely
-- why a client-predicted hitmarker is worse than no hitmarker at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local SYSTEM = "CombatHUD"

local CombatHUD = {}

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local MARKER_AREA = 72 -- the box the ticks live in, centred on screen
local TICK_LENGTH = 14
local TICK_WIDTH = 4
local TICK_GAP = 9 -- how far from dead centre a tick starts
local TICK_OUTLINE = 2

local MARKER_HOLD = 0.05 -- the snap, before it starts leaving
local MARKER_FADE = 0.2

local DAMAGE_RISE = 46 -- pixels a damage number drifts before it is gone
local DAMAGE_LIFE = 0.55

local FEED_ROWS = 5
local FEED_LIFE = 6

local EVENT_ROWS = 4
local EVENT_LIFE = 2.2

local STREAK_MINIMUM = 2 -- one kill is not a streak

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local screen: ScreenGui? = nil
local marker: Frame? = nil
local markerScale: UIScale? = nil
local diagonalTicks: { Frame } = {}
local axisTicks: { Frame } = {}
local diamond: Frame? = nil
local damageLayer: Frame? = nil
local feedLayer: Frame? = nil
local eventLayer: Frame? = nil
local streakPill: Frame? = nil
local streakLabel: TextLabel? = nil

-- Bumped every time the marker is shown. A hit landing during the previous
-- hit's fade must cancel that fade, and a token is how the old tween's
-- completion callback knows it is no longer the current one — without it, a
-- fast gun's second hitmarker is erased by the first one finishing.
local markerToken = 0

-- The fade tweens currently in flight, so the next hit can CANCEL them.
--
-- Resetting the transparency was not enough and the reason is worth writing
-- down: a running Tween keeps writing its property every frame regardless of
-- what anyone else assigns. So a second hit landing mid-fade set the ticks to
-- opaque and the first hit's tween immediately faded them again — which at an
-- SMG's rate of fire (a shot every 0.075s, well inside the 0.2s fade) meant
-- the marker got DIMMER the more you were hitting.
local markerTweens: { Tween } = {}

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function tick(parent: Instance, rotation: number, distance: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(TICK_WIDTH, TICK_LENGTH)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.color.textOnPrimary
	frame.Rotation = rotation
	-- Pushed out along its own rotation, so the four ticks sit on the arms of an
	-- X rather than on a square.
	local radians = math.rad(rotation)
	frame.Position = UDim2.new(
		0.5,
		math.sin(radians) * distance,
		0.5,
		-math.cos(radians) * distance
	)
	frame.Parent = parent
	Components.corner(frame, 1)
	-- A dark outline on every tick, and it is not decoration. Pink Panic's
	-- world is nearly white — pale cobbles, blush buildings — and a white
	-- hitmarker on it is invisible, which was true on screen the first time
	-- this ran. Light fill plus dark edge is the only combination that reads
	-- against both a pink lobby and whatever an arena turns out to be.
	Components.stroke(frame, Theme.color.scrim, TICK_OUTLINE, 0)
	return frame
end

local function buildMarker(parent: Instance)
	local root = Instance.new("Frame")
	root.Name = "Hitmarker"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(MARKER_AREA, MARKER_AREA)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent
	marker = root

	local scale = Instance.new("UIScale")
	scale.Parent = root
	markerScale = scale

	local reach = TICK_GAP + TICK_LENGTH / 2
	for _, rotation in { 45, 135, 225, 315 } do
		table.insert(diagonalTicks, tick(root, rotation, reach))
	end
	for _, rotation in { 0, 90, 180, 270 } do
		local axis = tick(root, rotation, reach)
		axis.Visible = false
		table.insert(axisTicks, axis)
	end

	-- The kill shape. A square on its corner, drawn as a stroke only — no fill,
	-- because a filled shape at screen centre covers the thing you are aiming
	-- at, which is the one thing a hitmarker must never do.
	local shape = Instance.new("Frame")
	shape.Name = "KillDiamond"
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromScale(0.5, 0.5)
	shape.Size = UDim2.fromOffset(34, 34)
	shape.Rotation = 45
	shape.BackgroundTransparency = 1
	shape.Visible = false
	shape.Parent = root
	Components.stroke(shape, Theme.color.kill, 3, 0)
	diamond = shape
end

local function buildLayers(parent: Instance)
	-- Damage numbers pop near the middle, not on it. Directly over the
	-- crosshair they cover the target at the exact moment you need to see
	-- whether it is still standing.
	local damage = Instance.new("Frame")
	damage.Name = "DamageNumbers"
	damage.AnchorPoint = Vector2.new(0.5, 0.5)
	damage.Position = UDim2.fromScale(0.5, 0.5)
	damage.Size = UDim2.fromOffset(320, 200)
	damage.BackgroundTransparency = 1
	damage.Parent = parent
	damageLayer = damage

	-- Killfeed: top right, newest first, out of the way of everything you
	-- actually aim at.
	local feed = Instance.new("Frame")
	feed.Name = "Killfeed"
	feed.AnchorPoint = Vector2.new(1, 0)
	feed.Position = UDim2.new(1, -Theme.space.lg, 0, Theme.space.lg + 56)
	feed.Size = UDim2.fromOffset(320, FEED_ROWS * 30)
	feed.BackgroundTransparency = 1
	feed.Parent = parent
	local feedLayout = Components.listLayout(feed, Enum.FillDirection.Vertical, Theme.space.xs)
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	feedLayer = feed

	-- Score events stack UPWARD from just below centre, so the newest is
	-- closest to where you are looking and the older ones climb away.
	local events = Instance.new("Frame")
	events.Name = "ScoreEvents"
	events.AnchorPoint = Vector2.new(0.5, 1)
	events.Position = UDim2.fromScale(0.5, 0.78)
	events.Size = UDim2.fromOffset(300, EVENT_ROWS * 28)
	events.BackgroundTransparency = 1
	events.Parent = parent
	local eventLayout = Components.listLayout(events, Enum.FillDirection.Vertical, 2)
	eventLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	eventLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	eventLayer = events

	-- Streak counter, top centre. Big enough to be a small event when it
	-- changes and quiet enough to ignore when it doesn't.
	local pill = Instance.new("Frame")
	pill.Name = "Streak"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, Theme.space.lg)
	pill.Size = UDim2.fromOffset(148, 34)
	pill.BackgroundColor3 = Theme.color.primaryDeep
	pill.BorderSizePixel = 0
	pill.Visible = false
	pill.Parent = parent
	Components.corner(pill, Theme.radius.pill)
	streakPill = pill

	streakLabel = Components.text(pill, {
		text = "",
		size = Theme.text.label,
		color = Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromScale(1, 1),
	})
end

-- ---------------------------------------------------------------------------
-- Hitmarker
-- ---------------------------------------------------------------------------

type Variant = "hit" | "headshot" | "kill"

local function showMarker(variant: Variant)
	local root, scale, shape = marker, markerScale, diamond
	if not root or not scale or not shape then
		return
	end

	markerToken += 1
	local token = markerToken

	-- Before touching a single transparency. See markerTweens above.
	for _, tween in markerTweens do
		tween:Cancel()
	end
	table.clear(markerTweens)

	local color = if variant == "kill"
		then Theme.color.kill
		elseif variant == "headshot" then Theme.color.primary
		else Theme.color.textOnPrimary

	for _, frame in diagonalTicks do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
	end
	for _, frame in axisTicks do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
		frame.Visible = variant ~= "hit"
	end
	shape.Visible = variant == "kill"

	-- Every outline, not just the diamond's: the ticks carry one too, and a
	-- stroke that does not fade with its fill leaves four dark ghosts on screen
	-- after the marker is gone.
	local strokes: { UIStroke } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("UIStroke") then
			descendant.Transparency = 0
			table.insert(strokes, descendant)
		end
	end

	root.Visible = true
	-- The snap. It arrives slightly too big and settles, which is what makes it
	-- register as an event rather than as something that was already there.
	scale.Scale = if variant == "kill" then 1.7 else 1.4
	TweenService:Create(scale, TweenInfo.new(MARKER_HOLD, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(MARKER_HOLD, function()
		if token ~= markerToken then
			return -- another hit landed; that one owns the marker now
		end
		local fade = TweenInfo.new(MARKER_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local function fadeOut(instance: Instance, goal: { [string]: any })
			local tween = TweenService:Create(instance, fade, goal)
			table.insert(markerTweens, tween)
			tween:Play()
		end
		for _, frame in diagonalTicks do
			fadeOut(frame, { BackgroundTransparency = 1 })
		end
		for _, frame in axisTicks do
			fadeOut(frame, { BackgroundTransparency = 1 })
		end
		for _, outline in strokes do
			fadeOut(outline, { Transparency = 1 })
		end
		task.delay(MARKER_FADE, function()
			if token == markerToken and marker then
				marker.Visible = false
			end
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Damage numbers
-- ---------------------------------------------------------------------------

local function popDamage(amount: number, headshot: boolean, killed: boolean)
	local layer = damageLayer
	if not layer then
		return
	end

	local label = Components.text(layer, {
		text = tostring(math.floor(amount + 0.5)),
		-- A big hit should look like one before you have read the digits.
		size = if killed then Theme.text.display elseif headshot then Theme.text.title else Theme.text.heading,
		color = if killed
			then Theme.color.kill
			elseif headshot then Theme.color.primary
			else Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromOffset(90, 30),
	})
	-- Offset so a burst does not stack four numbers into an unreadable smear.
	label.Position = UDim2.new(0.5, math.random(14, 58), 0.5, math.random(-26, 6))
	-- A UIStroke rather than TextStrokeTransparency, because the built-in one
	-- is a fixed hairline and a hairline is not enough here: over pale cobbles
	-- a white number with a 1px edge reads as grey. This one has a thickness.
	local outline = Components.stroke(label, Theme.color.scrim, 2, 0)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local rise = TweenInfo.new(DAMAGE_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, rise, {
		Position = label.Position - UDim2.fromOffset(0, DAMAGE_RISE),
		TextTransparency = 1,
	}):Play()
	-- The outline fades on its own tween. A UIStroke is a separate instance
	-- from the text it wraps, so text that fades without it leaves a hollow
	-- number hanging in the air.
	TweenService:Create(outline, rise, { Transparency = 1 }):Play()

	task.delay(DAMAGE_LIFE, function()
		label:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- Score events
-- ---------------------------------------------------------------------------

local function trim(layer: Frame, keep: number)
	local rows = {}
	for _, child in layer:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(rows, child)
		end
	end
	-- LayoutOrder ascending is oldest-first for both lists, so the excess is
	-- always at the front.
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #rows - keep do
		rows[index]:Destroy()
	end
end

local nextOrder = 0

local function popEvent(label: string, score: number)
	local layer = eventLayer
	if not layer or score <= 0 then
		return
	end

	nextOrder += 1

	local row = Instance.new("Frame")
	row.Size = UDim2.fromOffset(300, 26)
	row.BackgroundTransparency = 1
	row.LayoutOrder = nextOrder
	row.Parent = layer

	local text = Components.text(row, {
		text = `+{score}  {label}`,
		size = Theme.text.heading,
		color = Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromScale(1, 1),
	})
	text.TextStrokeTransparency = 0
	text.TextStrokeColor3 = Theme.color.scrim

	trim(layer, EVENT_ROWS)

	task.delay(EVENT_LIFE, function()
		if row.Parent == nil then
			return
		end
		local fade = TweenInfo.new(Theme.duration.normal, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(text, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(Theme.duration.normal, function()
			row:Destroy()
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Streak
-- ---------------------------------------------------------------------------

local function setStreak(count: number)
	local pill, label = streakPill, streakLabel
	if not pill or not label then
		return
	end

	if count < STREAK_MINIMUM then
		pill.Visible = false
		return
	end

	label.Text = `{Theme.glyph.heart} {count} STREAK`
	if not pill.Visible then
		pill.Visible = true
	end

	-- A small kick every time it goes up, so the number changing is something
	-- you notice in peripheral vision rather than something you have to read.
	local scale = pill:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = pill
	scale.Scale = 1.18
	TweenService:Create(scale, Theme.easing.enter, { Scale = 1 }):Play()
end

-- ---------------------------------------------------------------------------
-- Killfeed
-- ---------------------------------------------------------------------------

type FeedEntry = {
	killer: string?,
	victim: string?,
	weaponId: string?,
	headshot: boolean?,
}

local function addFeedRow(entry: FeedEntry)
	local layer = feedLayer
	if not layer then
		return
	end

	local victim = entry.victim
	if type(victim) ~= "string" then
		return
	end
	local killer = if type(entry.killer) == "string" then entry.killer else nil

	nextOrder += 1

	local row = Instance.new("Frame")
	row.Size = UDim2.fromOffset(320, 26)
	row.BackgroundColor3 = Theme.color.scrim
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder
	row.Parent = layer
	Components.corner(row, Theme.radius.chip)

	local gun = if entry.weaponId then GunCatalog.get(entry.weaponId) else nil
	local weaponName = if gun then gun.name else "—"
	-- Rarity-tinted, because the gun is the interesting part of a killfeed
	-- line: who died matters for a second, what killed them changes what you
	-- do next.
	local weaponColor = if gun then Theme.rarityColor(gun.rarity) else Theme.color.textMuted

	local me = Players.LocalPlayer.Name
	local involved = killer == me or victim == me

	Components.text(row, {
		text = killer or "—",
		size = Theme.text.label,
		color = if killer == me then Theme.color.primary else Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Right,
		area = UDim2.new(0.36, -Theme.space.sm, 1, 0),
		position = UDim2.fromOffset(Theme.space.sm, 0),
		truncate = true,
	})

	Components.text(row, {
		text = if entry.headshot then `▸ {weaponName} ★` else `▸ {weaponName}`,
		size = Theme.text.caption,
		color = weaponColor,
		align = Enum.TextXAlignment.Center,
		area = UDim2.new(0.3, 0, 1, 0),
		position = UDim2.new(0.36, Theme.space.sm, 0, 0),
		truncate = true,
	})

	Components.text(row, {
		text = victim,
		size = Theme.text.label,
		color = if victim == me then Theme.color.kill else Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Left,
		area = UDim2.new(0.32, -Theme.space.sm, 1, 0),
		position = UDim2.new(0.66, Theme.space.sm, 0, 0),
		truncate = true,
	})

	if involved then
		Components.stroke(row, Theme.color.primary, 2, 0.2)
	end

	trim(layer, FEED_ROWS)

	task.delay(FEED_LIFE, function()
		if row.Parent == nil then
			return
		end
		TweenService:Create(row, Theme.easing.exit, { BackgroundTransparency = 1 }):Play()
		for _, child in row:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, Theme.easing.exit, { TextTransparency = 1 }):Play()
			end
		end
		task.delay(Theme.duration.quick, function()
			row:Destroy()
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function CombatHUD.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under the menus (LoadoutController is 8) and over the world. A hitmarker
	-- drawn on top of an open loadout screen would be a hitmarker for a shot
	-- you could not have taken.
	gui.DisplayOrder = 4
	gui.Parent = playerGui
	screen = gui

	buildMarker(gui)
	buildLayers(gui)

	-- Feedback for a hit the SERVER resolved. `killed` rides on this same event
	-- rather than arriving with the kill, so the last shot of a fight draws one
	-- marker instead of two racing each other.
	Remotes.listen("DamageDealt", function(amount, zone, killed)
		if type(amount) ~= "number" then
			return
		end
		local headshot = zone == "Head"
		local variant: Variant = if killed == true then "kill" elseif headshot then "headshot" else "hit"
		showMarker(variant)
		popDamage(amount, headshot, killed == true)
	end)

	Remotes.listen("ScoreEvent", function(label, score, _xp, _coins, streak)
		if type(label) ~= "string" or type(score) ~= "number" then
			return
		end
		popEvent(label, score)
		if type(streak) == "number" then
			setStreak(streak)
		end
	end)

	Remotes.listen("Killfeed", function(entry)
		if type(entry) ~= "table" then
			return
		end
		addFeedRow(entry)
		-- Your own death, from the one event that always knows about it. The
		-- streak counter has to clear even when the thing that killed you was
		-- not a player and there was no score event to carry the zero.
		if entry.victim == Players.LocalPlayer.Name then
			setStreak(0)
		end
	end)

	Diagnostics.ok(SYSTEM, `hitmarkers · damage numbers · {FEED_ROWS}-row killfeed · streak counter`)
end

return CombatHUD
