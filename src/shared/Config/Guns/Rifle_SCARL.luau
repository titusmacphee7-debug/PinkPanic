--!strict
-- Buttercup (SCAR-L) — the flattest recoil in the game and twenty rounds to
-- spend it on. Rewards people who fire in bursts; punishes people who hold the
-- trigger, because the magazine runs out mid-fight rather than the gun rising.
return {
	name = "Buttercup",
	archetype = "SCAR-L",
	class = "Rifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 1800,
	unlockLevel = 12,
	why = "Almost no recoil at all, with only twenty rounds behind it — the rifle for people who would rather aim once than spray twice.",
	stats = {
		damageNear = 33, damageFar = 14, rangeNear = 32, rangeFar = 100,
		headshotMult = 1.5, rpm = 700, auto = true, magSize = 20, reloadSeconds = 2.0,
		spreadDeg = 1.3, adsSpreadDeg = 0.14,
		recoilVert = 0.30, recoilHoriz = 0.10, recoilRecovery = 14,
		velocity = 2000, drop = 26, moveSpeedMult = 1.00,
		equipTime = 0.42, sprintToFire = 0.16, adsTime = 0.26,
	},
}
