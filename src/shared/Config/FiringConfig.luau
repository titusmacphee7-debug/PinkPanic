--!strict
-- FiringConfig — the numbers behind the trigger (NOD-136).
--
-- Per-gun handling lives in GunCatalog: fire rate, magazine, reload, equip
-- time, sprint-to-fire. What is here is the stuff that is the same for every
-- gun in the game, plus the tolerances the client/server seam needs.
--
-- Data only. The state machine that reads these is shared/Systems/Weapon.

local FiringConfig = {}

-- ---------------------------------------------------------------------------
-- Reload
-- ---------------------------------------------------------------------------

-- Where in the reload the rounds actually land now lives in `derive.cancelFraction`
-- below, with the other three derived handling times (NOD-143). It used to be
-- here as `reloadAmmoFraction`; having it in two places would be two answers to
-- the single most important number in how a reload feels.

-- Shotguns load shells one at a time and can be cut off between any two.
-- `shellReload` in the catalog is the per-shell cadence; this is the wind-up
-- before the first shell and the wind-down after the last, which is what stops
-- shell-by-shell from being strictly better than a magazine at every count.
FiringConfig.shellReloadStartSeconds = 0.35
FiringConfig.shellReloadEndSeconds = 0.4

-- ---------------------------------------------------------------------------
-- Handling
-- ---------------------------------------------------------------------------

-- Putting a gun away, when the gun does not say. Holstering a light pistol and
-- an LMG are not the same motion, so the real number is DERIVED from the gun's
-- own equipTime below and this is only the floor.
FiringConfig.holsterSeconds = 0.18

-- Sprint has to actually end before sprintToFire starts counting, otherwise
-- tapping sprint for one frame while already firing costs nothing.
FiringConfig.sprintReleaseGraceSeconds = 0.05

-- ---------------------------------------------------------------------------
-- Derived handling times (NOD-143)
--
-- The issue lists nine per-gun timings. Four of them are not in the catalog and
-- were not going to be typed thirty-two times each: a number entered once per
-- gun by hand is a number that gets entered wrong, and 128 of them is a balance
-- surface nobody can hold in their head.
--
-- So they are DERIVED from the timings the catalog does have, each with a
-- ratio here, and any gun may override its own by naming the field directly.
-- Derivation is not a shortcut — it is what makes "heavy guns are slow" one
-- decision instead of thirty-two.
-- ---------------------------------------------------------------------------

FiringConfig.derive = {
	-- holsterTime. Putting a gun away is quicker than bringing it up, but a
	-- heavy gun is slow at both.
	holsterFromEquip = 0.7,
	-- reloadEmptyTime. From empty there is a bolt to run, so it costs more.
	emptyFromReload = 1.25,
	-- reloadCancelTime, where the rounds actually land, as a fraction of
	-- whichever reload is running — so the empty reload's payout moves with it.
	--
	-- The single most important number in how a reload FEELS. A reload that only
	-- pays out on the last frame punishes you for the animation's follow-through;
	-- one that pays out instantly makes reload cancelling free. 0.72 means the
	-- magazine is in at roughly the point the animation seats it, and the last
	-- quarter-second — the pat, the charging handle — can be cancelled by
	-- sprinting or swapping with the ammo already banked.
	cancelFraction = 0.72,
	-- tacSprintToFire. Tactical sprint has the gun right down, and this is the
	-- cost that stops it being a free upgrade over an ordinary sprint.
	tacFromSprint = 1.9,
}

-- ---------------------------------------------------------------------------
-- Aiming down sights (NOD-143)
-- ---------------------------------------------------------------------------

FiringConfig.ads = {
	-- Movement speed while aimed, as a multiple. Aiming is a trade, and this is
	-- the half of the trade the player feels.
	moveSpeedMult = 0.62,
	-- How far into the ADS transition the tighter cone starts to apply. Aiming
	-- is not a switch: half-aimed is half the benefit, which is what makes
	-- adsTime a stat worth caring about rather than a cosmetic animation length.
	spreadAtFraction = 0.85,
	-- **The server does not take the client's word for free.**
	--
	-- Sprinting is safe to self-report because claiming it only ever DELAYS your
	-- own shots. Aiming is the opposite: it tightens your cone, so a modified
	-- client would simply always claim it. The claim is therefore only honoured
	-- while the player's measured speed is within this multiple of the ADS
	-- speed cap — which is a thing the server samples anyway, in MoveAudit.
	--
	-- Lying then costs you exactly what telling the truth costs you: you have to
	-- actually slow down.
	speedToleranceMultiplier = 1.35,
}

-- ---------------------------------------------------------------------------
-- Burst
-- ---------------------------------------------------------------------------

-- A burst gun sets `burstCount` in the catalog. `burstRpm` is optional: when
-- absent the burst runs at the gun's own rpm, and the gap between bursts is
-- what makes it a burst weapon rather than a slow auto.
--
-- No gun in the roster is burst yet. The mode exists, and is tested, so that
-- making one burst is one line in GunCatalog rather than a firing rewrite.
FiringConfig.burstGapSeconds = 0.22

-- ---------------------------------------------------------------------------
-- The client/server seam
-- ---------------------------------------------------------------------------

-- The client predicts its own ammo and the server owns the truth. They drift
-- for one round-trip after every shot, which is normal and must never produce
-- a correction — a magazine counter that flickers is worse than one that is
-- briefly stale.
--
-- A correction is sent when the disagreement exceeds this, which in practice
-- means the client got a shot rejected and does not know it yet.
FiringConfig.ammoDesyncTolerance = 1

-- How often the server may re-state a player's ammo when nothing is wrong.
-- The heartbeat exists so a client that missed a correction packet recovers
-- without needing another rejected shot to notice.
FiringConfig.ammoHeartbeatSeconds = 2

-- Rejections are normal at a low rate: the client fires on the frame its
-- magazine empties, the server has already counted the shot before it. A rate
-- above this is either lag worth knowing about or a client that is lying, and
-- either way the manifest should say so rather than the shots just vanishing.
FiringConfig.rejectionRateWarn = 0.08

-- Below this many shots the rate is noise — one rejection out of three is 33%
-- and means nothing.
FiringConfig.rejectionRateMinShots = 40

return FiringConfig
