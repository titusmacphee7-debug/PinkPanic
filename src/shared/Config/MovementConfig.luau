--!strict
-- MovementConfig — sprint/slide/momentum/stamina tuning (NOD-100). All feel
-- feedback lands in this file.

return {
	baseWalkSpeed = 20,
	sprintWalkSpeed = 30, -- +50%
	fireRaiseDelay = 0.25, -- fallback sprint-to-fire; weapons override per-config

	-- Jump: higher and floatier than stock Roblox, and it carries your speed.
	jumpHeight = 9.5, -- stock is ~6.4 studs
	jumpGravityScale = 0.76, -- character gravity while airborne (lower = floatier)

	-- Friction: releasing the keys skids you to a stop instead of the
	-- engine's instant brake.
	skidFriction = 45, -- studs/s^2 bled while skidding (matches momentum decay)
	skidMinSpeed = 12, -- skids only start above this speed
	skidStopSpeed = 6, -- control snaps back below this

	-- Crouch: hold C/Ctrl while not sprinting (a slide melts into a crouch
	-- if you keep the key held). Tighter spread and calmer recoil while down.
	crouchSpeedMult = 0.55,
	crouchHipDrop = 0.55,
	crouchCameraDrop = 0.9,

	-- ADS: aiming slows the walk and gently zooms (per-class zoom lives in
	-- WeaponController).
	adsWalkMult = 0.62,

	slideInitialSpeed = 44,
	slideEndSpeed = 27,
	slideDuration = 1.25,
	slideDecayRate = 2.1, -- exponential glide on flat ground: high = grippy, low = ice
	slideCooldown = 1.1,
	slideHipDrop = 0.9, -- lowered profile while sliding
	slideCameraDrop = 1.5, -- first-person camera sinks low to the ground
	slideCameraRoll = 0.09, -- radians of camera cant while sliding

	-- Momentum: the shared speed pool that slides build, ramps feed, falling
	-- trickles into, the air carries at full steering authority, and bunny
	-- hops preserve. Grounded without hopping, it drains back to normal.
	momentumHardCap = 62,
	rampAccel = 34, -- speed gained per second per unit of downhill steepness
	rampSlideExtend = 0.35, -- sliding downhill keeps extending the slide
	fallSpeedGain = 2.5, -- horizontal speed gained per second while falling
	bhopWindow = 0.22, -- jump within this after landing to keep momentum
	bhopRetention = 0.97, -- momentum kept per hop (a whisper of tax)
	groundMomentumDecay = 45, -- momentum lost per second grounded past the window

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
