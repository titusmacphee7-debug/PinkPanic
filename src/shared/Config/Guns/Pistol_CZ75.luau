--!strict
-- Cozy 75 (CZ-75) — the accurate one. Tightest cone and calmest climb of the
-- five, sixteen rounds, and full damage further out than any other pistol. The
-- sidearm for people who actually aim with their sidearm.
return {
	name = "Cozy 75",
	archetype = "CZ-75",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 1700,
	unlockLevel = 12,
	why = "Holds full damage to 34 ft — further than any other sidearm — with the tightest cone and the calmest recoil of the five.",
	stats = {
		damageNear = 30, damageFar = 17, rangeNear = 32, rangeFar = 66,
		headshotMult = 1.5, rpm = 390, auto = false, magSize = 16, reloadSeconds = 1.9,
		spreadDeg = 1.8, adsSpreadDeg = 0.26,
		recoilVert = 0.36, recoilHoriz = 0.13, recoilRecovery = 19,
		-- walk 17.5, sprint 25.0
		velocity = 1340, drop = 46, moveSpeedMult = 1.03, sprintSpeedMult = 1.04,
		equipTime = 0.25, sprintToFire = 0.08, adsTime = 0.16,
	},
}
