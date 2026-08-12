--!strict
-- Pixie — the machine pistol end of the class.
return {
	name = "Pixie",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Rare",
	price = 3200,
	why = "Fires fastest of any sidearm, so it is the one that can actually finish a wounded runner before they turn a corner.",
	stats = {
		damageNear = 20, damageFar = 11, rangeNear = 25, rangeFar = 52,
		headshotMult = 1.55, rpm = 480, auto = false, magSize = 15, reloadSeconds = 1.45,
		spreadDeg = 1.8, adsSpreadDeg = 0.32,
		recoilVert = 0.30, recoilHoriz = 0.12, recoilRecovery = 16,
		velocity = 1080, drop = 38, moveSpeedMult = 1.05,
		equipTime = 0.20, sprintToFire = 0.08, adsTime = 0.14,
	},
}
