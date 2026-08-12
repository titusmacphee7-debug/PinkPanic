--!strict
-- Cupcake Cannon — the fast LMG. Closest an LMG gets to a rifle.
return {
	name = "Cupcake Cannon",
	class = "LMG",
	slot = "Primary",
	rarity = "Epic",
	price = 10400,
	why = "Fires fast enough to win a mid-range duel outright, which no other LMG does, and reloads for five full seconds if you lose one.",
	stats = {
		damageNear = 22, damageFar = 16, rangeNear = 55, rangeFar = 108,
		headshotMult = 1.45, rpm = 650, auto = true, magSize = 125, reloadSeconds = 5.0,
		spreadDeg = 2.7, adsSpreadDeg = 0.25,
		recoilVert = 0.52, recoilHoriz = 0.24, recoilRecovery = 9,
		velocity = 1520, drop = 30, moveSpeedMult = 0.91,
		equipTime = 0.69, sprintToFire = 0.30, adsTime = 0.43,
	},
}
