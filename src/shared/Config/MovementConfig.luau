--!strict
-- MovementConfig — sprint/slide/stamina tuning (NOD-100). All feel feedback
-- lands in this file.

return {
	baseWalkSpeed = 20,
	sprintWalkSpeed = 30, -- +50%
	fireRaiseDelay = 0.25, -- fallback sprint-to-fire; weapons override per-config

	slideInitialSpeed = 44,
	slideEndSpeed = 27,
	slideDuration = 1.25,
	slideDecayRate = 2.1, -- exponential glide: high = grippy, low = ice
	slideCooldown = 1.1,
	slideHipDrop = 0.9, -- lowered profile while sliding
	slideCameraDrop = 1.5, -- first-person camera sinks low to the ground
	slideCameraRoll = 0.09, -- radians of camera cant while sliding
	postSlideGlideWindow = 0.45, -- momentum blends out instead of snapping

	-- Slide-jump chains: boosted ground speed for a short window after
	-- jumping out of a slide, so slide->jump->slide flows.
	chainWalkSpeed = 34,
	chainWindow = 1.0,

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
