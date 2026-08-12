--!strict
-- Pipsqueak 7 (MP7) — the smallest, lightest thing in the game. Best hands and
-- best legs of any weapon, full stop: up in 0.16s, out of a sprint in 0.09s, and
-- it moves you faster than anything else you could be carrying.
return {
	name = "Pipsqueak 7",
	archetype = "MP7",
	class = "SMG",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2000,
	unlockLevel = 16,
	why = "The fastest hands and fastest legs in the game — it is already firing while everything else is still coming up, and it has the shortest reload to go with it.",
	stats = {
		damageNear = 25, damageFar = 11, rangeNear = 20, rangeFar = 62,
		headshotMult = 1.4, rpm = 1000, auto = true, magSize = 30, reloadSeconds = 1.6,
		spreadDeg = 2.2, adsSpreadDeg = 0.31,
		recoilVert = 0.26, recoilHoriz = 0.15, recoilRecovery = 18,
		-- walk 18.2, sprint 26.2 — the fastest anything moves in Pink Panic
		velocity = 1500, drop = 38, moveSpeedMult = 1.07, sprintSpeedMult = 1.09,
		equipTime = 0.28, sprintToFire = 0.09, adsTime = 0.16,
	},
}
