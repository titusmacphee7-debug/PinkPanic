--!strict
-- Tiny (M60) — the largest weapon in the game, and the joke is the name. Longest
-- reach of any automatic, the slowest hands of anything at all, and a
-- six-and-a-half second reload you will not survive being caught in.
return {
	name = "Tiny",
	archetype = "M60",
	class = "LMG",
	slot = "Primary",
	rarity = "SuperRare",
	price = 5800,
	unlockLevel = 45,
	why = "The longest-reaching automatic in the game and the heaviest thing you can carry — it owns a lane completely and cannot answer anything that gets close.",
	stats = {
		damageNear = 34, damageFar = 26, rangeNear = 58, rangeFar = 132,
		headshotMult = 1.4, rpm = 500, auto = true, magSize = 100, reloadSeconds = 6.6,
		spreadDeg = 3.2, adsSpreadDeg = 0.46,
		recoilVert = 0.64, recoilHoriz = 0.28, recoilRecovery = 7,
		-- walk 14.3, sprint 19.2 — the slowest anyone moves in Pink Panic
		velocity = 1700, drop = 32, moveSpeedMult = 0.84, sprintSpeedMult = 0.80,
		equipTime = 0.68, sprintToFire = 0.32, adsTime = 0.48,
	},
}
