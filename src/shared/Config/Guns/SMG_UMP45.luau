--!strict
-- Bumper 45 (UMP-45) — the SMG that reaches. Longest range of the six and the
-- only one still killing in six at 43 ft, fired slowly enough that it is closer
-- to a small rifle than to the rest of its class.
return {
	name = "Bumper 45",
	archetype = "UMP-45",
	class = "SMG",
	slot = "Primary",
	rarity = "Uncommon",
	price = 1600,
	unlockLevel = 10,
	why = "The longest reach in the class and a four-shot kill up close — the SMG for people who keep getting caught at ranges an SMG should not be at.",
	stats = {
		damageNear = 38, damageFar = 18, rangeNear = 20, rangeFar = 68,
		headshotMult = 1.4, rpm = 650, auto = true, magSize = 25, reloadSeconds = 2.0,
		spreadDeg = 2.3, adsSpreadDeg = 0.28,
		recoilVert = 0.36, recoilHoriz = 0.17, recoilRecovery = 15,
		-- walk 17.3, sprint 24.7
		velocity = 1150, drop = 50, moveSpeedMult = 1.02, sprintSpeedMult = 1.03,
		equipTime = 0.32, sprintToFire = 0.11, adsTime = 0.20,
	},
}
