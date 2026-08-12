--!strict
-- MovementController — reads input, runs the state machine, drives the
-- actuator (NOD-139).
--
-- The split is deliberate and it is the whole shape of M2:
--
--   Movement  (shared)  what states exist and which transitions are legal
--   Actuator  (client)  how force reaches the character without flinging it
--   this file (client)  input, ground, and the frame loop that joins them
--
-- Only the core lands here. Omnimovement (NOD-140), slide and dive (NOD-141)
-- and the camera rig (NOD-142) are the rest of the milestone; their states are
-- already declared and legal in the transition table, with nothing driving them
-- yet. That is on purpose — a state you can enter before anyone has decided how
-- it feels is a state that gets designed by accident.
--
-- **Ground locomotion is driven through Humanoid.WalkSpeed, not the actuator,
-- and that is a measured decision rather than a shortcut.** A live Humanoid's
-- controller cannot be out-argued by a finite force; only `math.huge` beats it,
-- and `math.huge` is precisely what threw Titus across the lobby. The numbers
-- are in Actuator.luau's header. What matters here is that the speed still
-- comes from `Movement.speedFor` — the same function the server's plausibility
-- check reads — so there is exactly one answer to how fast a state is, and the
-- actuator is waiting, bounded, for the momentum states that actually need it.
--
-- **It fails toward being able to walk.** If the rig is missing, the character
-- is mid-respawn, or anything else goes wrong, the Humanoid keeps its speed and
-- Roblox's own movement carries on. A movement system that is broken should
-- leave the player able to move, not standing still wondering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Movement = require(ReplicatedStorage.Shared.Systems.Movement)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local Actuator = require(script.Parent.Parent.Movement.Actuator)
local Firing = require(script.Parent.Parent.Systems.Firing)

local SYSTEM = "MovementController"
local BIND = "PinkPanicMovement"

local MovementController = {}

local player = Players.LocalPlayer

local rig: Actuator.Rig? = nil
local machine = Movement.create("lobby")

-- Input edges, read on the frame rather than reacted to, so a key held across a
-- respawn does not need re-pressing.
local sprintHeld = false
local crouchHeld = false

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

local function desiredState(moving: boolean): Movement.State
	if not grounded and clock - leftGroundAt > Config.coyoteSeconds then
		return "Air"
	end
	if crouchHeld then
		return "Crouch"
	end
	if not moving then
		return "Idle"
	end
	if sprintHeld then
		return "Sprint"
	end
	return "Walk"
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function releaseControl()
	local current = rig
	if current then
		Actuator.release(current)
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
		crouchHeld = false
	end

	local wasGrounded = grounded
	grounded = probeGround(current)
	if wasGrounded and not grounded then
		leftGroundAt = clock
	end

	local direction = current.humanoid.MoveDirection
	local moving = direction.Magnitude > 0.05

	Movement.transition(machine, desiredState(moving))

	-- Air keeps whatever speed you left the ground with, so the Humanoid's
	-- own air control carries the jump. Setting a walk speed mid-air would
	-- brake you in the air, which reads as the jump being cut short.
	if machine.state == "Air" then
		return
	end

	-- The speed comes from the shared resolver, not from a number here. The
	-- server's plausibility check reads the same function, which is the only
	-- reason the two can never disagree about what is legal.
	--
	-- Idle resolves to 0 and would freeze the character mid-step, so a state
	-- with no speed leaves the walk speed alone: Idle means "not asking to
	-- move", not "may not move".
	local speed = Movement.speedFor(machine.state, weight())
	if speed > 0 then
		current.humanoid.WalkSpeed = speed
	end
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

	-- Attached but silent. The constraint exists from the first frame with its
	-- force ceiling already set, so slide and dive (NOD-141) have somewhere to
	-- push from and nobody has to rediscover why math.huge is not an option.
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
	panel.Size = UDim2.fromOffset(250, 96)
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
			local force = if current then current.mover.MaxForce else 0
			local walk = if current then current.humanoid.WalkSpeed else 0
			label.Text = table.concat({
				`state    {machine.state}  (from {machine.previous})`,
				`profile  {machine.profile}`,
				`speed    {string.format("%.1f", speed)} actual / {string.format("%.1f", walk)} driven`,
				`ceiling  {string.format("%.1f", Movement.speedFor(machine.state, weight()))} for this state`,
				`grounded {tostring(grounded)}`,
				`force    {string.format("%.0f", force)}  (idle until NOD-141; never huge)`,
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
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			crouchHeld = true
		end
	end)

	-- Released even when the input was "processed", because a key going up
	-- while a text box has focus is still that key going up. Sprint that
	-- latches on is worse than sprint that does not work.
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			crouchHeld = false
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
	-- sessions. One above it is always after.
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Input.Value + 1, step)

	buildOverlay()

	Diagnostics.ok(
		SYSTEM,
		`walk {Config.speed.Walk} sprint {Config.speed.Sprint} crouch {Config.speed.Crouch} · `
			.. `jump {Config.jumpHeightStuds} · 5-ray ground · overlay {Config.overlayKey.Name} · `
			.. `actuator attached and bounded, idle until NOD-141`
	)
end

return MovementController
