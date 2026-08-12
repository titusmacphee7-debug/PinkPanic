--!strict
-- CameraConfig — every number the camera uses, in one file (NOD-142).
--
-- The slide roll used to live in MovementConfig, which was defensible right up
-- until there were four camera effects in three files and "where do I turn this
-- down" had no answer. A camera number belongs here even when the thing causing
-- it is a movement state.
--
-- Data only.

local CameraConfig = {}

-- ---------------------------------------------------------------------------
-- Field of view
--
-- Only ever written in COMBAT. The lobby camera is a fixed, hand-placed shot
-- that Titus composed at whatever FOV the place file has, and changing the FOV
-- changes that composition — a kick that reads as speed in first person reads
-- as the storefront breathing when the camera is looking AT you.
-- ---------------------------------------------------------------------------

CameraConfig.baseFov = 90
-- What the settings slider allows. Wider than most games because a shooter FOV
-- is a comfort setting before it is a competitive one.
CameraConfig.fovMin = 70
CameraConfig.fovMax = 110

-- Degrees added on top of the base while in each state. Absent means none.
--
-- The kick IS the speed cue. It is why tactical sprint feels faster than sprint
-- by more than its five extra studs a second deserve, and it is the cheapest
-- honest way to make a slide read as fast.
CameraConfig.fovKick = {
	Sprint = 5,
	TacSprint = 11,
	Slide = 14,
	Dive = 8,
}

-- How fast the FOV chases its target. A time constant, not a rate: the same
-- number produces the same feel whatever the frame rate.
CameraConfig.fovSeconds = 0.14
-- Coming DOWN off a kick is slower than going up. A snap back to base at the
-- end of a sprint reads as a stutter; easing out reads as settling.
CameraConfig.fovReleaseSeconds = 0.22

-- Aiming down sights, as a fraction of the base FOV, by gun class.
--
-- Per-CLASS rather than per-gun, because "per-optic" means optics, and optics
-- are attachments (M4). A sniper is a different instrument from an SMG and that
-- is the distinction worth having today; the day a 4x scope exists it overrides
-- this by class the same way.
CameraConfig.adsFovScale = {
	Pistol = 0.86,
	Revolver = 0.82,
	SMG = 0.88,
	Shotgun = 0.9,
	Rifle = 0.8,
	BattleRifle = 0.74,
	LMG = 0.84,
	-- Between a rifle and a sniper, which is the whole class: enough
	-- magnification to pick a chest out at 120 studs, not enough to lose the
	-- room around it.
	Marksman = 0.6,
	Sniper = 0.42,
}

-- ---------------------------------------------------------------------------
-- Roll, tilt and dip
--
-- All three are OFFSETS multiplied onto whatever the camera already is. None of
-- them writes an absolute CFrame, which is what makes them composable and what
-- keeps them from fighting the player's mouse.
-- ---------------------------------------------------------------------------

-- Slide lean. Proportional to how far the slide heading has carved away from
-- where you are looking, so a straight slide gets none and a slide you are
-- steering leans into it — which makes the steering visible, and the steering
-- is the part of a slide players are meant to feel.
CameraConfig.slideRollDegrees = 7
CameraConfig.slideRollInSeconds = 0.1
CameraConfig.slideRollOutSeconds = 0.22

-- Dive: nose down through the arc. Small, because a dive already moves the
-- whole view and pitching it hard on top is where motion sickness comes from.
CameraConfig.diveTiltDegrees = 5
CameraConfig.diveTiltInSeconds = 0.12
CameraConfig.diveTiltOutSeconds = 0.3

-- Landing dip: the knees. Scaled by how fast you were falling, because a hop
-- off a kerb and a drop off a roof should not feel the same.
CameraConfig.landingDip = {
	-- Below this fall speed there is no dip at all. A step down is not a landing.
	minFallSpeed = 22,
	-- Studs of dip at `maxFallSpeed` and above.
	maxStuds = 0.85,
	maxFallSpeed = 90,
	inSeconds = 0.05,
	outSeconds = 0.3,
}

-- ---------------------------------------------------------------------------
-- Breathing
--
-- PUBLISHED, NOT APPLIED — see CameraRig. Breathing the camera is what makes
-- people motion-sick and it makes "is my view stable" unanswerable. CoD breathes
-- the WEAPON. So the rig computes this and hands it to the viewmodel (M11), and
-- the camera itself stays still when you are standing still.
-- ---------------------------------------------------------------------------

CameraConfig.breathing = {
	-- Cycles per second. Roughly a resting breath.
	rate = 0.28,
	-- Studs of travel at the amplitude below, in the viewmodel's own space.
	amplitude = 0.035,
	-- Slower and shallower the lower you are, which is most of why prone feels
	-- steady in a shooter.
	byState = {
		Idle = 1,
		Walk = 0.8,
		Sprint = 0.35,
		TacSprint = 0.2,
		Crouch = 0.55,
		Prone = 0.25,
	},
}

-- ---------------------------------------------------------------------------
-- The foreign-writer check
--
-- The rig records what it wrote and, near the end of the frame, checks the
-- camera still says that. Anything else writing the camera outside the chain
-- shows up here — a controller, a plugin, a future system that picked its own
-- priority — which is a far better test than looking for the string
-- "BindToRenderStep", because it catches the SYMPTOM rather than the syntax.
-- ---------------------------------------------------------------------------

-- How far the camera may drift from what the rig last wrote before it counts.
CameraConfig.auditPositionStuds = 0.01
CameraConfig.auditAngleDot = 0.9999
-- Consecutive drifting frames before saying anything. Half a second at 60fps,
-- so one odd frame during a respawn is not an accusation.
CameraConfig.auditFrames = 30

return CameraConfig
