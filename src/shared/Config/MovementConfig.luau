--!strict
-- MovementConfig — every number movement uses, in one file (NOD-139).
--
-- Nothing in the movement code may contain a speed, an acceleration, an angle
-- or a duration. If a constant appears in logic it belongs here, because the
-- alternative is what this rebuild is removing: a walk speed in the controller,
-- a different one in the state machine, and a third in whatever reads them.
--
-- Data only.

local MovementConfig = {}

-- ---------------------------------------------------------------------------
-- Speeds, studs per second
--
-- Anchored to Roblox's stock WalkSpeed of 16 so the lobby does not suddenly
-- feel like a different game. Walk is a touch above it because Pink Panic is a
-- shooter and stock Humanoid walking reads as wading.
-- ---------------------------------------------------------------------------

MovementConfig.speed = {
	Idle = 0,
	Walk = 17,
	-- Sprint is the default way to cross a map. It is only ~1.4x walk because
	-- the gap between walking and sprinting is what makes sprinting feel fast,
	-- and a huge gap makes walking feel broken.
	Sprint = 24,
	-- Tactical sprint: faster, costs your gun (M2, NOD-140). Declared now so
	-- the ceiling exists before the state does.
	TacSprint = 29,
	Crouch = 9,
	Prone = 3.5,
	-- Slide and Dive are driven by their own momentum curves (NOD-141) rather
	-- than held at a speed. The numbers here are the CEILINGS the server's
	-- plausibility check allows, not targets.
	Slide = 32,
	Dive = 34,
	-- Air keeps whatever horizontal speed you left the ground with; this is the
	-- cap, not a target.
	Air = 34,
	Mantle = 12,
	Stun = 0,
}

-- ---------------------------------------------------------------------------
-- The actuator
--
-- Consumed by Actuator.luau, which is attached and bounded from the first frame
-- but not yet the primary mover — ground locomotion runs on Humanoid.WalkSpeed,
-- for the measured reason written up in that file's header. These numbers are
-- the ceiling slide and dive (NOD-141) will push against.
-- ---------------------------------------------------------------------------

-- Acceleration, studs/s². The force applied is `mass * accel`, which is the
-- whole reason the fling is gone.
--
-- **Never MaxForce = math.huge.** The previous attempt used it, and sprinting
-- into the lobby fountain threw Titus across the plaza: an infinite force wins
-- every argument with the collision solver, so the character is resolved out of
-- the geometry at whatever speed that takes. A finite force loses that argument,
-- which is what "the wall stops you" actually means.
MovementConfig.accelGround = 90
-- Much weaker in the air. Full authority mid-jump means you can turn a jump
-- into a hover and there is no commitment to leaving the ground.
MovementConfig.accelAir = 22
-- Ceiling on the force, as a multiple of `mass * accelGround`. Braking and
-- direction changes ask for more than steady-state movement does, and this is
-- the number that says how much more they may have.
MovementConfig.forceCeiling = 2.5

-- How fast you stop when you stop asking to move. Higher is snappier; a
-- shooter wants snappy, because the fight is decided by whether you were where
-- you meant to be.
MovementConfig.brakeMultiplier = 1.6

-- ---------------------------------------------------------------------------
-- Ground
-- ---------------------------------------------------------------------------

-- How far below the root to look for floor. The R15 rig's hip height plus
-- enough margin to survive a step, and not so much that standing beside a ledge
-- counts as standing on it.
MovementConfig.groundProbeStuds = 3.2
-- Corner probes, as a fraction of the root's half-width. One ray down the
-- middle says you are airborne the moment your centre clears an edge, while
-- most of you is still on it.
MovementConfig.groundProbeSpread = 0.72
-- Steepest floor you can stand on. Above this the surface is a wall that
-- happens to be tilted, and treating it as ground is how players climb terrain
-- they should not.
MovementConfig.maxSlopeDegrees = 55
-- Grace after leaving the ground before the state machine believes it — coyote
-- time. Without it, a jump initiated one frame after walking off a ledge is
-- silently a fall.
MovementConfig.coyoteSeconds = 0.1

-- ---------------------------------------------------------------------------
-- Jump
-- ---------------------------------------------------------------------------

MovementConfig.jumpHeightStuds = 7.2
-- NOT consumed yet, and deliberately so. Buffering a press before landing and
-- forgiving one just after leaving a ledge both need the jump impulse to be
-- ours, and it is the Humanoid's while the Humanoid is the mover. Calling
-- ChangeState(Jumping) on top of the Humanoid's own jump gives you a double
-- jump, which is a worse bug than the one it fixes. They land with NOD-141.
MovementConfig.jumpBufferSeconds = 0.12
MovementConfig.jumpCooldownSeconds = 0.18

-- ---------------------------------------------------------------------------
-- Profiles
--
-- The lobby camera is fixed and hand-placed. Slide, dive and mantle all move
-- the camera in ways that look wrong under it, so the lobby simply does not
-- have them — which is a rule about the CAMERA, not about the moves.
-- ---------------------------------------------------------------------------

export type ProfileName = "lobby" | "combat"

MovementConfig.profiles = {
	-- Crouch IS in the lobby, and the exclusions above are the reason: what the
	-- fixed camera cannot show is a slide arc, a dive, or a mantle. Crouching is
	-- just a shorter character. Leaving it out would mean the crouch key does
	-- nothing in the only place currently testable, which teaches the player
	-- that it is broken.
	lobby = {
		allowed = { Idle = true, Walk = true, Sprint = true, Crouch = true, Air = true, Stun = true },
	},
	combat = {
		allowed = {
			Idle = true,
			Walk = true,
			Sprint = true,
			TacSprint = true,
			Crouch = true,
			Prone = true,
			Slide = true,
			Dive = true,
			Air = true,
			Mantle = true,
			Stun = true,
		},
	},
}

-- ---------------------------------------------------------------------------
-- Server plausibility (NOD-139; hardening proper is NOD-161)
--
-- FLAG, do not rubber-band. A false positive that teleports a player is far
-- worse than a false positive that prints a line, and until M14 there is not
-- enough evidence about what normal looks like to act on it.
-- ---------------------------------------------------------------------------

-- How much over the fastest legal speed a player may be measured at before it
-- is worth reporting. Generous: a laggy client genuinely covers ground in
-- bursts, and lifts, conveyors and knockback are all legitimately fast.
MovementConfig.speedToleranceMultiplier = 1.6
-- Studs in a single sample that no legal movement explains.
MovementConfig.teleportStuds = 90
-- How often the server samples a position. Slower than a heartbeat on purpose:
-- this is a fairness canary, not a physics simulation.
MovementConfig.auditIntervalSeconds = 0.5
-- ...but never at EXACTLY that interval. A fixed sampling period can be
-- phase-locked: measured on 2026-08-12, a character teleporting 260 studs back
-- and forth every 0.25s was sampled at 0.5s and read as perfectly stationary,
-- because every sample landed on the same end of the trip. The interval is
-- multiplied by 1 ± this each time so there is no period to hide inside.
MovementConfig.auditIntervalJitter = 0.4
-- Consecutive bad samples before saying anything, so one hitch is not an
-- accusation.
MovementConfig.auditStrikes = 4

-- ---------------------------------------------------------------------------
-- Diagnostics overlay
-- ---------------------------------------------------------------------------

MovementConfig.overlayKey = Enum.KeyCode.F3

return MovementConfig
