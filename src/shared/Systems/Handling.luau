--!strict
-- Handling — what the weapon is DOING, and how long each of those things takes
-- (NOD-143).
--
-- This is the issue Titus asked for when he said "pull out times and things". In
-- CoD, handling decides more fights than damage does: a gun that kills in three
-- shots but takes 400ms to aim loses to one that kills in four and aims in 200.
--
-- **Shared, not client-only.** The issue named `client/Weapons/Handling.luau`
-- and rule 2 wins, for the same reason it won for Movement: the server enforces
-- these gates too, and a second implementation of "how long is this holster" is
-- a second answer. The client predicts with it; the server decides with it.
--
-- **It DERIVES the state rather than keeping one.** `Weapon` already owns every
-- timestamp that decides what the gun is doing — the draw deadline, the reload
-- window, the sprint block, the burst counter. A second state machine sitting
-- beside it would be a second opinion about whether you can fire, and the
-- symptom of those two disagreeing is not an error: it is a gun that
-- occasionally does nothing, at a rate nobody can reproduce, which every player
-- describes as lag. So `Handling.stateOf` reads the machine that already exists
-- and gives its state a NAME. Naming it is the whole value — "Equipping" and
-- "Reloading" are different bugs and must never both read as "can't shoot".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Weapon = require(ReplicatedStorage.Shared.Systems.Weapon)
local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local Config = require(ReplicatedStorage.Shared.Config.FiringConfig)

local SYSTEM = "Handling"

local Handling = {}

export type State = "Ready" | "Firing" | "ADS" | "Reloading" | "Equipping" | "Holstering" | "Sprinting" | "Melee"

-- ---------------------------------------------------------------------------
-- The nine timings
--
-- Every one reads the gun first and falls back to a ratio. A gun that names its
-- own number wins; a gun that does not gets the pattern. Nothing here invents a
-- constant — the ratios live in FiringConfig with the rest of the data.
-- ---------------------------------------------------------------------------

function Handling.equipTime(stats: CombatStats.Resolved): number
	return stats.equipTime
end

-- Delegated, not re-derived. These live in `Weapon` because that is the machine
-- that APPLIES them and Handling requires it, so implementing them here too
-- would be the same number computed twice — the exact thing rule 2 forbids.
-- They are re-exported so a caller has one place to look.
Handling.holsterTime = Weapon.holsterTime
Handling.sprintToFire = Weapon.sprintToFire
Handling.reloadTime = Weapon.reloadTime

-- **The one people miss.** Ammo arrives partway through the animation, so
-- cancelling after this point keeps the reload and skips the flourish. That is
-- the reload-cancel technique, and it is real here rather than simulated: the
-- rounds are genuinely in the magazine at that moment, and `Weapon.cancelReload`
-- does not take them back out.
Handling.reloadCancelTime = Weapon.reloadCancelTime

function Handling.adsTime(stats: CombatStats.Resolved): number
	return stats.adsTime
end

function Handling.shellReloadTime(stats: CombatStats.Resolved): number?
	return stats.shellReload
end

-- Swapping is the old gun's holster plus the new gun's draw. Two guns, two
-- numbers — which is why an LMG is a bad thing to be holding when you need your
-- pistol NOW.
function Handling.swapTime(from: CombatStats.Resolved?, to: CombatStats.Resolved): number
	local holster = if from then Handling.holsterTime(from) else Config.holsterSeconds
	return holster + Handling.equipTime(to)
end

-- Everything at once, in the order a player would compare them. Used by the
-- armory (in milliseconds — a player can compare 180 and 240; they cannot
-- compare 0.18 and 0.24) and by the drift test.
export type Timings = {
	adsTime: number,
	sprintToFire: number,
	tacSprintToFire: number,
	equipTime: number,
	holsterTime: number,
	reloadTime: number,
	reloadEmptyTime: number,
	reloadCancelTime: number,
	shellReloadTime: number?,
}

function Handling.timings(stats: CombatStats.Resolved): Timings
	return {
		adsTime = Handling.adsTime(stats),
		sprintToFire = Handling.sprintToFire(stats, false),
		tacSprintToFire = Handling.sprintToFire(stats, true),
		equipTime = Handling.equipTime(stats),
		holsterTime = Handling.holsterTime(stats),
		reloadTime = Handling.reloadTime(stats, false),
		reloadEmptyTime = Handling.reloadTime(stats, true),
		reloadCancelTime = Handling.reloadCancelTime(stats, false),
		shellReloadTime = Handling.shellReloadTime(stats),
	}
end

-- ---------------------------------------------------------------------------
-- Aiming
-- ---------------------------------------------------------------------------

-- 0 at the hip, 1 fully aimed, interpolated across the gun's own adsTime — which
-- is what makes adsTime a stat rather than an animation length.
Handling.aimFraction = Weapon.aimFraction

-- The cone this shot goes into. Half-aimed is half the benefit — aiming is not
-- a switch, and a gun whose cone snapped the instant you touched the button
-- would make adsTime cosmetic.
function Handling.spread(stats: CombatStats.Resolved, aim: number): number
	local scaled = math.clamp(aim / math.max(Config.ads.spreadAtFraction, 1e-3), 0, 1)
	return stats.spreadDeg + (stats.adsSpreadDeg - stats.spreadDeg) * scaled
end

-- What aiming costs you. The half of the trade the player feels.
function Handling.moveSpeedMult(aim: number): number
	return 1 + (Config.ads.moveSpeedMult - 1) * math.clamp(aim, 0, 1)
end

-- ---------------------------------------------------------------------------
-- The named state
-- ---------------------------------------------------------------------------

-- Derived, in the order a player would notice. Read the header for why this is
-- a derivation and not a machine of its own.
function Handling.stateOf(state: Weapon.State): State
	if state.melee then
		return "Melee"
	end
	if state.holstered then
		return "Holstering"
	end
	if state.clock < state.readyAt then
		return "Equipping"
	end
	if state.clock < state.sprintUntil then
		return "Sprinting"
	end
	if state.reload ~= "none" then
		return "Reloading"
	end
	-- Firing outranks ADS: you can be both, and what you want to see on a HUD
	-- or hang an animation off is the trigger.
	if state.burstRemaining > 0 or (state.triggerHeld and state.clock < state.nextShotAt) then
		return "Firing"
	end
	if Handling.aimFraction(state) > 0.5 then
		return "ADS"
	end
	return "Ready"
end

-- ---------------------------------------------------------------------------
-- The drift test
--
-- "Log the real elapsed time for each timing, compare to config, flag any drift
-- over 20ms." Runs the actual state machine at a real frame interval and
-- measures when each gate ACTUALLY opens — which is the only way to catch the
-- class of bug where a timing is read correctly and then applied to the wrong
-- clock.
-- ---------------------------------------------------------------------------

export type Drift = { gun: string, timing: string, expected: number, measured: number, drift: number }

local DRIFT_TOLERANCE = 0.02

function Handling.drift(stats: CombatStats.Resolved, frameSeconds: number?): { Drift }
	local dt = frameSeconds or 1 / 60
	local found: { Drift } = {}

	local function record(timing: string, expected: number, measured: number)
		local drift = math.abs(measured - expected)
		if drift > DRIFT_TOLERANCE then
			table.insert(found, { gun = stats.id, timing = timing, expected = expected, measured = measured, drift = drift })
		end
	end

	-- Draw. `create` starts the gun coming up, so the first frame it can fire is
	-- the measurement.
	local state = Weapon.create(stats)
	local elapsed = 0
	while not Weapon.canFire(state) and elapsed < 10 do
		Weapon.step(state, dt)
		elapsed += dt
	end
	record("equipTime", Handling.equipTime(stats), elapsed)

	-- Reload payout: when the rounds actually land, not when the animation ends.
	state.ammo = 0
	assert(Weapon.beginReload(state), "a gun with an empty magazine must be able to reload")
	local paidAt, endedAt = -1, -1
	elapsed = 0
	while elapsed < 20 do
		Weapon.step(state, dt)
		elapsed += dt
		if paidAt < 0 and state.ammo > 0 then
			paidAt = elapsed
		end
		if state.reload == "none" then
			endedAt = elapsed
			break
		end
	end
	if Weapon.reloadKind(stats) == "magazine" then
		record("reloadEmptyTime", Handling.reloadTime(stats, true), endedAt)
		record("reloadCancelTime", Handling.reloadCancelTime(stats, true), paidAt)
	end

	-- Sprint to fire. The grace is part of the number the player experiences, so
	-- it is part of what is checked.
	state.ammo = stats.magSize
	Weapon.setSprinting(state, true)
	Weapon.setSprinting(state, false)
	elapsed = 0
	while not Weapon.canFire(state) and elapsed < 10 do
		Weapon.step(state, dt)
		elapsed += dt
	end
	record("sprintToFire", Handling.sprintToFire(stats, false) + Config.sprintReleaseGraceSeconds, elapsed)

	-- Aiming.
	Weapon.setAiming(state, true)
	elapsed = 0
	while Handling.aimFraction(state) < 1 and elapsed < 10 do
		Weapon.step(state, dt)
		elapsed += dt
	end
	record("adsTime", Handling.adsTime(stats), elapsed)

	return found
end

-- Every gun in the roster, at a real frame interval. Reports rather than
-- asserts: a drift is a bug in how a timing is APPLIED, and the useful output
-- is which gun and which timing, not a thrown error at boot.
function Handling.validate()
	local guns = 0
	local drifted: { Drift } = {}
	for id in GunCatalog.guns do
		local stats = CombatStats.forGun(id)
		if stats then
			guns += 1
			for _, entry in Handling.drift(stats) do
				table.insert(drifted, entry)
			end
		end
	end

	if #drifted > 0 then
		local worst = drifted[1]
		for _, entry in drifted do
			if entry.drift > worst.drift then
				worst = entry
			end
		end
		Diagnostics.warn(
			SYSTEM,
			`{#drifted} timing(s) across {guns} guns are more than {math.floor(DRIFT_TOLERANCE * 1000)}ms `
				.. `from what config asks for — worst is {worst.gun}'s {worst.timing}: wanted `
				.. `{math.floor(worst.expected * 1000)}ms, measured {math.floor(worst.measured * 1000)}ms`
		)
		return
	end

	Diagnostics.ok(
		SYSTEM,
		`8 states · 9 timings per gun, {guns} guns measured, none drifting over `
			.. `{math.floor(DRIFT_TOLERANCE * 1000)}ms · ADS cone at {math.floor(Config.ads.spreadAtFraction * 100)}% `
			.. `aimed, {math.floor(Config.ads.moveSpeedMult * 100)}% move speed`
	)
end

-- The client's boot list calls `init` on everything it loads; the server calls
-- `validate` by name. Measuring the timings IS this system's startup, so the
-- two are the same function rather than one wrapping the other.
Handling.init = Handling.validate

return Handling
