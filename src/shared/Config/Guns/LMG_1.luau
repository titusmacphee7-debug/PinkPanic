--!strict
-- Big Sister — the baseline LMG. A rifle that never has to stop.
return {
	name = "Big Sister",
	class = "LMG",
	slot = "Primary",
	rarity = "Rare",
	price = 6800,
	why = "A hundred rounds of rifle damage without a reload, so it wins any fight that lasts longer than one magazine.",
	stats = {
		damageNear = 24, damageFar = 17, rangeNear = 58, rangeFar = 112,
		headshotMult = 1.45, rpm = 600, auto = true, magSize = 100, reloadSeconds = 4.6,
		spreadDeg = 2.6, adsSpreadDeg = 0.24,
		recoilVert = 0.58, recoilHoriz = 0.22, recoilRecovery = 9,
		velocity = 1560, drop = 29, moveSpeedMult = 0.92,
		equipTime = 0.66, sprintToFire = 0.28, adsTime = 0.40,
	},
}
