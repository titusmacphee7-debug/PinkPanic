--!strict
-- Hall Monitor (SCAR-H) — twenty rounds and the fastest handling of any
-- marksman, so it is the one you can actually fight a corridor with instead of
-- only watching one.
return {
	name = "Hall Monitor",
	archetype = "SCAR-H",
	class = "Marksman",
	slot = "Primary",
	rarity = "Rare",
	price = 4300,
	unlockLevel = 35,
	why = "Twenty rounds and the quickest hands in the class — the marksman that can be surprised and still win, at the cost of the shortest reach of the four.",
	stats = {
		damageNear = 50, damageFar = 50, rangeNear = 85, rangeFar = 145,
		headshotMult = 1.85, rpm = 280, auto = false, magSize = 20, reloadSeconds = 2.8,
		spreadDeg = 1.6, adsSpreadDeg = 0.09,
		recoilVert = 0.86, recoilHoriz = 0.16, recoilRecovery = 11,
		-- walk 15.8, sprint 22.1
		velocity = 2250, drop = 22, moveSpeedMult = 0.93, sprintSpeedMult = 0.92,
		equipTime = 0.50, sprintToFire = 0.23, adsTime = 0.36,
	},
}
