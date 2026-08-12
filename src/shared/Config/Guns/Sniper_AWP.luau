--!strict
-- Whisper (AWP) — the middle sniper and the tightest cone of the four. Nothing
-- remarkable about the round; everything remarkable about how reliably it goes
-- where you pointed it.
return {
	name = "Whisper",
	archetype = "AWP",
	class = "Sniper",
	slot = "Primary",
	rarity = "Rare",
	price = 4800,
	unlockLevel = 33,
	why = "The most accurate rifle in the game and the flattest round — it does not hit harder than the others, it simply never misses for a reason that was the gun's fault.",
	stats = {
		damageNear = 156, damageFar = 156, rangeNear = 190, rangeFar = 225,
		headshotMult = 2.0, rpm = 50, auto = false, magSize = 5, reloadSeconds = 3.6,
		spreadDeg = 1.9, adsSpreadDeg = 0.01,
		recoilVert = 2.10, recoilHoriz = 0.24, recoilRecovery = 6,
		-- walk 14.3, sprint 19.0
		velocity = 3200, drop = 8, moveSpeedMult = 0.84, sprintSpeedMult = 0.79,
		equipTime = 0.74, sprintToFire = 0.44, adsTime = 0.64,
	},
}
