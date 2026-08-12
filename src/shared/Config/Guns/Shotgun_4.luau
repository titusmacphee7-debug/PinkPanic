--!strict
-- Double Trouble — the two-shot shotgun. Fewer, harder pellets and a fast
-- enough cycle that the second shell is part of the plan.
return {
	name = "Double Trouble",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Rare",
	price = 5400,
	why = "Six tight pellets that need two shells but reach 14 studs, for corridors a one-shot shotgun cannot cover.",
	stats = {
		damageNear = 15, damageFar = 5, rangeNear = 14, rangeFar = 28, pellets = 6,
		headshotMult = 1.3, rpm = 180, auto = false, magSize = 8, reloadSeconds = 0.5,
		shellReload = 1,
		spreadDeg = 5.8, adsSpreadDeg = 3.2,
		recoilVert = 0.92, recoilHoriz = 0.26, recoilRecovery = 12,
		velocity = 900, drop = 46, moveSpeedMult = 1.04,
		equipTime = 0.34, sprintToFire = 0.11, adsTime = 0.21,
	},
}
