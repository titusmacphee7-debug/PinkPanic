--!strict
-- Chatterbox (RPD) — a hundred and fifty rounds, the largest magazine in the
-- game. It does not stop, which is the entire personality, and the six-second
-- reload is what you pay when it finally does.
return {
	name = "Chatterbox",
	archetype = "RPD",
	class = "LMG",
	slot = "Primary",
	rarity = "Rare",
	price = 4600,
	unlockLevel = 38,
	why = "A hundred and fifty rounds — the longest anyone in this game can fire without stopping, and a six-second reload the moment they do.",
	stats = {
		damageNear = 28, damageFar = 21, rangeNear = 50, rangeFar = 120,
		headshotMult = 1.4, rpm = 650, auto = true, magSize = 150, reloadSeconds = 6.2,
		spreadDeg = 3.0, adsSpreadDeg = 0.44,
		recoilVert = 0.50, recoilHoriz = 0.25, recoilRecovery = 8,
		-- walk 14.6, sprint 19.7
		velocity = 1680, drop = 36, moveSpeedMult = 0.86, sprintSpeedMult = 0.82,
		equipTime = 0.64, sprintToFire = 0.30, adsTime = 0.44,
	},
}
