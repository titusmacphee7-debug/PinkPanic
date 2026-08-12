--!strict
-- ScaleConfig — what a stud is, in real units (NOD-169).
--
-- Studs are meaningless on their own. "This shotgun works to 40 studs" is not a
-- sentence anyone can sanity-check, and that is how a game ends up with a
-- shotgun that dies at conversational distance and a sniper lane you could
-- cross by walking. Declaring the character's real height gives every other
-- distance in the game a real-world referent for free.
--
-- The chain is: the character is a known height in feet, we MEASURE that same
-- character in studs, and the ratio between them converts everything else. So
-- the conversion cannot drift from the game — change the rig and the number
-- follows it, because `Systems/Scale` recalibrates from a live character.
--
-- Data only. The measurement and the maths live in `Systems/Scale`.

local ScaleConfig = {}

-- How tall the standard Pink Panic character is *meant* to be, in inches.
-- 68in / 5'8" is a deliberately neutral adult height: the rig is one fixed size
-- for every player (NOD-167), so this is the height of everyone in the game and
-- not an average of anything.
--
-- This is the one number to change if the world ever feels too big or too
-- small. Everything else is derived.
ScaleConfig.characterHeightInches = 68

-- The same character, measured in studs. Bounding-box height of the standard
-- R15 rig, taken on 2026-08-12 from a live spawn.
--
-- Height specifically, because it is the one axis that is pose-invariant: the
-- same character measured on spawn and a second later after the idle animation
-- settled differed by 0.9 studs in X and Z and matched to three decimals in Y
-- (see CharacterService). A conversion that changes when someone lowers their
-- arms is not a conversion.
--
-- Kept here as the fallback so the maths works before anybody has spawned and
-- in Edit mode. `Scale.calibrate` replaces it from the real rig at runtime and
-- says so if it has moved.
ScaleConfig.referenceRigStuds = 5.3187

-- Rounding for display. Distances are quoted to the nearest foot below this
-- many feet and to the nearest five above it — "43 ft" is useful, "437 ft" is
-- false precision on a number nobody paces out.
ScaleConfig.coarseAboveFeet = 100

return ScaleConfig
