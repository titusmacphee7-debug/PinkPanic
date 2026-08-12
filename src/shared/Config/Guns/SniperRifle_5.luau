--!strict
-- Heartstopper — the quick-scope sniper. Fastest cycle and handling of the
-- heavies, shortest full-damage window to pay for it.
return {
	name = "Heartstopper",
	class = "Sniper",
	slot = "Primary",
	rarity = "Legendary",
	price = 14500,
	why = "The only sniper that can take a second shot inside a second, traded against the shortest one-shot window of the three.",
	stats = {
		damageNear = 102, damageFar = 86, rangeNear = 175, rangeFar = 350,
		headshotMult = 1.5, rpm = 55, auto = false, magSize = 6, reloadSeconds = 2.9,
		spreadDeg = 5.2, adsSpreadDeg = 0.07,
		recoilVert = 1.58, recoilHoriz = 0.22, recoilRecovery = 10,
		velocity = 2320, drop = 18, moveSpeedMult = 0.93,
		equipTime = 0.64, sprintToFire = 0.34, adsTime = 0.50,
	},
}
