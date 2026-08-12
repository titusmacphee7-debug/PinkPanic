--!strict
-- Teddy Gun (Thompson) — the four-shot SMG. Slowest fire rate in the class and
-- the hardest round, so it beats every other SMG in a straight trade and loses
-- to all of them the moment the fight lasts longer than one magazine.
return {
	name = "Teddy Gun",
	archetype = "Thompson",
	class = "SMG",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2400,
	unlockLevel = 22,
	why = "Four shots inside 23 ft, which no other SMG manages — bought with the slowest fire rate, the heaviest hands and the worst climb in the class.",
	stats = {
		damageNear = 38, damageFar = 16, rangeNear = 22, rangeFar = 64,
		headshotMult = 1.4, rpm = 720, auto = true, magSize = 30, reloadSeconds = 2.0,
		spreadDeg = 2.6, adsSpreadDeg = 0.34,
		recoilVert = 0.38, recoilHoriz = 0.20, recoilRecovery = 14,
		-- walk 17.2, sprint 24.5 — the heaviest SMG on its feet
		velocity = 1200, drop = 48, moveSpeedMult = 1.01, sprintSpeedMult = 1.02,
		equipTime = 0.32, sprintToFire = 0.12, adsTime = 0.21,
	},
}
