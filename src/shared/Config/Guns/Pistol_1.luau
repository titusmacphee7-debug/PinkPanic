--!strict
-- Pip — the starter pistol and the honest baseline for the class.
return {
	name = "Pip",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Common",
	price = 0,
	why = "Four shots at 0.45s: the fastest fallback that still cannot beat a primary, which is exactly what a sidearm should be.",
	stats = {
		damageNear = 25, damageFar = 13, rangeNear = 30, rangeFar = 60,
		headshotMult = 1.6, rpm = 400, auto = false, magSize = 12, reloadSeconds = 1.5,
		spreadDeg = 1.4, adsSpreadDeg = 0.26,
		recoilVert = 0.38, recoilHoriz = 0.10, recoilRecovery = 15,
		velocity = 1150, drop = 36, moveSpeedMult = 1.04,
		equipTime = 0.22, sprintToFire = 0.09, adsTime = 0.16,
	},
}
