--!strict
-- MovementController (NOD-100) — sprint, slide, slide-jump momentum chains,
-- and stamina. Sprinting is a commitment: you can't fire until you come off
-- it (short raise delay). Slides burst you forward low to the ground and you
-- CAN fire out of them. Stamina governs the spam.

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
local slideStartedAt = 0
local slideEndsAt = 0
local lastSlideAt = 0
local chainUntil = 0
local raiseBlockedUntil = 0
local stamina = MovementConfig.staminaMax
local regenPausedUntil = 0
local originalHipHeight: number? = nil
local slideCameraAlpha = 0 -- smoothed 0..1 for the low camera + roll

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

-- ---------------------------------------------------------------------------
-- Public state (WeaponController and ViewmodelController read these)
-- ---------------------------------------------------------------------------

function MovementController.isSprinting(): boolean
	return sprinting
end

function MovementController.isSliding(): boolean
	return sliding
end

-- Firing is allowed unless sprinting or still raising the weapon.
function MovementController.canFire(): boolean
	return not sprinting and os.clock() >= raiseBlockedUntil
end

-- A blocked fire attempt breaks sprint and starts the raise delay (the
-- weapon's sprint-to-fire stat), so holding the trigger fires shortly after
-- you come off the sprint.
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
	-- Momentum blends out (glide window) instead of snapping to a walk.
	chainUntil = math.max(chainUntil, os.clock() + MovementConfig.postSlideGlideWindow)
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
	slideStartedAt = now
	slideEndsAt = now + MovementConfig.slideDuration

	local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	slideDirection = if flat.Magnitude > 2 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	if not originalHipHeight then
		originalHipHeight = humanoid.HipHeight
	end
	humanoid.HipHeight = (originalHipHeight :: number) - MovementConfig.slideHipDrop
end

-- Jumping out of a slide keeps momentum for a chain window.
local function onJumping()
	if sliding then
		local _, humanoid = character()
		endSlide(humanoid)
		chainUntil = os.clock() + MovementConfig.chainWindow
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

local function update(deltaTime: number)
	local _, humanoid, root = character()
	local now = os.clock()

	if not humanoid or not root then
		sprinting = false
		endSlide(nil)
		return
	end

	-- Slide physics: an ice glide — exponential decay along the locked
	-- direction, so it's fast out of the gate and slips the rest of the way.
	if sliding then
		if now >= slideEndsAt then
			endSlide(humanoid)
		else
			local progress = (now - slideStartedAt) / MovementConfig.slideDuration
			local speed = MovementConfig.slideEndSpeed
				+ (MovementConfig.slideInitialSpeed - MovementConfig.slideEndSpeed)
					* math.exp(-MovementConfig.slideDecayRate * progress)
			local vertical = root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = slideDirection * speed + Vector3.new(0, vertical, 0)
		end
	end

	-- Low-to-the-ground camera while sliding (first person sinks with you).
	local slideTarget = if sliding then 1 else 0
	slideCameraAlpha += (slideTarget - slideCameraAlpha) * math.min(deltaTime * 10, 1)
	humanoid.CameraOffset = Vector3.new(0, -MovementConfig.slideCameraDrop * slideCameraAlpha, 0)

	-- Sprint state: held + moving + stamina, never while sliding.
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if sprinting then
		sprinting = sprintHeld and moving and stamina > 1 and not sliding
	else
		sprinting = sprintHeld and moving and not sliding and stamina > MovementConfig.minSprintStamina
	end

	-- Stamina drain/regen.
	if sprinting then
		stamina = math.max(0, stamina - MovementConfig.sprintDrainPerSecond * deltaTime)
		regenPausedUntil = math.max(regenPausedUntil, now) -- regen waits for sprint to end
	elseif not sliding and now >= regenPausedUntil then
		stamina = math.min(MovementConfig.staminaMax, stamina + MovementConfig.regenPerSecond * deltaTime)
	end

	-- WalkSpeed by state (slide speed is velocity-driven, not WalkSpeed).
	if sliding then
		humanoid.WalkSpeed = MovementConfig.slideEndSpeed
	elseif sprinting then
		humanoid.WalkSpeed = MovementConfig.sprintWalkSpeed
	elseif now < chainUntil then
		humanoid.WalkSpeed = MovementConfig.chainWalkSpeed
	else
		humanoid.WalkSpeed = MovementConfig.baseWalkSpeed
	end

	-- FOV feel, combat only (the lobby camera owns its framing there).
	local camera = workspace.CurrentCamera
	if camera and not ClientData.inLobby() then
		local target = if sliding
			then MovementConfig.fovSlide
			elseif sprinting then MovementConfig.fovSprint
			else MovementConfig.fovBase
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(deltaTime * 8, 1)
	end

	-- Meter: full bar fades out, anything less shows.
	local fill = staminaFill
	local bar = staminaBar
	if fill and bar then
		local alpha = stamina / MovementConfig.staminaMax
		fill.Size = UDim2.fromScale(alpha, 1)
		local visible = alpha < 0.999 and not ClientData.inLobby()
		bar.Visible = visible
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
			humanoid.Jumping:Connect(function(active)
				if active then
					onJumping()
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
		stamina = MovementConfig.staminaMax
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
