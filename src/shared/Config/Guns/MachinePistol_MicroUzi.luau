--!strict
-- Oozi (Micro Uzi) — 1050 rpm out of a sidearm slot, the fastest hands in the
-- game outside the MP7, and a cone you could park a bus in. Twenty-five rounds
-- gone in 1.4 seconds.
return {
	name = "Oozi",
	archetype = "Micro Uzi",
	class = "MachinePistol",
	slot = "Secondary",
	rarity = "Rare",
	price = 3000,
	unlockLevel = 25,
	why = "The fastest-firing sidearm in the game and the widest cone of anything that is not a shotgun — it wins the first second of a room and nothing after it.",
	stats = {
		damageNear = 22, damageFar = 10, rangeNear = 12, rangeFar = 40,
		headshotMult = 1.4, rpm = 1050, auto = true, magSize = 25, reloadSeconds = 1.7,
		spreadDeg = 3.8, adsSpreadDeg = 0.78,
		recoilVert = 0.48, recoilHoriz = 0.34, recoilRecovery = 18,
		-- walk 17.9, sprint 25.4
		velocity = 980, drop = 62, moveSpeedMult = 1.05, sprintSpeedMult = 1.06,
		equipTime = 0.22, sprintToFire = 0.07, adsTime = 0.14,
	},
}
