--!strict
-- Stiletto — the accurate pistol.
return {
	name = "Stiletto",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 1600,
	why = "The tightest sidearm cone and the longest full-damage window, for finishing someone at a distance Pip cannot.",
	stats = {
		damageNear = 27, damageFar = 14, rangeNear = 32, rangeFar = 64,
		headshotMult = 1.65, rpm = 360, auto = false, magSize = 10, reloadSeconds = 1.6,
		spreadDeg = 1.1, adsSpreadDeg = 0.20,
		recoilVert = 0.42, recoilHoriz = 0.09, recoilRecovery = 15,
		velocity = 1200, drop = 35, moveSpeedMult = 1.03,
		equipTime = 0.24, sprintToFire = 0.10, adsTime = 0.17,
	},
}
