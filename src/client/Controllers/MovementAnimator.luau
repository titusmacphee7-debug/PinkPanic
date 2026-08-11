--!strict
-- MovementAnimator (NOD-100/NOD-105) — full-body procedural animation for
-- EVERY character. No animation clips, no Moon Animator: poses are computed
-- fresh every render frame and spring-blended, so motion is perfectly
-- fluid at any framerate. Layers, like a real animator would build them:
--
--   · velocity layer — sprint lean + stride bob, banking into turns,
--     lean-in on acceleration / sit-back on braking
--   · slide pose — asymmetric recline: lead leg kicked out, trail leg
--     tucked, arms out for balance, head up watching the lane
--   · crouch pose — compact stack: thighs up, knees folded, chest forward
--   · air pose — legs tucked mid-jump, opening up as you fall
--   · landing pulse — knees swallow the impact, body dips and recovers
--   · head stabilization — the head counter-rotates so it stays level
--     while the body reclines/leans (the #1 thing that sells a pose)
--
-- Applied as a rest-pose offset on each joint — Motor6D.C0 on the classic
-- rig, Attachment0.CFrame on Roblox's newer AnimationConstraint rig. Either
-- way animations own Transform and we own the base, so keyframed clips
-- (Moon Animator included) and this layer compose instead of fighting.
-- The local player's stance comes
-- straight from MovementController (zero latency); everyone else's arrives
-- as character attributes set by MovementStateService.
--
-- All rotation signs live in SIGNS: if any limb bends the wrong way in a
-- playtest, flip exactly one number here and nothing else moves.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MovementController = require(script.Parent.MovementController)

local MovementAnimator = {}

-- ---------------------------------------------------------------------------
-- Tuning
-- ---------------------------------------------------------------------------

local SIGNS = {
	pitchForward = 1, -- +X rotation pitches the torso/limb forward
	kneeBend = -1, -- knee flex direction
	armOut = 1, -- shoulder roll away from the body
}

local SPRINT_SPEED = 26 -- velocity layer fades in above walking pace
local WALK_SPEED = 8

-- Pose magnitudes (radians / studs). Crafted, not random: every value has
-- a counter-value somewhere else so silhouettes stay balanced.
local POSE = {
	-- Sprint layer (scaled by how fast the character is actually moving)
	sprintLean = 0.17,
	sprintWaist = 0.05,
	bobAmount = 0.055, -- studs of vertical stride bounce
	bobRate = 0.62, -- stride frequency per stud/s of speed
	bankPerAccel = 0.011, -- roll into turns
	bankMax = 0.13,
	accelLean = 0.008, -- pitch per stud/s^2 of forward acceleration
	accelLeanMax = 0.1,

	-- Slide: reclined, low, alive
	slideRootPitch = -0.55, -- backward recline
	slideWaist = -0.12,
	slideHead = 0.36, -- chin up, eyes on the lane
	slideLeadHip = 0.95, -- lead leg kicked out front
	slideLeadKnee = 0.12, -- nearly straight
	slideTrailHip = 0.42, -- trail leg tucked under
	slideTrailKnee = 0.85,
	slideArmOut = 0.34, -- arms flare for balance
	slideArmBack = -0.14,
	slideElbow = 0.24,

	-- Crouch: compact stack
	crouchRootPitch = 0.13,
	crouchWaist = 0.09,
	crouchHead = -0.15, -- keep the eyes level
	crouchHip = 0.8, -- thighs fold up
	crouchKnee = 0.95, -- knees fold back
	crouchArm = 0.1,
	crouchElbow = 0.32,

	-- Airborne tuck
	airHip = 0.32,
	airKnee = 0.5,
	airRootPitch = 0.06,
	airArmOut = 0.22,
	airElbow = 0.2,

	-- Landing pulse
	landKnee = 0.5,
	landRootPitch = 0.1,
	landDip = 0.22, -- studs, transient
}

-- Blend speeds (per second). Fast in, softer out = weight.
local RATE = {
	slideIn = 16, slideOut = 7,
	crouchIn = 13, crouchOut = 10,
	air = 9,
	velocity = 8,
	landDecay = 4.5,
}

-- ---------------------------------------------------------------------------
-- Per-character rig state
-- ---------------------------------------------------------------------------

-- Two rig generations, one interface.
--
-- Classic R15 hangs a Motor6D off each limb and we offset its C0. Roblox's
-- newer constraint rig replaces every Motor6D with an AnimationConstraint
-- driven by a pair of RigAttachments — same joint NAMES, same parents, but
-- `joint:IsA("Motor6D")` is false, which silently killed this entire system.
--
-- The C0 analogue there is Attachment0.CFrame (the parent-side rig
-- attachment). Measured in Studio on the live rig: identical sign convention
-- (+0.436 rad in → +0.436 rad out) and translation applies too, despite
-- MaxForce being 0. The constraint's own `Transform` is NOT usable — the
-- Animator overwrites it every frame, exactly like Motor6D.Transform, which
-- is what lets keyframe animations and this layer compose instead of fight.
type JointRef = {
	joint: Instance, -- Motor6D or AnimationConstraint; identity + liveness
	motor: Motor6D?, -- classic rig
	attachment: Attachment?, -- constraint rig
	base: CFrame, -- rest pose, captured once
}

type Rig = {
	root: JointRef, waist: JointRef, neck: JointRef,
	lHip: JointRef, rHip: JointRef, lKnee: JointRef, rKnee: JointRef,
	lShoulder: JointRef, rShoulder: JointRef, lElbow: JointRef, rElbow: JointRef,
}

type PoseState = {
	rig: Rig,
	slide: number, crouch: number, air: number, velocityAlpha: number,
	bank: number, accelPitch: number, bobPhase: number, landPulse: number,
	prevVelY: number,
	prevPlanar: Vector3,
}

local states: { [Model]: PoseState } = {}

local JOINT_PATHS: { [string]: { string } } = {
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	rHip = { "RightUpperLeg", "RightHip" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	rShoulder = { "RightUpperArm", "RightShoulder" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	rElbow = { "RightLowerArm", "RightElbow" },
}

-- Rigs already reported. stateFor runs every frame for every character, so
-- without this a bad rig would warn 60 times a second.
local reportedRigs: { [Model]: true } = {}

-- A joint we can't drive and a joint that hasn't streamed in yet look
-- identical from here, and only one of them will ever fix itself. So: stay
-- quiet while limbs are still arriving, and say something concrete once a
-- joint is present but the wrong shape.
local function reportRig(model: Model, jointName: string, found: Instance?)
	if reportedRigs[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return -- still assembling
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		reportedRigs[model] = true
		warn(
			`[PinkPanic] ⚠️ {model.Name} is {humanoid.RigType.Name}, not R15 — procedural animation `
				.. `is OFF for this character. Set Home → Game Settings → Avatar → Avatar Type → R15.`
		)
	elseif found then
		reportedRigs[model] = true
		warn(
			`[PinkPanic] ⚠️ {model.Name}: joint "{jointName}" is a {found.ClassName}, which this `
				.. `build can't drive — procedural animation is OFF for this character.`
		)
	end
end

-- Resolves one joint on either rig generation, or nil if it isn't drivable.
local function jointRef(model: Model, limbName: string, jointName: string): JointRef?
	local limb = model:FindFirstChild(limbName)
	local joint = limb and limb:FindFirstChild(jointName)
	if not joint then
		return nil -- limb still streaming in; caller stays quiet
	end

	if joint:IsA("Motor6D") then
		return { joint = joint, motor = joint, attachment = nil, base = joint.C0 }
	end

	-- Compared by ClassName rather than IsA: AnimationConstraint may not exist
	-- in the type definitions this file is checked against, and an unknown
	-- class name in IsA is a --!strict error rather than a runtime miss.
	if joint.ClassName == "AnimationConstraint" then
		local parentSide = (joint :: any).Attachment0
		if typeof(parentSide) == "Instance" and parentSide:IsA("Attachment") then
			return { joint = joint, motor = nil, attachment = parentSide, base = parentSide.CFrame }
		end
		return nil -- constraint present but not wired up yet
	end

	reportRig(model, jointName, joint)
	return nil
end

local function buildRig(model: Model): Rig?
	local rig = {}
	for key, path in JOINT_PATHS do
		local ref = jointRef(model, path[1], path[2])
		if not ref then
			-- Covers R6, where the limb itself is absent so jointRef returns
			-- before it can report anything.
			reportRig(model, path[2], nil)
			return nil
		end
		rig[key] = ref
	end
	return (rig :: any) :: Rig
end

local function stateFor(model: Model): PoseState?
	local existing = states[model]
	if existing and existing.rig.root.joint.Parent then
		return existing
	end
	local rig = buildRig(model)
	if not rig then
		return nil
	end
	local fresh: PoseState = {
		rig = rig,
		slide = 0, crouch = 0, air = 0, velocityAlpha = 0,
		bank = 0, accelPitch = 0, bobPhase = 0, landPulse = 0,
		prevVelY = 0,
		prevPlanar = Vector3.zero,
	}
	states[model] = fresh
	return fresh
end

-- ---------------------------------------------------------------------------
-- Per-frame pose solve
-- ---------------------------------------------------------------------------

local function approach(current: number, target: number, rate: number, deltaTime: number): number
	return current + (target - current) * math.min(rate * deltaTime, 1)
end

local function apply(ref: JointRef, offset: CFrame)
	local motor = ref.motor
	if motor then
		motor.C0 = ref.base * offset
		return
	end
	local attachment = ref.attachment
	if attachment then
		attachment.CFrame = ref.base * offset
	end
end

local function solveCharacter(player: Player, model: Model, deltaTime: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	local pose = stateFor(model)
	if not pose then
		return
	end

	-- ----- Observe -----
	local velocity = root.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = planar.Magnitude
	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	local isLocal = player == Players.LocalPlayer
	local sliding = if isLocal
		then MovementController.isSliding()
		else model:GetAttribute("PPSliding") == true
	local crouching = if isLocal
		then MovementController.isCrouching()
		else model:GetAttribute("PPCrouching") == true

	-- Landing: falling fast a moment ago, grounded now → the body swallows it.
	if not airborne and pose.prevVelY < -22 then
		pose.landPulse = math.min(1, -pose.prevVelY / 60)
	end
	pose.prevVelY = velocity.Y
	pose.landPulse = math.max(0, pose.landPulse - RATE.landDecay * deltaTime * pose.landPulse - deltaTime * 0.8)

	-- Acceleration in body space → banking + lean (secondary motion).
	local accel = (planar - pose.prevPlanar) / math.max(deltaTime, 1 / 240)
	pose.prevPlanar = planar
	local rightward = accel:Dot(root.CFrame.RightVector)
	local forward = accel:Dot(root.CFrame.LookVector)
	local moveScale = math.clamp((speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0, 1)
	pose.bank = approach(
		pose.bank,
		math.clamp(-rightward * POSE.bankPerAccel, -POSE.bankMax, POSE.bankMax) * moveScale,
		RATE.velocity, deltaTime
	)
	pose.accelPitch = approach(
		pose.accelPitch,
		math.clamp(forward * POSE.accelLean, -POSE.accelLeanMax, POSE.accelLeanMax) * moveScale,
		RATE.velocity, deltaTime
	)

	-- ----- Blend stance alphas -----
	pose.slide = approach(pose.slide, if sliding then 1 else 0,
		if sliding then RATE.slideIn else RATE.slideOut, deltaTime)
	pose.crouch = approach(pose.crouch, if crouching and not sliding then 1 else 0,
		if crouching then RATE.crouchIn else RATE.crouchOut, deltaTime)
	pose.air = approach(pose.air, if airborne and not sliding then 1 else 0, RATE.air, deltaTime)
	pose.velocityAlpha = approach(pose.velocityAlpha,
		moveScale * (1 - pose.slide) * (1 - pose.crouch * 0.6), RATE.velocity, deltaTime)

	-- Stride bob phase runs on actual ground speed, so feet and bounce agree.
	if not airborne and speed > WALK_SPEED then
		pose.bobPhase += deltaTime * speed * POSE.bobRate
	end

	local sl, cr, air, vel, land = pose.slide, pose.crouch, pose.air, pose.velocityAlpha, pose.landPulse
	local pf = SIGNS.pitchForward
	local kb = SIGNS.kneeBend
	local ao = SIGNS.armOut

	-- ----- Compose layers -----
	-- Root: every layer votes on the torso; translation is decoration only
	-- (real height comes from HipHeight physics, which replicates).
	local rootPitch = pf * (
		POSE.sprintLean * vel + pose.accelPitch
		+ POSE.slideRootPitch * sl
		+ POSE.crouchRootPitch * cr
		+ POSE.airRootPitch * air
		+ POSE.landRootPitch * land
	)
	local bob = math.sin(pose.bobPhase) * POSE.bobAmount * vel
	local rootOffset = CFrame.new(0, bob - POSE.landDip * land, 0)
		* CFrame.Angles(rootPitch, 0, pose.bank)

	local waistPitch = pf * (
		POSE.sprintWaist * vel
		+ POSE.slideWaist * sl
		+ POSE.crouchWaist * cr
	)
	local waistOffset = CFrame.Angles(waistPitch, 0, pose.bank * 0.4)

	-- Head stabilization: counter most of the body pitch, then add the
	-- pose's own intent (chin up in a slide, eyes level in a crouch).
	local headPitch = -(rootPitch + waistPitch) * 0.6
		+ pf * (POSE.slideHead * sl + POSE.crouchHead * cr)
	local neckOffset = CFrame.Angles(headPitch, 0, -pose.bank * 0.5)

	-- Legs. Slide is asymmetric (lead right, trail left); crouch, air and
	-- landing are symmetric.
	local sharedHip = pf * (POSE.crouchHip * cr + POSE.airHip * air)
	local sharedKnee = kb * (POSE.crouchKnee * cr + POSE.airKnee * air + POSE.landKnee * land)
	local rHipOffset = CFrame.Angles(sharedHip + pf * POSE.slideLeadHip * sl, 0, 0)
	local rKneeOffset = CFrame.Angles(sharedKnee + kb * POSE.slideLeadKnee * sl, 0, 0)
	local lHipOffset = CFrame.Angles(sharedHip + pf * POSE.slideTrailHip * sl, 0, 0)
	local lKneeOffset = CFrame.Angles(sharedKnee + kb * POSE.slideTrailKnee * sl, 0, 0)

	-- Arms: flare in a slide/air for balance, settle close in a crouch.
	local armPitch = pf * (POSE.slideArmBack * sl + POSE.crouchArm * cr)
	local armRoll = ao * (POSE.slideArmOut * sl + POSE.airArmOut * air)
	local elbow = pf * (POSE.slideElbow * sl + POSE.crouchElbow * cr + POSE.airElbow * air)
	local rShoulderOffset = CFrame.Angles(armPitch, 0, armRoll)
	local lShoulderOffset = CFrame.Angles(armPitch, 0, -armRoll)
	local elbowOffset = CFrame.Angles(elbow, 0, 0)

	-- ----- Apply (restore exactly when everything is at rest) -----
	local active = sl + cr + air + vel + land
		+ math.abs(pose.bank) + math.abs(pose.accelPitch)
	local rig = pose.rig
	if active < 0.004 then
		for _, key in { "root", "waist", "neck", "lHip", "rHip", "lKnee", "rKnee", "lShoulder", "rShoulder", "lElbow", "rElbow" } do
			apply((rig :: any)[key] :: JointRef, CFrame.identity)
		end
		return
	end

	apply(rig.root, rootOffset)
	apply(rig.waist, waistOffset)
	apply(rig.neck, neckOffset)
	apply(rig.rHip, rHipOffset)
	apply(rig.rKnee, rKneeOffset)
	apply(rig.lHip, lHipOffset)
	apply(rig.lKnee, lKneeOffset)
	apply(rig.rShoulder, rShoulderOffset)
	apply(rig.lShoulder, lShoulderOffset)
	apply(rig.rElbow, elbowOffset)
	apply(rig.lElbow, elbowOffset)
end

local function update(deltaTime: number)
	for _, player in Players:GetPlayers() do
		local model = player.Character
		if model then
			solveCharacter(player, model, deltaTime)
		end
	end
	for model in states do
		if not model.Parent then
			states[model] = nil
		end
	end
	for model in reportedRigs do
		if not model.Parent then
			reportedRigs[model] = nil
		end
	end
end

function MovementAnimator.init()
	RunService.Heartbeat:Connect(update)
end

return MovementAnimator
