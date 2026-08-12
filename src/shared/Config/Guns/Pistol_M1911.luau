--!strict
-- Jawbreaker (M1911) — four shots, seven rounds. Two magazines is two fights,
-- and the second one had better be short.
return {
	name = "Jawbreaker",
	archetype = "M1911",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 1400,
	unlockLevel = 8,
	why = "Four shots to kill where the Glock needs five, out of seven rounds — the sidearm that rewards you for counting.",
	stats = {
		damageNear = 38, damageFar = 20, rangeNear = 26, rangeFar = 58,
		headshotMult = 1.5, rpm = 340, auto = false, magSize = 7, reloadSeconds = 2.0,
		spreadDeg = 2.2, adsSpreadDeg = 0.32,
		recoilVert = 0.58, recoilHoriz = 0.19, recoilRecovery = 14,
		-- walk 17.3, sprint 24.7
		velocity = 1180, drop = 54, moveSpeedMult = 1.02, sprintSpeedMult = 1.03,
		equipTime = 0.26, sprintToFire = 0.09, adsTime = 0.18,
	},
}
