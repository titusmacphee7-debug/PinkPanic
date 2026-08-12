--!strict
-- Cherry Bomb — the accurate rifle. Slowest of the five-shot ARs, tightest cone.
return {
	name = "Cherry Bomb",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 5200,
	why = "The tightest aimed cone of any automatic, which is what makes its five shots land at 60 studs when a faster rifle's do not.",
	stats = {
		damageNear = 24, damageFar = 17, rangeNear = 50, rangeFar = 95,
		headshotMult = 1.55, rpm = 620, auto = true, magSize = 30, reloadSeconds = 2.25,
		spreadDeg = 1.4, adsSpreadDeg = 0.16,
		recoilVert = 0.44, recoilHoriz = 0.12, recoilRecovery = 12,
		velocity = 1500, drop = 31, moveSpeedMult = 1.00,
		equipTime = 0.41, sprintToFire = 0.15, adsTime = 0.27,
	},
}
