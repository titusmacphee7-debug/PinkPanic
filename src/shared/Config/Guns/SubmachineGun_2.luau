--!strict
-- Bubbler — the heavy SMG. Slowest cycle in the class, hardest hit.
return {
	name = "Bubbler",
	class = "SMG",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2200,
	why = "Hits hard enough to keep its five-shot kill two studs further out than any other SMG, and reloads slowest to pay for it.",
	stats = {
		damageNear = 23, damageFar = 12, rangeNear = 22, rangeFar = 58,
		headshotMult = 1.4, rpm = 800, auto = true, magSize = 32, reloadSeconds = 2.15,
		spreadDeg = 2.0, adsSpreadDeg = 0.24,
		recoilVert = 0.30, recoilHoriz = 0.17, recoilRecovery = 15,
		velocity = 1010, drop = 39, moveSpeedMult = 1.06,
		equipTime = 0.32, sprintToFire = 0.10, adsTime = 0.19,
	},
}
