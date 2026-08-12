--!strict
-- Slowpoke (Mk14 EBR) — and it has to earn the name. Slowest-firing and
-- heaviest-handling marksman in the game, which buys it the only two-shot body
-- kill in the class.
--
-- If a later balance pass makes another marksman slower, this name is wrong and
-- should move rather than the number being fudged to protect it.
return {
	name = "Slowpoke",
	archetype = "Mk14 EBR",
	class = "Marksman",
	slot = "Primary",
	rarity = "SuperRare",
	price = 5600,
	unlockLevel = 43,
	why = "The only marksman that kills in two body shots, on the slowest trigger and the heaviest hands in the class — one hit is half a kill, and one miss is the whole fight.",
	stats = {
		damageNear = 76, damageFar = 76, rangeNear = 110, rangeFar = 170,
		headshotMult = 1.8, rpm = 185, auto = false, magSize = 10, reloadSeconds = 3.1,
		spreadDeg = 1.5, adsSpreadDeg = 0.07,
		recoilVert = 1.05, recoilHoriz = 0.18, recoilRecovery = 8,
		-- walk 15.1, sprint 20.9
		velocity = 2300, drop = 20, moveSpeedMult = 0.89, sprintSpeedMult = 0.87,
		equipTime = 0.58, sprintToFire = 0.30, adsTime = 0.46,
	},
}
