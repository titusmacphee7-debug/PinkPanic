--!strict
-- Dessert Eagle (Desert Eagle) — three shots, and the longest reach of any
-- sidearm in the game. The recoil is the worst thing about any pistol here by a
-- wide margin, which is the only reason a three-shot secondary is allowed to
-- exist at all.
return {
	name = "Dessert Eagle",
	archetype = "Desert Eagle",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Rare",
	price = 4400,
	unlockLevel = 34,
	why = "Three shots to kill and 112 ft of reach — a sidearm that can genuinely answer a rifle, held back by the hardest recoil of anything you can hold in one hand.",
	stats = {
		-- rangeFar 66 not 70: travelMax is rangeFar x 1.6, and anything at or past
		-- 68.75 leaves the bullet alive at the 110-stud band, where the Pistol
		-- class is required to be dead.
		damageNear = 50, damageFar = 26, rangeNear = 30, rangeFar = 66,
		headshotMult = 1.5, rpm = 260, auto = false, magSize = 7, reloadSeconds = 2.3,
		spreadDeg = 2.4, adsSpreadDeg = 0.30,
		recoilVert = 0.95, recoilHoriz = 0.28, recoilRecovery = 11,
		-- walk 16.8, sprint 24.0
		velocity = 1450, drop = 40, moveSpeedMult = 0.99, sprintSpeedMult = 1.00,
		equipTime = 0.30, sprintToFire = 0.11, adsTime = 0.22,
	},
}
