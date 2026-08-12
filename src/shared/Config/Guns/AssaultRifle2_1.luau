--!strict
-- Sweet Talker — the light rifle. Was a Carbine; the class was never a real one.
return {
	name = "Sweet Talker",
	class = "Rifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 3100,
	why = "Handles almost like an SMG and still kills in five at 40 studs, for a rifle that stops working soonest past that.",
	stats = {
		damageNear = 22, damageFar = 15, rangeNear = 40, rangeFar = 84,
		headshotMult = 1.5, rpm = 750, auto = true, magSize = 28, reloadSeconds = 2.0,
		spreadDeg = 1.8, adsSpreadDeg = 0.22,
		recoilVert = 0.34, recoilHoriz = 0.15, recoilRecovery = 14,
		velocity = 1380, drop = 34, moveSpeedMult = 1.02,
		equipTime = 0.35, sprintToFire = 0.13, adsTime = 0.23,
	},
}
