--!strict
-- Pom-Pom 90 (P90) — fifty rounds. Nothing else in the class can take three
-- fights without touching the reload key, and that is the entire pitch: it wins
-- the room you did not know had four people in it.
return {
	name = "Pom-Pom 90",
	archetype = "P90",
	class = "SMG",
	slot = "Primary",
	rarity = "Rare",
	price = 3200,
	unlockLevel = 26,
	why = "Fifty rounds in one magazine — the only SMG that can fight three people in a row, at the cost of the worst damage past 27 ft in the class.",
	stats = {
		damageNear = 26, damageFar = 12, rangeNear = 20, rangeFar = 60,
		headshotMult = 1.4, rpm = 950, auto = true, magSize = 50, reloadSeconds = 2.2,
		spreadDeg = 2.2, adsSpreadDeg = 0.32,
		recoilVert = 0.24, recoilHoriz = 0.16, recoilRecovery = 17,
		-- walk 17.5, sprint 25.0
		velocity = 1350, drop = 42, moveSpeedMult = 1.03, sprintSpeedMult = 1.04,
		equipTime = 0.32, sprintToFire = 0.12, adsTime = 0.20,
	},
}
