--!strict
-- Pillow Fight (PKM) — the hard-hitting LMG. Five shots up close where the rest
-- of the class needs six, at the slowest cadence short of the M60, out of a
-- hundred and twenty rounds.
return {
	name = "Pillow Fight",
	archetype = "PKM",
	class = "LMG",
	slot = "Primary",
	rarity = "Rare",
	price = 4000,
	unlockLevel = 31,
	why = "Five shots to kill where every other LMG needs six, and it holds full damage further out than any of them — the one that wins a straight exchange instead of outlasting it.",
	stats = {
		damageNear = 30, damageFar = 23, rangeNear = 60, rangeFar = 130,
		headshotMult = 1.4, rpm = 560, auto = true, magSize = 120, reloadSeconds = 5.8,
		spreadDeg = 2.9, adsSpreadDeg = 0.42,
		recoilVert = 0.56, recoilHoriz = 0.24, recoilRecovery = 8,
		-- walk 14.8, sprint 19.9
		velocity = 1820, drop = 30, moveSpeedMult = 0.87, sprintSpeedMult = 0.83,
		equipTime = 0.63, sprintToFire = 0.29, adsTime = 0.43,
	},
}
