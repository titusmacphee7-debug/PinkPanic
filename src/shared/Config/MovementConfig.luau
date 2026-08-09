--!strict
-- MovementConfig — sprint/slide/stamina tuning (NOD-100). All feel feedback
-- lands in this file.

return {
	baseWalkSpeed = 16,
	sprintWalkSpeed = 24, -- +50%
	fireRaiseDelay = 0.25, -- fallback sprint-to-fire; weapons override per-config

	slideInitialSpeed = 34,
	slideEndSpeed = 20,
	slideDuration = 0.95,
	slideDecayRate = 3.2, -- exponential glide: high = grippy, low = ice
	slideCooldown = 1.1,
	slideHipDrop = 0.9, -- lowered profile while sliding
	slideCameraDrop = 1.5, -- first-person camera sinks low to the ground
	slideCameraRoll = 0.09, -- radians of camera cant while sliding
	postSlideGlideWindow = 0.3, -- momentum blends out instead of snapping

	-- Slide-jump chains: boosted ground speed for a short window after
	-- jumping out of a slide, so slide->jump->slide flows.
	chainWalkSpeed = 26,
	chainWindow = 0.9,

	staminaMax = 100,
	sprintDrainPerSecond = 10,
	slideCost = 25,
	regenPerSecond = 18,
	regenDelay = 0.4, -- pause after spending before regen kicks in
	minSprintStamina = 5,

	-- Combat-only FOV feel (the lobby camera owns its own framing).
	fovBase = 70,
	fovSprint = 74,
	fovSlide = 78,
}
