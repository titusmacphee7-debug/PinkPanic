--!strict
-- Old Faithful (M14) — the longest reach of any automatic weapon in the game
-- and the flattest round outside a sniper. Slowest fire rate in the class, the
-- heaviest to run with, and the only battle rifle that still kills in four at
-- 117 ft.
return {
	name = "Old Faithful",
	archetype = "M14",
	class = "BattleRifle",
	slot = "Primary",
	rarity = "SuperRare",
	price = 5400,
	unlockLevel = 40,
	why = "Reaches 232 ft with the flattest round short of a sniper — the only automatic that is still a four-shot kill at 75 ft, and the slowest-firing, heaviest thing to carry in exchange.",
	stats = {
		damageNear = 42, damageFar = 32, rangeNear = 55, rangeFar = 145,
		headshotMult = 1.5, rpm = 420, auto = true, magSize = 20, reloadSeconds = 2.9,
		spreadDeg = 1.6, adsSpreadDeg = 0.13,
		recoilVert = 0.58, recoilHoriz = 0.15, recoilRecovery = 10,
		-- walk 15.8, sprint 21.1 — the heaviest thing short of an LMG
		velocity = 2150, drop = 22, moveSpeedMult = 0.93, sprintSpeedMult = 0.88,
		equipTime = 0.50, sprintToFire = 0.23, adsTime = 0.36,
	},
}
