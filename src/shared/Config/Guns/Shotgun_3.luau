--!strict
-- Homemaker — the wide one. Ten pellets, so it is the most forgiving aim in
-- the game and the fastest to fall apart at range.
return {
	name = "Homemaker",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Uncommon",
	price = 3400,
	why = "Ten pellets in the widest cone: the shotgun that still connects when you are panicking, and the one with the shortest reach.",
	stats = {
		damageNear = 11, damageFar = 3, rangeNear = 11, rangeFar = 24, pellets = 10,
		headshotMult = 1.2, rpm = 70, auto = false, magSize = 5, reloadSeconds = 0.6,
		shellReload = 1,
		spreadDeg = 9.0, adsSpreadDeg = 5.6,
		recoilVert = 1.25, recoilHoriz = 0.34, recoilRecovery = 10,
		velocity = 820, drop = 50, moveSpeedMult = 1.03,
		equipTime = 0.38, sprintToFire = 0.13, adsTime = 0.25,
	},
}
