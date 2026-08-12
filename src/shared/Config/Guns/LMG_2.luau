--!strict
-- Rolling Pin — the drum. Longest belt, weakest round.
return {
	name = "Rolling Pin",
	class = "LMG",
	slot = "Primary",
	rarity = "Epic",
	price = 9600,
	why = "A hundred and fifty rounds: it is the only gun that can hold a doorway shut, and the slowest thing in the game to point somewhere new.",
	stats = {
		damageNear = 19, damageFar = 14, rangeNear = 52, rangeFar = 105,
		headshotMult = 1.4, rpm = 700, auto = true, magSize = 150, reloadSeconds = 5.4,
		spreadDeg = 3.0, adsSpreadDeg = 0.28,
		recoilVert = 0.46, recoilHoriz = 0.26, recoilRecovery = 9,
		velocity = 1480, drop = 31, moveSpeedMult = 0.90,
		equipTime = 0.72, sprintToFire = 0.32, adsTime = 0.46,
	},
}
