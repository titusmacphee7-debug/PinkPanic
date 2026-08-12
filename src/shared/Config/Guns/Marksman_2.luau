--!strict
-- Keepsake — the heavy marksman. Slowest cycle, best headshot payoff.
--
-- 48 damage is chosen so two body shots are 96 and do NOT kill, while a head
-- (48 x 1.95 = 93.6) plus any body shot does. That is the one gun in the game
-- where aiming higher changes the shot count.
return {
	name = "Keepsake",
	class = "Marksman",
	slot = "Primary",
	rarity = "Rare",
	price = 6600,
	why = "Two shots if either one is a head, three if neither is — the only gun where aiming higher shortens the kill.",
	stats = {
		damageNear = 48, damageFar = 41, rangeNear = 112, rangeFar = 205,
		headshotMult = 1.95, rpm = 240, auto = false, magSize = 10, reloadSeconds = 2.45,
		spreadDeg = 2.3, adsSpreadDeg = 0.10,
		recoilVert = 0.86, recoilHoriz = 0.14, recoilRecovery = 11,
		velocity = 2000, drop = 22, moveSpeedMult = 0.95,
		equipTime = 0.55, sprintToFire = 0.27, adsTime = 0.37,
	},
}
