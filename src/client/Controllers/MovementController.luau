--!strict
-- MovementController — reads input, runs the state machine, drives the
-- character (NOD-139, NOD-140, NOD-141).
--
-- The split is deliberate and it is the whole shape of M2:
--
--   Movement  (shared)  what states exist, which transitions are legal, and how
--                       fast each one may be — the server reads the same answers
--   Traversal (client)  is there a ledge in front of me, and is it safe
--   Actuator  (client)  a bounded force, for the day something needs one
--   this file (client)  input, ground, and the frame loop that joins them
--
-- **Everything is moved through the Humanoid, and that is measured rather than
-- assumed.** A live Humanoid's own controller cannot be out-argued by a finite
-- force; only `math.huge` beats it, and `math.huge` is precisely what threw
-- Titus across the lobby. So instead of fighting it, every move here drives it:
--
--   ground   Humanoid.WalkSpeed, from the shared speed resolver
--   slide    Humanoid:Move(locked heading) + a decaying WalkSpeed
--   dive     ChangeState(Jumping) for the arc, Move + WalkSpeed for the length
--   mantle   PlatformStand, then the root's CFrame written along a checked path
--
-- Measured 2026-08-12: `Humanoid:Move` bound at Input+1 fully overrides the
-- default control script (22.3 studs in one second at WalkSpeed 24, MoveDirection
-- exactly as written), a jump-plus-Move arc holds its horizontal speed for the
-- whole 0.5s of airtime, and a CFrame-written mantle lands 0.05 studs from where
-- it was aimed. Setting velocity directly while GROUNDED does not work at all —
-- the Running controller ate a 30-stud impulse inside one frame — which is why
-- the dive launches through the jump rather than through a shove.
--
-- Because the Humanoid stays the mover, a wall still stops you. That is not a
-- detail: it is the entire reason the fling is gone.
--
-- **It fails toward being able to walk.** If the rig is missing, the character is
-- mid-respawn, or anything else goes wrong, the Humanoid keeps its speed and
-- Roblox's own movement carries on. A movement system that is broken should
-- leave the player able to move, not standing still wondering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Movement = require(ReplicatedStorage.Shared.Systems.Movement)
local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local Actuator = require(script.Parent.Parent.Movement.Actuator)
local Traversal = require(script.Parent.Parent.Movement.Traversal)
local Firing = require(script.Parent.Parent.Systems.Firing)

local SYSTEM = "MovementController"
local BIND = "PinkPanicMovement"
local ROLL_BIND = "PinkPanicSlideRoll"

local MovementController = {}

local player = Players.LocalPlayer

local rig: Actuator.Rig? = nil
local machine = Movement.create("lobby")

-- Input edges, read on the frame rather than reacted to, so a key held across a
-- respawn does not need re-pressing.
local sprintHeld = false

-- Stance input (NOD-140). Tap toggles, hold holds — both schemes at once, which
-- is why there is no setting for it. A player who taps crouch expects to stay
-- crouched; a player who holds it expects to stand up when they let go. Making
-- them pick in a menu is asking them to describe a habit they have never had to
-- name.
local crouchToggled = false
local proneToggled = false
local crouchPressedAt = -math.huge
local pronePressedAt = -math.huge
-- Whether the stance was already latched when the key went down, which is what
-- tells a tap-to-cancel apart from a hold.
local crouchWasLatched = false
local proneWasLatched = false

-- Tactical sprint: entered by double-tapping sprint, drains while held, and
-- refills after a delay.
local tacRequested = false
local tacCharge = 1 -- 0..1
local tacEndedAt = -math.huge
local lastSprintPressAt = -math.huge

-- When the player finishes standing back up, and what they are standing up
-- INTO. Instant crouching is the spam that makes a fight about who presses a
-- key faster; charging for the rise rather than the drop is what stops it
-- without making the drop feel laggy.
local stanceReadyAt = 0
local pendingRise: Movement.State? = nil

-- Requests raised by the input callbacks and consumed by the frame. An input
-- handler that transitions the machine directly runs at whatever moment the key
-- happened to arrive, which is how a move ends up depending on frame timing.
local slideRequested = false
local diveRequested = false
local jumpRequested = false

-- Slide (NOD-141)
local slideHeading = Vector3.zAxis
local slideEntrySpeed = 0
local slideCooldownUntil = -math.huge
local slideHopCapUntil = -math.huge
-- When the current sprint began. A slide has to be EARNED: you cannot tap
-- sprint and immediately slide, and you cannot slide out of a slide.
local sprintSince = math.huge

-- Dive (NOD-141)
local diveHeading = Vector3.zAxis
local diveSpeed = 0
local diveLeftGround = false
local diveLanded = false
local diveHitWall = false
local diveRecoveryUntil = 0
local diveCooldownUntil = -math.huge

-- Mantle (NOD-141)
local mantleFrom = Vector3.zero
local mantleTarget = Vector3.zero
local mantleRotation = CFrame.identity
local mantleCooldownUntil = -math.huge
local mantleWhyNot = "—"

-- Ground state, from our own probes rather than Humanoid.FloorMaterial: the
-- Humanoid's answer lags a frame on ramps and lies on the edge of a platform,
-- and both of those are exactly where movement feels wrong.
local grounded = false
local leftGroundAt = -math.huge

local clock = 0

-- ---------------------------------------------------------------------------
-- Ground
-- ---------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local COS_MAX_SLOPE = math.cos(math.rad(Config.maxSlopeDegrees))

-- Five probes: the centre, and one at each corner of the root's footprint.
--
-- One ray down the middle says you are airborne the moment your centre clears
-- an edge while most of you is still standing on it — which reads as the ground
-- dropping out from under you at every ledge, and is the single most common way
-- a hand-rolled mover feels bad.
local function probeGround(current: Actuator.Rig): boolean
	local root = current.root
	groundParams.FilterDescendantsInstances = { current.root.Parent :: Instance }

	local size = root.Size
	local spread = Config.groundProbeSpread
	local dx, dz = size.X * 0.5 * spread, size.Z * 0.5 * spread
	local origin = root.Position
	local down = Vector3.new(0, -Config.groundProbeStuds, 0)

	local offsets = {
		Vector3.zero,
		Vector3.new(dx, 0, dz),
		Vector3.new(-dx, 0, dz),
		Vector3.new(dx, 0, -dz),
		Vector3.new(-dx, 0, -dz),
	}

	for _, offset in offsets do
		local result = workspace:Raycast(origin + offset, down, groundParams)
		-- The slope test is what stops a steep face counting as floor. Without
		-- it a wall at 70 degrees is something you can stand on, and players
		-- find that within a minute of being handed a map.
		if result and result.Normal.Y >= COS_MAX_SLOPE then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Desired state
-- ---------------------------------------------------------------------------

local function weight(): number
	local _, stats = Firing.weapon()
	return if stats then stats.moveSpeedMult else 1
end

-- Is the player asking to be crouched / prone right now? A tap latched the
-- toggle; a hold is the key still being down.
local function crouchWanted(): boolean
	return crouchToggled
end

local function proneWanted(): boolean
	return proneToggled
end

local function sprinting(state: Movement.State): boolean
	return state == "Sprint" or state == "TacSprint"
end

-- Where the player is asking to go, flattened and unit, or nil if they are not
-- asking. Falls back to facing where a heading is required and none was given —
-- a dive with no input still has to go somewhere, and "where you are looking" is
-- the only answer that is never surprising.
local function inputHeading(current: Actuator.Rig): Vector3?
	local direction = current.humanoid.MoveDirection
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return flat.Unit
end

local function facingHeading(current: Actuator.Rig): Vector3
	local look = current.root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else Vector3.zAxis
end

local function desiredState(moving: boolean): Movement.State
	if not grounded and clock - leftGroundAt > Config.coyoteSeconds then
		return "Air"
	end
	-- Prone outranks crouch: it is the more committed choice and the one with
	-- the get-up cost, so it should not be silently overridden by a crouch key
	-- that happens to also be down.
	if proneWanted() then
		return "Prone"
	end
	if crouchWanted() then
		return "Crouch"
	end
	if not moving then
		return "Idle"
	end
	if sprintHeld then
		-- Tactical sprint only while there is charge left, and it drops back to
		-- ordinary sprint rather than to a walk when the tank empties. Falling
		-- to a walk mid-chase would read as the game taking the input away.
		if tacRequested and tacCharge > 0 then
			return "TacSprint"
		end
		return "Sprint"
	end
	return "Walk"
end

-- ---------------------------------------------------------------------------
-- Stance
-- ---------------------------------------------------------------------------

-- How long moving between two stances takes. Getting up from prone is the
-- slowest thing in the game on purpose.
local function stanceDuration(from: Movement.State, to: Movement.State): number
	local s = Config.stance
	if from == "Prone" then
		return s.fromProneSeconds
	end
	if to == "Prone" then
		return s.toProneSeconds
	end
	if to == "Crouch" then
		return s.toCrouchSeconds
	end
	if from == "Crouch" then
		return s.toStandSeconds
	end
	return 0
end

local STANCE_STATES: { [Movement.State]: boolean } = { Idle = true, Walk = true, Crouch = true, Prone = true }

-- How low a stance is. Higher number, closer to the floor. Used only to tell
-- "going down" from "coming up", which is the one distinction the get-up delay
-- rests on.
local STANCE_RANK: { [Movement.State]: number } = { Idle = 0, Walk = 0, Sprint = 0, TacSprint = 0, Crouch = 1, Prone = 2 }

local function stanceRank(state: Movement.State): number
	return STANCE_RANK[state] or 0
end

-- Attributes for everything else that cares — the animator, the viewmodel, and
-- anything M8 adds. Written on the CHARACTER rather than held here so a system
-- can read the stance without depending on this controller.
local function publishStance(current: Actuator.Rig, state: Movement.State)
	local character = current.root.Parent
	if not character then
		return
	end
	local names = Config.attributes
	-- The state itself, by name. The four booleans below are the stance flags
	-- other systems were already written against; this is the whole answer, and
	-- it exists because "why did my slide end after half a second" was not
	-- answerable from outside the controller — every observer could see four
	-- flags go false at once and none of them could see what replaced them.
	character:SetAttribute(names.state, state)
	character:SetAttribute(names.sprinting, sprinting(state))
	character:SetAttribute(names.crouching, state == "Crouch")
	-- A dive is prone from the moment it lands, not from the moment it starts:
	-- you are in the air for the first half of it, and anything reading "prone"
	-- to decide how tall you are would be wrong for exactly that half.
	character:SetAttribute(names.prone, state == "Prone" or (state == "Dive" and diveLanded))
	character:SetAttribute(names.sliding, state == "Slide")
end

-- How low you SEE from. The camera only, for now.
--
-- The obvious implementation is to drop `HipHeight` by the same amount, which
-- lowers every part and is a genuine change to what a shot has to clear. It
-- also puts the character's feet through the floor, because the legs do not
-- bend — there is no crouch pose yet, and lowering a standing rig is not
-- crouching, it is sinking. Tried it, looked broken.
--
-- Resizing parts is not the alternative either: NOD-167 pins every rig to one
-- size for fairness, and a stance that changed part sizes would break that
-- guarantee and trip CharacterService's audit.
--
-- So the numbers in `Config.stanceDrop` are real and applied to the view, which
-- is most of what a stance feels like in first person, and the hit-volume half
-- waits for a pose that actually bends the knees (NOD-157). Which is the right
-- order anyway: a hitbox that does not match what everyone else can see is a
-- worse bug than one that has not changed yet.
local function applyStanceHeight(current: Actuator.Rig, state: Movement.State)
	local drop = Config.stanceDrop[state] or 0
	current.humanoid.CameraOffset = Vector3.new(0, -drop, 0)
end

local function enter(current: Actuator.Rig, state: Movement.State): boolean
	local from = machine.state
	if not Movement.transition(machine, state) or machine.state == from then
		return false
	end
	applyStanceHeight(current, machine.state)
	publishStance(current, machine.state)
	return true
end

-- ---------------------------------------------------------------------------
-- Slide (NOD-141)
--
-- A slide is a commitment. You steer it — Titus asked for that in his first
-- message and it survived every revision — but you cannot stop it early, you
-- cannot spin on the spot, and you cannot have another one until you have earned
-- another sprint.
-- ---------------------------------------------------------------------------

local function slideAvailable(): boolean
	return clock >= slideCooldownUntil and clock - sprintSince >= Config.slide.sprintChargeSeconds
end

local function beginSlide(current: Actuator.Rig): boolean
	if not grounded or not slideAvailable() then
		return false
	end
	local heading = inputHeading(current) or facingHeading(current)
	-- The speed you were actually carrying, not the speed the state allows.
	-- Entering a slide out of a hard turn should not hand you a boost you had
	-- not built up.
	local carried = math.max(Actuator.planarSpeed(current), Config.speed.Walk)

	if not enter(current, "Slide") then
		return false
	end

	slideHeading = heading
	slideEntrySpeed = Movement.slideEntrySpeed(carried, weight())
	slideCooldownUntil = clock + Config.slide.maxSeconds + Config.slide.cooldownSeconds
	sprintSince = math.huge -- re-earn the sprint before the next one
	Diagnostics.count(SYSTEM, "slide")
	return true
end

-- Rotate `from` toward `to` by at most `maxRadians`, around Y.
--
-- A cap, not a lerp: a lerp is fastest when the turn is biggest, which is
-- exactly backwards for a slide. The cap is what makes it CURVE rather than
-- pivot, and a slide you can pivot on is a slide that dodges bullets.
local function turnToward(from: Vector3, to: Vector3, maxRadians: number): Vector3
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxRadians then
		return to
	end
	-- Which way round. `CFrame.Angles(0, +θ, 0)` turns +X toward −Z, and the Y of
	-- that same cross product is positive, so the sign carries straight across —
	-- written this way rather than as a hand-rolled sin/cos pair precisely
	-- because getting that sign backwards makes a slide steer away from your
	-- input, which reads as the controls being inverted.
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	local turned = CFrame.Angles(0, maxRadians * sign, 0) * from
	return Vector3.new(turned.X, 0, turned.Z).Unit
end

local function endSlide(current: Actuator.Rig)
	slideCooldownUntil = clock + Config.slide.cooldownSeconds
	if proneWanted() then
		enter(current, "Prone")
	elseif crouchWanted() then
		enter(current, "Crouch")
	else
		enter(current, if inputHeading(current) then "Walk" else "Idle")
	end
end

local function stepSlide(current: Actuator.Rig, deltaTime: number)
	local slide = Config.slide
	local elapsed = machine.elapsed
	local speed = Movement.slideSpeed(slideEntrySpeed, elapsed)

	-- The slide-hop. It cancels cleanly and grants NO speed: the cap below runs
	-- for a moment after take-off and pulls anything above ground sprint back
	-- down to it. Speed is earned on the ground and spent in the air, and a hop
	-- that let you keep the slide boost would be the bunny-hop chain the
	-- readability rule exists to prevent.
	if jumpRequested then
		jumpRequested = false
		slideHopCapUntil = clock + 0.35
		Diagnostics.count(SYSTEM, "slideHop")
		-- Jumping is standing up. Leaving the crouch latched meant the slide
		-- ended INTO a crouch, the Humanoid braked to crouch speed on the ground
		-- before the jump had left it, and the hop arrived in the air at 9.2
		-- studs/s against a sprint's 24 — measured. "Cancels cleanly and grants
		-- no speed" is a ceiling, not a tax: you keep a sprint out of it, and the
		-- cap in the frame loop is what stops you keeping any more than that.
		crouchToggled = false
		proneToggled = false
		endSlide(current)
		current.humanoid.WalkSpeed = Movement.speedFor("Sprint", weight())
		return
	end

	if elapsed >= slide.maxSeconds or speed <= slide.exitSpeed then
		endSlide(current)
		return
	end
	-- Coyote-tolerant, deliberately: the same grace the walk path uses. A slide
	-- crosses lips, kerbs and the gaps between hand-built lobby parts, and every
	-- one of those un-grounds you for a frame or two. Cancelling on the raw probe
	-- makes a slide over ordinary geometry end at a random point partway
	-- through, which reads as the slide being unreliable rather than as the
	-- floor being uneven.
	if not grounded and clock - leftGroundAt > Config.coyoteSeconds then
		enter(current, "Air")
		return
	end
	-- Standing up out of it, once you have paid the minimum. Below the minimum
	-- a slide would be a one-frame speed tap you could spam.
	if elapsed >= slide.minSeconds and not crouchWanted() and not proneWanted() then
		endSlide(current)
		return
	end

	local wanted = inputHeading(current)
	if wanted then
		slideHeading = turnToward(slideHeading, wanted, math.rad(slide.turnRateDeg) * deltaTime)
	end

	current.humanoid.WalkSpeed = speed
	current.humanoid:Move(slideHeading, false)
end

-- ---------------------------------------------------------------------------
-- Dive (NOD-141)
--
-- The omnimovement signature move: an arc with real airtime in any of eight
-- directions. You are helpless in the air, and you land on your face. That is
-- the price, and it is what stops a dive from being a free reposition.
-- ---------------------------------------------------------------------------

local function beginDive(current: Actuator.Rig): boolean
	if not grounded or clock < diveCooldownUntil then
		return false
	end
	local heading = inputHeading(current) or facingHeading(current)
	local facing = facingHeading(current)
	local dot = math.clamp(facing:Dot(heading), -1, 1)

	if not enter(current, "Dive") then
		return false
	end

	diveHeading = heading
	diveSpeed = Movement.diveLaunchSpeed(dot, weight())
	diveLeftGround = false
	diveLanded = false
	diveHitWall = false
	diveRecoveryUntil = 0
	diveCooldownUntil = clock + Config.dive.cooldownSeconds

	-- The arc comes from the Humanoid's own jump. A velocity impulse does not
	-- work here at all: measured on 2026-08-12, the Running controller ate a
	-- 30-stud shove inside a single frame. The jump is a code path it cannot
	-- argue with, and JumpHeight is restored the moment the dive ends.
	current.humanoid.JumpHeight = Config.dive.heightStuds
	current.humanoid.WalkSpeed = diveSpeed
	current.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	Diagnostics.count(SYSTEM, "dive")
	return true
end

local diveWallParams = RaycastParams.new()
diveWallParams.FilterType = Enum.RaycastFilterType.Exclude
diveWallParams.IgnoreWater = true

local function stepDive(current: Actuator.Rig, _deltaTime: number)
	local dive = Config.dive
	local humanoid = current.humanoid

	if diveLanded then
		-- Recovery. Flat on your face and worth nothing to anyone, which is the
		-- half of the dive that makes the first half fair.
		humanoid.WalkSpeed = 0
		if clock >= diveRecoveryUntil then
			humanoid.JumpHeight = Config.jumpHeightStuds
			-- You land prone, and the latch decides whether you stay there: the
			-- key still down means you meant it, the key released means get up.
			-- That IS "the option to get up immediately" — no separate input.
			enter(current, "Prone")
		end
		return
	end

	-- A dive that never leaves the ground would otherwise wait forever for a
	-- landing that already happened. Jumping can be denied — a low ceiling, a
	-- Humanoid mid-state-change — and "stuck at dive speed with no way out" is
	-- exactly the class of bug that gets reported as "movement broke".
	if machine.elapsed >= dive.maxAirSeconds then
		diveLanded = true
		diveRecoveryUntil = clock + dive.recoverySeconds
		humanoid.WalkSpeed = 0
		Diagnostics.count(SYSTEM, "diveTimedOut")
		return
	end

	if not grounded then
		diveLeftGround = true
		-- Skip the servo's ramp-in. Measured, the Humanoid takes about 0.3s to
		-- reach a new WalkSpeed, and a dive that spends a third of its airtime
		-- accelerating reads as a hop rather than a launch. In the AIR the
		-- velocity write sticks — it is only on the ground that it gets eaten.
		local velocity = current.root.AssemblyLinearVelocity
		local planar = Vector3.new(velocity.X, 0, velocity.Z)
		if planar.Magnitude < diveSpeed - 0.5 then
			local wanted = diveHeading * diveSpeed
			current.root.AssemblyLinearVelocity = Vector3.new(wanted.X, velocity.Y, wanted.Z)
		end

		diveWallParams.FilterDescendantsInstances = { current.root.Parent :: Instance }
		local ahead = workspace:Raycast(current.root.Position, diveHeading * dive.wallProbeStuds, diveWallParams)
		if ahead and math.abs(ahead.Normal.Y) < 0.5 then
			diveHitWall = true
		end
	end

	humanoid.WalkSpeed = diveSpeed
	humanoid:Move(diveHeading, false)

	-- Landing. The airborne gate is what stops the frame you leave the ground
	-- from counting as the frame you arrive back on it.
	if diveLeftGround and grounded and machine.elapsed >= dive.minAirborneSeconds then
		diveLanded = true
		diveRecoveryUntil = clock + dive.recoverySeconds + (if diveHitWall then dive.wallRecoveryBonus else 0)
		humanoid.WalkSpeed = 0
		publishStance(current, "Dive")
		Diagnostics.count(SYSTEM, if diveHitWall then "diveIntoWall" else "diveLanded")
	end
end

-- ---------------------------------------------------------------------------
-- Mantle (NOD-141)
--
-- Auto-mantle: no key. If you jump at a ledge you can reach, you go over it. A
-- mantle key is a key people forget they have.
-- ---------------------------------------------------------------------------

-- Every other frame while airborne. Six raycasts is cheap; six raycasts sixty
-- times a second for the whole of a fall is not, and a ledge does not appear
-- and vanish inside 16 milliseconds.
local mantleProbeFrame = 0

local function tryMantle(current: Actuator.Rig): boolean
	if clock < mantleCooldownUntil then
		return false
	end
	mantleProbeFrame += 1
	if mantleProbeFrame % 2 == 1 then
		return false
	end

	local velocity = current.root.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local heading = if planar.Magnitude > 1 then planar.Unit else facingHeading(current)

	local ledge, why = Traversal.findLedge(current.root, current.humanoid, heading)
	mantleWhyNot = why
	if not ledge then
		return false
	end

	if not enter(current, "Mantle") then
		return false
	end

	mantleFrom = current.root.Position
	mantleTarget = ledge.target
	mantleRotation = current.root.CFrame.Rotation
	current.humanoid.PlatformStand = true
	Diagnostics.count(SYSTEM, "mantle")
	return true
end

local function stepMantle(current: Actuator.Rig)
	local alpha = machine.elapsed / Config.mantle.durationSeconds
	local point = Traversal.pathPoint(mantleFrom, mantleTarget, alpha)

	current.root.CFrame = CFrame.new(point) * mantleRotation
	-- Zeroed every frame, or the fall you were in the middle of is waiting for
	-- you at the top and yanks you straight back off the ledge.
	current.root.AssemblyLinearVelocity = Vector3.zero

	if alpha >= 1 then
		current.humanoid.PlatformStand = false
		mantleCooldownUntil = clock + Config.mantle.cooldownSeconds
		enter(current, if inputHeading(current) then "Walk" else "Idle")
	end
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function releaseControl()
	local current = rig
	if current then
		Actuator.release(current)
		current.humanoid.PlatformStand = false
		current.humanoid.JumpHeight = Config.jumpHeightStuds
		current.humanoid.WalkSpeed = Config.speed.Walk
	end
end

local function step(deltaTime: number)
	clock += deltaTime
	Movement.step(machine, deltaTime)

	local current = rig
	if not current or current.root.Parent == nil or current.humanoid.Health <= 0 then
		return
	end

	-- Menus own the keyboard. Without this, closing the loadout screen leaves
	-- you sprinting because the key that opened it was never seen going up.
	if ClientData.menuOpen() then
		sprintHeld = false
		tacRequested = false
		slideRequested = false
		diveRequested = false
		jumpRequested = false
	end

	local wasGrounded = grounded
	grounded = probeGround(current)
	if wasGrounded and not grounded then
		leftGroundAt = clock
	end

	-- The slide-hop cap. Anything above ground sprint gets pulled back to it for
	-- a moment after take-off, so a hop out of a slide arrives in the air at
	-- exactly the speed a sprint-jump would have. This is the "grants no speed"
	-- subtask, and it is enforced here rather than trusted to the decay curve.
	if clock < slideHopCapUntil then
		local ceiling = Movement.speedFor("Sprint", weight())
		local velocity = current.root.AssemblyLinearVelocity
		local planar = Vector3.new(velocity.X, 0, velocity.Z)
		if planar.Magnitude > ceiling then
			local capped = planar.Unit * ceiling
			current.root.AssemblyLinearVelocity = Vector3.new(capped.X, velocity.Y, capped.Z)
		end
	end

	-- The three committed states each own their frame outright. That is what
	-- "commitment" means mechanically: while one is running, the stance keys,
	-- the sprint key and the ordinary speed resolver do not get a vote.
	if machine.state == "Mantle" then
		stepMantle(current)
		return
	end
	if machine.state == "Dive" then
		stepDive(current, deltaTime)
		return
	end
	if machine.state == "Slide" then
		stepSlide(current, deltaTime)
		return
	end

	local direction = current.humanoid.MoveDirection
	local moving = direction.Magnitude > 0.05

	-- Tactical sprint drains while it is what you are doing, and refills after
	-- a delay once it is not. The delay is what stops tapping in and out from
	-- being a way to stay in it permanently.
	local tac = Config.tacSprint
	if machine.state == "TacSprint" then
		tacCharge = math.max(tacCharge - deltaTime / tac.seconds, 0)
		tacEndedAt = clock
		if tacCharge <= 0 then
			tacRequested = false
		end
	elseif clock - tacEndedAt >= tac.rechargeDelaySeconds then
		tacCharge = math.min(tacCharge + deltaTime / tac.rechargeSeconds, 1)
	end

	-- Entries. Checked before the ordinary state path so that sprint+crouch is a
	-- slide rather than a crouch that happens to be fast.
	if slideRequested then
		slideRequested = false
		if sprinting(machine.state) and beginSlide(current) then
			return
		end
	end
	if diveRequested then
		diveRequested = false
		if sprinting(machine.state) and beginDive(current) then
			return
		end
	end
	jumpRequested = false

	if machine.state == "Air" and tryMantle(current) then
		return
	end

	local wanted = desiredState(moving)

	-- Going DOWN is instant; coming UP takes time.
	--
	-- That asymmetry is the whole of "the get-up delay that makes going prone a
	-- commitment". Delaying the way down would just feel like the game
	-- swallowing the input you press when you are being shot at. Delaying the
	-- way up means the time you spend flat is a price, and dropping prone is a
	-- decision rather than a free crouch.
	--
	-- It is also what kills crouch spam: you can drop instantly as often as you
	-- like, but every one of those costs you the rise.
	local currentState = machine.state
	if STANCE_STATES[wanted] and STANCE_STATES[currentState] and wanted ~= currentState then
		local rising = stanceRank(wanted) < stanceRank(currentState)
		if rising then
			if pendingRise ~= wanted then
				pendingRise = wanted
				stanceReadyAt = clock + stanceDuration(currentState, wanted)
			end
			if clock < stanceReadyAt then
				wanted = currentState -- still on the way up
			else
				pendingRise = nil
			end
		else
			pendingRise = nil
		end
	elseif wanted == currentState then
		pendingRise = nil
	end

	if enter(current, wanted) and sprinting(machine.state) and not sprinting(currentState) then
		-- A fresh sprint re-arms the slide. Tracked here rather than off the key
		-- because holding sprint through a slide should not hand you the next
		-- one for free — you have to actually be sprinting again.
		sprintSince = clock
	end
	if not sprinting(machine.state) then
		sprintSince = math.huge
	end

	-- Air keeps whatever speed you left the ground with, so the Humanoid's
	-- own air control carries the jump. Setting a walk speed mid-air would
	-- brake you in the air, which reads as the jump being cut short — and it
	-- is also the readability rule: speed is earned on the ground and spent in
	-- the air, never gained there.
	if machine.state == "Air" then
		return
	end

	-- Which way you are pointing versus which way you are going. Omnimovement
	-- (NOD-140) is this one number: sprinting backwards is slower than
	-- sprinting forwards, and every multiplier is at or below 1, so no
	-- direction is ever faster than straight ahead.
	local dot = 1
	if moving then
		local facing = current.root.CFrame.LookVector
		local flatFacing = Vector3.new(facing.X, 0, facing.Z)
		local flatMove = Vector3.new(direction.X, 0, direction.Z)
		if flatFacing.Magnitude > 1e-4 and flatMove.Magnitude > 1e-4 then
			dot = flatFacing.Unit:Dot(flatMove.Unit)
		end
	end

	-- The speed comes from the shared resolver, not from a number here. The
	-- server's plausibility check reads the same functions, which is the only
	-- reason the two can never disagree about what is legal.
	--
	-- Idle resolves to 0 and would freeze the character mid-step, so a state
	-- with no speed leaves the walk speed alone: Idle means "not asking to
	-- move", not "may not move".
	local speed = Movement.resolvedSpeed(machine.state, weight(), dot)
	if speed > 0 then
		current.humanoid.WalkSpeed = speed
	end
end

-- ---------------------------------------------------------------------------
-- Camera roll (PinkPanicSlideRoll, Camera+3 in the documented chain)
--
-- The roll IS the carve. It is proportional to how far the slide heading has
-- turned away from where you are looking, so a straight slide gets none and a
-- slide you are steering leans into it — which makes the steering visible, and
-- the steering is the part of a slide players are supposed to feel.
-- ---------------------------------------------------------------------------

local rollNow = 0

local function slideRoll(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local target = 0
	local current = rig
	-- Skipped in the lobby on purpose: there the camera is a fixed hand-placed
	-- shot of the storefront row, and rolling it tilts the storefront rather
	-- than the player. That is the whole of what "the lobby cannot show an arc"
	-- ever really meant, and it is a rule about this function, not about slides.
	if current and machine.state == "Slide" and not ClientData.inLobby() then
		local right = current.root.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		if flat.Magnitude > 1e-4 then
			target = math.rad(Config.slide.rollDegrees) * math.clamp(flat.Unit:Dot(slideHeading), -1, 1)
		end
	end

	local rate = if math.abs(target) > math.abs(rollNow) then Config.slide.rollInSeconds else Config.slide.rollOutSeconds
	rollNow += (target - rollNow) * (1 - math.exp(-deltaTime / math.max(rate, 1e-3)))
	if math.abs(rollNow) < 1e-4 then
		rollNow = 0
		return
	end
	camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, rollNow)
end

-- ---------------------------------------------------------------------------
-- Trigger counts
--
-- The old build had a slide that never fired. It was in the code, it compiled,
-- it did nothing, and nobody knew for days. So the counts say so out loud: one
-- line, printed when something changes and once at the first interval, with
-- "never fired" spelled out rather than left as a zero to notice.
-- ---------------------------------------------------------------------------

local lastReport: { [string]: number } = {}

local function countsNow(): { [string]: number }
	return {
		slide = Diagnostics.getCount(SYSTEM, "slide"),
		dive = Diagnostics.getCount(SYSTEM, "dive"),
		mantle = Diagnostics.getCount(SYSTEM, "mantle"),
	}
end

function MovementController.report(force: boolean?): string
	local counts = countsNow()

	local changed = force == true
	for name, value in counts do
		if lastReport[name] ~= value then
			changed = true
		end
	end
	lastReport = counts

	local parts: { string } = {}
	local dead: { string } = {}
	for _, name in { "slide", "dive", "mantle" } do
		table.insert(parts, `{name} {counts[name]}`)
		if counts[name] == 0 then
			table.insert(dead, name)
		end
	end
	local line = table.concat(parts, " · ")
	if #dead > 0 then
		line ..= ` — {table.concat(dead, ", ")} {if #dead == 1 then "has" else "have"} NEVER FIRED`
	end

	if changed then
		print(`[PinkPanic] 🏃 moves: {line}`)
	end
	return line
end

-- Sprinting is cancelled by shooting, aiming, or reloading — not merely
-- ignored. Public because the trigger lives in WeaponController and this is the
-- seam between them; a controller reaching into another controller's input
-- state is how two systems end up disagreeing about whether you are sprinting.
function MovementController.cancelSprint()
	sprintHeld = false
	tacRequested = false
end

-- ---------------------------------------------------------------------------
-- Rig lifecycle
-- ---------------------------------------------------------------------------

local function bind(character: Model)
	local built = Actuator.attach(character)
	if not built then
		Diagnostics.warn(SYSTEM, "character spawned without a root or humanoid — leaving stock movement alone")
		return
	end

	rig = built
	grounded = false
	leftGroundAt = -math.huge
	machine = Movement.create(if ClientData.inLobby() then "lobby" else "combat")

	built.humanoid.WalkSpeed = Config.speed.Walk
	built.humanoid.UseJumpPower = false
	built.humanoid.JumpHeight = Config.jumpHeightStuds
	built.humanoid.PlatformStand = false

	built.humanoid.CameraOffset = Vector3.zero

	-- A fresh life stands up. Carrying a latched crouch through a respawn means
	-- spawning into a fight already committed to a stance you did not choose.
	crouchToggled = false
	proneToggled = false
	tacRequested = false
	tacCharge = 1
	stanceReadyAt = 0
	pendingRise = nil
	slideRequested = false
	diveRequested = false
	jumpRequested = false
	sprintSince = math.huge
	slideCooldownUntil = -math.huge
	diveCooldownUntil = -math.huge
	mantleCooldownUntil = -math.huge
	diveLanded = false
	publishStance(built, "Idle")

	-- Attached but silent. The constraint exists from the first frame with its
	-- force ceiling already set — nothing drives it today, and the header in
	-- Actuator.luau is the measurement that says why.
	Actuator.release(built)

	built.humanoid.Died:Connect(function()
		releaseControl()
	end)
end

local function unbind()
	local current = rig
	rig = nil
	if current then
		Actuator.detach(current)
	end
end

-- ---------------------------------------------------------------------------
-- Overlay
-- ---------------------------------------------------------------------------

local overlay: TextLabel? = nil

local function buildOverlay()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "MovementOverlay"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, Theme.space.lg, 1, -Theme.space.lg)
	panel.Size = UDim2.fromOffset(290, 130)
	panel.BackgroundColor3 = Theme.color.scrim
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Components.corner(panel, Theme.radius.card)
	Components.padding(panel, Theme.space.sm)

	overlay = Components.text(panel, {
		text = "",
		size = Theme.text.caption,
		color = Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Left,
		area = UDim2.fromScale(1, 1),
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Config.overlayKey then
			screen.Enabled = not screen.Enabled
		end
	end)

	-- Its own loop, at a readable rate. Updating a debug label every frame is
	-- both wasteful and unreadable — the numbers strobe.
	task.spawn(function()
		while true do
			task.wait(0.1)
			local label = overlay
			if not label or not screen.Enabled then
				continue
			end
			local current = rig
			local speed = if current then Actuator.planarSpeed(current) else 0
			local walk = if current then current.humanoid.WalkSpeed else 0
			local counts = countsNow()
			label.Text = table.concat({
				`state    {machine.state}  (from {machine.previous})`,
				`profile  {machine.profile}`,
				`speed    {string.format("%.1f", speed)} actual / {string.format("%.1f", walk)} driven`,
				`ceiling  {string.format("%.1f", Movement.speedFor(machine.state, weight()))} forward, this state`,
				`grounded {tostring(grounded)}   tac {math.floor(tacCharge * 100)}%`,
				`stance   crouch={tostring(crouchWanted())} prone={tostring(proneWanted())}`,
				`moves    slide {counts.slide} · dive {counts.dive} · mantle {counts.mantle}`,
				`ledge    {mantleWhyNot}`,
				`refused  {machine.refused}`,
			}, "\n")
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function MovementController.init()
	Movement.validate()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift then
			-- Double tap for tactical sprint. One key for both, because a
			-- separate key for "sprint but more" is a key nobody presses.
			if clock - lastSprintPressAt <= Config.tacSprint.doubleTapSeconds and tacCharge > 0 then
				tacRequested = true
			end
			lastSprintPressAt = clock
			sprintHeld = true
		elseif key == Enum.KeyCode.Space then
			-- Only ever read by a slide, to cancel it. Ordinary jumping stays the
			-- Humanoid's, because it already works and a second jump path is a
			-- double jump waiting to happen.
			jumpRequested = true
		elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.C then
			-- The stance engages on the PRESS, not on the release. Waiting for
			-- the key to come up before crouching is a whole keystroke of lag
			-- on the input you press when you are being shot at.
			crouchPressedAt = clock
			crouchWasLatched = crouchToggled
			crouchToggled = true
			-- Crouching cancels prone on the way past: Ctrl from prone means
			-- "get up a bit", not "nothing happens".
			proneToggled = false
			-- The same press is a SLIDE if you were sprinting. The frame decides
			-- whether it takes it; an input handler that transitions the machine
			-- itself runs at whatever moment the key happened to arrive.
			slideRequested = true
		elseif key == Enum.KeyCode.X then
			pronePressedAt = clock
			proneWasLatched = proneToggled
			proneToggled = true
			crouchToggled = false
			diveRequested = true
		end
	end)

	-- Released even when the input was "processed", because a key going up
	-- while a text box has focus is still that key going up. Sprint that
	-- latches on is worse than sprint that does not work.
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift then
			sprintHeld = false
			tacRequested = false
		elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.C then
			-- A HOLD ends when you let go. A TAP leaves the stance latched —
			-- unless it was already latched, in which case the tap cancels it.
			-- Both schemes at once, which is why there is no setting for it and
			-- no habit anyone has to name.
			if clock - crouchPressedAt > Config.stance.tapSeconds or crouchWasLatched then
				crouchToggled = false
			end
		elseif key == Enum.KeyCode.X then
			if clock - pronePressedAt > Config.stance.tapSeconds or proneWasLatched then
				proneToggled = false
			end
		end
	end)

	player.CharacterAdded:Connect(function(character)
		unbind()
		-- One frame for CharacterService to standardise the rig; attaching to a
		-- root that is about to be re-scaled reads the wrong footprint.
		task.wait()
		bind(character)
	end)
	player.CharacterRemoving:Connect(unbind)
	if player.Character then
		task.spawn(bind, player.Character)
	end

	-- The lobby profile follows the round, so it is right the moment a match
	-- starts rather than at the next respawn.
	ClientData.roundStateChanged:Connect(function()
		Movement.setProfile(machine, if ClientData.inLobby() then "lobby" else "combat")
	end)

	-- Input+1, not Input. Roblox's own control script binds at Input and is what
	-- writes Humanoid.MoveDirection; binding at the same number leaves the order
	-- between them down to whoever registered first, and reading MoveDirection
	-- one frame stale is a whole frame of input lag that comes and goes between
	-- sessions. One above it is always after — which is also what lets
	-- `Humanoid:Move` override the control script during a slide or a dive.
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Input.Value + 1, step)
	-- Camera+3, between the aim recoil and the viewmodel. Documented in
	-- CLAUDE.md; breaking that order is the jitter that looks like a physics bug.
	RunService:BindToRenderStep(ROLL_BIND, Enum.RenderPriority.Camera.Value + 3, slideRoll)

	buildOverlay()

	task.spawn(function()
		while true do
			task.wait(Config.moveReportSeconds)
			MovementController.report()
		end
	end)

	Diagnostics.ok(
		SYSTEM,
		`walk {Config.speed.Walk} sprint {Config.speed.Sprint} crouch {Config.speed.Crouch} · `
			.. `8-way sprint, back at {math.floor(Config.directional.backward * 100)}% · `
			.. `tac-sprint {Config.tacSprint.seconds}s on double-shift · crouch Ctrl/C, prone X · `
			.. `slide sprint+Ctrl ({Config.slide.maxSeconds}s, steer + hop) · dive sprint+X · auto-mantle {Config.mantle.minHeightStuds}-{Config.mantle.maxHeightStuds} studs · `
			.. `overlay {Config.overlayKey.Name}`
	)
end

return MovementController
