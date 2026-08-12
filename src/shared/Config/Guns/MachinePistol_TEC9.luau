--!strict
-- Yappy (TEC-9) — the middle machine pistol. Full-auto in your off hand, which
-- is the whole class: faster than any pistol at spitting damage out, and gone
-- entirely by 75 ft.
return {
	name = "Yappy",
	archetype = "TEC-9",
	class = "MachinePistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 0,
	unlockLevel = 1,
	why = "Full-auto out of a sidearm slot — it wins the panic fight no pistol can, and its bullets do not exist past 71 ft.",
	stats = {
		damageNear = 25, damageFar = 10, rangeNear = 14, rangeFar = 42,
		headshotMult = 1.4, rpm = 850, auto = true, magSize = 32, reloadSeconds = 1.8,
		spreadDeg = 3.2, adsSpreadDeg = 0.62,
		recoilVert = 0.44, recoilHoriz = 0.26, recoilRecovery = 16,
		-- walk 17.7, sprint 25.2
		velocity = 1050, drop = 58, moveSpeedMult = 1.04, sprintSpeedMult = 1.05,
		equipTime = 0.23, sprintToFire = 0.075, adsTime = 0.15,
	},
}
