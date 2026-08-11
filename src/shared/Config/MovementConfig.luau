--!strict
-- MovementConfig — the whole feel of the game in one file (NOD-100).
--
-- Pink Panic does NOT use Humanoid movement. The Humanoid's mover has no
-- acceleration curve, no friction and no air model: direction changes are
-- instant snaps and stops are instant brakes, which is exactly the "clunky
-- Roblox shooter" signature. We set WalkSpeed = 0 and drive the root's
-- horizontal velocity ourselves through a Source-derived accelerate/friction
-- model, leaving the Y axis to gravity so jumps and falls stay stock.
--
-- The numbers below are in studs and seconds. Feel feedback lands here.

return {
	-- -----------------------------------------------------------------------
	-- Speed ladder — the target speed the accel model chases.
	-- -----------------------------------------------------------------------
	baseWalkSpeed = 20,
	sprintWalkSpeed = 30, -- +50%
	fireRaiseDelay = 0.25, -- fallback sprint-to-fire; weapons override per-config

	-- -----------------------------------------------------------------------
	-- Ground acceleration. This is the single most important pair of numbers
	-- in the game.
	--
	-- `groundAccel` is how hard you chase the target speed, in target-speeds
	-- per second: 12 means you reach walk pace in about 1/12 of a second of
	-- input, which reads as instant to the hand but still has a ramp for the
	-- animation and camera to hang off. Raise it for snappier, lower it for
	-- heavier.
	--
	-- `groundFriction` is the same curve running backwards when you let go.
	-- This REPLACES the old skid system outright — releasing the keys now
	-- glides you down instead of the engine's instant brake, and it does so
	-- through the same code path that accelerates you, so there is no
	-- "skidding" state to get stuck in.
	-- -----------------------------------------------------------------------
	groundAccel = 12,
	groundFriction = 8,
	stopSpeed = 7, -- below this, friction is constant rather than proportional,
	-- so the last few studs/s die cleanly instead of asymptoting

	-- -----------------------------------------------------------------------
	-- Air control. Two separate terms, deliberately.
	--
	-- `airTurnRate` is steering authority: radians per second that your
	-- existing velocity can be rotated toward the stick, at NO cost to speed.
	-- This is what makes you feel in control in the air. 5.2 rad/s is a little
	-- under a full turn per second — generous, modern, Rivals/Apex-like.
	--
	-- `airAccel` + `airWishCap` is the classic strafe-jump term: it can only
	-- chase `airWishCap` studs/s, so holding W in the air does almost nothing,
	-- but turning the mouse while holding a strafe key keeps the input vector
	-- just off your velocity and lets this term add speed every frame. That's
	-- the skill ceiling. Low cap = you must strafe properly to gain.
	--
	-- Splitting them is the whole trick: steering is free and generous so new
	-- players never feel stuck, while going FASTER still has to be earned.
	-- -----------------------------------------------------------------------
	airTurnRate = 5.2,
	airAccel = 2.4,
	airWishCap = 7,

	-- -----------------------------------------------------------------------
	-- Jump. `jumpApex` is the real apparent peak in studs, measured against
	-- the reduced airborne gravity below — set the height you want and the
	-- launch velocity is derived, so changing float doesn't silently change
	-- how high you go.
	-- -----------------------------------------------------------------------
	jumpApex = 7.8,
	jumpGravityScale = 0.58, -- character gravity while airborne (lower = floatier)

	-- Forgiveness. Both of these are pure "you are always in control" and cost
	-- nothing: coyote lets you jump just after walking off an edge, buffer
	-- lets you press jump just before you land and still get it.
	coyoteTime = 0.12,
	jumpBuffer = 0.14,

	-- -----------------------------------------------------------------------
	-- Crouch: hold C/Ctrl while not sprinting (a slide melts into a crouch
	-- if you keep the key held). Tighter spread and calmer recoil while down.
	-- -----------------------------------------------------------------------
	crouchSpeedMult = 0.55,
	crouchHipDrop = 0.55,
	crouchCameraDrop = 0.9,

	-- ADS: aiming slows the walk and gently zooms (per-class zoom lives in
	-- WeaponController).
	adsWalkMult = 0.62,

	-- -----------------------------------------------------------------------
	-- Slide. Steerable: the direction turns toward your input instead of
	-- locking at entry, so a slide is a move you drive rather than a
	-- commitment you regret. Turn authority falls off with speed, so fast
	-- slides carve wide arcs and slow ones pivot tight.
	-- -----------------------------------------------------------------------
	slideInitialSpeed = 44,
	slideEndSpeed = 27,
	slideDuration = 1.25,
	slideDecayRate = 2.1, -- exponential glide on flat ground: high = grippy, low = ice
	slideCooldown = 1.1,
	slideTurnRate = 2.6, -- rad/s of steering at slideTurnRefSpeed
	slideTurnRefSpeed = 44, -- turn rate scales inversely with speed past this
	slideHipDrop = 0.9, -- lowered profile while sliding
	slideCameraDrop = 1.5, -- first-person camera sinks low to the ground
	slideCameraRoll = 0.09, -- radians of camera cant while sliding

	-- -----------------------------------------------------------------------
	-- Momentum. With a real velocity model, momentum IS velocity — ground
	-- friction is the only thing that takes it away, so there is no separate
	-- pool to keep in sync any more. What's left is the stuff friction can't
	-- express on its own.
	-- -----------------------------------------------------------------------
	momentumHardCap = 62,
	rampAccel = 34, -- speed gained per second per unit of downhill steepness
	rampSlideExtend = 0.35, -- sliding downhill keeps extending the slide
	fallSpeedGain = 2.5, -- horizontal speed gained per second while falling
	bhopWindow = 0.22, -- jump within this of landing and friction never applies,
	-- which is what preserves a hop chain
	bhopRetention = 0.97, -- speed kept per hop (a whisper of tax)

	staminaMax = 150,
	sprintDrainPerSecond = 3,
	slideCost = 12,
	regenPerSecond = 40,
	regenDelay = 0.2, -- pause after spending before regen kicks in
	minSprintStamina = 2,

	-- Combat-only FOV feel (the lobby camera owns its own framing).
	fovBase = 70,
	fovSprint = 74,
	fovSlide = 82,
}
