--!strict
-- Bestie (M4A1) — the reference gun. Every other rifle is described as a change
-- from this one, so it sits dead centre of the class window on purpose.
--
-- 5 shots in a room, 10 across a lane. That gap IS the class.
return {
	name = "Bestie",
	archetype = "M4A1",
	class = "Rifle",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "The rifle with no weakness and no edge: five shots inside 37 ft and nothing to learn before it works. Everything else in the class beats it at something.",
	stats = {
		damageNear = 31, damageFar = 15, rangeNear = 35, rangeFar = 100,
		headshotMult = 1.5, rpm = 750, auto = true, magSize = 30, reloadSeconds = 2.1,
		spreadDeg = 1.5, adsSpreadDeg = 0.18,
		recoilVert = 0.38, recoilHoriz = 0.13, recoilRecovery = 12,
		velocity = 1900, drop = 30, moveSpeedMult = 1.00,
		equipTime = 0.40, sprintToFire = 0.16, adsTime = 0.25,
	},
}
