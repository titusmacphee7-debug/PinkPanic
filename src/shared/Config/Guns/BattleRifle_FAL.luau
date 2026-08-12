--!strict
-- Big Softie (FN FAL) — four shots at any range you can see someone. The
-- hardest single round of any automatic weapon in the game, fired slower than
-- anything in the rifle class, out of twenty rounds.
--
-- It is called Big Softie because it is not one.
return {
	name = "Big Softie",
	archetype = "FN FAL",
	class = "BattleRifle",
	slot = "Primary",
	rarity = "Rare",
	price = 3600,
	unlockLevel = 28,
	why = "Four shots to kill out to 43 ft and five at any distance beyond it — the flattest damage curve of any automatic, paid for with the slowest cadence and twenty rounds to do it in.",
	stats = {
		damageNear = 42, damageFar = 28, rangeNear = 40, rangeFar = 130,
		headshotMult = 1.5, rpm = 460, auto = true, magSize = 20, reloadSeconds = 3.0,
		spreadDeg = 2.0, adsSpreadDeg = 0.20,
		recoilVert = 0.62, recoilHoriz = 0.20, recoilRecovery = 9,
		-- walk 16.0, sprint 21.6 (base 17 / 24)
		velocity = 2000, drop = 30, moveSpeedMult = 0.94, sprintSpeedMult = 0.90,
		equipTime = 0.50, sprintToFire = 0.22, adsTime = 0.34,
	},
}
