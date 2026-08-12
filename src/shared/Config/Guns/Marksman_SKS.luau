--!strict
-- Nitpick (SKS) — the free marksman. Crudest of the four and the quickest
-- trigger, which makes it the one that forgives a miss; calling it fussy is the
-- joke, because it is the least fussy rifle in the class.
return {
	name = "Nitpick",
	archetype = "SKS",
	class = "Marksman",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "Free, and the fastest trigger of any marksman — three shots at any distance in the game, with enough cadence that a missed one is survivable.",
	stats = {
		damageNear = 50, damageFar = 50, rangeNear = 90, rangeFar = 150,
		headshotMult = 1.9, rpm = 300, auto = false, magSize = 10, reloadSeconds = 2.7,
		spreadDeg = 1.4, adsSpreadDeg = 0.08,
		recoilVert = 0.72, recoilHoriz = 0.14, recoilRecovery = 11,
		-- walk 15.6, sprint 21.6
		velocity = 2400, drop = 18, moveSpeedMult = 0.92, sprintSpeedMult = 0.90,
		equipTime = 0.52, sprintToFire = 0.24, adsTime = 0.38,
	},
}
