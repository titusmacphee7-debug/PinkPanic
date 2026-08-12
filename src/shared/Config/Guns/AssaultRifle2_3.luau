--!strict
-- Sprinkler — the magazine rifle. Longest sustained burst before a reload.
return {
	name = "Sprinkler",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 5600,
	why = "Forty rounds in the magazine, so it is the rifle that wins the second and third fight without stopping to reload.",
	stats = {
		damageNear = 23, damageFar = 16, rangeNear = 42, rangeFar = 86,
		headshotMult = 1.5, rpm = 700, auto = true, magSize = 40, reloadSeconds = 2.6,
		spreadDeg = 1.7, adsSpreadDeg = 0.21,
		recoilVert = 0.37, recoilHoriz = 0.15, recoilRecovery = 13,
		velocity = 1410, drop = 33, moveSpeedMult = 0.99,
		equipTime = 0.42, sprintToFire = 0.16, adsTime = 0.27,
	},
}
