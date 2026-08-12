--!strict
-- RecoilConfig — the recoil patterns, and the rule that does not move (NOD-144).
--
-- **Recoil has no bloom.** Titus vetoed it and the veto stands. Spread is a
-- fixed per-gun cone that never grows — `spreadDeg` from the hip, `adsSpreadDeg`
-- aimed — and the CAMERA climbs instead.
--
-- The reason is about who is holding the controller. Bloom punishes you for
-- firing accurately: your bullets quietly stop going where the crosshair points
-- and nothing on screen tells you why. Pattern recoil punishes you for not
-- learning the gun, which is a thing you can see happening and fix. For a game
-- whose target audience is new players, that difference is the whole design.
--
-- A pattern is an ordered list of per-shot kicks. Shot 7 of an AR always goes to
-- the same place, so the gun can be LEARNED. A small random jitter sits on top
-- as a percentage of each kick so it is not robotic, but the shape is fixed.
--
-- Data only.

local RecoilConfig = {}

-- ---------------------------------------------------------------------------
-- The patterns
--
-- Each entry is `{vert, horiz}` as a MULTIPLE of the gun's own `recoilVert` and
-- `recoilHoriz`. Relative rather than absolute, which is the whole reason there
-- are six patterns instead of thirty-two: the SHAPE of a gun's climb is a
-- family trait, the SIZE of it is that gun's own stat. An LMG and an SMG can
-- share "climbs then drifts left" and still kick completely differently.
--
-- Positive vert is up. Positive horiz is right.
--
-- Past the end of a list it LOOPS, so a 100-round drum does not run out of
-- pattern and fall back to something else halfway through the magazine.
-- ---------------------------------------------------------------------------

export type Kick = { vert: number, horiz: number }

RecoilConfig.patterns = {
	-- The classic AR: a hard vertical opening you can pull straight down, then
	-- a lean to the right that catches people who only learned the first half.
	climbThenRight = {
		{ vert = 1.15, horiz = 0 },
		{ vert = 1.1, horiz = 0.15 },
		{ vert = 1, horiz = -0.1 },
		{ vert = 0.95, horiz = 0.3 },
		{ vert = 0.85, horiz = 0.5 },
		{ vert = 0.8, horiz = 0.7 },
		{ vert = 0.7, horiz = 0.85 },
		{ vert = 0.65, horiz = 0.95 },
		{ vert = 0.6, horiz = 1 },
		{ vert = 0.6, horiz = 0.9 },
	},

	-- SMGs: less climb, more wander. Hard to hold at range on purpose — that is
	-- what keeps a 1000rpm gun from also being a rifle.
	--
	-- It DRIFTS left while it wobbles, rather than alternating evenly. The first
	-- version alternated sign shot for shot and summed to almost nothing, so the
	-- gun vibrated a tenth of a stud and came straight back — which reads as a
	-- rifle with a shake, not as a gun that runs away from you. A wander has to
	-- go somewhere.
	fastWander = {
		{ vert = 0.9, horiz = -0.3 },
		{ vert = 0.85, horiz = 0.25 },
		{ vert = 0.8, horiz = -0.7 },
		{ vert = 0.75, horiz = -0.45 },
		{ vert = 0.7, horiz = 0.6 },
		{ vert = 0.7, horiz = -0.9 },
		{ vert = 0.65, horiz = -1.1 },
		{ vert = 0.65, horiz = 0.5 },
	},

	-- LMGs: an S. Up, out left, back through the middle, out right. Long,
	-- readable, and it rewards a player who commits to holding a beam.
	sweepingS = {
		{ vert = 1.2, horiz = 0 },
		{ vert = 1.1, horiz = -0.25 },
		{ vert = 0.95, horiz = -0.5 },
		{ vert = 0.85, horiz = -0.65 },
		{ vert = 0.75, horiz = -0.4 },
		{ vert = 0.7, horiz = 0 },
		{ vert = 0.65, horiz = 0.4 },
		{ vert = 0.6, horiz = 0.65 },
		{ vert = 0.55, horiz = 0.8 },
		{ vert = 0.55, horiz = 0.6 },
		{ vert = 0.5, horiz = 0.2 },
		{ vert = 0.5, horiz = -0.2 },
	},

	-- Semi-autos. Every shot is the same snap because every shot is a decision;
	-- there is no pattern to learn when you are not holding the trigger.
	snap = {
		{ vert = 1, horiz = 0.1 },
		{ vert = 1, horiz = -0.1 },
	},

	-- Snipers and shotguns: one enormous kick that has recovered before you can
	-- fire again, so what matters is the SIZE, not the shape.
	heavyThump = {
		{ vert = 1, horiz = 0.2 },
		{ vert = 1, horiz = -0.2 },
	},
}

-- Which pattern each gun class gets, when the gun does not name one itself.
--
-- Per-class rather than per-gun because a pattern is a family trait and 32
-- hand-authored arrays is 32 chances to author one badly and never notice. Any
-- gun overrides by naming `recoilPattern` in the catalog, which is what a gun
-- with a real identity of its own should do.
RecoilConfig.byClass = {
	Pistol = "snap",
	Revolver = "heavyThump",
	SMG = "fastWander",
	Shotgun = "heavyThump",
	Rifle = "climbThenRight",
	-- A battle rifle is an AR that reaches, so it climbs like one. The
	-- difference the player feels is the size of each kick, which comes from the
	-- gun's own recoilVert, not from a different shape.
	BattleRifle = "climbThenRight",
	-- The S was written for this class before the class existed (NOD-148). A
	-- long readable sweep is only legible on a gun you hold the trigger down on
	-- for two seconds, which is the LMG and nothing else.
	LMG = "sweepingS",
	-- Semi-auto: there is no pattern to learn when you are not holding the
	-- trigger, so every shot is the same snap.
	Marksman = "snap",
	Sniper = "heavyThump",
}

RecoilConfig.defaultPattern = "climbThenRight"

-- ---------------------------------------------------------------------------
-- Jitter
--
-- A PERCENTAGE of the kick, never an absolute value. An absolute jitter is the
-- same wobble on a pistol as on an LMG, which means it is invisible on one and
-- dominates the other — and a jitter that dominates is bloom wearing a hat.
-- ---------------------------------------------------------------------------

RecoilConfig.jitterFraction = 0.12

-- ---------------------------------------------------------------------------
-- Horizontal scale
--
-- One dial for how far these guns wander sideways, applied to every pattern's
-- `horiz` on the way out.
--
-- It exists because the catalog's `recoilHoriz` values sit around a fifth of
-- their `recoilVert`, so every horizontal shape in this file came out under a
-- fifth of a stud at 30 studs — the S-sweep and the SMG drift were both real,
-- both correct, and both far too small for a player to ever see. The choice was
-- one number here or thirty-two edits in the catalog, where `recoilHoriz` also
-- means something to the attachment modifiers.
--
-- The horizontal ceiling still caps the result, so this widens the shape without
-- letting any gun become unholdable.
-- ---------------------------------------------------------------------------

RecoilConfig.horizontalScale = 2.6

-- ---------------------------------------------------------------------------
-- Recovery
-- ---------------------------------------------------------------------------

-- The standard CoD partial return: this much of the burst's climb snaps back on
-- its own, and the remainder lingers. What is left is the part you have to pull
-- down yourself, and it is the reason controlling a gun is a skill rather than a
-- waiting game.
--
-- Measured from the PEAK of the burst, not from wherever the camera is this
-- frame — see Systems/Recoil.step for why the first version of that quietly
-- returned everything and made this number a no-op.
RecoilConfig.returnFraction = 0.72

-- How much slower the last of it bleeds off, once the fast return is spent.
-- Low enough that the tail is something you notice and correct; not zero,
-- because a residue that never leaves walks the camera into its own ceiling and
-- switches the whole system off partway through a match.
RecoilConfig.tailRateFraction = 0.3

-- How long after the last shot before recovery starts, **in shots** rather than
-- in seconds.
--
-- This was 0.09s flat and it quietly deleted most of the patterns in the game.
-- A rifle at 420rpm leaves 0.143s between rounds, so recovery ran between every
-- single shot of a held burst: the Grump plateaued at 0.9° instead of climbing
-- to its 6.12° ceiling, and shots 10 through 30 all landed on top of each other.
-- Only guns above ~660rpm were fast enough to keep their shape, which is not a
-- rule anybody chose.
--
-- Above 1, so the gap inside a burst is always shorter than the delay and
-- sustained fire never recovers at all. That is what makes shot 7 land in the
-- same place every time: recovery inside a burst would make each shot depend on
-- the exact millisecond the last one left, which is a pattern you cannot learn
-- because it is never quite the same twice.
--
-- The moment you release, recovery starts a little over one shot later.
RecoilConfig.returnDelayShots = 1.35
-- Clamps, because "one shot" is 0.05s on an SMG and 1.5s on a sniper. The floor
-- keeps a fast gun from feeling sticky; the ceiling means a slow gun still gets
-- to settle between deliberate shots, which is the entire feel of a revolver.
RecoilConfig.returnDelayMinSeconds = 0.06
RecoilConfig.returnDelayMaxSeconds = 0.4

-- ---------------------------------------------------------------------------
-- Ceilings
--
-- Derived from the gun's OWN first kick rather than shared, so a pistol that
-- kicks 0.38° and an LMG that kicks 1.4° do not top out in the same place.
-- ---------------------------------------------------------------------------

-- Where the climb stops, measured in first-shots. Past here the gun stops going
-- up and only drifts sideways — the "wall" every AR has, and the point after
-- which holding the trigger is a decision rather than a habit.
--
-- 15 rather than 9: with recovery no longer eating the burst, 9 put the Grump's
-- wall at shot 7 of a 25-round magazine, so two thirds of the pattern was a flat
-- line with nothing left to learn.
RecoilConfig.ceilingShots = 15
-- Sideways drift is capped tighter than climb. A gun that can wander as far
-- horizontally as it climbs vertically is a gun you cannot hold at all.
RecoilConfig.horizontalCeilingFraction = 0.55

-- ---------------------------------------------------------------------------
-- Modifiers
--
-- Everything that makes recoil smaller. Multiplied together, so a crouched
-- player aiming down sights gets both.
-- ---------------------------------------------------------------------------

RecoilConfig.adsMultiplier = 0.72
RecoilConfig.stanceMultiplier = {
	Idle = 1,
	Walk = 1,
	Sprint = 1,
	TacSprint = 1,
	Crouch = 0.85,
	Prone = 0.7,
	Slide = 1.15,
	Dive = 1.3,
	Air = 1.25,
	Mantle = 1,
	Stun = 1,
}

-- ---------------------------------------------------------------------------
-- Visual recoil
--
-- The GUN kicks harder than your AIM does. That gap is most of what makes a
-- weapon feel powerful without making it hard to shoot — the viewmodel is
-- theatre, the camera is the part that costs you accuracy.
--
-- Consumed by the viewmodel (M11); published now so the number lives with the
-- rest of recoil rather than being invented later by whoever builds the gun.
-- ---------------------------------------------------------------------------

RecoilConfig.visualMultiplier = 2.4
RecoilConfig.visualRecoverySeconds = 0.12

return RecoilConfig
