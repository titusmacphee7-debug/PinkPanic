--!strict
-- Scrunchie — the pump with a stock. Two shells, but the fastest pump and the
-- steadiest cone of the class.
return {
	name = "Scrunchie",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Rare",
	price = 4900,
	why = "Two shells and the tightest shotgun cone, so it is the one that still works at 13 studs when the others have thinned out.",
	stats = {
		damageNear = 13, damageFar = 4, rangeNear = 13, rangeFar = 27, pellets = 7,
		headshotMult = 1.3, rpm = 200, auto = false, magSize = 7, reloadSeconds = 0.5,
		shellReload = 1,
		spreadDeg = 6.4, adsSpreadDeg = 3.6,
		recoilVert = 1.0, recoilHoriz = 0.28, recoilRecovery = 12,
		velocity = 880, drop = 47, moveSpeedMult = 1.04,
		equipTime = 0.35, sprintToFire = 0.12, adsTime = 0.22,
	},
}
