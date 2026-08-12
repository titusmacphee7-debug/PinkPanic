--!strict
-- Sparkler 12 (Saiga-12) — full-auto, twenty-round drum, twelve LIGHT pellets in
-- the widest cone in the game. It is the one shotgun that never one-shots
-- anybody and the only one that can hold down a doorway.
--
-- The light pellets are the trade, and they are why this is the shotgun that
-- most needs the fixed pattern: twelve small hits are exactly the case where
-- random scatter turns "two shots" into "six" for no reason the player can see.
return {
	name = "Sparkler 12",
	archetype = "Saiga-12",
	class = "Shotgun",
	slot = "Primary",
	rarity = "SuperRare",
	price = 5200,
	unlockLevel = 42,
	why = "Full-auto with twenty rounds — it never one-shots anyone and it is the only shotgun that can hold a doorway against three people.",
	stats = {
		damageNear = 8, damageFar = 2.2, rangeNear = 8, rangeFar = 58, pellets = 12,
		headshotMult = 1.35, rpm = 225, auto = true, magSize = 20, reloadSeconds = 3.6,
		spreadDeg = 5.4, adsSpreadDeg = 3.6,
		recoilVert = 0.70, recoilHoriz = 0.30, recoilRecovery = 11,
		-- walk 16.2, sprint 22.3 — the heaviest shotgun
		velocity = 1000, drop = 62, moveSpeedMult = 0.95, sprintSpeedMult = 0.93,
		equipTime = 0.42, sprintToFire = 0.17, adsTime = 0.30,
	},
}
