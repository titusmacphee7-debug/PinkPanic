--!strict
-- Charm Python (Colt Python) — three shots at any range you can see, six in the
-- cylinder. The revolver that behaves like a small marksman rifle you happen to
-- be carrying in your off hand.
return {
	name = "Charm Python",
	archetype = "Colt Python",
	class = "Revolver",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 2300,
	unlockLevel = 19,
	why = "Three shots to kill out to 36 ft and still only six at 117 ft — a sidearm that answers people your pistol cannot even reach.",
	stats = {
		damageNear = 50, damageFar = 25, rangeNear = 34, rangeFar = 84,
		headshotMult = 1.5, rpm = 280, auto = false, magSize = 6, reloadSeconds = 2.6,
		spreadDeg = 2.0, adsSpreadDeg = 0.24,
		recoilVert = 0.78, recoilHoriz = 0.22, recoilRecovery = 12,
		-- walk 17.2, sprint 24.5
		velocity = 1380, drop = 44, moveSpeedMult = 1.01, sprintSpeedMult = 1.02,
		equipTime = 0.32, sprintToFire = 0.13, adsTime = 0.24,
	},
}
