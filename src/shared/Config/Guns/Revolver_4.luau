--!strict
-- Smooch — the quick revolver.
return {
	name = "Smooch",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 2900,
	why = "Cycles fastest of the revolvers, so its three shots land in the window where Heartbreaker only manages two.",
	stats = {
		damageNear = 40, damageFar = 22, rangeNear = 38, rangeFar = 74,
		headshotMult = 1.65, rpm = 210, auto = false, magSize = 7, reloadSeconds = 2.1,
		spreadDeg = 1.5, adsSpreadDeg = 0.20,
		recoilVert = 0.78, recoilHoriz = 0.13, recoilRecovery = 13,
		velocity = 1290, drop = 34, moveSpeedMult = 1.02,
		equipTime = 0.29, sprintToFire = 0.12, adsTime = 0.21,
	},
}
