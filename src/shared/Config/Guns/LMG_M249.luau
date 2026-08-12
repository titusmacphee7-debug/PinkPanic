--!strict
-- Seesaw (M249 SAW) — the free LMG and the lightest of the four. A hundred
-- rounds, the best kill speed in a class that is not supposed to have one, and
-- a five-and-a-half second reload to remind you which class it is.
return {
	name = "Seesaw",
	archetype = "M249 SAW",
	class = "LMG",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "A hundred rounds for free — the entry to a class whose whole idea is that you never stop firing, and the quickest of the four to get on target.",
	stats = {
		damageNear = 26, damageFar = 20, rangeNear = 55, rangeFar = 125,
		headshotMult = 1.4, rpm = 700, auto = true, magSize = 100, reloadSeconds = 5.4,
		spreadDeg = 2.8, adsSpreadDeg = 0.40,
		recoilVert = 0.46, recoilHoriz = 0.22, recoilRecovery = 9,
		-- walk 15.0, sprint 20.2
		velocity = 1750, drop = 34, moveSpeedMult = 0.88, sprintSpeedMult = 0.84,
		equipTime = 0.62, sprintToFire = 0.28, adsTime = 0.42,
	},
}
