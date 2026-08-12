--!strict
-- Granny (Mosin-Nagant) — genuinely ancient and the slowest bolt in the game.
-- Five rounds, 38 rpm, and the second-hardest hit; the joke is the name and the
-- gun is not joking.
return {
	name = "Granny",
	archetype = "Mosin-Nagant",
	class = "Sniper",
	slot = "Primary",
	rarity = "Uncommon",
	price = 2900,
	unlockLevel = 23,
	why = "The slowest bolt in the game and the second-hardest round — a rifle that is only ever as good as your first shot, which is why it is cheap.",
	stats = {
		damageNear = 160, damageFar = 160, rangeNear = 195, rangeFar = 230,
		headshotMult = 2.0, rpm = 38, auto = false, magSize = 5, reloadSeconds = 3.8,
		spreadDeg = 2.6, adsSpreadDeg = 0.03,
		recoilVert = 2.60, recoilHoriz = 0.36, recoilRecovery = 5,
		-- walk 14.1, sprint 18.7
		velocity = 2900, drop = 12, moveSpeedMult = 0.83, sprintSpeedMult = 0.78,
		equipTime = 0.76, sprintToFire = 0.46, adsTime = 0.68,
	},
}
