--!strict
-- Jitterbug — the fastest kill in the game, on a five-shot magazine tax.
return {
	name = "Jitterbug",
	class = "SMG",
	slot = "Primary",
	rarity = "Epic",
	price = 7400,
	why = "The quickest close-range kill anywhere at 0.25s, bought with the smallest magazine in the class and a cone you cannot hipfire past 15 studs.",
	stats = {
		damageNear = 20, damageFar = 10, rangeNear = 19, rangeFar = 52,
		headshotMult = 1.45, rpm = 950, auto = true, magSize = 25, reloadSeconds = 1.95,
		spreadDeg = 2.3, adsSpreadDeg = 0.26,
		recoilVert = 0.25, recoilHoriz = 0.18, recoilRecovery = 16,
		velocity = 970, drop = 40, moveSpeedMult = 1.07,
		equipTime = 0.29, sprintToFire = 0.09, adsTime = 0.17,
	},
}
