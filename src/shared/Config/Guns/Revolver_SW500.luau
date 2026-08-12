--!strict
-- Sweet & Wesson (S&W 500) — the two-shot sidearm. Hardest-hitting round in the
-- game outside a sniper, five in the cylinder, three seconds to fill it, and the
-- slowest trigger of anything that is not bolt-action.
--
-- Two shots, and if you miss both you have lost the fight.
return {
	name = "Sweet & Wesson",
	archetype = "S&W 500",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Legendary",
	price = 6800,
	unlockLevel = 47,
	why = "Two shots to kill at any range in the game — the hardest round outside a sniper, on the slowest trigger and a three-second reload for five of them.",
	stats = {
		damageNear = 75, damageFar = 38, rangeNear = 30, rangeFar = 90,
		headshotMult = 1.5, rpm = 165, auto = false, magSize = 5, reloadSeconds = 3.0,
		spreadDeg = 2.6, adsSpreadDeg = 0.28,
		recoilVert = 1.45, recoilHoriz = 0.38, recoilRecovery = 8,
		-- walk 16.7, sprint 23.8
		velocity = 1500, drop = 42, moveSpeedMult = 0.98, sprintSpeedMult = 0.99,
		equipTime = 0.38, sprintToFire = 0.16, adsTime = 0.30,
	},
}
