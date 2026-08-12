--!strict
-- Thumper 870 (Remington 870) — the heavy pump. Eight fat pellets in the
-- tightest cone in the class, which is what lets it still be a TWO-shot kill at
-- 43 ft while the light-pellet guns are asking for three.
--
-- One shot inside 15 ft. Slowest cycle of anything that is not bolt-action, so
-- a miss costs most of a second.
return {
	name = "Thumper 870",
	archetype = "Remington 870",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "One shot inside 15 ft and still only two at 43 ft — the heaviest pellets in the game, fired slowly enough that missing with them genuinely hurts.",
	stats = {
		damageNear = 22, damageFar = 9, rangeNear = 14, rangeFar = 46, pellets = 8,
		headshotMult = 1.35, rpm = 85, auto = false, magSize = 6, reloadSeconds = 3.4,
		shellReload = 0.42,
		spreadDeg = 3.4, adsSpreadDeg = 2.2,
		recoilVert = 1.30, recoilHoriz = 0.30, recoilRecovery = 7,
		-- walk 16.3, sprint 22.6
		velocity = 900, drop = 70, moveSpeedMult = 0.96, sprintSpeedMult = 0.94,
		equipTime = 0.44, sprintToFire = 0.18, adsTime = 0.32,
	},
}
