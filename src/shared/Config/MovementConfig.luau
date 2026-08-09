--!strict
-- MovementConfig — sprint/slide/momentum/stamina tuning (NOD-100). All feel
-- feedback lands in this file.

return {
	baseWalkSpeed = 20,
	sprintWalkSpeed = 30, -- +50%
	fireRaiseDelay = 0.25, -- fallback sprint-to-fire; weapons override per-config

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
