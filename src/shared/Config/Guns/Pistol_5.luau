--!strict
-- Jawbreaker — the hand cannon.
return {
	name = "Jawbreaker",
	class = "Pistol",
	slot = "Secondary",
	rarity = "Epic",
	price = 6200,
	why = "Four heavy shots that still land at 34 studs, for the sidearm fight you expect to have at range rather than in a doorway.",
	stats = {
		damageNear = 33, damageFar = 17, rangeNear = 34, rangeFar = 68,
		headshotMult = 1.6, rpm = 300, auto = false, magSize = 8, reloadSeconds = 1.75,
		spreadDeg = 1.5, adsSpreadDeg = 0.24,
		recoilVert = 0.60, recoilHoriz = 0.12, recoilRecovery = 13,
		velocity = 1260, drop = 34, moveSpeedMult = 1.02,
		equipTime = 0.27, sprintToFire = 0.11, adsTime = 0.19,
	},
}
