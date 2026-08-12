--!strict
-- Drama Queen — the two-shot revolver, and the hardest-hitting secondary.
-- Deliberately the slowest cycle in the game for a sidearm: two shots at
-- 130rpm is 0.46s, which still loses to every primary in the roster.
return {
	name = "Drama Queen",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Legendary",
	price = 9800,
	why = "The only sidearm that kills in two, on the slowest trigger in the game — land both or lose the fight.",
	stats = {
		damageNear = 52, damageFar = 28, rangeNear = 46, rangeFar = 86,
		headshotMult = 1.8, rpm = 130, auto = false, magSize = 5, reloadSeconds = 2.5,
		spreadDeg = 1.6, adsSpreadDeg = 0.16,
		recoilVert = 1.15, recoilHoriz = 0.16, recoilRecovery = 10,
		velocity = 1420, drop = 31, moveSpeedMult = 0.99,
		equipTime = 0.36, sprintToFire = 0.17, adsTime = 0.27,
	},
}
