--!strict
-- Marshmallow — battle rifle. Was a Bullpup, which was a rifle with a nametag.
return {
	name = "Marshmallow",
	class = "BattleRifle",
	slot = "Primary",
	rarity = "Rare",
	price = 6400,
	why = "Holds its four-shot kill out to 62 studs where every rifle has dropped to five, and aims down slowly enough that you must see them first.",
	stats = {
		damageNear = 27, damageFar = 20, rangeNear = 62, rangeFar = 125,
		headshotMult = 1.55, rpm = 480, auto = true, magSize = 24, reloadSeconds = 2.5,
		spreadDeg = 1.5, adsSpreadDeg = 0.15,
		recoilVert = 0.62, recoilHoriz = 0.18, recoilRecovery = 10,
		velocity = 1720, drop = 26, moveSpeedMult = 0.97,
		equipTime = 0.50, sprintToFire = 0.20, adsTime = 0.32,
	},
}
