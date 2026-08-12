--!strict
-- Mixtape 5 (MP5) — the reference SMG. Middle of the class on every axis, and
-- the calmest recoil of the six, so it is the one that teaches you what an SMG
-- is supposed to feel like before you go and pick a weirder one.
return {
	name = "Mixtape 5",
	archetype = "MP5",
	class = "SMG",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "The SMG with no quirk: five shots in a room, the steadiest climb in the class, and thirty rounds to be wrong with.",
	stats = {
		damageNear = 30, damageFar = 13, rangeNear = 24, rangeFar = 62,
		headshotMult = 1.4, rpm = 800, auto = true, magSize = 30, reloadSeconds = 1.9,
		spreadDeg = 2.1, adsSpreadDeg = 0.30,
		recoilVert = 0.28, recoilHoriz = 0.14, recoilRecovery = 16,
		-- walk 17.9, sprint 25.4 (base 17 / 24)
		velocity = 1400, drop = 40, moveSpeedMult = 1.05, sprintSpeedMult = 1.06,
		equipTime = 0.30, sprintToFire = 0.10, adsTime = 0.18,
	},
}
