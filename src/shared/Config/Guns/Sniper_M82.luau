--!strict
-- Big Boo Boo (Barrett M82) — the hardest round in the game, and the only
-- SEMI-AUTOMATIC sniper. It fires nearly twice as fast as any bolt gun, which
-- means a missed shot is recoverable, which is the actual reason it is the
-- best sniper and costs the most.
--
-- 165 damage is the ceiling, not a choice: limbs take 0.9x and 166 would
-- one-shot someone through a foot.
return {
	name = "Big Boo Boo",
	archetype = "Barrett M82",
	class = "Sniper",
	slot = "Primary",
	rarity = "Legendary",
	price = 7500,
	unlockLevel = 50,
	why = "The only semi-automatic sniper — it can miss and immediately try again, which no bolt gun can, and it hits harder than all of them while doing it.",
	stats = {
		damageNear = 165, damageFar = 165, rangeNear = 200, rangeFar = 235,
		headshotMult = 2.0, rpm = 70, auto = false, magSize = 10, reloadSeconds = 4.2,
		spreadDeg = 2.8, adsSpreadDeg = 0.04,
		recoilVert = 3.00, recoilHoriz = 0.42, recoilRecovery = 4,
		-- walk 13.6, sprint 18.0 — the slowest anything moves in Pink Panic
		velocity = 3400, drop = 6, moveSpeedMult = 0.80, sprintSpeedMult = 0.75,
		equipTime = 0.80, sprintToFire = 0.50, adsTime = 0.72,
	},
}
