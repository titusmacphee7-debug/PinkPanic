--!strict
-- Night Night (Remington 700) — the free sniper, and the quickest of the four
-- to get on target. One shot kills at any range in the game including point
-- blank; what stops that being oppressive is the 0.62s it takes to aim and the
-- 1.3 seconds between rounds.
--
-- Damage is 152 and not higher for a reason worth writing down: limbs take 0.9x,
-- so anything over 166 one-shots someone through a FOOT. A sniper deleting a
-- chest is the class doing its job; a sniper deleting a foot is the thing that
-- makes a lobby quit, and `Balance.validate` fails the build for it.
return {
	name = "Night Night",
	archetype = "Remington 700",
	class = "Sniper",
	slot = "Primary",
	rarity = "Common",
	price = 0,
	unlockLevel = 1,
	why = "Free, and one shot kills at any distance — the quickest sniper to aim and the least punishing to learn on, which is why it is the one everybody starts with.",
	stats = {
		damageNear = 152, damageFar = 152, rangeNear = 180, rangeFar = 220,
		headshotMult = 2.0, rpm = 45, auto = false, magSize = 5, reloadSeconds = 3.4,
		spreadDeg = 2.2, adsSpreadDeg = 0.02,
		recoilVert = 2.20, recoilHoriz = 0.30, recoilRecovery = 6,
		-- walk 14.5, sprint 19.2
		velocity = 3000, drop = 10, moveSpeedMult = 0.85, sprintSpeedMult = 0.80,
		equipTime = 0.72, sprintToFire = 0.42, adsTime = 0.62,
	},
}
