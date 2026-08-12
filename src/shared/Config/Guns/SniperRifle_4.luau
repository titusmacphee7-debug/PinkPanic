--!strict
-- Star Crossed — marksman.
--
-- This is the gun that used to one-shot at every range with no falloff, which
-- NOD-148 named as the single worst thing in the roster.
--
-- It was rewritten TWICE. The first pass made it a 2-shot at 0.30s, which the
-- TTK table immediately showed was the same bug in a new costume: flat damage
-- plus a 0.30s kill meant it beat every rifle at every distance, and "the AR is
-- strictly best" had simply become "the marksman is strictly best". Three
-- shots at 0.43s puts it behind every rifle up close and ahead of all of them
-- past 60 studs, which is the trade the class is supposed to be making.
return {
	name = "Star Crossed",
	class = "Marksman",
	slot = "Primary",
	rarity = "Epic",
	price = 10800,
	why = "Kills in three at ANY distance, so it beats a rifle everywhere the rifle has started to fall off and loses to it everywhere else.",
	stats = {
		damageNear = 40, damageFar = 35, rangeNear = 115, rangeFar = 210,
		headshotMult = 1.8, rpm = 280, auto = false, magSize = 10, reloadSeconds = 2.5,
		spreadDeg = 2.6, adsSpreadDeg = 0.08,
		recoilVert = 1.05, recoilHoriz = 0.15, recoilRecovery = 11,
		velocity = 2100, drop = 20, moveSpeedMult = 0.94,
		equipTime = 0.58, sprintToFire = 0.29, adsTime = 0.40,
	},
}
