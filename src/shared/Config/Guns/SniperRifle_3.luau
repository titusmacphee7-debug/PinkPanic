--!strict
-- Scout's Honor — marksman. Was filed as a sniper; it never one-shot anything.
return {
	name = "Scout's Honor",
	class = "Marksman",
	slot = "Primary",
	rarity = "Rare",
	price = 7600,
	why = "The heaviest three-shot: it holds full damage 120 studs out, further than any automatic keeps its own shot count.",
	stats = {
		damageNear = 44, damageFar = 38, rangeNear = 120, rangeFar = 220,
		headshotMult = 1.7, rpm = 260, auto = false, magSize = 10, reloadSeconds = 2.6,
		spreadDeg = 2.4, adsSpreadDeg = 0.09,
		recoilVert = 0.95, recoilHoriz = 0.14, recoilRecovery = 11,
		velocity = 2050, drop = 21, moveSpeedMult = 0.95,
		equipTime = 0.56, sprintToFire = 0.28, adsTime = 0.38,
	},
}
