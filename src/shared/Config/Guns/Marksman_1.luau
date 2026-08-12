--!strict
-- Locket — the fast marksman. Three shots, quickest cycle in the class.
return {
	name = "Locket",
	class = "Marksman",
	slot = "Primary",
	rarity = "Uncommon",
	price = 4400,
	why = "Cycles fast enough to correct a miss, which no other marksman does, at the cost of needing three hits instead of two.",
	stats = {
		damageNear = 38, damageFar = 33, rangeNear = 105, rangeFar = 195,
		headshotMult = 1.65, rpm = 300, auto = false, magSize = 12, reloadSeconds = 2.3,
		spreadDeg = 2.2, adsSpreadDeg = 0.11,
		recoilVert = 0.72, recoilHoriz = 0.13, recoilRecovery = 12,
		velocity = 1950, drop = 23, moveSpeedMult = 0.96,
		equipTime = 0.52, sprintToFire = 0.24, adsTime = 0.34,
	},
}
