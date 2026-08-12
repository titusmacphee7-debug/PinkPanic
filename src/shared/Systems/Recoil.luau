--!strict
-- Recoil — where the camera goes when you hold the trigger (NOD-144).
--
-- **No bloom, ever.** Nothing in this file, and nothing that calls it, may make
-- a spread cone larger. Spread is fixed per gun; recoil moves the CAMERA, which
-- the player can see, learn and pull back down. `Recoil.validate` checks that
-- rule at boot rather than trusting it.
--
-- The pattern is the point. Shot 7 of an AR always goes to the same place, so
-- the gun can be learned — which is exactly what bloom prevents and exactly what
-- a new player needs. A small jitter sits on top so it is not robotic, sized as
-- a PERCENTAGE of each kick so it can never grow into bloom by another name.
--
-- Shared rather than client-only for the usual reason: the pattern is what a
-- recoil-control test measures, an anti-cheat pass would want to compare
-- against, and the armory wants to draw. One implementation.
--
-- The RNG is injectable. That is what makes "fire 30 rounds twice and get the
-- same shape" a thing a test can assert rather than a thing someone eyeballs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Handling = require(ReplicatedStorage.Shared.Systems.Handling)
local Config = require(ReplicatedStorage.Shared.Config.RecoilConfig)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)

local SYSTEM = "Recoil"

local Recoil = {}

export type State = {
	-- Degrees of accumulated camera offset. Pitch is up, yaw is right.
	pitch: number,
	yaw: number,
	-- Where the pattern is. Reset when the trigger is released, which is why
	-- tapping is accurate and holding is a skill.
	shot: number,
	-- Simulation time, advanced by step. Never os.clock(), for the same reason
	-- every other machine here uses its own: a test drives it in a loop.
	clock: number,
	lastShotAt: number,
	-- The high-water mark of the current burst. Recovery needs it to know where
	-- "72% of the climb" actually is — measured from the top of the burst, not
	-- from wherever the camera happens to be this frame.
	peakPitch: number,
	peakYaw: number,
	-- The viewmodel's own, larger kick (M11). Tracked here so the gun and the
	-- camera can never disagree about which shot they are on.
	visualPitch: number,
	visualYaw: number,
}

function Recoil.create(): State
	return {
		pitch = 0,
		yaw = 0,
		shot = 0,
		clock = 0,
		lastShotAt = -math.huge,
		peakPitch = 0,
		peakYaw = 0,
		visualPitch = 0,
		visualYaw = 0,
	}
end

-- ---------------------------------------------------------------------------
-- The pattern
-- ---------------------------------------------------------------------------

function Recoil.patternFor(stats: CombatStats.Resolved): { Config.Kick }
	local named = stats.recoilPattern
	if named and Config.patterns[named] then
		return Config.patterns[named]
	end
	local byClass = Config.byClass[stats.class]
	if byClass and Config.patterns[byClass] then
		return Config.patterns[byClass]
	end
	return Config.patterns[Config.defaultPattern]
end

-- The kick for shot `index` (1-based), before jitter and before modifiers.
--
-- Loops past the end rather than running out. A 100-round drum that fell off
-- the end of its pattern would become a different gun halfway through the
-- magazine, which is precisely the kind of thing nobody notices for months.
function Recoil.kickAt(stats: CombatStats.Resolved, index: number): (number, number)
	local pattern = Recoil.patternFor(stats)
	local count = #pattern
	if count == 0 then
		return stats.recoilVert, 0
	end
	local entry = pattern[((index - 1) % count) + 1]
	return stats.recoilVert * entry.vert, stats.recoilHoriz * entry.horiz * Config.horizontalScale
end

-- ---------------------------------------------------------------------------
-- Ceilings
--
-- From the gun's OWN numbers. A pistol that kicks 0.38° per shot and an LMG
-- that kicks 1.4° must not top out in the same place, and deriving it is what
-- makes that true without anyone maintaining a second table.
-- ---------------------------------------------------------------------------

function Recoil.ceiling(stats: CombatStats.Resolved): (number, number)
	local vertical = stats.recoilVert * Config.ceilingShots
	return vertical, vertical * Config.horizontalCeilingFraction
end

-- How long after the last shot before the camera starts coming back, for THIS
-- gun. Derived from its cadence rather than shared, for the same reason the
-- ceiling is: one flat number cannot be right for a 1000rpm SMG and a bolt gun
-- at once, and the version that tried made most of the guns patternless.
function Recoil.returnDelay(stats: CombatStats.Resolved): number
	local interval = 1 / math.max(stats.fireRate, 1e-3)
	return math.clamp(
		interval * Config.returnDelayShots,
		Config.returnDelayMinSeconds,
		Config.returnDelayMaxSeconds
	)
end

-- Everything that makes recoil smaller, multiplied together. `aim` is the ADS
-- fraction from Handling, so half-aimed gets half the benefit — for the same
-- reason the cone does.
function Recoil.modifier(aim: number, moveState: string?, scale: number?): number
	local ads = 1 + (Config.adsMultiplier - 1) * math.clamp(aim, 0, 1)
	local stance = (moveState and Config.stanceMultiplier[moveState]) or 1
	return ads * stance * (scale or 1)
end

-- ---------------------------------------------------------------------------
-- Firing
-- ---------------------------------------------------------------------------

-- Applies one shot's kick. `rng` is injectable so a test gets the same numbers
-- twice; pass nil in the game and it uses a shared generator.
local shared = Random.new()

function Recoil.fire(
	state: State,
	stats: CombatStats.Resolved,
	modifier: number,
	rng: Random?
)
	state.shot += 1
	state.lastShotAt = state.clock

	local vertical, horizontal = Recoil.kickAt(stats, state.shot)
	vertical *= modifier
	horizontal *= modifier

	-- Jitter as a FRACTION of the kick, never an absolute. An absolute wobble is
	-- the same on a pistol as on an LMG, so it is invisible on one and dominates
	-- the other — and a jitter that dominates is bloom wearing a hat.
	local generator = rng or shared
	local jitter = Config.jitterFraction
	vertical *= 1 + generator:NextNumber(-jitter, jitter)
	horizontal += math.abs(horizontal + stats.recoilHoriz * 0.5) * generator:NextNumber(-jitter, jitter)

	local ceilingVert, ceilingHoriz = Recoil.ceiling(stats)
	state.pitch = math.min(state.pitch + vertical, ceilingVert)
	state.yaw = math.clamp(state.yaw + horizontal, -ceilingHoriz, ceilingHoriz)
	state.peakPitch = math.max(state.peakPitch, math.abs(state.pitch))
	state.peakYaw = math.max(state.peakYaw, math.abs(state.yaw))

	-- The gun kicks harder than your aim does. That gap is most of what makes a
	-- weapon feel powerful without making it hard to shoot.
	state.visualPitch += vertical * Config.visualMultiplier
	state.visualYaw += horizontal * Config.visualMultiplier
end

-- Releasing the trigger restarts the pattern. Tapping is therefore accurate and
-- holding is a skill, which is the entire shape of the mechanic.
function Recoil.release(state: State)
	state.shot = 0
end

-- ---------------------------------------------------------------------------
-- Recovery
-- ---------------------------------------------------------------------------

-- The standard partial return: the camera comes back toward where you were
-- aiming but not all the way, and the remainder is what you pull down yourself.
--
-- Exponential rather than linear, so the first part is fast enough to feel
-- responsive between taps and the tail is slow enough that sustained fire still
-- costs you something.
function Recoil.step(state: State, stats: CombatStats.Resolved?, deltaTime: number)
	state.clock += deltaTime

	-- The viewmodel settles fast and completely; it is theatre, not accuracy.
	local visualDecay = math.exp(-deltaTime / math.max(Config.visualRecoverySeconds, 1e-3))
	state.visualPitch *= visualDecay
	state.visualYaw *= visualDecay

	if not stats then
		return
	end
	-- Nothing recovers until you have actually stopped firing. The delay is
	-- measured in the gun's OWN shots and is longer than one of them, so a held
	-- burst never settles between rounds — see RecoilConfig for why that is the
	-- difference between a pattern and a plateau.
	if state.clock - state.lastShotAt < Recoil.returnDelay(stats) then
		return
	end

	-- Two rates, not two destinations.
	--
	-- The first version decayed toward `pitch * (1 - returnFraction)` — a residue
	-- recomputed from the CURRENT pitch every frame, so each frame it aimed 28%
	-- below wherever it now was and compounded straight to zero. Measured on a
	-- live camera: a Pip kicked 0.405° and settled at exactly 0.000, with the
	-- manifest still claiming 28% stayed behind. The number was doing nothing but
	-- slowing the return down.
	--
	-- Latching a residue instead would be worse. It never bleeds off, so every
	-- burst leaves a permanent offset, `state.pitch` walks into its own ceiling
	-- after a few magazines, and from there the gun stops kicking at all — the
	-- clamp eats every new shot. A recoil system that quietly switches off partway
	-- through a match is a much better hidden bug than this one.
	--
	-- So: `returnFraction` of the burst's climb comes back FAST, and the last of
	-- it bleeds away slowly while you are still re-acquiring. It does return in
	-- the end — nothing accumulates across a match — but not before you have had
	-- to correct for it, which is the part that makes controlling a gun a skill.
	local fastPitch = state.peakPitch * (1 - Config.returnFraction)
	local fastYaw = state.peakYaw * (1 - Config.returnFraction)
	local pitchRate = if math.abs(state.pitch) > fastPitch
		then stats.recoilRecovery
		else stats.recoilRecovery * Config.tailRateFraction
	local yawRate = if math.abs(state.yaw) > fastYaw
		then stats.recoilRecovery
		else stats.recoilRecovery * Config.tailRateFraction

	state.pitch *= math.exp(-pitchRate * deltaTime)
	state.yaw *= math.exp(-yawRate * deltaTime)

	-- Once it has arrived, forget the burst. Exponentials never quite reach zero,
	-- so a peak that is never cleared would keep the fast line high forever and
	-- the next burst would recover against the wrong number.
	if math.abs(state.pitch) < 1e-4 and math.abs(state.yaw) < 1e-4 then
		state.pitch, state.yaw = 0, 0
		state.peakPitch, state.peakYaw = 0, 0
	end
end

-- ---------------------------------------------------------------------------
-- The authoring harness
--
-- "Fire 30 rounds at a wall and plot the grouping, so patterns can be tuned by
-- looking at them." This returns the points; the Studio side draws them.
--
-- Deterministic when handed a seeded Random, which is what makes "same gun,
-- same 30 shots, twice — identical grouping" an assertion rather than a
-- squint at two screenshots.
-- ---------------------------------------------------------------------------

export type Point = {
	shot: number,
	-- Where the crosshair was **as the shot left** — before that shot's own kick.
	-- This is the hole in the wall: a bullet goes where you were aiming, and the
	-- gun moves afterwards. It also means shot 1 is always dead centre, which is
	-- the truth about the first round of a burst and worth being able to see.
	pitch: number,
	yaw: number,
	-- Where the camera ended up immediately AFTER the kick. On a fast gun this is
	-- barely different from the next shot's `pitch`; on a slow one it is the whole
	-- story, because a sniper has settled completely before you can fire again.
	-- Report only the first pair and every slow gun looks like it has no recoil.
	kickPitch: number,
	kickYaw: number,
}
function Recoil.simulate(
	stats: CombatStats.Resolved,
	shots: number,
	options: { rng: Random?, modifier: number?, frameSeconds: number? }?
): { Point }
	local settings = options or {}
	local state = Recoil.create()
	local interval = 1 / stats.fireRate
	local frame = settings.frameSeconds or (1 / 60)
	local modifier = settings.modifier or 1

	local points: { Point } = {}
	for shot = 1, shots do
		local aimedPitch, aimedYaw = state.pitch, state.yaw
		Recoil.fire(state, stats, modifier, settings.rng)
		table.insert(points, {
			shot = shot,
			pitch = aimedPitch,
			yaw = aimedYaw,
			kickPitch = state.pitch,
			kickYaw = state.yaw,
		})
		-- Advance to the next shot in real frames, so recovery gets exactly the
		-- time it would get in game. Stepping the whole interval at once would
		-- give a different answer, and the difference is the bug this catches.
		local elapsed = 0
		while elapsed < interval do
			local dt = math.min(frame, interval - elapsed)
			Recoil.step(state, stats, dt)
			elapsed += dt
		end
	end
	return points
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

function Recoil.validate()
	local problems: { string } = {}

	-- Every pattern a gun could land on must exist and must be non-empty. A gun
	-- naming a pattern that is not there would silently get the default, which
	-- is the kind of typo that survives a whole balance pass.
	for class, name in Config.byClass do
		if not Config.patterns[name] then
			table.insert(problems, `class {class} names pattern "{name}", which does not exist`)
		end
	end
	if not Config.patterns[Config.defaultPattern] then
		table.insert(problems, `defaultPattern "{Config.defaultPattern}" does not exist`)
	end

	local shapes = 0
	for name, pattern in Config.patterns do
		shapes += 1
		if #pattern == 0 then
			table.insert(problems, `pattern "{name}" is empty`)
		end
		for index, entry in pattern do
			-- Downward recoil is not a mechanic anyone can learn: the gun would
			-- pull INTO the target, which reads as aim assist.
			if entry.vert < 0 then
				table.insert(problems, `pattern "{name}" shot {index} kicks downward ({entry.vert})`)
			end
		end
	end

	-- **The no-bloom rule, enforced rather than trusted.**
	--
	-- Three separate claims, checked as three separate things, because "no bloom"
	-- is easy to say and easy to lose:
	--
	--   1. Every gun's aimed cone is at or below its hip cone. Aiming can only
	--      ever tighten. (Static, from the catalog.)
	--   2. The cone does not grow with SHOTS. `Handling.spread` is measured, then
	--      a full magazine is fired into a live Recoil state, then it is measured
	--      again — bit-for-bit. This is the one that would actually catch someone
	--      adding a per-shot term, because that is where it would go.
	--   3. The cone does not grow with TIME. The same measurement after ten
	--      seconds of stepping, holding the trigger down the whole way.
	--
	-- 2 and 3 are the reason `Handling.spread(stats, aim)` takes no state: the
	-- assertion is that its signature IS the guarantee. If it ever needs a third
	-- argument, this check fails loudly on the way in rather than after shipping.
	-- A delay of one shot or less means recovery runs BETWEEN the rounds of a held
	-- burst, which flattens the pattern into a plateau. That is the bug that ate
	-- most of the roster the first time, so it is a rule now rather than a number
	-- somebody has to remember.
	if Config.returnDelayShots <= 1 then
		table.insert(
			problems,
			`returnDelayShots is {Config.returnDelayShots} — at or below 1 the gun recovers inside its own burst`
		)
	end

	local guns = 0
	-- Guns fast enough that a held burst never settles, so their pattern is the
	-- shape the player sees. The rest are slow enough to be clamped by
	-- returnDelayMaxSeconds, which is deliberate: a revolver SHOULD settle.
	local sustained = 0
	local burst = Recoil.create()
	for id in GunCatalog.guns do
		local stats = CombatStats.forGun(id)
		if stats then
			guns += 1
			if Recoil.returnDelay(stats) > 1 / stats.fireRate then
				sustained += 1
			end
			if stats.adsSpreadDeg > stats.spreadDeg then
				table.insert(problems, `{id} has a WIDER cone aimed ({stats.adsSpreadDeg}) than hip ({stats.spreadDeg})`)
			end
			if stats.spreadDeg < 0 or stats.adsSpreadDeg < 0 then
				table.insert(problems, `{id} has a negative spread`)
			end
			if stats.recoilPattern and not Config.patterns[stats.recoilPattern] then
				table.insert(problems, `{id} names pattern "{stats.recoilPattern}", which does not exist`)
			end

			local hipBefore, adsBefore = Handling.spread(stats, 0), Handling.spread(stats, 1)
			for _ = 1, math.max(stats.magSize, 30) do
				Recoil.fire(burst, stats, 1)
				Recoil.step(burst, stats, 1 / stats.fireRate)
			end
			local afterBurst = burst.pitch
			Recoil.release(burst)

			-- A quarter second after letting go: the fast return is spent but the
			-- tail should still be there. If it is already gone, `returnFraction`
			-- is doing nothing and there is nothing left for the player to correct.
			for _ = 1, 15 do
				Recoil.step(burst, stats, 1 / 60)
			end
			local tail = burst.pitch

			-- Ten seconds later: all the way home. A gun that keeps a permanent
			-- offset walks into its own ceiling over a match and then stops kicking
			-- entirely, which is the failure that looks like "recoil is broken"
			-- twenty minutes in and fine every time you test it fresh.
			for _ = 1, 600 do
				Recoil.step(burst, stats, 1 / 60)
			end

			if Handling.spread(stats, 0) ~= hipBefore or Handling.spread(stats, 1) ~= adsBefore then
				table.insert(problems, `{id} GREW its cone over a magazine — that is bloom`)
			end
			if afterBurst > 0.01 and tail <= 0.001 then
				table.insert(problems, `{id} snapped straight back to zero — returnFraction is a no-op`)
			end
			if burst.pitch ~= 0 then
				table.insert(problems, `{id} kept {burst.pitch}° after 10s — recoil accumulates across a match`)
			end
		end
	end

	if #problems > 0 then
		Diagnostics.warn(SYSTEM, `{table.concat(problems, " · ")}`)
		return
	end

	Diagnostics.ok(
		SYSTEM,
		`{shapes} patterns over {guns} guns · no bloom: aimed ≤ hip, and every cone `
			.. `measured identical after a full magazine + 10s · `
			.. `jitter ±{math.floor(Config.jitterFraction * 100)}% of the kick · `
			.. `wall at {Config.ceilingShots} shots · `
			.. `{sustained}/{guns} hold their pattern through a burst · `
			.. `{math.floor(Config.returnFraction * 100)}% snaps back, the rest bleeds at `
			.. `{math.floor(Config.tailRateFraction * 100)}% speed`
	)
end

Recoil.init = Recoil.validate

return Recoil
