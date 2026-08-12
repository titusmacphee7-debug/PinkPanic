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

-- Where in the reload the rounds actually land, as a fraction of reloadSeconds.
--
-- This is `reloadCancelTime` in COD terms and it is the single most important
-- number in how a reload FEELS. A reload that only pays out on the last frame
-- punishes you for the animation's follow-through; one that pays out instantly
-- makes reload cancelling free. 0.72 means the magazine is in at roughly the
-- point the animation seats it, and the last quarter-second — the pat, the
-- charging handle — can be cancelled by sprinting or swapping with the ammo
-- already banked.
FiringConfig.reloadAmmoFraction = 0.72

-- Shotguns load shells one at a time and can be cut off between any two.
-- `shellReload` in the catalog is the per-shell cadence; this is the wind-up
-- before the first shell and the wind-down after the last, which is what stops
-- shell-by-shell from being strictly better than a magazine at every count.
FiringConfig.shellReloadStartSeconds = 0.35
FiringConfig.shellReloadEndSeconds = 0.4

-- ---------------------------------------------------------------------------
-- Handling
-- ---------------------------------------------------------------------------

-- Putting a gun away. Not in the catalog because holstering is the same motion
-- whatever you are holding — the gun you are drawing owns the time that
-- follows, via its own equipTime.
FiringConfig.holsterSeconds = 0.18

-- Sprint has to actually end before sprintToFire starts counting, otherwise
-- tapping sprint for one frame while already firing costs nothing.
FiringConfig.sprintReleaseGraceSeconds = 0.05

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
