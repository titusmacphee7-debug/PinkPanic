--!strict
-- Scribble (KRISS Vector) — 1150 rpm, the fastest fire rate in the game. Empties
-- a 25-round magazine in 1.3 seconds and hits like a wet paper towel at any
-- range you could not also throw something.
return {
	name = "Scribble",
	archetype = "KRISS Vector",
	class = "SMG",
	slot = "Primary",
	rarity = "Rare",
	price = 3800,
	unlockLevel = 32,
	why = "The fastest trigger in the game — it wins any fight decided in the first half second, and runs dry in 1.3 seconds if it does not.",
	stats = {
		damageNear = 22, damageFar = 10, rangeNear = 18, rangeFar = 60,
		headshotMult = 1.4, rpm = 1150, auto = true, magSize = 25, reloadSeconds = 1.7,
		spreadDeg = 2.4, adsSpreadDeg = 0.36,
		recoilVert = 0.34, recoilHoriz = 0.19, recoilRecovery = 18,
		-- walk 17.9, sprint 25.7
		velocity = 1250, drop = 46, moveSpeedMult = 1.05, sprintSpeedMult = 1.07,
		equipTime = 0.28, sprintToFire = 0.09, adsTime = 0.16,
	},
}
