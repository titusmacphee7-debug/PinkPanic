--!strict
-- WeaponController — the keys, the camera kick, and the ammo readout
-- (NOD-136).
--
-- Firing owns the state machine; this owns everything a player touches. The
-- split is deliberate: input is full of Roblox-specific edge cases (a menu
-- eating the click, a gamepad, the mouse leaving the window) and the firing
-- machine must stay testable without any of it.
--
-- **Recoil has no bloom.** Titus vetoed it, and the reason is worth writing
-- down: bloom makes the crosshair lie. Spread here is a fixed per-gun cone
-- that never grows — the bullets always go where the crosshair points — and
-- what climbs instead is the CAMERA, which you can see, learn, and pull back
-- down. A new player who holds the trigger and watches the screen rise
-- understands what is happening to them. A new player whose bullets quietly
-- stop going where they aimed does not.
--
-- The camera write is bound at PinkPanicAim, one priority above the camera
-- itself, per the render step ordering in CLAUDE.md. Breaking that order shows
-- up as jitter that looks exactly like a physics bug.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local ClientData = require(script.Parent.Parent.ClientData)
local Firing = require(script.Parent.Parent.Systems.Firing)
local EffectsController = require(script.Parent.EffectsController)
-- One direction only: the trigger tells movement that a sprint is over.
-- MovementController does not require this file back, so there is no cycle.
local MovementController = require(script.Parent.MovementController)
local CameraRig = require(script.Parent.Parent.Camera.CameraRig)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local SYSTEM = "WeaponController"

-- The master volume for recoil. Per-gun ceilings derive from each gun's own
-- stats below, so turning this down softens a pistol and an LMG in proportion
-- rather than flattening both to the same feel.
local RECOIL_SCALE = 1

-- How far the climb may accumulate before it stops climbing, as a multiple of
-- one shot's kick. A gun that kicks 0.38° per shot tops out much lower than
-- one that kicks 1.4°, which is the whole point of deriving it.
local RECOIL_CEILING_SHOTS = 9

local AIM_BIND = "PinkPanicAim"
local FIRE_ACTION = "PinkPanicFire"
local RELOAD_ACTION = "PinkPanicReload"
local SPRINT_ACTION = "PinkPanicSprint"
local SLOT_ACTION = "PinkPanicSlot"

local WeaponController = {}

-- Accumulated camera offset in degrees, and the amount already handed to the
-- camera. Tracking both is what lets recovery pull the view back down without
-- fighting the player's own mouse: we only ever apply the DIFFERENCE.
local recoilPitch = 0
local recoilYaw = 0
local appliedPitch = 0
local appliedYaw = 0

local sprinting = false

-- ---------------------------------------------------------------------------
-- Gating
-- ---------------------------------------------------------------------------

-- Shooting is off while any menu owns the mouse, off in the lobby (which has
-- its own cosmetic shot), and off when you are dead. All three used to be
-- checked in separate places with three slightly different answers.
--
-- "Am I in a fight" moved to `ClientData.fighting()` (NOD-142), because the
-- CAMERA needs exactly the same answer: whichever rule decides the trigger
-- works has to be the rule that decides you are in first person, or you end up
-- shooting people through a lobby camera.
local function combatActive(): boolean
	if ClientData.menuOpen() or ClientData.armoryBusy then
		return false
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end

	return ClientData.fighting()
end

-- ---------------------------------------------------------------------------
-- Recoil
-- ---------------------------------------------------------------------------

local function kick(stats: any)
	local vertical = stats.recoilVert * RECOIL_SCALE
	local horizontal = stats.recoilHoriz * RECOIL_SCALE
	local ceiling = vertical * RECOIL_CEILING_SHOTS

	recoilPitch = math.min(recoilPitch + vertical, ceiling)
	recoilYaw = math.clamp(
		recoilYaw + (math.random() * 2 - 1) * horizontal,
		-ceiling * 0.5,
		ceiling * 0.5
	)
end

local function stepRecoil(deltaTime: number)
	local _, stats = Firing.weapon()
	if stats then
		-- Exponential settle rather than a linear one: the first part of the
		-- recovery is fast enough to feel responsive between taps, and the
		-- tail is slow enough that sustained fire still costs you something.
		local decay = math.exp(-stats.recoilRecovery * deltaTime)
		recoilPitch *= decay
		recoilYaw *= decay
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Only ever the delta. Writing the absolute offset would overwrite the
	-- player's own mouse movement every frame, which reads as the camera
	-- fighting you.
	local dPitch = recoilPitch - appliedPitch
	local dYaw = recoilYaw - appliedYaw
	if math.abs(dPitch) < 1e-5 and math.abs(dYaw) < 1e-5 then
		return
	end
	appliedPitch = recoilPitch
	appliedYaw = recoilYaw

	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(dPitch), math.rad(-dYaw), 0)
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function onFireAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		if not combatActive() then
			return Enum.ContextActionResult.Pass
		end
		-- Shooting ENDS a sprint rather than being refused during one
		-- (NOD-140). Refusing the shot means the player pressed fire and
		-- nothing happened, which they will read as the game dropping their
		-- input; cancelling the sprint means the shot costs them the
		-- sprint-to-fire delay, which is a price they can learn.
		MovementController.cancelSprint()
		Firing.setTrigger(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		Firing.setTrigger(false)
	end
	return Enum.ContextActionResult.Sink
end

local function onReloadAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and combatActive() then
		-- Reload-with-intent: you meant to reload, so you meant to stop
		-- sprinting. A reload that silently kept you sprinting would finish
		-- with the gun still down.
		MovementController.cancelSprint()
		Firing.reload()
	end
	return Enum.ContextActionResult.Sink
end

local function setSprinting(value: boolean)
	if sprinting == value then
		return
	end
	sprinting = value
	Firing.setSprinting(value)
end

local function onSprintAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprinting(false)
	end
	return Enum.ContextActionResult.Pass -- movement wants this key too
end

local function onSlotAction(_action: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if not combatActive() then
		return Enum.ContextActionResult.Pass
	end
	Firing.swap(if input.KeyCode == Enum.KeyCode.One then "Primary" else "Secondary")
	return Enum.ContextActionResult.Sink
end

-- ---------------------------------------------------------------------------
-- The ammo readout
--
-- Bottom-right, and deliberately plain. The number is the thing: a predicted
-- magazine that the player cannot see is a prediction nobody can tell is
-- working. The reload ring is the one piece of chrome, because "am I reloading
-- and how much longer" is the question you ask under fire.
-- ---------------------------------------------------------------------------

local ammoRoot: Frame? = nil
local ammoLabel: TextLabel? = nil
local weaponLabel: TextLabel? = nil
local reloadFill: Frame? = nil

local function buildAmmoHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "AmmoHUD"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.new(1, -Theme.space.lg, 1, -Theme.space.lg)
	root.Size = UDim2.fromOffset(158, 62)
	root.BackgroundColor3 = Theme.color.surfaceRaised
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = screen
	Components.corner(root, Theme.radius.panel)
	Components.stroke(root, Theme.color.primary, 2, 0.45)
	ammoRoot = root

	ammoLabel = Components.text(root, {
		text = "0 / 0",
		size = Theme.text.title,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Right,
		area = UDim2.new(1, -Theme.space.md * 2, 0, 30),
		position = UDim2.fromOffset(Theme.space.md, 6),
	})

	weaponLabel = Components.text(root, {
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		align = Enum.TextXAlignment.Right,
		area = UDim2.new(1, -Theme.space.md * 2, 0, 14),
		position = UDim2.fromOffset(Theme.space.md, 34),
	})

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -Theme.space.md * 2, 0, 5)
	track.Position = UDim2.new(0, Theme.space.md, 1, -13)
	track.BackgroundColor3 = Theme.color.surfaceSunken
	track.BorderSizePixel = 0
	track.Parent = root
	Components.corner(track, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.color.primary
	fill.BorderSizePixel = 0
	fill.Parent = track
	Components.corner(fill, Theme.radius.pill)
	reloadFill = fill
end

local function refreshAmmoHud()
	local root, label, name, fill = ammoRoot, ammoLabel, weaponLabel, reloadFill
	if not root or not label or not name or not fill then
		return
	end

	local weaponId, stats = Firing.weapon()
	if not weaponId or not stats then
		root.Visible = false
		return
	end

	-- Shown wherever the trigger works, so "why can't I shoot" and "where did
	-- my ammo counter go" are never two separate mysteries.
	root.Visible = combatActive() or Firing.reloading()

	local ammo, magSize = Firing.ammo()
	label.Text = `{ammo} / {magSize}`
	-- Empty reads differently from low. Under fire you do not read a number,
	-- you notice a colour.
	label.TextColor3 = if ammo == 0
		then Theme.color.danger
		elseif ammo <= math.max(1, math.floor(magSize * 0.25)) then Theme.color.primaryDeep
		else Theme.color.text
	name.Text = `{stats.name} · {Firing.slot()}`

	local reloading = Firing.reloading()
	fill.Parent.Visible = reloading
	fill.Size = UDim2.fromScale(Firing.reloadProgress(), 1)
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function step(deltaTime: number)
	-- The trigger is released, not merely ignored, when combat turns off.
	-- Ignoring it means the shot fires the instant the menu closes — which is
	-- how a player closes their loadout and immediately shoots the floor.
	if not combatActive() then
		Firing.setTrigger(false)
		if sprinting then
			setSprinting(false)
		end
	end

	Firing.step(deltaTime)
	-- Every frame rather than on Firing.changed: the reload ring is a moving
	-- value and nothing fires an event for "0.3 seconds have passed".
	refreshAmmoHud()
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function WeaponController.init()
	Firing.init()
	buildAmmoHud()

	Firing.fired:Connect(function(origin: Vector3, direction: Vector3, stats: any)
		kick(stats)
		-- Predicted, on the frame of the click. The server will draw this for
		-- everyone else when it accepts the shot; drawing our own here is what
		-- "instant" means, and a shot the server later rejects has already been
		-- corrected on the counter by then.
		EffectsController.playShotSound(0.5)
		EffectsController.launchProjectileVisual(origin, direction, stats.velocity, stats.drop, stats.travelMax)
	end)

	ContextActionService:BindAction(FIRE_ACTION, onFireAction, false, Enum.UserInputType.MouseButton1)
	ContextActionService:BindAction(RELOAD_ACTION, onReloadAction, false, Enum.KeyCode.R)
	ContextActionService:BindAction(SPRINT_ACTION, onSprintAction, false, Enum.KeyCode.LeftShift)
	ContextActionService:BindAction(SLOT_ACTION, onSlotAction, false, Enum.KeyCode.One, Enum.KeyCode.Two)

	RunService.Heartbeat:Connect(step)

	-- The Aim slot, claimed from the rig rather than bound here (NOD-142). The
	-- order of the camera chain was hard-won and is not this file's to know: it
	-- asks for the slot that runs after the shot and before the effects, and the
	-- rig decides what number that is.
	CameraRig.claim("Aim", SYSTEM, stepRecoil)

	-- Releasing the trigger when the window loses focus. Without it, alt-tab
	-- mid-burst leaves the mouse button logically held and the gun keeps
	-- firing at a window nobody is looking at.
	UserInputService.WindowFocusReleased:Connect(function()
		Firing.setTrigger(false)
		setSprinting(false)
	end)

	Diagnostics.ok(SYSTEM, `recoil x{RECOIL_SCALE}, no bloom · fire M1 · reload R · slots 1/2`)
end

return WeaponController
