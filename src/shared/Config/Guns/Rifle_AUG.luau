--!strict
-- Hug (AUG) — the fastest, flattest round in the class. Its damage falls off
-- like every other rifle's; what it keeps is the ability to actually LAND the
-- shot on someone sprinting sideways at distance, because there is almost no
-- lead and almost no drop to guess.
return {
	name = "Hug",
	archetype = "AUG",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 2800,
	unlockLevel = 24,
	why = "The fastest bullet and flattest arc of any rifle — it hits moving targets at range that the others simply miss, even though it hurts no more than they do out there.",
	stats = {
		damageNear = 33, damageFar = 14, rangeNear = 38, rangeFar = 107,
		headshotMult = 1.5, rpm = 680, auto = true, magSize = 30, reloadSeconds = 2.3,
		spreadDeg = 1.5, adsSpreadDeg = 0.16,
		recoilVert = 0.36, recoilHoriz = 0.12, recoilRecovery = 12,
		velocity = 2250, drop = 20, moveSpeedMult = 0.99,
		equipTime = 0.42, sprintToFire = 0.17, adsTime = 0.27,
	},
}
