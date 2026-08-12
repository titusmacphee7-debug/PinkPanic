--!strict
-- Button Nose (snub-nose .38) — the free revolver. Fastest trigger and lightest
-- hands of the three, five rounds, and the only one a new player can reach for
-- when they want a sidearm that still works at 117 ft.
return {
	name = "Button Nose",
	archetype = "Snub-nose .38",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "The quickest revolver and the only free one — four shots up close, and unlike every pistol its bullets still arrive at 117 ft.",
	stats = {
		damageNear = 38, damageFar = 20, rangeNear = 24, rangeFar = 76,
		headshotMult = 1.5, rpm = 380, auto = false, magSize = 5, reloadSeconds = 2.2,
		spreadDeg = 2.4, adsSpreadDeg = 0.36,
		recoilVert = 0.54, recoilHoriz = 0.20, recoilRecovery = 15,
		-- walk 17.5, sprint 25.0
		velocity = 1220, drop = 52, moveSpeedMult = 1.03, sprintSpeedMult = 1.04,
		equipTime = 0.28, sprintToFire = 0.10, adsTime = 0.20,
	},
}
