--!strict
-- HealthConfig — how much health, and how it comes back (NOD-134). Data only.
--
-- 150hp, one pool, CoD-style: it comes back on its own after a beat, and a stim
-- brings it back faster on demand. Objective modes (Domination, Hardpoint, Kill
-- Confirmed) are the reason it works this way — a mode where you have to STAND
-- somewhere cannot also be a mode where health only comes from kills, because
-- holding a point would mean bleeding out with no way to fix it.
--
-- Why 150 rather than 100: at 100hp the only per-shot damage values that exist
-- are 34/25/20/17/15 — five breakpoints to spread fifty guns across, which is
-- the arithmetic reason seven rifles ended up within 0.08s of each other. 150
-- gives 50/37.5/30/25/21.4/18.75/16.7/15, so two guns can differ by one shot
-- without a cliff in damage.
--
-- The TTK windows in ClassCharter are stated in SECONDS, so none of them move
-- when this number does. That is the whole reason they are stated that way.

return {
	maxHealth = 150,

	-- CoD-style regeneration: nothing for a beat after you were last hit, then
	-- back quickly. The delay is the number that matters — it is what decides
	-- whether disengaging from a fight is a real option or a death sentence,
	-- and it is the difference between trading damage being survivable and
	-- every fight being decided by who shot first.
	regenDelaySeconds = 5,
	regenPerSecond = 50,

	-- The stim: heal on demand, on a recharging charge rather than a pickup.
	-- Its job is to let you re-enter a fight you just won without waiting out
	-- the regen delay — which is the difference between aggression being
	-- rewarded and aggression being punished by the clock.
	--
	-- Heals over a moment rather than instantly, so using one in the middle of
	-- a fight is a decision with a cost rather than a free reset.
	stimHealAmount = 150,
	stimHealSeconds = 1.2,
	stimCharges = 2,
	stimRechargeSeconds = 40,

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
