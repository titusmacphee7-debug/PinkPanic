--!strict
-- Dolly — the fastest hands in the game.
return {
	name = "Dolly",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Common",
	price = 500,
	why = "The quickest draw and reload anywhere; it is the sidearm you swap to instead of reloading, and it kills slowest to pay for that.",
	stats = {
		damageNear = 22, damageFar = 12, rangeNear = 27, rangeFar = 55,
		headshotMult = 1.55, rpm = 440, auto = false, magSize = 14, reloadSeconds = 1.25,
		spreadDeg = 1.6, adsSpreadDeg = 0.30,
		recoilVert = 0.32, recoilHoriz = 0.11, recoilRecovery = 16,
		velocity = 1120, drop = 37, moveSpeedMult = 1.06,
		equipTime = 0.18, sprintToFire = 0.07, adsTime = 0.13,
	},
}
