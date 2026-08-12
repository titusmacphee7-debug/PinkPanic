--!strict
-- Chatterbox — the baseline SMG. Everything else in the class is a trade
-- against this one.
return {
	name = "Chatterbox",
	class = "SMG",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	why = "The SMG with no weakness inside 20 studs — pick it when you do not yet know which room you are walking into.",
	stats = {
		damageNear = 21, damageFar = 11, rangeNear = 20, rangeFar = 55,
		headshotMult = 1.4, rpm = 900, auto = true, magSize = 30, reloadSeconds = 1.9,
		spreadDeg = 2.1, adsSpreadDeg = 0.25,
		recoilVert = 0.26, recoilHoriz = 0.16, recoilRecovery = 16,
		velocity = 980, drop = 40, moveSpeedMult = 1.07,
		equipTime = 0.30, sprintToFire = 0.09, adsTime = 0.18,
	},
}
