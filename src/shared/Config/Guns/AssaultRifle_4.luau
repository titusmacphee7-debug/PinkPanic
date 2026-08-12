--!strict
-- Picnic Punch — the four-shot rifle. Slow, heavy, and it ends fights early.
return {
	name = "Picnic Punch",
	class = "Rifle",
	slot = "Primary",
	rarity = "Epic",
	price = 8100,
	why = "The only rifle that kills in four, so it beats every other AR in a straight trade and punishes you hardest for missing one.",
	stats = {
		damageNear = 27, damageFar = 19, rangeNear = 52, rangeFar = 98,
		headshotMult = 1.5, rpm = 560, auto = true, magSize = 24, reloadSeconds = 2.4,
		spreadDeg = 1.6, adsSpreadDeg = 0.19,
		recoilVert = 0.55, recoilHoriz = 0.16, recoilRecovery = 11,
		velocity = 1530, drop = 30, moveSpeedMult = 0.99,
		equipTime = 0.44, sprintToFire = 0.17, adsTime = 0.29,
	},
}
