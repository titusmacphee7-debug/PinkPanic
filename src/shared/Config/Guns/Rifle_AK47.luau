--!strict
-- cAKe-47 (AK-47) — the four-shot kill, and the only rifle that holds full
-- damage out to 43 ft. Pays for both with the hardest climb in the game and the
-- slowest rifle cadence, so a missed shot costs more here than anywhere else.
return {
	name = "cAKe-47",
	archetype = "AK-47",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 4200,
	unlockLevel = 36,
	why = "Four shots to kill and full damage all the way to 43 ft — the hardest-hitting rifle, held back by the worst recoil and the slowest fire rate in the class.",
	stats = {
		damageNear = 39, damageFar = 19, rangeNear = 40, rangeFar = 105,
		headshotMult = 1.5, rpm = 560, auto = true, magSize = 30, reloadSeconds = 2.4,
		spreadDeg = 1.9, adsSpreadDeg = 0.22,
		recoilVert = 0.52, recoilHoriz = 0.19, recoilRecovery = 10,
		velocity = 1650, drop = 42, moveSpeedMult = 0.99,
		equipTime = 0.44, sprintToFire = 0.18, adsTime = 0.28,
	},
}
