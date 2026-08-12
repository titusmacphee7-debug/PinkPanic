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
	character:SetAttribute(names.sprinting, state == "Sprint" or state == "TacSprint")
	character:SetAttribute(names.crouching, state == "Crouch")
	character:SetAttribute(names.prone, state == "Prone")
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
		tacRequested = false
	end

	local wasGrounded = grounded
	grounded = probeGround(current)
	if wasGrounded and not grounded then
		leftGroundAt = clock
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

	-- Going DOWN is instant; coming UP takes time.
	--
	-- That asymmetry is the whole of "the get-up delay that makes going prone a
	-- commitment". Delaying the way down would just feel like the game
	-- swallowing the input you press when you are being shot at. Delaying the
	-- way up means the thirty-five hundredths of a second you spend flat is a
	-- price, and dropping prone is a decision rather than a free crouch.
	--
	-- It is also what kills crouch spam: you can drop instantly as often as you
	-- like, but every one of those costs you the rise.
	local wanted = desiredState(moving)
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

	if Movement.transition(machine, wanted) and machine.state ~= currentState then
		applyStanceHeight(current, machine.state)
		publishStance(current, machine.state)
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

	built.humanoid.CameraOffset = Vector3.zero

	-- A fresh life stands up. Carrying a latched crouch through a respawn means
	-- spawning into a fight already committed to a stance you did not choose.
	crouchToggled = false
	proneToggled = false
	tacRequested = false
	tacCharge = 1
	stanceReadyAt = 0
	pendingRise = nil
	publishStance(built, "Idle")

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
				`ceiling  {string.format("%.1f", Movement.speedFor(machine.state, weight()))} forward, this state`,
				`grounded {tostring(grounded)}   tac {math.floor(tacCharge * 100)}%`,
				`stance   crouch={tostring(crouchWanted())} prone={tostring(proneWanted())}`,
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
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift then
			-- Double tap for tactical sprint. One key for both, because a
			-- separate key for "sprint but more" is a key nobody presses.
			if clock - lastSprintPressAt <= Config.tacSprint.doubleTapSeconds and tacCharge > 0 then
				tacRequested = true
			end
			lastSprintPressAt = clock
			sprintHeld = true
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
		elseif key == Enum.KeyCode.X then
			pronePressedAt = clock
			proneWasLatched = proneToggled
			proneToggled = true
			crouchToggled = false
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
	-- sessions. One above it is always after.
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Input.Value + 1, step)

	buildOverlay()

	Diagnostics.ok(
		SYSTEM,
		`walk {Config.speed.Walk} sprint {Config.speed.Sprint} crouch {Config.speed.Crouch} · `
			.. `8-way sprint, back at {math.floor(Config.directional.backward * 100)}% · `
			.. `tac-sprint {Config.tacSprint.seconds}s on double-shift · crouch Ctrl/C, prone X · `
			.. `overlay {Config.overlayKey.Name}`
	)
end

return MovementController
