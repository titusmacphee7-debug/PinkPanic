--!strict
-- Barrette M9 (Beretta M9) — the fastest trigger of the pistols and fifteen
-- rounds behind it. Weakest per-shot of the five, so it is the sidearm that
-- wants you to keep pulling rather than to aim carefully.
return {
	name = "Barrette M9",
	archetype = "Beretta M9",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 1200,
	unlockLevel = 6,
	why = "The quickest trigger of any sidearm with fifteen rounds behind it — it out-shoots the Glock in a panic and runs out of damage before any of the others do.",
	stats = {
		damageNear = 30, damageFar = 15, rangeNear = 26, rangeFar = 60,
		headshotMult = 1.5, rpm = 450, auto = false, magSize = 15, reloadSeconds = 1.9,
		spreadDeg = 2.1, adsSpreadDeg = 0.33,
		recoilVert = 0.40, recoilHoriz = 0.17, recoilRecovery = 18,
		-- walk 17.5, sprint 25.0
		velocity = 1280, drop = 50, moveSpeedMult = 1.03, sprintSpeedMult = 1.04,
		equipTime = 0.25, sprintToFire = 0.085, adsTime = 0.17,
	},
}
