--!strict
-- StatBlock — the shared COD-style stat panel, rendered identically on the
-- Loadout stat column and the Gun Detail screen.
--
-- Two rules from the design that are easy to get wrong:
--
--  · Bars normalise WITHIN A CLASS, never across the roster. A pistol scored
--    against a sniper's range reads as broken.
--  · Numbers always print alongside their bar. Bars alone hide the roster's
--    identity, which lives in the details.
--
-- Every value comes from CombatStats.resolve — the same resolver the server
-- uses for real damage, so nothing here can drift from what a bullet does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Handling = require(ReplicatedStorage.Shared.Systems.Handling)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

-- The falloff bar's height, which is also its pill radius doubled — the two
-- segments overlap by half of this so their curves meet.
local TRACK_HEIGHT = 18

local MAX_HEALTH = 100 -- CombatService.MAX_HEALTH

local StatBlock = {}

-- ---------------------------------------------------------------------------
-- Per-class normalisation
-- ---------------------------------------------------------------------------

type Extract = (CombatStats.Resolved) -> number

local EXTRACT: { [string]: Extract } = {
	rpm = function(s)
		return s.fireRate * 60
	end,
	magSize = function(s)
		return s.magSize
	end,
	reloadSeconds = function(s)
		return s.reloadSeconds
	end,
	spreadDeg = function(s)
		return s.spreadDeg
	end,
	adsSpreadDeg = function(s)
		return s.adsSpreadDeg
	end,
	recoilVert = function(s)
		return s.recoilVert
	end,
	recoilHoriz = function(s)
		return s.recoilHoriz
	end,
	recoilRecovery = function(s)
		return s.recoilRecovery
	end,
	adsTime = function(s)
		return s.adsTime
	end,
	equipTime = function(s)
		return s.equipTime
	end,
	sprintToFire = function(s)
		return s.sprintToFire
	end,
	moveSpeedMult = function(s)
		return s.moveSpeedMult
	end,
	velocity = function(s)
		return s.velocity
	end,
	travelMax = function(s)
		return s.travelMax
	end,
}

-- Lower is better for these, so the bar inverts — a longer bar always means
-- "better within this class".
local INVERT: { [string]: boolean } = {
	reloadSeconds = true,
	spreadDeg = true,
	adsSpreadDeg = true,
	recoilVert = true,
	recoilHoriz = true,
	adsTime = true,
	equipTime = true,
	sprintToFire = true,
}

local rangeCache: { [string]: { lo: number, hi: number } } = {}

local function classRange(class: string, key: string): (number, number)
	local cacheKey = `{class}|{key}`
	local hit = rangeCache[cacheKey]
	if hit then
		return hit.lo, hit.hi
	end

	local extract = EXTRACT[key]
	local lo, hi = math.huge, -math.huge
	if extract then
		for gunId, def in GunCatalog.guns do
			if def.class == class then
				local value = extract(CombatStats.resolve(gunId))
				lo = math.min(lo, value)
				hi = math.max(hi, value)
			end
		end
	end
	if lo == math.huge then
		lo, hi = 0, 1
	end
	rangeCache[cacheKey] = { lo = lo, hi = hi }
	return lo, hi
end

-- Returns a bar length in percent, 12..100.
function StatBlock.pct(class: string, key: string, value: number): number
	local lo, hi = classRange(class, key)
	local t = if hi == lo then 0.568 else (value - lo) / (hi - lo)
	if INVERT[key] then
		t = 1 - t
	end
	return 12 + 88 * math.clamp(t, 0, 1)
end

-- ---------------------------------------------------------------------------
-- Derived numbers — more useful to a player than any raw stat
-- ---------------------------------------------------------------------------

function StatBlock.shotsToKill(stats: CombatStats.Resolved): number
	local perShot = stats.damageNear * math.max(stats.pellets, 1)
	if perShot <= 0 then
		return math.huge
	end
	return math.ceil(MAX_HEALTH / perShot)
end

function StatBlock.timeToKill(stats: CombatStats.Resolved): number
	local shots = StatBlock.shotsToKill(stats)
	if shots <= 1 or stats.fireRate <= 0 then
		return 0
	end
	return (shots - 1) / stats.fireRate
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------

local function card(parent: Instance, height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.color.surface
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Components.corner(frame, Theme.radius.card)
	return frame
end

-- The signature stat: a two-stop bar split proportionally by rangeNear /
-- rangeFar, solid for near damage and translucent for far.
local function falloffCard(parent: Instance, stats: CombatStats.Resolved, order: number)
	local frame = card(parent, 92, order)
	Components.padding(frame, Theme.space.md)

	local header = if stats.pellets > 1
		then `{stats.pellets} pellets · ×{stats.headshotMult} headshot`
		else `×{stats.headshotMult} headshot`

	Components.text(frame, {
		text = "DAMAGE FALLOFF",
		size = Theme.text.label,
		color = Theme.color.primaryDeep,
		area = UDim2.new(0.6, 0, 0, 16),
	})
	Components.text(frame, {
		text = header,
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		align = Enum.TextXAlignment.Right,
		area = UDim2.new(0.4, 0, 0, 16),
		position = UDim2.new(0.6, 0, 0, 0),
	})

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, TRACK_HEIGHT)
	track.Position = UDim2.fromOffset(0, 24)
	track.BackgroundColor3 = Theme.color.surfaceSunken
	track.BorderSizePixel = 0
	track.Parent = frame
	Components.corner(track, Theme.radius.pill)

	-- Split the bar where near-damage ends, as a fraction of total range.
	local span = math.max(stats.rangeFar, 1)
	local nearFraction = math.clamp(stats.rangeNear / span, 0.08, 0.92)

	local near = Instance.new("Frame")
	near.Size = UDim2.fromScale(nearFraction, 1)
	near.BackgroundColor3 = Theme.color.primary
	near.BorderSizePixel = 0
	near.Parent = track
	Components.corner(near, Theme.radius.pill)

	-- Pill-rounded like the near segment, and overlapped back by the radius so
	-- the two curves meet instead of leaving a notch. Without the corner its
	-- right end was a square edge poking out of a rounded track — the same
	-- thing that made the gun cards look square, at bar scale.
	local far = Instance.new("Frame")
	far.Size = UDim2.new(1 - nearFraction, TRACK_HEIGHT / 2, 1, 0)
	far.Position = UDim2.new(nearFraction, -TRACK_HEIGHT / 2, 0, 0)
	far.BackgroundColor3 = Theme.color.primary
	far.BackgroundTransparency = 0.58
	far.BorderSizePixel = 0
	Components.corner(far, Theme.radius.pill)
	far.Parent = track
	Components.corner(far, Theme.radius.pill)

	local perShotNear = stats.damageNear * math.max(stats.pellets, 1)
	local perShotFar = stats.damageFar * math.max(stats.pellets, 1)

	Components.text(frame, {
		text = `{math.floor(perShotNear + 0.5)} dmg to {math.floor(stats.rangeNear)} studs`,
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(0.5, 0, 0, 16),
		position = UDim2.fromOffset(0, 46),
	})
	Components.text(frame, {
		text = `{math.floor(perShotFar + 0.5)} dmg past {math.floor(stats.rangeFar)} studs`,
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		align = Enum.TextXAlignment.Right,
		area = UDim2.new(0.5, 0, 0, 16),
		position = UDim2.new(0.5, 0, 0, 46),
	})
end

local function derivedPair(parent: Instance, stats: CombatStats.Resolved, big: number, order: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 74)
	row.LayoutOrder = order
	row.Parent = parent

	local shots = StatBlock.shotsToKill(stats)
	local ttk = StatBlock.timeToKill(stats)

	local function tile(x: number, value: string, label: string)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0.5, -4, 1, 0)
		frame.Position = UDim2.new(x, if x == 0 then 0 else 4, 0, 0)
		frame.BackgroundColor3 = Theme.color.surface
		frame.BorderSizePixel = 0
		frame.Parent = row
		Components.corner(frame, Theme.radius.card)

		Components.text(frame, {
			text = value,
			size = big,
			color = Theme.color.primaryDeep,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, big + 8),
			position = UDim2.fromOffset(0, 12),
		})
		Components.text(frame, {
			text = label,
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, 14),
			position = UDim2.new(0, 0, 1, -22),
		})
	end

	tile(0, if shots == math.huge then "—" else tostring(shots), "SHOTS TO KILL")
	tile(0.5, if shots <= 1 then "instant" else `{math.floor(ttk * 1000 + 0.5)}ms`, "TIME TO KILL")
end

type Row = { label: string, value: string, key: string?, raw: number? }

local function groupCard(
	parent: Instance,
	title: string,
	rows: { Row },
	class: string,
	order: number
)
	local height = 30 + #rows * 22 + 10
	local frame = card(parent, height, order)
	Components.padding(frame, Theme.space.md)

	Components.text(frame, {
		text = title,
		size = Theme.text.label,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, 0, 0, 18),
	})

	for index, row in rows do
		local y = 24 + (index - 1) * 22

		Components.text(frame, {
			text = row.label,
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			area = UDim2.fromOffset(126, 18),
			position = UDim2.fromOffset(0, y),
		})

		-- Some rows are categorical (Trigger, Bullet drop) and get no bar.
		if row.key and row.raw then
			local track = Instance.new("Frame")
			track.Size = UDim2.new(1, -126 - 74, 0, 8)
			track.Position = UDim2.fromOffset(126, y + 5)
			track.BackgroundColor3 = Theme.color.surfaceSunken
			track.BackgroundTransparency = 0.1
			track.BorderSizePixel = 0
			track.Parent = frame
			Components.corner(track, Theme.radius.pill)

			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(StatBlock.pct(class, row.key, row.raw) / 100, 1)
			fill.BackgroundColor3 = Theme.color.primarySoft
			fill.BorderSizePixel = 0
			fill.Parent = track
			Components.corner(fill, Theme.radius.pill)
		end

		Components.text(frame, {
			text = row.value,
			size = Theme.text.label,
			color = Theme.color.text,
			align = Enum.TextXAlignment.Right,
			area = UDim2.fromOffset(70, 18),
			position = UDim2.new(1, -70, 0, y),
		})
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- Fills `parent` (expects a UIListLayout) with the full block. `big` is the
-- font size for the derived pair: 34 on Detail, 26 in the Loadout column.
-- Returns the total pixel height so the caller can size its canvas.
function StatBlock.build(parent: Instance, gunId: string, big: number): number
	local stats = CombatStats.resolve(gunId)
	local class = stats.class

	falloffCard(parent, stats, 1)
	derivedPair(parent, stats, big, 2)

	groupCard(parent, "FIRE", {
		{ label = "Rate of fire", value = `{math.floor(stats.fireRate * 60 + 0.5)} rpm`, key = "rpm", raw = stats.fireRate * 60 },
		{ label = "Trigger", value = if stats.auto then "Automatic" else "Semi-Auto" },
		{ label = "Magazine", value = tostring(stats.magSize), key = "magSize", raw = stats.magSize },
		{ label = "Reload", value = `{string.format("%.1f", stats.reloadSeconds)}s`, key = "reloadSeconds", raw = stats.reloadSeconds },
	}, class, 3)

	-- "Hip-fire cone" is worded as a FIXED cone on purpose. There is no bloom
	-- in this game — never show a growing crosshair or a spread meter.
	groupCard(parent, "ACCURACY & RECOIL", {
		{ label = "Hip-fire cone", value = `{stats.spreadDeg}°`, key = "spreadDeg", raw = stats.spreadDeg },
		{ label = "Aimed cone", value = `{stats.adsSpreadDeg}°`, key = "adsSpreadDeg", raw = stats.adsSpreadDeg },
		{ label = "Vertical kick", value = `{stats.recoilVert}°`, key = "recoilVert", raw = stats.recoilVert },
		{ label = "Horizontal kick", value = `{stats.recoilHoriz}°`, key = "recoilHoriz", raw = stats.recoilHoriz },
		{ label = "Recovery", value = `{stats.recoilRecovery}°/s`, key = "recoilRecovery", raw = stats.recoilRecovery },
	}, class, 4)

	local weight = math.floor((stats.moveSpeedMult - 1) * 100 + 0.5)
	-- In MILLISECONDS, and that is the point (NOD-143). A player can compare 180
	-- and 240 at a glance; nobody compares 0.18 and 0.24, and handling decides
	-- more fights than damage does — so it has to be the readable half of the
	-- card, not the decimal one.
	local timings = Handling.timings(stats)
	local function ms(seconds: number): string
		return `{math.floor(seconds * 1000 + 0.5)} ms`
	end

	local handling = {
		{ label = "Aim down sight", value = ms(timings.adsTime), key = "adsTime", raw = stats.adsTime },
		{ label = "Draw", value = ms(timings.equipTime), key = "equipTime", raw = stats.equipTime },
		{ label = "Holster", value = ms(timings.holsterTime) },
		{
			label = "Sprint to fire",
			value = ms(timings.sprintToFire),
			key = "sprintToFire",
			raw = stats.sprintToFire,
		},
		{ label = "Tac-sprint to fire", value = ms(timings.tacSprintToFire) },
		{ label = "Reload", value = ms(timings.reloadTime), key = "reloadSeconds", raw = stats.reloadSeconds },
		{ label = "Reload, empty", value = ms(timings.reloadEmptyTime) },
		-- The one people miss: where the rounds actually land, which is what
		-- makes reload-cancelling a technique rather than a rumour.
		{ label = "Ammo lands at", value = ms(timings.reloadCancelTime) },
		{ label = "Weight", value = `{if weight >= 0 then "+" else ""}{weight}% speed`, key = "moveSpeedMult", raw = stats.moveSpeedMult },
	}
	if timings.shellReloadTime then
		table.insert(handling, #handling, { label = "Per shell", value = ms(timings.shellReloadTime) })
	end
	groupCard(parent, "HANDLING", handling, class, 5)

	-- Bullets are real server-simulated projectiles with gravity drop, so
	-- these are live numbers, not flavour.
	groupCard(parent, "BALLISTICS", {
		{ label = "Muzzle velocity", value = `{math.floor(stats.velocity)} studs/s`, key = "velocity", raw = stats.velocity },
		{ label = "Bullet drop", value = `{stats.drop} studs/s²` },
		{ label = "Max travel", value = `{math.floor(stats.travelMax)} studs`, key = "travelMax", raw = stats.travelMax },
	}, class, 6)

	-- falloff 92 + pair 74 + fire 118 + accuracy 140 + handling 118 + ballistics 96
	-- plus five 12px gaps between the six cards.
	return 92 + 74 + 118 + 140 + 118 + 96 + 5 * Theme.space.md
end

return StatBlock
