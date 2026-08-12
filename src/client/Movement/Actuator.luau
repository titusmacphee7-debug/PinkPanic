--!strict
-- Actuator — the thing that actually moves the character (NOD-139).
--
-- One `LinearVelocity` in `Plane` mode on world X/Z, so Y stays free for
-- gravity and jumps. Measured, not assumed: `PrimaryTangentAxis = Vector3.xAxis`
-- with `SecondaryTangentAxis = Vector3.zAxis` leaves vertical motion entirely
-- to the engine, which is what lets a jump be a jump rather than something this
-- file has to simulate.
--
-- **MaxForce is proportional to mass and never `math.huge`.** This is the whole
-- reason the file exists, and it is worth being blunt about why: the previous
-- attempt used an infinite force, and sprinting into the lobby fountain threw
-- Titus across the plaza. An infinite force wins every argument with the
-- collision solver, so the character gets resolved out of the geometry at
-- whatever speed that takes. A finite force LOSES that argument — and losing
-- that argument is exactly what "the wall stops you" means.
--
-- `AssemblyMass` rather than a constant, because the mass a character reports
-- is not fixed: accessories, a welded gun and a carried object all change it,
-- and a force tuned for an empty rig would accelerate a loaded one differently.
--
-- ---------------------------------------------------------------------------
-- MEASURED, 2026-08-12, and the reason this is not the primary mover yet
-- ---------------------------------------------------------------------------
--
-- A live Humanoid's own controller cannot be out-argued by a finite force. It
-- is a servo driving toward `MoveDirection * WalkSpeed`, and with WalkSpeed at
-- zero that target is zero — so it spends whatever it takes to hold the
-- character still. Driving this constraint at 24 studs/s for one second, on a
-- 14-mass rig:
--
--     force  1260  (mass x 90)    ->   0.60 studs travelled
--     force  2800  (mass x 200)   ->   1.34
--     force  5600  (mass x 400)   ->   2.67
--     force 22400  (mass x 1600)  ->   1.37
--     force 89600  (mass x 6400)  ->   9.93
--     math.huge                   ->  24.30   ✓
--
-- Seventy times the force buys a third of the distance. The curve does not
-- converge: `math.huge` is not "a very large force", it is a different code
-- path in the solver, and it is the ONLY value that beats the Humanoid.
--
-- Which is the whole story of the old fling. Somebody needed the character to
-- move, found that only `math.huge` worked, used it, and got a mover that also
-- resolves the character out of any geometry it touches at whatever speed that
-- takes. Sprinting into the fountain threw Titus across the plaza.
--
-- So this is NOT the primary mover today. Ground locomotion runs on
-- `Humanoid.WalkSpeed`, resolved through the same shared `Movement.speedFor`,
-- and this constraint is the momentum channel for slide and dive (NOD-141),
-- which are short, committed, and the only places worth switching the Humanoid
-- controller off for. It is attached, bounded and released at boot so that when
-- NOD-141 arrives the force ceiling is already in place and nobody has to
-- rediscover the above.
--
-- `PlatformStand = true` does silence the Humanoid controller, and was measured
-- too: 4.7 studs/s at mass x 90 with the character loose, and 0.0 with an
-- AlignOrientation holding it upright — floor friction eats it. A slide will
-- need its own answer to that (zero-friction feet, or a downward-only
-- constraint), which is NOD-141's problem and not a number to guess here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)

local Actuator = {}

export type Rig = {
	root: BasePart,
	humanoid: Humanoid,
	mover: LinearVelocity,
	attachment: Attachment,
	owned: boolean, -- did we create the attachment, and must we clean it up
}

local ATTACHMENT_NAME = "PinkPanicMove"
local MOVER_NAME = "PinkPanicActuator"

-- Builds (or re-finds) the constraint on a character. Returns nil rather than
-- erroring: a character can be half-replicated, mid-respawn or already
-- destroyed, and none of those are exceptional enough to take a controller down.
function Actuator.attach(character: Model): Rig?
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end

	-- The rig ships with RootAttachment; reuse it rather than adding a second
	-- attachment at the same CFrame, which is the kind of duplicate that only
	-- shows up as a mystery six months later.
	local existingAttachment = root:FindFirstChild(ATTACHMENT_NAME)
	local attachment: Attachment
	local owned = false
	if existingAttachment and existingAttachment:IsA("Attachment") then
		attachment = existingAttachment
	else
		local rootAttachment = root:FindFirstChild("RootAttachment")
		if rootAttachment and rootAttachment:IsA("Attachment") then
			attachment = rootAttachment
		else
			local fresh = Instance.new("Attachment")
			fresh.Name = ATTACHMENT_NAME
			fresh.Parent = root
			attachment = fresh
			owned = true
		end
	end

	local existingMover = root:FindFirstChild(MOVER_NAME)
	local mover: LinearVelocity
	if existingMover and existingMover:IsA("LinearVelocity") then
		mover = existingMover
	else
		local fresh = Instance.new("LinearVelocity")
		fresh.Name = MOVER_NAME
		fresh.Attachment0 = attachment
		fresh.RelativeTo = Enum.ActuatorRelativeTo.World
		fresh.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		-- World X/Z. Y is left alone on purpose — see the header.
		fresh.PrimaryTangentAxis = Vector3.xAxis
		fresh.SecondaryTangentAxis = Vector3.zAxis
		fresh.PlaneVelocity = Vector2.zero
		fresh.MaxForce = 0
		fresh.Enabled = false
		fresh.Parent = root
		mover = fresh
	end

	return {
		root = root,
		humanoid = humanoid,
		mover = mover,
		attachment = attachment,
		owned = owned,
	}
end

function Actuator.detach(rig: Rig)
	if rig.mover.Parent then
		rig.mover:Destroy()
	end
	if rig.owned and rig.attachment.Parent then
		rig.attachment:Destroy()
	end
end

-- The force this rig may apply, in Newtons-ish Roblox units.
--
-- Two numbers multiplied and then capped, rather than one tuned constant: the
-- acceleration is what the movement FEELS like, the ceiling is what stops a
-- direction change from being an impulse, and keeping them separate means
-- tuning the feel cannot accidentally re-enable the fling.
local function forceFor(rig: Rig, grounded: boolean): number
	local mass = rig.root.AssemblyMass
	local accel = if grounded then Config.accelGround else Config.accelAir
	local ceiling = mass * Config.accelGround * Config.forceCeiling
	return math.min(mass * accel, ceiling)
end

-- `desired` is a world-space X/Z velocity. Y is ignored; gravity owns it.
function Actuator.drive(rig: Rig, desired: Vector3, grounded: boolean)
	if rig.root.Parent == nil then
		return
	end
	rig.mover.PlaneVelocity = Vector2.new(desired.X, desired.Z)
	rig.mover.MaxForce = forceFor(rig, grounded)
	rig.mover.Enabled = true
end

-- Stopping is not driving toward zero with the same authority. Braking asks for
-- more force than steady movement, because a shooter is decided by whether you
-- were where you meant to be, and a slide-to-a-halt costs fights.
function Actuator.brake(rig: Rig, grounded: boolean)
	if rig.root.Parent == nil then
		return
	end
	rig.mover.PlaneVelocity = Vector2.zero
	rig.mover.MaxForce = forceFor(rig, grounded) * Config.brakeMultiplier
	rig.mover.Enabled = true
end

-- Hands control back to whatever else is moving the character. Used when the
-- controller shuts down and by the fail-safe in MovementController: a movement
-- system that is broken should leave the player able to walk, not frozen.
function Actuator.release(rig: Rig)
	if rig.mover.Parent == nil then
		return
	end
	rig.mover.Enabled = false
	rig.mover.MaxForce = 0
	rig.mover.PlaneVelocity = Vector2.zero
end

-- Current horizontal speed, studs/s. The vertical component is deliberately
-- dropped: falling fast is not moving fast, and a plausibility check that
-- cannot tell the difference flags every jump.
function Actuator.planarSpeed(rig: Rig): number
	local velocity = rig.root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

return Actuator
