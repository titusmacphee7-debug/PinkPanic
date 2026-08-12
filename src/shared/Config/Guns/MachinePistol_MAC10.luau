--!strict
-- Mac & Cheese (MAC-10) — the heavy machine pistol. Slowest of the three and
-- the hardest-hitting, so it is a five-shot kill where the Uzi needs seven, with
-- thirty-two rounds to do it.
return {
	name = "Mac & Cheese",
	archetype = "MAC-10",
	class = "MachinePistol",
	slot = "Secondary",
	rarity = "Uncommon",
	price = 2400,
	unlockLevel = 21,
	why = "Five shots where the Uzi needs seven, and thirty-two rounds behind it — the machine pistol you can actually finish two people with.",
	stats = {
		damageNear = 30, damageFar = 12, rangeNear = 16, rangeFar = 42,
		headshotMult = 1.4, rpm = 700, auto = true, magSize = 32, reloadSeconds = 1.9,
		spreadDeg = 3.4, adsSpreadDeg = 0.66,
		recoilVert = 0.52, recoilHoriz = 0.28, recoilRecovery = 15,
		-- walk 17.5, sprint 25.0
		velocity = 1000, drop = 60, moveSpeedMult = 1.03, sprintSpeedMult = 1.04,
		equipTime = 0.24, sprintToFire = 0.08, adsTime = 0.16,
	},
}
