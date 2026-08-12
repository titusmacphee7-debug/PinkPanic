--!strict
-- Grump — the default answer. If you do not know what to bring, bring this.
return {
	name = "Grump",
	class = "Rifle",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	why = "The rifle with no bad range: five shots from 0 to 48 studs and six beyond, so you are never holding the wrong gun.",
	stats = {
		damageNear = 24, damageFar = 17, rangeNear = 48, rangeFar = 92,
		headshotMult = 1.5, rpm = 660, auto = true, magSize = 30, reloadSeconds = 2.2,
		spreadDeg = 1.6, adsSpreadDeg = 0.20,
		recoilVert = 0.42, recoilHoriz = 0.14, recoilRecovery = 12,
		velocity = 1450, drop = 32, moveSpeedMult = 1.00,
		equipTime = 0.40, sprintToFire = 0.15, adsTime = 0.26,
	},
}
