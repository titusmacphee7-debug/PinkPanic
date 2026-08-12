--!strict
-- Heartbreaker — the baseline revolver.
return {
	name = "Heartbreaker",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 2400,
	why = "Three heavy shots to 40 studs, for players who would rather land fewer than spray more.",
	stats = {
		damageNear = 45, damageFar = 24, rangeNear = 40, rangeFar = 78,
		headshotMult = 1.7, rpm = 190, auto = false, magSize = 6, reloadSeconds = 2.2,
		spreadDeg = 1.4, adsSpreadDeg = 0.18,
		recoilVert = 0.88, recoilHoriz = 0.14, recoilRecovery = 12,
		velocity = 1320, drop = 33, moveSpeedMult = 1.01,
		equipTime = 0.30, sprintToFire = 0.13, adsTime = 0.22,
	},
}
