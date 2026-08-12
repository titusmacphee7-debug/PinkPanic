--!strict
-- Tick Tock (M16A4) — the other burst rifle, and the opposite of Tutu. Tighter
-- cone, faster round, slower gap between bursts. Where Tutu is a brawler that
-- happens to burst, this is a precision weapon that punishes a rushed second
-- press harder than anything else in the class.
return {
	name = "Tick Tock",
	archetype = "M16A4",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 5000,
	unlockLevel = 44,
	why = "The tightest cone of any rifle and a burst that lands all three where you pointed it — with the longest wait between pulls in the game if the first burst was not enough.",
	stats = {
		damageNear = 39, damageFar = 17, rangeNear = 30, rangeFar = 105,
		headshotMult = 1.5, rpm = 240, auto = false, magSize = 30, reloadSeconds = 2.2,
		burstCount = 3, burstRpm = 1100,
		spreadDeg = 1.2, adsSpreadDeg = 0.10,
		recoilVert = 0.34, recoilHoriz = 0.09, recoilRecovery = 15,
		velocity = 2100, drop = 24, moveSpeedMult = 1.00,
		equipTime = 0.44, sprintToFire = 0.17, adsTime = 0.28,
	},
}
