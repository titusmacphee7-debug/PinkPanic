--!strict
-- Shortcake (sawed-off) — the smallest weapon in the game and the fastest hands
-- in the class by a distance. Nine pellets, one shot inside 12 ft, two rounds,
-- and the shortest reach of anything that shoots.
return {
	name = "Shortcake",
	archetype = "Sawed-off",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Uncommon",
	price = 1500,
	unlockLevel = 9,
	why = "Up and firing faster than any other shotgun and lethal inside 12 ft — carried by people who intend to be around a corner, not down a corridor.",
	stats = {
		damageNear = 24, damageFar = 4, rangeNear = 8, rangeFar = 44, pellets = 9,
		headshotMult = 1.35, rpm = 180, auto = false, magSize = 2, reloadSeconds = 2.6,
		spreadDeg = 5.0, adsSpreadDeg = 3.4,
		recoilVert = 1.40, recoilHoriz = 0.42, recoilRecovery = 8,
		-- walk 17.0, sprint 24.0 — it weighs nothing
		velocity = 820, drop = 82, moveSpeedMult = 1.00, sprintSpeedMult = 1.00,
		equipTime = 0.30, sprintToFire = 0.12, adsTime = 0.20,
	},
}
