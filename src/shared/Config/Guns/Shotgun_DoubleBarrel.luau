--!strict
-- Double Trouble (double-barrel) — ten pellets, one shot inside 11 ft, and then
-- you have exactly one round left and a three-second reload. The highest
-- risk-to-reward in the game: two chances, then you are holding a stick.
return {
	name = "Double Trouble",
	archetype = "Double-barrel",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Uncommon",
	price = 1900,
	unlockLevel = 14,
	why = "One shot inside 11 ft with a second right behind it — and then two rounds is all there was, which is the whole gun.",
	stats = {
		damageNear = 20, damageFar = 3, rangeNear = 10, rangeFar = 44, pellets = 10,
		headshotMult = 1.35, rpm = 200, auto = false, magSize = 2, reloadSeconds = 3.0,
		spreadDeg = 4.2, adsSpreadDeg = 2.8,
		recoilVert = 1.15, recoilHoriz = 0.34, recoilRecovery = 9,
		-- walk 16.8, sprint 23.5
		velocity = 880, drop = 74, moveSpeedMult = 0.99, sprintSpeedMult = 0.98,
		equipTime = 0.36, sprintToFire = 0.14, adsTime = 0.24,
	},
}
