--!strict
-- Toastie — the long battle rifle. The most reach that still fires automatic.
return {
	name = "Toastie",
	class = "BattleRifle",
	slot = "Primary",
	rarity = "Epic",
	price = 9200,
	why = "The furthest-reaching automatic in the game and the slowest to bring up; it owns the lane it is already pointed down.",
	stats = {
		damageNear = 28, damageFar = 21, rangeNear = 66, rangeFar = 132,
		headshotMult = 1.6, rpm = 450, auto = true, magSize = 20, reloadSeconds = 2.6,
		spreadDeg = 1.4, adsSpreadDeg = 0.13,
		recoilVert = 0.68, recoilHoriz = 0.19, recoilRecovery = 10,
		velocity = 1780, drop = 25, moveSpeedMult = 0.96,
		equipTime = 0.52, sprintToFire = 0.22, adsTime = 0.34,
	},
}
