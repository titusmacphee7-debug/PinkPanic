--!strict
-- MovementController (NOD-100) — sprint, ice slides, and a Source-style
-- momentum system: slides build speed, ramps feed it (slide downhill = keep
-- accelerating), falling trickles into it, the air carries it at full
-- steering authority (air strafing), and bunny hops preserve it. Grounded
-- without hopping, momentum drains back to normal. Stamina only exists to
-- cap degenerate spam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
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
-- Momentum: extra speed above the normal ladder, carried across states.
local momentumSpeed = 0
local lastLandedAt = 0
-- Skid: releasing the keys glides you to a stop instead of instant brakes.
local skidding = false
local skidSpeed = 0
local lastMoveDirection = Vector3.zAxis
local lastMovingSpeed = 0
-- The engine control module, for reading REAL player input: the skid's own
-- injected Humanoid:Move would otherwise read back as "the player is
-- steering" and cancel the skid every other frame. Loaded async in init;
-- skids only arm once it's available.
local controls: any = nil

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

local function horizontalSpeed(root: BasePart): number
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
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

local function endSlide(humanoid: Humanoid?)
	if not sliding then
		return
	end
	sliding = false
	-- The speed you built carries into momentum (glide-out, air, bhops).
	momentumSpeed = math.max(momentumSpeed, slideSpeed)
	if humanoid and originalHipHeight then
		humanoid.HipHeight = originalHipHeight
	end
end

local function trySlide()
	local _, humanoid, root = character()
	if not humanoid or not root then
		return
	end
	local now = os.clock()
	if sliding
		or not sprinting
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
	slideEndsAt = now + MovementConfig.slideDuration
	-- Momentum-fed entry: a bhop chain slides in FASTER than a fresh slide.
	slideSpeed = math.max(MovementConfig.slideInitialSpeed * weaponSpeedMult, horizontalSpeed(root), momentumSpeed)
	slideSpeed = math.min(slideSpeed, MovementConfig.momentumHardCap)

	local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	slideDirection = if flat.Magnitude > 2
		then flat.Unit
		else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	if not originalHipHeight then
		originalHipHeight = humanoid.HipHeight
	end
	humanoid.HipHeight = (originalHipHeight :: number) - MovementConfig.slideHipDrop
end

local function onJumping()
	local now = os.clock()
	if sliding then
		local _, humanoid = character()
		endSlide(humanoid)
	end
	-- Bunny hop: jumping right after landing keeps momentum (tiny tax).
	if now - lastLandedAt <= MovementConfig.bhopWindow and momentumSpeed > 0 then
		momentumSpeed *= MovementConfig.bhopRetention
	end
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
-- Main loop
-- ---------------------------------------------------------------------------

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

local function update(deltaTime: number)
	local model, humanoid, root = character()
	local now = os.clock()

	if not model or not humanoid or not root then
		sprinting = false
		sliding = false
		skidding = false
		momentumSpeed = 0
		return
	end

	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	-- Real input beats MoveDirection: the latter includes our own skid
	-- injection, the former is only what the player is pressing.
	local realInput: Vector3? = nil
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			realInput = vector
		end
	end
	local moving = if realInput
		then realInput.Magnitude > 0.05
		else humanoid.MoveDirection.Magnitude > 0.1
	if moving and not skidding then
		lastMoveDirection = humanoid.MoveDirection
		lastMovingSpeed = horizontalSpeed(root)
	end

	local float = ensureFloatForce(root)
	float.Force = Vector3.new(
		0,
		root.AssemblyMass * workspace.Gravity * (1 - MovementConfig.jumpGravityScale),
		0
	)
	float.Enabled = airborne

	-- Slide physics: ice glide with gravity feeding it on slopes.
	if sliding then
		if now >= slideEndsAt then
			endSlide(humanoid)
		else
			-- Slope sensing: project gravity onto the floor plane; sliding
			-- downhill accelerates you (and keeps the slide alive), uphill
			-- bleeds you out.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { model }
			local floor = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
			local rampAccel = 0
			if floor then
				local normal = floor.Normal
				local surfaceDown = Vector3.new(0, -1, 0) - normal * normal:Dot(Vector3.new(0, -1, 0))
				local steepness = surfaceDown.Magnitude
				if steepness > 0.02 then
					rampAccel = MovementConfig.rampAccel * steepness * slideDirection:Dot(surfaceDown.Unit)
				end
			end

			if rampAccel > 0.5 then
				-- Downhill: accelerate and extend the ride.
				slideSpeed += rampAccel * deltaTime
				slideEndsAt = math.max(slideEndsAt, now + MovementConfig.rampSlideExtend)
			else
				-- Flat/uphill: exponential ice decay (plus uphill bleed).
				slideSpeed = MovementConfig.slideEndSpeed
					+ (slideSpeed - MovementConfig.slideEndSpeed)
						* math.exp(-MovementConfig.slideDecayRate * deltaTime)
				slideSpeed += math.min(rampAccel, 0) * deltaTime
			end
			slideSpeed = math.min(slideSpeed, MovementConfig.momentumHardCap)
			if slideSpeed < MovementConfig.slideEndSpeed * 0.8 then
				endSlide(humanoid) -- uphill killed it
			else
				local vertical = root.AssemblyLinearVelocity.Y
				root.AssemblyLinearVelocity = slideDirection * slideSpeed + Vector3.new(0, vertical, 0)
				momentumSpeed = math.max(momentumSpeed, slideSpeed)
			end
		end
	end

	-- Momentum bookkeeping outside slides.
	if not sliding then
		if airborne then
			-- The air carries momentum; falling feeds it a little.
			momentumSpeed = math.max(momentumSpeed, horizontalSpeed(root))
			if root.AssemblyLinearVelocity.Y < -3 then
				momentumSpeed += MovementConfig.fallSpeedGain * deltaTime
			end
		elseif now - lastLandedAt > MovementConfig.bhopWindow then
			-- Grounded past the hop window: drain back to the normal ladder.
			momentumSpeed = math.max(0, momentumSpeed - MovementConfig.groundMomentumDecay * deltaTime)
		end
		momentumSpeed = math.min(momentumSpeed, MovementConfig.momentumHardCap)
	end

	-- Low-to-the-ground camera while sliding.
	local slideTarget = if sliding then 1 else 0
	slideCameraAlpha += (slideTarget - slideCameraAlpha) * math.min(deltaTime * 10, 1)
	humanoid.CameraOffset = Vector3.new(0, -MovementConfig.slideCameraDrop * slideCameraAlpha, 0)

	-- Friction: no input at speed = skid along the last direction, bleeding
	-- speed gradually instead of the engine's instant brake.
	if skidding then
		skidSpeed -= MovementConfig.skidFriction * deltaTime
		momentumSpeed = math.min(momentumSpeed, math.max(skidSpeed, 0))
		if
			moving
			or airborne
			or sliding
			or ClientData.inLobby()
			or skidSpeed <= MovementConfig.skidStopSpeed
		then
			skidding = false
		end
	elseif realInput and not moving and not sliding and not airborne and not ClientData.inLobby() then
		local speed = math.max(horizontalSpeed(root), lastMovingSpeed)
		if speed > MovementConfig.skidMinSpeed then
			skidding = true
			skidSpeed = speed
		end
		lastMovingSpeed = 0
	end

	-- Sprint state: held + moving + stamina, never while sliding.
	if sprinting then
		sprinting = sprintHeld and moving and stamina > 1 and not sliding
	else
		sprinting = sprintHeld and moving and not sliding and stamina > MovementConfig.minSprintStamina
	end

	-- Stamina drain/regen.
	if sprinting then
		stamina = math.max(0, stamina - MovementConfig.sprintDrainPerSecond * deltaTime)
		regenPausedUntil = math.max(regenPausedUntil, now)
	elseif not sliding and now >= regenPausedUntil then
		stamina = math.min(MovementConfig.staminaMax, stamina + MovementConfig.regenPerSecond * deltaTime)
	end

	-- WalkSpeed: the normal ladder, or carried momentum — whichever is
	-- faster. Airborne this doubles as air-strafe authority: full steering
	-- at your carried speed.
	local ladder = (if sprinting then MovementConfig.sprintWalkSpeed else MovementConfig.baseWalkSpeed)
		* weaponSpeedMult
	if sliding then
		humanoid.WalkSpeed = MovementConfig.slideEndSpeed
	elseif skidding then
		humanoid.WalkSpeed = math.max(skidSpeed, 0)
	else
		humanoid.WalkSpeed = math.max(ladder, momentumSpeed)
	end

	-- FOV feel, combat only; momentum widens it so speed reads visually.
	local camera = workspace.CurrentCamera
	if camera and not ClientData.inLobby() then
		local target = if sliding
			then MovementConfig.fovSlide
			elseif sprinting then MovementConfig.fovSprint
			else MovementConfig.fovBase
		local momentumStretch = math.clamp((momentumSpeed - MovementConfig.sprintWalkSpeed) / 30, 0, 1) * 6
		target += momentumStretch
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

	task.spawn(function()
		local ok, result = pcall(function()
			local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
			return (require(playerScripts:WaitForChild("PlayerModule")) :: any):GetControls()
		end)
		if ok and result then
			controls = result
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			trySlide()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		end
	end)

	local function hookCharacter(model: Model)
		local humanoid = model:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			originalHipHeight = nil
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = MovementConfig.jumpHeight
			humanoid.Jumping:Connect(function(active)
				if active then
					onJumping()
				end
			end)
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
		skidding = false
		momentumSpeed = 0
		stamina = MovementConfig.staminaMax
		task.spawn(hookCharacter, model)
	end)

	RunService.Heartbeat:Connect(update)

	-- Skid steering: keep the character drifting along its last direction
	-- after the player's own control module has run (last Move call wins).
	RunService:BindToRenderStep("PinkPanicSkid", Enum.RenderPriority.Input.Value + 1, function()
		if not skidding then
			return
		end
		local _, humanoid = character()
		if humanoid then
			humanoid:Move(lastMoveDirection, false)
		end
	end)

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
