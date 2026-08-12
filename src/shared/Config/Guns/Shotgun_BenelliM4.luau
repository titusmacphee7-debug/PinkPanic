--!strict
-- Bossy (Benelli M4) — semi-auto. Never a one-shot, but it fires more than
-- twice as fast as the pump, so it forgives a miss the way nothing else in the
-- class does. Two shots in a room, three at 43 ft.
return {
	name = "Bossy",
	archetype = "Benelli M4",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Rare",
	price = 3600,
	unlockLevel = 29,
	why = "Never a one-shot, and it does not need to be — semi-auto cadence means two shots land before the pump has cycled once, and a miss is not a lost fight.",
	stats = {
		damageNear = 17, damageFar = 4, rangeNear = 12, rangeFar = 46, pellets = 8,
		headshotMult = 1.35, rpm = 200, auto = false, magSize = 7, reloadSeconds = 3.2,
		shellReload = 0.38,
		spreadDeg = 3.8, adsSpreadDeg = 2.5,
		recoilVert = 0.85, recoilHoriz = 0.26, recoilRecovery = 10,
		-- walk 16.5, sprint 23.0
		velocity = 950, drop = 66, moveSpeedMult = 0.97, sprintSpeedMult = 0.96,
		equipTime = 0.40, sprintToFire = 0.16, adsTime = 0.28,
	},
}
