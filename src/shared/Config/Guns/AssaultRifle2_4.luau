--!strict
-- Chunky — the slow rifle that reaches. The bridge to the battle rifles.
return {
	name = "Chunky",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 6000,
	why = "Keeps full damage to 50 studs and still fires automatic, for when a battle rifle would reach far enough but cycle too slowly.",
	stats = {
		damageNear = 24, damageFar = 18, rangeNear = 50, rangeFar = 94,
		headshotMult = 1.5, rpm = 600, auto = true, magSize = 30, reloadSeconds = 2.35,
		spreadDeg = 1.5, adsSpreadDeg = 0.18,
		recoilVert = 0.48, recoilHoriz = 0.13, recoilRecovery = 11,
		velocity = 1520, drop = 30, moveSpeedMult = 0.98,
		equipTime = 0.43, sprintToFire = 0.16, adsTime = 0.28,
	},
}
