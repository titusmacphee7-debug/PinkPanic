--!strict
-- Slumber Party — the accurate LMG. Smallest belt, tightest cone.
return {
	name = "Slumber Party",
	class = "LMG",
	slot = "Primary",
	rarity = "Rare",
	price = 7200,
	why = "The only LMG you can aim: a rifle's cone on an eighty-round belt, for holding an angle rather than spraying one.",
	stats = {
		damageNear = 24, damageFar = 18, rangeNear = 62, rangeFar = 118,
		headshotMult = 1.5, rpm = 550, auto = true, magSize = 80, reloadSeconds = 4.2,
		spreadDeg = 2.2, adsSpreadDeg = 0.18,
		recoilVert = 0.64, recoilHoriz = 0.19, recoilRecovery = 10,
		velocity = 1620, drop = 28, moveSpeedMult = 0.93,
		equipTime = 0.62, sprintToFire = 0.26, adsTime = 0.38,
	},
}
