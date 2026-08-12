--!strict
-- Glitter 17 (Glock 17) — the sidearm everyone starts with. Seventeen rounds,
-- no character, and enough of everything that you never feel robbed for not
-- having bought one of the others yet.
return {
	name = "Glitter 17",
	archetype = "Glock 17",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "Seventeen rounds and no weakness — the sidearm that finishes a fight your primary started, which is the entire job of a sidearm.",
	stats = {
		damageNear = 30, damageFar = 16, rangeNear = 28, rangeFar = 56,
		headshotMult = 1.5, rpm = 420, auto = false, magSize = 17, reloadSeconds = 1.8,
		spreadDeg = 2.0, adsSpreadDeg = 0.34,
		recoilVert = 0.42, recoilHoriz = 0.16, recoilRecovery = 17,
		-- walk 17.7, sprint 25.2
		velocity = 1300, drop = 48, moveSpeedMult = 1.04, sprintSpeedMult = 1.05,
		equipTime = 0.24, sprintToFire = 0.08, adsTime = 0.16,
	},
}
