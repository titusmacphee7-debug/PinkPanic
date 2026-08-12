--!strict
-- Gumdrop — the fast rifle. Trades reach for cadence.
return {
	name = "Gumdrop",
	class = "Rifle",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2600,
	why = "The fastest-firing rifle, so it wins the mid-range trade an SMG cannot reach and a slower AR loses.",
	stats = {
		damageNear = 23, damageFar = 16, rangeNear = 44, rangeFar = 88,
		headshotMult = 1.5, rpm = 720, auto = true, magSize = 30, reloadSeconds = 2.15,
		spreadDeg = 1.7, adsSpreadDeg = 0.21,
		recoilVert = 0.38, recoilHoriz = 0.15, recoilRecovery = 13,
		velocity = 1420, drop = 33, moveSpeedMult = 1.01,
		equipTime = 0.38, sprintToFire = 0.14, adsTime = 0.25,
	},
}
