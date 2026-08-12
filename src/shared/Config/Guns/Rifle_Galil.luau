--!strict
-- Lunchbox (Galil) — thirty-five rounds, the biggest rifle magazine in the
-- game, and the slowest hands in the class. It cannot win a fight it did not
-- see coming; it can win three fights in a row without reloading.
return {
	name = "Lunchbox",
	archetype = "Galil",
	class = "Rifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2200,
	unlockLevel = 18,
	why = "Thirty-five rounds and the slowest handling of any rifle — it loses every fight it is surprised in and wins every one that lasts.",
	stats = {
		damageNear = 32, damageFar = 15, rangeNear = 36, rangeFar = 102,
		headshotMult = 1.5, rpm = 620, auto = true, magSize = 35, reloadSeconds = 2.6,
		spreadDeg = 1.7, adsSpreadDeg = 0.19,
		recoilVert = 0.43, recoilHoriz = 0.16, recoilRecovery = 11,
		velocity = 1700, drop = 38, moveSpeedMult = 0.97,
		equipTime = 0.44, sprintToFire = 0.18, adsTime = 0.29,
	},
}
