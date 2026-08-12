--!strict
-- HealthConfig — how much health, and how it comes back (NOD-134). Data only.

return {
	maxHealth = 100,

	-- CoD-style regeneration: nothing for a beat after you were last hit, then
	-- back quickly. The delay is the number that matters — it is what decides
	-- whether disengaging from a fight is a real option or a death sentence,
	-- and it is the difference between trading damage being survivable and
	-- every fight being decided by who shot first.
	regenDelaySeconds = 5,
	regenPerSecond = 40,

	-- Off by default. Team modes (M9) turn it on or off per mode; until then
	-- the safe answer is that you cannot kill your own team by accident.
	friendlyFire = false,

	-- How long after a kill an earlier damage contribution still counts as an
	-- assist. Long enough that softening someone up is rewarded, short enough
	-- that a hit from a minute ago is not.
	assistWindowSeconds = 10,

	-- Damage below this is dropped rather than applied. Guards against a
	-- pellet at extreme falloff registering as a hit that removes nothing —
	-- which shows a hitmarker, makes a sound, and teaches the player their
	-- shot mattered when it did not.
	minimumDamage = 0.5,
}
