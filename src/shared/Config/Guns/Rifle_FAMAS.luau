--!strict
-- Tutu (FAMAS) — three-round burst, four-shot kill. Two bursts and someone is
-- down, which makes it the fastest rifle in the game AT the trigger pull and
-- the slowest one if you fumble the second press.
--
-- `rpm` is the gap BETWEEN bursts; `burstRpm` is the cadence inside one.
return {
	name = "Tutu",
	archetype = "FAMAS",
	class = "Rifle",
	slot = "Primary",
	rarity = "Rare",
	price = 3400,
	unlockLevel = 30,
	why = "Two bursts kill inside 43 ft, so it beats every automatic rifle that has to land five — as long as you can hit with a weapon that stops firing when you still want it to.",
	stats = {
		damageNear = 39, damageFar = 19, rangeNear = 34, rangeFar = 100,
		headshotMult = 1.5, rpm = 300, auto = false, magSize = 25, reloadSeconds = 2.2,
		burstCount = 3, burstRpm = 900,
		spreadDeg = 1.4, adsSpreadDeg = 0.15,
		recoilVert = 0.40, recoilHoriz = 0.11, recoilRecovery = 15,
		velocity = 1950, drop = 28, moveSpeedMult = 1.00,
		equipTime = 0.42, sprintToFire = 0.16, adsTime = 0.26,
	},
}
