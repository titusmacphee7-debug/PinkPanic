--!strict
-- Weapon — the magazine and handling state machine (NOD-136).
--
-- This is the one answer to "may this player fire right now, and what happens
-- to their magazine if they do". The CLIENT runs it to predict, the SERVER
-- runs it to decide, and they run *the same code* — which is rule 2: client
-- and server never compute the same number twice.
--
-- That matters more here than anywhere else in the game. The alternative is a
-- client that decides it can fire and a server that decides it cannot, and the
-- symptom is not an error: it is a gun that occasionally does nothing, at a
-- rate nobody can reproduce, which every player will describe as lag.
--
-- Three things this owns and nothing else may duplicate:
--
--   1. **The magazine.** How many rounds are in it, when they leave, when they
--      come back.
--   2. **Whether the trigger does anything.** Drawing, reloading, sprinting and
--      an empty magazine are four different noes, and each returns its own
--      reason so a rejection is never just silence.
--   3. **Cadence.** Semi fires once per press. Auto fires at the gun's rpm.
--      Burst fires its own count at its own rate and then waits. All three come
--      out of the same `nextShotAt`, so a burst gun cannot be made to fire like
--      an auto by holding the button.
--
-- Time is an accumulated clock advanced by `step`, never os.clock(). It makes
-- the whole machine testable without waiting real seconds, and it means a
-- server that hitches does not hand out a free reload — the same reasoning as
-- Health's regen clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Config = require(ReplicatedStorage.Shared.Config.FiringConfig)

local Weapon = {}

-- Why the trigger did nothing. These strings are the shared vocabulary between
-- the client's prediction and the server's enforcement, and they are what a
-- rejection shows up as in Diagnostics — "drawing" and "empty" are very
-- different bugs and must never both read as "shot rejected".
export type Reason = "drawing" | "reloading" | "empty" | "cadence" | "sprinting" | "holstered" | "dead"

export type Reload = "none" | "magazine" | "shells"

export type State = {
	stats: CombatStats.Resolved,
	clock: number,

	ammo: number,
	-- Rounds are not in the magazine the instant a reload starts. See
	-- Weapon.reloadCancelTime.
	reload: Reload,
	reloadStartedAt: number,
	reloadAmmoAt: number,
	reloadEndsAt: number,
	shellNextAt: number,

	readyAt: number, -- the draw finishes
	holstered: boolean,
	nextShotAt: number,
	sprintUntil: number,
	-- Which kind of sprint is being ended, remembered from the press.
	sprintTactical: boolean,
	dead: boolean,

	-- Aiming (NOD-143). Stored as an intent plus the moment it changed, rather
	-- than as a 0..1 that something has to remember to advance every frame: the
	-- fraction is then a pure function of the clock, which is what lets the
	-- client and the server arrive at the same cone without exchanging it.
	--
	-- `aimFrom` is where the transition started, so releasing halfway through
	-- comes back from halfway rather than snapping to fully aimed first.
	aiming: boolean,
	aimChangedAt: number,
	aimFrom: number,

	-- Melee is declared here and driven by nobody yet — see the note on
	-- `Weapon.setMelee`. Handling reads it so the state it names is the complete
	-- set the issue asked for rather than seven of eight.
	melee: boolean,

	-- Semi-auto: one shot per press, so holding the button is one shot and a
	-- macro is no faster than a finger.
	triggerHeld: boolean,
	triggerConsumed: boolean,

	burstRemaining: number,
}

-- ---------------------------------------------------------------------------
-- Derived timings. All read from the resolved stats, so an attachment that
-- changes fire rate or reload time changes these too, for free.
-- ---------------------------------------------------------------------------

function Weapon.shotInterval(stats: CombatStats.Resolved): number
	return 1 / stats.fireRate
end

-- The gap between shots INSIDE a burst, which is not the gun's fire rate. A
-- burst gun that used its rpm between shots would be a slow auto with extra
-- steps; the rpm governs the gap between bursts.
function Weapon.burstInterval(stats: CombatStats.Resolved): number
	if stats.burstRpm and stats.burstRpm > 0 then
		return 60 / stats.burstRpm
	end
	return 1 / stats.fireRate
end

-- The fastest cadence this weapon may ever legally fire at. The server's
-- ballistics gate uses this rather than the fire rate, because for a burst gun
-- those are different numbers and the fire rate is the wrong one.
function Weapon.minInterval(stats: CombatStats.Resolved): number
	return math.min(Weapon.shotInterval(stats), Weapon.burstInterval(stats))
end

function Weapon.isBurst(stats: CombatStats.Resolved): boolean
	return (stats.burstCount or 0) > 1
end

-- Magazine or shell-by-shell. Shotguns with a `shellReload` cadence load one
-- at a time and can be interrupted between any two of them.
function Weapon.reloadKind(stats: CombatStats.Resolved): Reload
	return if stats.shellReload and stats.shellReload > 0 then "shells" else "magazine"
end

-- The derived handling times (NOD-143). They live HERE rather than in
-- Systems/Handling because this is the machine that applies them, and Handling
-- requires this file — putting them the other way round would be a cycle.
-- Handling re-exports them so callers have one place to look.
--
-- Each reads the gun first and falls back to a ratio in FiringConfig. A gun
-- that names its own number wins; a gun that does not gets the pattern.

function Weapon.holsterTime(stats: CombatStats.Resolved): number
	if stats.holsterTime then
		return stats.holsterTime
	end
	return math.max(stats.equipTime * Config.derive.holsterFromEquip, Config.holsterSeconds)
end

-- Reloading from empty costs more: there is a bolt to run. That difference is
-- the reason people count their shots.
function Weapon.reloadTime(stats: CombatStats.Resolved, empty: boolean?): number
	if not empty then
		return stats.reloadSeconds
	end
	if stats.reloadEmptyTime then
		return stats.reloadEmptyTime
	end
	return stats.reloadSeconds * Config.derive.emptyFromReload
end

-- Where in the reload the rounds actually land — `reloadCancelTime`, and the
-- single most important number in how a reload feels.
function Weapon.reloadCancelTime(stats: CombatStats.Resolved, empty: boolean?): number
	if stats.reloadCancelTime then
		return stats.reloadCancelTime
	end
	return Weapon.reloadTime(stats, empty) * Config.derive.cancelFraction
end

-- Tactical sprint has the gun right down, and this is the cost that stops it
-- being a free upgrade over an ordinary sprint.
function Weapon.sprintToFire(stats: CombatStats.Resolved, tactical: boolean?): number
	if not tactical then
		return stats.sprintToFire
	end
	if stats.tacSprintToFire then
		return stats.tacSprintToFire
	end
	return stats.sprintToFire * Config.derive.tacFromSprint
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- A fresh draw: full magazine, unable to fire until equipTime has passed.
function Weapon.create(stats: CombatStats.Resolved): State
	return {
		stats = stats,
		clock = 0,
		ammo = stats.magSize,
		reload = "none",
		reloadStartedAt = 0,
		reloadAmmoAt = 0,
		reloadEndsAt = 0,
		shellNextAt = 0,
		readyAt = stats.equipTime,
		holstered = false,
		nextShotAt = 0,
		sprintUntil = 0,
		sprintTactical = false,
		dead = false,
		triggerHeld = false,
		triggerConsumed = false,
		burstRemaining = 0,
		aiming = false,
		aimChangedAt = 0,
		aimFrom = 0,
		melee = false,
	}
end

-- Switching weapons. The gun going away keeps its own magazine in its own
-- state; this is the gun coming out, and it starts drawing now.
--
-- `ammo` carries over when you re-draw a gun you already had out — swapping to
-- your pistol and back must not be a free reload, which is the exact exploit
-- that makes weapon swapping strictly better than reloading in every game that
-- gets this wrong.
function Weapon.equip(state: State, stats: CombatStats.Resolved, ammo: number?)
	-- The gun going away owns the holster half, the gun coming out owns the
	-- draw. Two guns, two numbers (NOD-143) — which is why an LMG is a bad
	-- thing to be holding when you need your pistol NOW. This used to be one
	-- flat 0.18s whatever you were putting away.
	local holster = Weapon.holsterTime(state.stats)

	state.stats = stats
	state.ammo = math.clamp(ammo or stats.magSize, 0, stats.magSize)
	state.reload = "none"
	state.holstered = false
	state.readyAt = state.clock + holster + stats.equipTime
	state.nextShotAt = state.readyAt
	state.burstRemaining = 0
	-- A swap drops you out of the sights. Coming up already aimed would make
	-- swapping strictly better than aiming, which is the wrong lesson.
	state.aiming = false
	state.aimFrom = 0
	state.aimChangedAt = state.clock
	-- Deliberately NOT cleared: a trigger held through a weapon swap must not
	-- fire the new gun the instant it is up. Clearing this here is how a swap
	-- becomes a free shot.
	state.triggerConsumed = state.triggerHeld
end

function Weapon.holster(state: State)
	state.holstered = true
	state.reload = "none"
	state.burstRemaining = 0
end

function Weapon.setDead(state: State, dead: boolean)
	state.dead = dead
	if dead then
		state.reload = "none"
		state.burstRemaining = 0
	end
end

-- ---------------------------------------------------------------------------
-- Input edges
-- ---------------------------------------------------------------------------

function Weapon.pressTrigger(state: State)
	state.triggerHeld = true
	state.triggerConsumed = false
end

function Weapon.releaseTrigger(state: State)
	state.triggerHeld = false
	state.triggerConsumed = false
end

-- Sprinting blocks the trigger, and letting go of sprint does not unblock it
-- immediately — sprintToFire is the delay, and it is one of the few handling
-- stats a good player actually feels.
function Weapon.setSprinting(state: State, sprinting: boolean, tactical: boolean?)
	if sprinting then
		-- Remembered at the PRESS, spent at the release. The release does not
		-- know which kind of sprint it is ending, and asking the caller to tell
		-- it twice is asking for the two answers to disagree.
		state.sprintTactical = tactical == true
		-- Held at infinity so it keeps blocking while the key is down; the
		-- release below is what turns it into a real deadline.
		state.sprintUntil = math.huge
		-- Sprinting cancels a reload that has not paid out yet. One that has is
		-- left alone: the rounds are already in.
		if state.reload ~= "none" and state.clock < state.reloadAmmoAt then
			Weapon.cancelReload(state)
		end
		state.burstRemaining = 0
		return
	end

	if state.sprintUntil == math.huge then
		state.sprintUntil = state.clock
			+ Config.sprintReleaseGraceSeconds
			+ Weapon.sprintToFire(state.stats, state.sprintTactical)
	end
end

-- ---------------------------------------------------------------------------
-- Aiming (NOD-143)
-- ---------------------------------------------------------------------------

-- Stored as an intent plus the moment it changed. The fraction is then a pure
-- function of the clock, which is what lets the client and the server arrive at
-- the same cone without ever putting it on the wire.
--
-- `aimFrom` is where the transition started, so letting go halfway comes back
-- from halfway rather than snapping to fully aimed and then falling.
function Weapon.setAiming(state: State, aiming: boolean)
	if state.aiming == aiming then
		return
	end
	state.aimFrom = Weapon.aimFraction(state)
	state.aiming = aiming
	state.aimChangedAt = state.clock
end

function Weapon.aimFraction(state: State): number
	local duration = state.stats.adsTime
	if duration <= 0 then
		return if state.aiming then 1 else 0
	end
	local progress = math.clamp((state.clock - state.aimChangedAt) / duration, 0, 1)
	if state.aiming then
		return state.aimFrom + (1 - state.aimFrom) * progress
	end
	return state.aimFrom * (1 - progress)
end

-- Melee. Declared and never set: a melee swing is a DAMAGE source, and every
-- damage source in this game is server-simulated from something the client
-- cannot fake. Adding the flag without the server half would be a state the
-- HUD can show and the game cannot cause, so the swing itself is its own piece
-- of work — this is the seam it will set.
function Weapon.setMelee(state: State, active: boolean)
	state.melee = active
end

-- ---------------------------------------------------------------------------
-- Reload
-- ---------------------------------------------------------------------------

-- Returns false when there is nothing to reload, so a caller never has to
-- guess whether an animation should play.
function Weapon.beginReload(state: State): boolean
	if state.dead or state.holstered then
		return false
	end
	if state.reload ~= "none" then
		return false
	end
	if state.ammo >= state.stats.magSize then
		return false
	end
	if state.clock < state.readyAt then
		return false -- still drawing
	end

	local kind = Weapon.reloadKind(state.stats)
	state.reload = kind
	state.reloadStartedAt = state.clock
	state.burstRemaining = 0

	if kind == "shells" then
		local shell = state.stats.shellReload or 0.5
		local missing = state.stats.magSize - state.ammo
		state.shellNextAt = state.clock + Config.shellReloadStartSeconds + shell
		-- A shell gun's cancel time is not derived from anything: the FIRST
		-- shell is the payout, because from that moment cancelling keeps
		-- whatever went in. That is the whole appeal of a tube-fed gun and it is
		-- why `Weapon.reloadCancelTime` is only asked about magazine reloads.
		-- The first shell IS the payout point: from that moment, cancelling
		-- keeps whatever went in. That is the whole appeal of a tube-fed gun.
		state.reloadAmmoAt = state.shellNextAt
		state.reloadEndsAt = state.clock
			+ Config.shellReloadStartSeconds
			+ shell * missing
			+ Config.shellReloadEndSeconds
		return true
	end

	-- Tactical (rounds still in the gun) versus from empty (NOD-143). From empty
	-- there is a bolt to run, so it costs more — and that difference is the
	-- reason people count their shots. Both durations, and the moment the rounds
	-- land inside each, come from Weapon.reloadTime / reloadCancelTime, which
	-- read the gun first and fall back to a ratio.
	local empty = state.ammo <= 0
	local duration = Weapon.reloadTime(state.stats, empty)
	state.reloadAmmoAt = state.clock + Weapon.reloadCancelTime(state.stats, empty)
	state.reloadEndsAt = state.clock + duration
	state.shellNextAt = 0
	return true
end

-- Interrupting. Rounds that have already landed stay landed — that is the
-- whole point of reloadCancelTime, and it makes reload cancelling a skill
-- rather than an exploit.
function Weapon.cancelReload(state: State)
	if state.reload == "none" then
		return
	end
	state.reload = "none"
	state.reloadStartedAt = 0
	state.reloadAmmoAt = 0
	state.reloadEndsAt = 0
	state.shellNextAt = 0
end

function Weapon.reloading(state: State): boolean
	return state.reload ~= "none"
end

-- 0 → 1 across the reload, for the UI ring. Returns 0 when not reloading
-- rather than nil, so a caller never has to branch on it.
function Weapon.reloadProgress(state: State): number
	if state.reload == "none" then
		return 0
	end
	local total = state.reloadEndsAt - state.reloadStartedAt
	if total <= 0 then
		return 1
	end
	return math.clamp((state.clock - state.reloadStartedAt) / total, 0, 1)
end

-- ---------------------------------------------------------------------------
-- Firing
-- ---------------------------------------------------------------------------

-- The one question. Every no has its own reason, in the order a player would
-- notice them.
function Weapon.canFire(state: State): (boolean, Reason?)
	if state.dead then
		return false, "dead"
	end
	if state.holstered then
		return false, "holstered"
	end
	if state.clock < state.readyAt then
		return false, "drawing"
	end
	if state.clock < state.sprintUntil then
		return false, "sprinting"
	end
	if state.reload ~= "none" then
		return false, "reloading"
	end
	if state.ammo <= 0 then
		return false, "empty"
	end
	if state.clock < state.nextShotAt then
		return false, "cadence"
	end
	return true
end

-- Consumes a round and sets the next legal shot time.
--
-- The SERVER calls this directly on an arriving intent — it has no trigger to
-- read, only shots that already claim to have happened. The client reaches it
-- through `update`. Both paths land here so the magazine can only ever be
-- decremented by one piece of code.
function Weapon.commitShot(state: State): (boolean, Reason?)
	local ok, reason = Weapon.canFire(state)
	if not ok then
		return false, reason
	end

	state.ammo -= 1

	if state.burstRemaining > 0 then
		state.burstRemaining -= 1
		state.nextShotAt = state.clock
			+ (if state.burstRemaining > 0
				then Weapon.burstInterval(state.stats)
				else math.max(Weapon.shotInterval(state.stats), Config.burstGapSeconds))
	else
		state.nextShotAt = state.clock + Weapon.shotInterval(state.stats)
	end

	return true
end

-- What the trigger wants THIS frame, given how it is being held. Returns true
-- at most once per call; the client sends one intent per true.
function Weapon.update(state: State): (boolean, Reason?)
	local stats = state.stats

	-- Mid-burst: the burst finishes on its own cadence whether or not the
	-- button is still down. That is what makes a burst gun a burst gun.
	if state.burstRemaining > 0 then
		if state.clock < state.nextShotAt then
			return false, "cadence"
		end
		local fired, reason = Weapon.commitShot(state)
		if not fired then
			-- Died, was holstered, ran dry mid-burst. Abandon the rest —
			-- otherwise burstRemaining stays positive forever and the trigger
			-- is dead for the rest of the life.
			state.burstRemaining = 0
		end
		return fired, reason
	end

	if not state.triggerHeld then
		return false
	end

	local burst = Weapon.isBurst(stats)
	local oneShotPerPress = burst or not stats.auto
	if oneShotPerPress and state.triggerConsumed then
		return false
	end

	-- Pulling the trigger during a shell-by-shell reload cuts it short and
	-- fires what is already in the tube. Magazine reloads deliberately cannot
	-- be interrupted this way: there is no magazine in the gun to fire.
	if state.reload == "shells" and state.ammo > 0 then
		Weapon.cancelReload(state)
	end

	local ok, reason = Weapon.canFire(state)
	if not ok then
		-- A press that lands on an empty gun, or on a corpse, is SPENT: one
		-- click on an empty magazine must not fire the instant the reload
		-- finishes.
		--
		-- Every other no is temporary and the press is BUFFERED through it.
		-- Consuming on "sprinting" or "drawing" was the first version and it is
		-- wrong in the way that matters: a player who clicks a fraction of a
		-- second before their sprint ends, or before their gun is up, gets
		-- nothing at all and has to click again — which feels precisely like
		-- the gun failing to fire.
		if reason == "empty" or reason == "dead" or reason == "holstered" then
			state.triggerConsumed = true
		end
		return false, reason
	end

	state.triggerConsumed = true

	if burst then
		state.burstRemaining = math.min(stats.burstCount :: number, state.ammo)
	end

	return Weapon.commitShot(state)
end

-- ---------------------------------------------------------------------------
-- Stepping
-- ---------------------------------------------------------------------------

-- Public and driven by the caller, for the same reason Ballistics.step and
-- Health.step are: a machine only reachable through Heartbeat can only be
-- tested by waiting real seconds and hoping the frame rate cooperates.
function Weapon.step(state: State, deltaTime: number)
	state.clock += deltaTime

	if state.reload == "magazine" then
		if state.clock >= state.reloadAmmoAt then
			state.ammo = state.stats.magSize
		end
		if state.clock >= state.reloadEndsAt then
			state.reload = "none"
		end
		return
	end

	if state.reload ~= "shells" then
		return
	end

	local shell = state.stats.shellReload or 0.5
	while state.clock >= state.shellNextAt and state.ammo < state.stats.magSize do
		state.ammo += 1
		state.shellNextAt += shell
	end

	-- Against the deadline computed once at beginReload, not one derived from
	-- shellNextAt here. The first version recomputed it, and once the magazine
	-- was full the while loop stopped running and left shellNextAt a whole
	-- shell past the last one — so the reload loaded every shell correctly and
	-- then never ended, which presents as a gun that will not fire again.
	if state.clock >= state.reloadEndsAt then
		state.reload = "none"
	end
end

return Weapon
