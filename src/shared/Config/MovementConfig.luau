--!strict
-- MovementConfig — sprint/slide/stamina tuning (NOD-100). All feel feedback
-- lands in this file.

return {
	baseWalkSpeed = 16,
	sprintWalkSpeed = 24, -- +50%
	fireRaiseDelay = 0.2, -- seconds after breaking sprint before you can shoot

	slideInitialSpeed = 32,
	slideEndSpeed = 16,
	slideDuration = 0.7,
	slideCooldown = 1.1,
	slideHipDrop = 0.9, -- lowered profile while sliding

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
