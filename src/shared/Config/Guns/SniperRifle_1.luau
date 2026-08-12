--!strict
-- Whisper — the baseline sniper.
--
-- damageNear is 105 on purpose. A torso hit is 105 and kills; a LIMB hit is
-- 105 x 0.9 = 94.5 and does not. That single digit is the whole "upper chest
-- and head, never a limb" rule from NOD-148, and Balance.validate checks it at
-- boot rather than trusting anyone to remember why 105 is not 120.
return {
	name = "Whisper",
	class = "Sniper",
	slot = "Primary",
	rarity = "Rare",
	price = 8400,
	why = "One shot to the chest inside 180 studs; miss the chest and you have lost the fight, because the second shot takes most of a second.",
	stats = {
		damageNear = 105, damageFar = 88, rangeNear = 180, rangeFar = 360,
		headshotMult = 1.5, rpm = 45, auto = false, magSize = 5, reloadSeconds = 3.1,
		spreadDeg = 5.5, adsSpreadDeg = 0.07,
		recoilVert = 1.70, recoilHoriz = 0.24, recoilRecovery = 9,
		velocity = 2280, drop = 18, moveSpeedMult = 0.92,
		equipTime = 0.68, sprintToFire = 0.36, adsTime = 0.54,
	},
}
