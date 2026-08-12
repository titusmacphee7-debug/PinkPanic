--!strict
-- Giggle 36 (G36C) — the aggressive rifle. Fastest to the shoulder and fastest
-- out of a sprint of anything in the class, and the shortest reach to pay for
-- it. This is the rifle you bring if you intend to be the one entering rooms.
return {
	name = "Giggle 36",
	archetype = "G36C",
	class = "Rifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 1200,
	unlockLevel = 6,
	why = "Up and firing quicker than any other rifle, and the first to fall apart past 45 ft — the rifle that wants you moving toward people.",
	stats = {
		damageNear = 31, damageFar = 13, rangeNear = 28, rangeFar = 92,
		headshotMult = 1.5, rpm = 720, auto = true, magSize = 30, reloadSeconds = 2.0,
		spreadDeg = 1.6, adsSpreadDeg = 0.20,
		recoilVert = 0.35, recoilHoriz = 0.15, recoilRecovery = 13,
		velocity = 1820, drop = 32, moveSpeedMult = 1.00,
		equipTime = 0.36, sprintToFire = 0.13, adsTime = 0.22,
	},
}
