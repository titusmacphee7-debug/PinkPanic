--!strict
-- GameConfig — round-loop rules (M2). One place to tune the match.

return {
	minPlayers = 2,
	intermissionSeconds = 10,
	roundSeconds = 180,
	roundEndSeconds = 8,
	scoreTarget = 10,
	-- Every carried weapon, in hotbar order (keys 1..n). Also the valid set
	-- for the starting-weapon loadout choice.
	loadout = { "Pistol", "Rifle", "Shotgun", "Knife" },
}
