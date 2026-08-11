--!strict
-- MovementController (NOD-100) — a full custom velocity controller.
--
-- WHY THIS DOESN'T USE HUMANOID MOVEMENT
--
-- Humanoid.WalkSpeed is a target, not a model. The engine's mover has no
-- acceleration curve, no friction and no separate air behaviour: input
-- direction becomes velocity direction the same frame, releasing the keys
-- brakes instantly, and "air control" is just the ground mover still running
-- while you're off the floor. That is the exact signature of a clunky Roblox
-- shooter, and no amount of tuning on top of it fixes the feel, because the
-- thing that feels bad is the instant snap itself.
--
-- So we set WalkSpeed = 0 and own the horizontal velocity:
--
--   · an accelerate/friction model on the ground, so speed ramps and bleeds
--     instead of snapping (this replaces the old skid system entirely —
--     there is no "skidding" state any more, letting go of the keys just
--     means wishSpeed is 0 and friction takes over)
--   · a deliberately flat air model: a jump is a committed arc, and the air
--     can never make you faster than you took off. Call of Duty movement is
--     fast on the ground and near-passive in the air, and that flatness is
--     what keeps players trackable enough for an average person to aim at
--   · steerable slides, coyote time and jump buffering, so you are never
--     fighting the controller for something you clearly meant to do
--
-- Applied through a LinearVelocity constraint in Plane mode on X/Z. The Y
-- axis is deliberately untouched: gravity, jump arcs, ragdolls and the
-- anti-gravity float force all stay stock.
--
-- Input still comes from Humanoid.MoveDirection, which keeps working with
-- WalkSpeed = 0 (verified live) and is already camera-relative and
-- device-agnostic, so keyboard, gamepad and touch all feed the same vector
-- with no PlayerModule dependency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local BLUSH = Color3.fromRGB(255, 227, 240)

local MovementController = {}

local sprintHeld = false
local sprinting = false
local sliding = false
local slideDirection = Vector3.zAxis
local slideSpeed = 0
local slideEndsAt = 0
local lastSlideAt = 0
local raiseBlockedUntil = 0
local stamina = MovementConfig.staminaMax
local regenPausedUntil = 0
local originalHipHeight: number? = nil
local slideCameraAlpha = 0
-- Crouch: C/Ctrl held while not sprinting; a slide melts into a crouch.
local crouchHeld = false
local crouching = false
local crouchCameraAlpha = 0
-- ADS state pushed by WeaponController: blocks sprint, slows the walk,
-- zooms the FOV.
local adsAlpha = 0
local adsZoom = 0
-- Stance replication (throttled, change-driven) so everyone poses this
-- character correctly.
local sentSliding = false
local sentCrouching = false
local lastStanceSentAt = 0
-- Jump: we own it, so it can be forgiving. Coyote time is measured from the
-- last grounded frame; the buffer is measured from the last press.
local jumpHeld = false
local jumpWasDown = false
local jumpBufferedAt = -1
local lastGroundedAt = -1
local lastLandedAt = -1
local lastJumpAt = -1
-- Locked the moment you leave the ground: the air can never make you faster
-- than you already were. See the air branch in update().
local wasAirborne = false
local airSpeedCeiling = 0

local staminaBar: Frame? = nil
local staminaFill: Frame? = nil

local function character(): (Model?, Humanoid?, BasePart?)
	local model = Players.LocalPlayer.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return model, humanoid, root
	end
	return nil, nil, nil
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalSpeed(root: BasePart): number
	return flat(root.AssemblyLinearVelocity).Magnitude
end

-- ---------------------------------------------------------------------------
-- The velocity model
-- ---------------------------------------------------------------------------

-- Source's friction curve. Above `stopSpeed` the drop is proportional to how
-- fast you're going, so high speeds bleed off quickly and then ease; below it
-- the drop is constant, so the last few studs/s actually reach zero instead of
-- asymptoting toward it and leaving you creeping.
local function applyFriction(velocity: Vector3, deltaTime: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.05 then
		return Vector3.zero
	end
	local control = math.max(speed, MovementConfig.stopSpeed)
	local newSpeed = math.max(speed - control * MovementConfig.groundFriction * deltaTime, 0)
	return velocity * (newSpeed / speed)
end

-- Source's accelerate. The critical detail is that it only ever adds along
-- `wishDir`, and only up to the part of `wishSpeed` you haven't already got in
-- that direction. Moving perpendicular to your velocity therefore costs you
-- nothing, which is what makes air-strafing gain speed rather than trade it.
local function accelerate(
	velocity: Vector3,
	wishDir: Vector3,
	wishSpeed: number,
	accel: number,
	deltaTime: number
): Vector3
	local projected = velocity:Dot(wishDir)
	local addSpeed = wishSpeed - projected
	if addSpeed <= 0 then
		return velocity
	end
	return velocity + wishDir * math.min(accel * wishSpeed * deltaTime, addSpeed)
end

-- Rotate `current` toward `target` by at most `maxRadians`, magnitude
-- untouched. Used for both air steering and slide carving: turning is free,
-- going faster is not.
local function steerToward(current: Vector3, target: Vector3, maxRadians: number): Vector3
	local angle = math.acos(math.clamp(current:Dot(target), -1, 1))
	if angle < 1e-4 then
		return target
	end
	return current:Lerp(target, math.min(maxRadians / angle, 1)).Unit
end

-- ---------------------------------------------------------------------------
-- Public state (WeaponController and ViewmodelController read these)
-- ---------------------------------------------------------------------------

-- Weapon weight from the held gun (WeaponController pushes it).
local weaponSpeedMult = 1

function MovementController.setWeaponSpeedMult(multiplier: number)
	weaponSpeedMult = math.clamp(multiplier, 0.85, 1.1)
end

function MovementController.isSprinting(): boolean
	return sprinting
end

function MovementController.isSliding(): boolean
	return sliding
end

function MovementController.isCrouching(): boolean
	return crouching
end

function MovementController.getHorizontalSpeed(): number
	local _, _, root = character()
	return if root then horizontalSpeed(root) else 0
end

-- WeaponController pushes the ADS blend every frame (0 = hip, 1 = aimed).
function MovementController.setAds(alpha: number, zoomDeg: number)
	adsAlpha = math.clamp(alpha, 0, 1)
	adsZoom = zoomDeg
end

-- Sliding is a firing stance; only sprint keeps the gun down.
function MovementController.canFire(): boolean
	return not sprinting and os.clock() >= raiseBlockedUntil
end

-- A blocked fire attempt breaks sprint and starts the weapon's
-- sprint-to-fire delay, so a held trigger fires shortly after.
function MovementController.noteFireAttempt(sprintToFire: number?)
	if sprinting then
		sprinting = false
		raiseBlockedUntil = os.clock() + (sprintToFire or MovementConfig.fireRaiseDelay)
	end
end

-- ---------------------------------------------------------------------------
-- Slide
-- ---------------------------------------------------------------------------

local function endSlide()
	sliding = false
	-- Speed carries: the velocity model picks it straight up from the root,
	-- so there is nothing to hand over. HipHeight is owned by the per-frame
	-- profile logic (slide/crouch/stand).
end

local function trySlide()
	local _, humanoid, root = character()
	if not humanoid or not root then
		return
	end
	local now = os.clock()
	if
		sliding
		or not sprinting
		-- No slides in the lobby. The plaza camera is a fixed anchor shot, not
		-- a follow cam, so a carved slide reads as the character skating out
		-- from under a camera that isn't tracking them. This is the only
		-- behavioural fork between lobby and combat.
		or ClientData.inLobby()
		or now - lastSlideAt < MovementConfig.slideCooldown
		or stamina < MovementConfig.slideCost
		or humanoid.FloorMaterial == Enum.Material.Air
	then
		return
	end

	stamina -= MovementConfig.slideCost
	regenPausedUntil = now + MovementConfig.regenDelay
	lastSlideAt = now
	sliding = true
	-- A slide is a firing stance: leave sprint NOW so the trigger works
	-- from the first frame of the slide.
	sprinting = false
	slideEndsAt = now + MovementConfig.slideDuration
	-- Momentum-fed entry: arriving fast slides in faster than a standing start.
	slideSpeed = math.min(
		math.max(MovementConfig.slideInitialSpeed * weaponSpeedMult, horizontalSpeed(root)),
		MovementConfig.momentumHardCap
	)

	local moving = flat(root.AssemblyLinearVelocity)
	slideDirection = if moving.Magnitude > 2 then moving.Unit else flat(root.CFrame.LookVector).Unit
end

-- ---------------------------------------------------------------------------
-- HUD: slim stamina meter above the health/ammo panel
-- ---------------------------------------------------------------------------

local function buildStaminaBar()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "StaminaHUD"
	screen.ResetOnSpawn = false

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -78)
	bar.Size = UDim2.fromOffset(180, 8)
	bar.BackgroundColor3 = BLUSH
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HOT_PINK
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	fill.Parent = bar

	bar.Parent = screen
	screen.Parent = playerGui
	staminaBar = bar
	staminaFill = fill
end

-- ---------------------------------------------------------------------------
-- Actuators
-- ---------------------------------------------------------------------------

-- Plane mode on world X/Z: we command horizontal velocity outright and never
-- touch Y, so gravity, the jump arc and the float force below all still apply.
local function ensureActuator(root: BasePart): LinearVelocity
	local existing = root:FindFirstChild("PinkPanicDrive")
	if existing and existing:IsA("LinearVelocity") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PinkPanicDriveAttachment"
	attachment.Parent = root
	local drive = Instance.new("LinearVelocity")
	drive.Name = "PinkPanicDrive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.MaxForce = math.huge
	drive.PlaneVelocity = Vector2.zero
	drive.Parent = root
	return drive
end

-- Anti-gravity assist while airborne: jumps hang longer and falls float a
-- touch, without touching global gravity (shells and ragdolls keep theirs).
local function ensureFloatForce(root: BasePart): VectorForce
	local existing = root:FindFirstChild("PinkPanicFloat")
	if existing and existing:IsA("VectorForce") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PinkPanicFloatAttachment"
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = "PinkPanicFloat"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Enabled = false
	force.Parent = root
	return force
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------

local function update(deltaTime: number)
	local model, humanoid, root = character()
	local now = os.clock()

	if not model or not humanoid or not root then
		sprinting = false
		sliding = false
		crouching = false
		return
	end

	local drive = ensureActuator(root)

	-- The Humanoid is a sensor and a state machine now, not a mover.
	humanoid.WalkSpeed = 0

	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	if not airborne then
		lastGroundedAt = now
	end

	-- Lock the air ceiling on takeoff. The floor is walking pace so that a
	-- standing jump can still be pushed up to a walk mid-air rather than
	-- leaving you frozen, but a sprint or slide jump carries its own speed
	-- and nothing anywhere can raise it.
	if airborne and not wasAirborne then
		airSpeedCeiling = math.max(
			flat(root.AssemblyLinearVelocity).Magnitude,
			MovementConfig.baseWalkSpeed * weaponSpeedMult
		)
	end
	wasAirborne = airborne

	-- MoveDirection keeps reporting real, camera-relative player input at
	-- WalkSpeed = 0 — and since nothing injects Move() any more, it is pure.
	local wish = flat(humanoid.MoveDirection)
	local wishDir = if wish.Magnitude > 0.05 then wish.Unit else Vector3.zero
	local moving = wishDir.Magnitude > 0

	local float = ensureFloatForce(root)
	float.Force = Vector3.new(
		0,
		root.AssemblyMass * workspace.Gravity * (1 - MovementConfig.jumpGravityScale),
		0
	)
	float.Enabled = airborne

	-- -----------------------------------------------------------------------
	-- Jump: coyote + buffer. Both windows are generous on purpose — every
	-- frame spent refusing a jump the player clearly asked for reads as the
	-- game being unresponsive, and neither window can be exploited for height.
	-- -----------------------------------------------------------------------
	-- Edge-detected across every input device at once: gamepad and touch
	-- arrive as Humanoid.Jump, the keyboard as our own Space listener. The
	-- engine re-asserts that flag every frame the button is held, so buffering
	-- off its level rather than its edge would silently become auto-bhop.
	local jumpDown = humanoid.Jump or jumpHeld
	humanoid.Jump = false
	if jumpDown and not jumpWasDown then
		jumpBufferedAt = now
	end
	jumpWasDown = jumpDown

	local jumped = false
	if
		now - jumpBufferedAt <= MovementConfig.jumpBuffer
		and now - lastGroundedAt <= MovementConfig.coyoteTime
		and now - lastJumpAt > 0.15
	then
		jumped = true
		jumpBufferedAt = -1
		lastJumpAt = now
		if sliding then
			endSlide()
		end
		local gravity = workspace.Gravity * MovementConfig.jumpGravityScale
		local launch = math.sqrt(2 * gravity * MovementConfig.jumpApex)
		root.AssemblyLinearVelocity = Vector3.new(
			root.AssemblyLinearVelocity.X,
			launch,
			root.AssemblyLinearVelocity.Z
		)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		-- Bunny hop tax: chaining hops keeps nearly everything you built.
		if now - lastLandedAt <= MovementConfig.bhopWindow then
			local carried = flat(root.AssemblyLinearVelocity) * MovementConfig.bhopRetention
			root.AssemblyLinearVelocity =
				Vector3.new(carried.X, root.AssemblyLinearVelocity.Y, carried.Z)
		end
	end

	-- -----------------------------------------------------------------------
	-- States
	-- -----------------------------------------------------------------------

	-- Sprint: held + moving + stamina, never while sliding or aimed in.
	if sprinting then
		sprinting = sprintHeld and moving and stamina > 1 and not sliding and adsAlpha < 0.2
	else
		sprinting = sprintHeld
			and moving
			and not sliding
			and stamina > MovementConfig.minSprintStamina
			and adsAlpha < 0.2
	end

	-- Crouch: key held, grounded, and nothing faster going on. A slide with
	-- the key still down melts into a crouch when it ends.
	crouching = crouchHeld and not sprinting and not sliding and not airborne

	-- Tell the server the stance changed (trailing send is guaranteed: the
	-- condition re-checks every frame until the send goes through).
	if (sliding ~= sentSliding or crouching ~= sentCrouching) and now - lastStanceSentAt > 0.1 then
		sentSliding = sliding
		sentCrouching = crouching
		lastStanceSentAt = now
		Remotes.event("MovementState"):FireServer(sliding, crouching)
	end

	-- -----------------------------------------------------------------------
	-- Velocity solve — one place decides how fast you are going and why.
	-- -----------------------------------------------------------------------

	-- The speed the model chases. Airborne this is only a reference for the
	-- capped strafe term; steering authority is separate and always full.
	local wishSpeed = (if sprinting then MovementConfig.sprintWalkSpeed else MovementConfig.baseWalkSpeed)
		* weaponSpeedMult
	if crouching then
		wishSpeed *= MovementConfig.crouchSpeedMult
	end
	wishSpeed *= 1 - (1 - MovementConfig.adsWalkMult) * adsAlpha

	local velocity = flat(root.AssemblyLinearVelocity)

	if sliding and now >= slideEndsAt then
		endSlide()
	end

	if sliding then
		-- Slope sensing: project gravity onto the floor plane. Sliding
		-- downhill accelerates you (and keeps the slide alive), uphill bleeds
		-- you out.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local floor = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
		local rampAccel = 0
		if floor then
			local down = Vector3.new(0, -1, 0)
			local surfaceDown = down - floor.Normal * floor.Normal:Dot(down)
			local steepness = surfaceDown.Magnitude
			if steepness > 0.02 then
				rampAccel = MovementConfig.rampAccel * steepness * slideDirection:Dot(surfaceDown.Unit)
			end
		end

		if rampAccel > 0.5 then
			slideSpeed += rampAccel * deltaTime
			slideEndsAt = math.max(slideEndsAt, now + MovementConfig.rampSlideExtend)
		else
			slideSpeed = MovementConfig.slideEndSpeed
				+ (slideSpeed - MovementConfig.slideEndSpeed)
					* math.exp(-MovementConfig.slideDecayRate * deltaTime)
			slideSpeed += math.min(rampAccel, 0) * deltaTime
		end
		slideSpeed = math.min(slideSpeed, MovementConfig.momentumHardCap)

		if slideSpeed < MovementConfig.slideEndSpeed * 0.8 then
			endSlide() -- uphill killed it
			velocity = slideDirection * slideSpeed
		else
			-- Carve. Turn authority falls off with speed, so a fast slide
			-- draws a wide arc and a slow one pivots tight — the slide stays
			-- a move you drive rather than a direction you committed to.
			if moving then
				local authority = MovementConfig.slideTurnRate
					* (MovementConfig.slideTurnRefSpeed / math.max(slideSpeed, 1))
				slideDirection = steerToward(slideDirection, wishDir, authority * deltaTime)
			end
			velocity = slideDirection * slideSpeed
		end
	elseif airborne then
		-- A jump is a committed arc. One weak acceleration term, purely so
		-- that jumping straight up and then pushing a direction does
		-- something, and then a hard ceiling at the speed you took off with.
		--
		-- The ceiling is what keeps this readable. Without it, `accelerate`
		-- pays out whenever your input is off-axis from your velocity, which
		-- is exactly the strafe-jump exploit: perpendicular input reads as
		-- "no speed in that direction yet", so it keeps adding, and a player
		-- who knows to swing the mouse while holding a strafe key leaves
		-- everyone else behind at a speed the game never telegraphs.
		velocity = accelerate(
			velocity,
			wishDir,
			math.min(wishSpeed, MovementConfig.airWishCap),
			MovementConfig.airAccel,
			deltaTime
		)
		if velocity.Magnitude > airSpeedCeiling then
			velocity = velocity.Unit * airSpeedCeiling
		end
	else
		-- Grounded. Friction runs every frame EXCEPT during a hop chain —
		-- skipping it for the couple of frames you're touching the floor
		-- mid-bhop is what lets momentum survive the landing.
		local chaining = jumped or (jumpHeld and now - lastLandedAt <= MovementConfig.bhopWindow)
		if not chaining then
			velocity = applyFriction(velocity, deltaTime)
		end
		velocity = accelerate(velocity, wishDir, wishSpeed, MovementConfig.groundAccel, deltaTime)
	end

	if velocity.Magnitude > MovementConfig.momentumHardCap then
		velocity = velocity.Unit * MovementConfig.momentumHardCap
	end
	drive.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)

	-- -----------------------------------------------------------------------
	-- Stance profile, stamina, camera
	-- -----------------------------------------------------------------------

	if not originalHipHeight then
		originalHipHeight = humanoid.HipHeight
	end
	local hipDrop = if sliding
		then MovementConfig.slideHipDrop
		elseif crouching then MovementConfig.crouchHipDrop
		else 0
	humanoid.HipHeight = (originalHipHeight :: number) - hipDrop

	local slideTarget = if sliding then 1 else 0
	slideCameraAlpha += (slideTarget - slideCameraAlpha) * math.min(deltaTime * 10, 1)
	local crouchTarget = if crouching then 1 else 0
	crouchCameraAlpha += (crouchTarget - crouchCameraAlpha) * math.min(deltaTime * 10, 1)
	humanoid.CameraOffset = Vector3.new(
		0,
		-(MovementConfig.slideCameraDrop * slideCameraAlpha + MovementConfig.crouchCameraDrop * crouchCameraAlpha),
		0
	)

	if sprinting then
		stamina = math.max(0, stamina - MovementConfig.sprintDrainPerSecond * deltaTime)
		regenPausedUntil = math.max(regenPausedUntil, now)
	elseif not sliding and now >= regenPausedUntil then
		stamina = math.min(MovementConfig.staminaMax, stamina + MovementConfig.regenPerSecond * deltaTime)
	end

	-- FOV feel, combat only; carried speed widens it so pace reads visually.
	local camera = workspace.CurrentCamera
	if camera and not ClientData.inLobby() then
		local target = if sliding
			then MovementConfig.fovSlide
			elseif sprinting then MovementConfig.fovSprint
			else MovementConfig.fovBase
		target += math.clamp(
			(velocity.Magnitude - MovementConfig.sprintWalkSpeed) / 30,
			0,
			1
		) * 6
		target -= adsZoom * adsAlpha -- aiming in zooms
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(deltaTime * 8, 1)
	end

	local fill = staminaFill
	local bar = staminaBar
	if fill and bar then
		local alpha = stamina / MovementConfig.staminaMax
		fill.Size = UDim2.fromScale(alpha, 1)
		bar.Visible = alpha < 0.999 and not ClientData.inLobby()
	end
end

function MovementController.init()
	buildStaminaBar()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.Space then
			jumpHeld = true
			jumpBufferedAt = os.clock()
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			-- Sprinting: this starts a slide. Otherwise: hold to crouch.
			-- Keeping it held through a slide melts the slide into a crouch.
			crouchHeld = true
			trySlide()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		elseif input.KeyCode == Enum.KeyCode.Space then
			jumpHeld = false
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			crouchHeld = false
		end
	end)

	local function hookCharacter(model: Model)
		local humanoid = model:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			originalHipHeight = nil
			-- We apply the launch impulse ourselves so coyote jumps work; the
			-- engine must contribute nothing on top of it.
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = 0
			humanoid.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.Landed then
					lastLandedAt = os.clock()
				end
			end)
		end
	end
	local existing = Players.LocalPlayer.Character
	if existing then
		task.spawn(hookCharacter, existing)
	end
	Players.LocalPlayer.CharacterAdded:Connect(function(model)
		sliding = false
		sprinting = false
		crouching = false
		stamina = MovementConfig.staminaMax
		jumpBufferedAt = -1
		lastJumpAt = -1
		actuator = nil
		task.spawn(hookCharacter, model)
	end)

	RunService.Heartbeat:Connect(update)

	-- Camera cant while sliding: applied after the engine camera each frame,
	-- combat only (the lobby camera composes its own shot).
	RunService:BindToRenderStep("PinkPanicSlideRoll", Enum.RenderPriority.Camera.Value + 3, function()
		if ClientData.inLobby() or slideCameraAlpha < 0.01 then
			return
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, -MovementConfig.slideCameraRoll * slideCameraAlpha)
		end
	end)
end

return MovementController
