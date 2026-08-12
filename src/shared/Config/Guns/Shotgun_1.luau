--!strict
-- Big Boop — the baseline shotgun. 8 x 13 = 104: a chest is one shot, a limb
-- is 93.6 and is not.
return {
	name = "Big Boop",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Common",
	price = 1800,
	why = "One shot to the chest inside 12 studs and nothing at all past 41, so it decides a room instantly and cannot leave it.",
	stats = {
		damageNear = 13, damageFar = 4, rangeNear = 12, rangeFar = 26, pellets = 8,
		headshotMult = 1.25, rpm = 75, auto = false, magSize = 6, reloadSeconds = 0.55,
		shellReload = 1,
		spreadDeg = 7.5, adsSpreadDeg = 4.4,
		recoilVert = 1.15, recoilHoriz = 0.30, recoilRecovery = 10,
		velocity = 860, drop = 48, moveSpeedMult = 1.03,
		equipTime = 0.36, sprintToFire = 0.12, adsTime = 0.23,
	},
}
