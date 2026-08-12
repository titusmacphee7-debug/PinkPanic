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
-- Omnimovement: sprinting in eight directions (NOD-140)
--
-- **It adds directions, not speed.** That is the readability rule the whole of
-- M2 is governed by, and it is Titus's, not a design instinct: Leah will not
-- play Killstreak because the movement is too crazy, and an average player has
-- to be able to aim at people. Every multiplier below is ≤ 1, so no input
-- sequence can produce a speed above plain forward sprint.
--
-- Indexed by the angle between where you are FACING and where you are MOVING.
-- Backwards is meaningfully slower, so retreating while shooting is a real
-- choice rather than the strictly-best way to fight.
-- ---------------------------------------------------------------------------

MovementConfig.directional = {
	forward = 1,
	-- 45°. Barely a cost, because diagonal is how you actually move in a
	-- shooter and taxing it would just teach people to zig-zag on the axes.
	diagonalForward = 0.96,
	-- 90°, pure strafe.
	strafe = 0.86,
	-- 135°.
	diagonalBack = 0.78,
	-- 180°.
	backward = 0.68,
}

-- Walking is NOT direction-scaled. At walk speed the difference is unreadable,
-- and scaling it would make aiming while repositioning feel sludgy for no gain
-- anyone can perceive.
MovementConfig.directionalStates = { Sprint = true, TacSprint = true }

-- ---------------------------------------------------------------------------
-- Tactical sprint
--
-- Faster, time-limited, and it costs you your gun for longer when it ends.
-- Draining is what stops it from simply being the sprint speed.
-- ---------------------------------------------------------------------------

MovementConfig.tacSprint = {
	-- How long a full tank lasts.
	seconds = 4,
	-- How long a full tank takes to refill from empty.
	rechargeSeconds = 6,
	-- Dead time after it ends before refilling starts, so tapping in and out
	-- is not a way to stay in it permanently.
	rechargeDelaySeconds = 0.8,
	-- Double-tap the sprint key within this to enter it.
	doubleTapSeconds = 0.28,
}

-- ---------------------------------------------------------------------------
-- Stances
--
-- Transitions take real time. Instant crouching is the "crouch spam" that makes
-- a fight about who can press a key faster, which is exactly the kind of
-- movement Leah does not want to play against.
-- ---------------------------------------------------------------------------

MovementConfig.stance = {
	toStandSeconds = 0.2,
	toCrouchSeconds = 0.22,
	toProneSeconds = 0.45,
	-- Getting up from prone is the slowest thing in the game on purpose: going
	-- prone has to be a commitment, or it is free cover.
	fromProneSeconds = 0.65,
	-- Under this, a press is a TAP and toggles the stance; over it, it is a
	-- HOLD and the stance ends with the key. Both schemes at once, which is why
	-- there is no setting to get wrong.
	tapSeconds = 0.2,
}

-- How far the character sits below standing, in studs. Applied through
-- Humanoid.HipHeight and CameraOffset rather than by resizing parts: NOD-167
-- pins every rig to one size, and a stance that changed part sizes would break
-- that guarantee AND trip CharacterService's size audit. Lowering the whole
-- body is a real change to what a shot has to clear.
MovementConfig.stanceDrop = {
	Idle = 0,
	Walk = 0,
	Sprint = 0,
	TacSprint = 0,
	Crouch = 1.4,
	Prone = 2.2,
	Slide = 1.6,
	Dive = 2.2,
	Air = 0,
	Mantle = 0,
	Stun = 0,
}

-- Character attributes other systems read. Named here so nothing has to
-- hardcode the string, and listed together so the set is visible at a glance.
MovementConfig.attributes = {
	-- The state machine's current state, by name. The booleans below predate it
	-- and stay because things are written against them; this one is what you
	-- read when the question is "what is this player actually doing".
	state = "PPMoveState",
	sprinting = "PPSprinting",
	crouching = "PPCrouching",
	prone = "PPProne",
	sliding = "PPSliding",
}

-- ---------------------------------------------------------------------------
-- Slide (NOD-141)
--
-- A slide is a COMMITMENT: you trade control for distance. You steer it, but you
-- cannot stop it early and you cannot re-enter one without re-earning the
-- sprint, which is what keeps it fair to shoot at.
-- ---------------------------------------------------------------------------

MovementConfig.slide = {
	-- Entry speed, as a multiple of the sprint you came in at. Clamped to
	-- `speed.Slide` above, so raising this cannot outrun the server's check.
	entryMultiplier = 1.35,
	-- Longest a slide can last. The curve below is sampled across exactly this.
	maxSeconds = 0.85,
	-- Shortest. Below this you cannot cancel out, so a slide is never a
	-- one-frame speed tap.
	minSeconds = 0.22,
	-- Ends early once it has decayed to here — a slide that trails off into a
	-- crawl reads as the game sticking rather than as a slide finishing.
	exitSpeed = 13,
	-- How long after a slide before another may start. With `sprintChargeSeconds`
	-- this is what stops slide-chaining down a corridor.
	cooldownSeconds = 0.8,
	-- How long you must have been sprinting before a slide is available.
	sprintChargeSeconds = 0.25,
	-- Steering: degrees per second the slide heading may turn toward your input.
	-- It CURVES, it does not pivot — a slide you can spin on the spot is a slide
	-- that dodges bullets, and the whole trade is supposed to be that you cannot.
	turnRateDeg = 190,
	-- Camera roll, degrees, applied at PinkPanicSlideRoll in the render chain.
	rollDegrees = 7,
	rollInSeconds = 0.1,
	rollOutSeconds = 0.22,
}

-- The decay curve, hand-tunable: speed as a fraction of the entry speed, sampled
-- at even intervals from the start of the slide to `maxSeconds` and interpolated
-- between. Bump a number, feel the change — no formula to re-derive.
--
-- Every entry must be ≤ the one before it. `Movement.validate` enforces that: a
-- slide that speeds up partway through is the readability rule broken, and it
-- would be found by a player long before it was found by anyone reading this.
MovementConfig.slideCurve = { 1, 0.98, 0.9, 0.78, 0.62, 0.45, 0.3 }

-- ---------------------------------------------------------------------------
-- Dive (NOD-141)
--
-- The omnimovement signature move: an arc with real airtime, in any of the eight
-- directions. You are helpless in the air and you land prone — that is the
-- price, and it is what stops a dive from being a free reposition.
-- ---------------------------------------------------------------------------

MovementConfig.dive = {
	-- Horizontal launch, studs/s, before direction scaling. Clamped to
	-- `speed.Dive`.
	launchSpeed = 33,
	-- Apex of the arc above where you left the ground.
	heightStuds = 5.2,
	-- Flat on your face at the far end. You may start getting up the moment this
	-- expires; you may not act during it.
	recoverySeconds = 0.5,
	-- Diving into a wall costs more, because otherwise a wall is a free way to
	-- stop a dive short and skip the distance you were supposed to pay for.
	wallRecoveryBonus = 0.45,
	wallProbeStuds = 3.5,
	-- Airborne for at least this long before a landing counts, so leaving the
	-- ground and immediately re-touching it does not end the dive on frame one.
	minAirborneSeconds = 0.12,
	-- The other end of the same guard: if the jump was refused (a low ceiling, a
	-- Humanoid mid-state-change) the dive would wait forever for a landing that
	-- already happened. Comfortably longer than any real arc.
	maxAirSeconds = 2,
	cooldownSeconds = 0.9,
}

-- Per-direction arc tuning, same five angles as `directional`. Diving backwards
-- covers less ground than diving forwards, for the same reason sprinting
-- backwards does.
MovementConfig.diveDirectional = {
	forward = 1,
	diagonalForward = 0.94,
	strafe = 0.82,
	diagonalBack = 0.7,
	backward = 0.6,
}

-- ---------------------------------------------------------------------------
-- Mantle (NOD-141)
--
-- Auto-mantle: no key. If you jump at a ledge you can reach, you go over it.
-- A mantle key is a key people forget they have.
-- ---------------------------------------------------------------------------

MovementConfig.mantle = {
	-- How far in front of you a wall may be and still be mantled.
	reachStuds = 2.8,
	-- The height band, measured from the floor you left. Below the minimum it is
	-- a step and the Humanoid already walks up it; above the maximum it is a
	-- wall, and climbing walls is not a thing this game has.
	minHeightStuds = 2.4,
	maxHeightStuds = 7,
	-- How much flat top surface the ledge needs before it counts as somewhere to
	-- stand rather than an edge to clip through.
	ledgeDepthStuds = 1.5,
	-- Headroom above the landing. Without this you mantle into a pipe.
	clearanceStuds = 5,
	-- Steepest the top surface may be. Steeper than this is a roof, not a ledge.
	maxSlopeDegrees = 40,
	-- The traversal itself. Long enough to read as a movement, short enough that
	-- being uncontrollable does not feel like being frozen.
	durationSeconds = 0.34,
	cooldownSeconds = 0.45,
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
-- Which moves a room has. There is exactly one difference between them now, and
-- it is about the CAMERA rather than about the moves.
-- ---------------------------------------------------------------------------

export type ProfileName = "lobby" | "combat"

MovementConfig.profiles = {
	-- The lobby used to exclude slide, dive and mantle, on the grounds that its
	-- fixed hand-placed camera could not show an arc. That was a rule about the
	-- camera written as a rule about the moves, and it had a consequence nobody
	-- had priced in: there is no round loop until M9 and a round needs two
	-- players, so "not in the lobby" meant "nowhere", and all three would have
	-- shipped as code that has never once run. That is the exact failure this
	-- rebuild exists to stop — the old slide was in the codebase, compiled, and
	-- never fired, and nobody knew for days.
	--
	-- So the lobby has all of it, and the camera fixes the camera: the slide roll
	-- is skipped while the fixed lobby shot owns the CFrame, because rolling a
	-- pinned shot of the storefront row tilts the storefront, not the player.
	lobby = {
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

-- How often the trigger counts for slide, dive and mantle are printed. The old
-- slide was present, compiled, and never fired once, and nothing in the game
-- could tell the difference — so the counts say so out loud on a timer, and
-- "0, never fired" is a line you can read from across the room.
--
-- Only printed when a count has CHANGED, plus once at the first interval, so a
-- session where nobody moves says so exactly once and then goes quiet.
MovementConfig.moveReportSeconds = 90

return MovementConfig
