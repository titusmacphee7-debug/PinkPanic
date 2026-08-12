--!strict
-- Grumpy (HK G3) — the battle rifle you can actually hold a fight with. Five
-- shots rather than four, but the fastest cadence and the calmest recoil of the
-- three, so it is the one that forgives a miss.
return {
	name = "Grumpy",
	archetype = "HK G3",
	class = "BattleRifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2600,
	unlockLevel = 20,
	why = "The forgiving battle rifle: five shots instead of four, but the quickest to fire and the easiest to control, so a missed round is not a lost fight.",
	stats = {
		damageNear = 32, damageFar = 24, rangeNear = 50, rangeFar = 135,
		headshotMult = 1.5, rpm = 520, auto = true, magSize = 20, reloadSeconds = 2.8,
		spreadDeg = 1.8, adsSpreadDeg = 0.18,
		recoilVert = 0.55, recoilHoriz = 0.17, recoilRecovery = 10,
		-- walk 16.2, sprint 22.1 — the lightest of the three on its feet
		velocity = 1900, drop = 32, moveSpeedMult = 0.95, sprintSpeedMult = 0.92,
		equipTime = 0.48, sprintToFire = 0.21, adsTime = 0.32,
	},
}
