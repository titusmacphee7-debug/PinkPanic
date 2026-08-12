--!strict
-- Shortcake — the sawn-off. The shortest one-shot window anywhere and the
-- fastest handling of any primary in the game.
return {
	name = "Shortcake",
	class = "Shotgun",
	slot = "Primary",
	rarity = "Epic",
	price = 7800,
	why = "Draws faster than a pistol and one-shots inside 9 studs; past 32 its pellets do not exist at all.",
	stats = {
		damageNear = 13, damageFar = 4, rangeNear = 9, rangeFar = 20, pellets = 8,
		headshotMult = 1.25, rpm = 130, auto = false, magSize = 2, reloadSeconds = 0.9,
		spreadDeg = 11.0, adsSpreadDeg = 7.5,
		recoilVert = 1.45, recoilHoriz = 0.40, recoilRecovery = 11,
		velocity = 780, drop = 54, moveSpeedMult = 1.05,
		equipTime = 0.26, sprintToFire = 0.08, adsTime = 0.17,
	},
}
