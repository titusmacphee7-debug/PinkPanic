--!strict
-- Peekaboo (Dragunov SVD) — the archetypal scope watching a window. Flat three
-- shots forever, the best headshot multiplier of the four, and a cone tight
-- enough that the only thing between you and the hit is you.
return {
	name = "Peekaboo",
	archetype = "Dragunov SVD",
	class = "Marksman",
	slot = "Primary",
	rarity = "Rare",
	price = 3900,
	unlockLevel = 27,
	why = "Two headshots kill at any range in the game — the marksman that turns holding one angle into a real threat rather than a slow one.",
	stats = {
		damageNear = 52, damageFar = 52, rangeNear = 100, rangeFar = 160,
		headshotMult = 2.0, rpm = 260, auto = false, magSize = 10, reloadSeconds = 2.9,
		spreadDeg = 1.3, adsSpreadDeg = 0.06,
		recoilVert = 0.80, recoilHoriz = 0.12, recoilRecovery = 10,
		-- walk 15.5, sprint 21.4
		velocity = 2550, drop = 15, moveSpeedMult = 0.91, sprintSpeedMult = 0.89,
		equipTime = 0.54, sprintToFire = 0.26, adsTime = 0.40,
	},
}
