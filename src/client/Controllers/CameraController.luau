--!strict
-- CameraController (NOD-88) — two camera worlds:
--  · Lobby: fixed low cinematic shot — ~15° down so the storefront row fills
--    the frame, with a gentle pan that leads your movement (the camera walks
--    with you, not behind you). Character rotation is movement-relative:
--    your character faces where they walk, never locked to the camera.
--  · Rounds: standard first-person (zoom pinned), engine-driven.
-- Zone framings and future interior shots run through the same smoothed
-- chase, so every transition feels like one continuous camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientData = require(script.Parent.Parent.ClientData)

-- Tuning knobs (all feel-related feedback lands here):
local FOLLOW_OFFSET = Vector3.new(0, 11, 34) -- low + pulled back: ~15° down-angle
local LOOK_HEIGHT = 2.5 -- aim point above the character's root
local CHASE_SPEED = 9 -- camera position responsiveness (higher = snappier)
local LEAD_SECONDS = 0.25 -- how far ahead of your velocity the camera drifts
local LEAD_MAX = 5 -- studs of maximum lead
local LEAD_SMOOTHING = 4 -- how quickly the lead itself eases in/out

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local CameraController = {}

local zonePart: BasePart? = nil
local shotOverride: CFrame? = nil -- interiors (NOD-90) will set fixed shots here
local currentCFrame: CFrame? = nil
local smoothedLead = Vector3.zero
local combatApplied = false

local function lobbyFolder(): Folder?
	return workspace:FindFirstChild("PinkPanicLobby") :: Folder?
end

local function plazaCenter(): Vector3
	local lobby = lobbyFolder()
	local center = lobby and lobby:GetAttribute("PlazaCenter")
	return if typeof(center) == "Vector3" then center else Vector3.zero
end

local function setRotationMode(movementRelative: boolean)
	pcall(function()
		UserGameSettings.RotationType = if movementRelative
			then Enum.RotationType.MovementRelative
			else Enum.RotationType.CameraRelative
	end)
end

local function desiredLobbyCFrame(deltaTime: number): CFrame?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local override = shotOverride
	if override then
		return override
	end

	local zone = zonePart
	if zone then
		-- Frame the building: camera between it and the plaza, looking in.
		local zonePosition = zone.Position
		local toPlaza = plazaCenter() - zonePosition
		local flat = Vector3.new(toPlaza.X, 0, toPlaza.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		local eye = zonePosition + direction * 24 + Vector3.new(0, 9, 0)
		return CFrame.lookAt(eye, zonePosition + Vector3.new(0, 3, 0))
	end

	-- Movement lead: drift the whole shot toward where you're heading.
	local velocity = root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local targetLead = flatVelocity * LEAD_SECONDS
	if targetLead.Magnitude > LEAD_MAX then
		targetLead = targetLead.Unit * LEAD_MAX
	end
	local leadAlpha = 1 - math.exp(-deltaTime * LEAD_SMOOTHING)
	smoothedLead = smoothedLead:Lerp(targetLead, leadAlpha)

	local focus = root.Position + smoothedLead
	return CFrame.lookAt(focus + FOLLOW_OFFSET, focus + Vector3.new(0, LOOK_HEIGHT, 0))
end

local function setCombatCamera()
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	setRotationMode(false)
	combatApplied = true
end

local function update(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if not ClientData.inLobby() then
		if not combatApplied then
			setCombatCamera()
		end
		currentCFrame = nil
		smoothedLead = Vector3.zero
		return
	end

	combatApplied = false
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 8
	player.CameraMaxZoomDistance = 60
	camera.CameraType = Enum.CameraType.Scriptable
	-- Every frame: the engine re-asserts camera-relative rotation from the
	-- first-person handoff; we assert movement-relative right back.
	setRotationMode(true)
	local characterModel = player.Character
	local humanoid = characterModel and characterModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end

	local desired = desiredLobbyCFrame(deltaTime)
	if not desired then
		return
	end
	local alpha = 1 - math.exp(-deltaTime * CHASE_SPEED)
	local current = currentCFrame
	currentCFrame = if current then current:Lerp(desired, alpha) else desired
	camera.CFrame = currentCFrame :: CFrame
end

-- LobbyController tells us which building the player is standing at.
function CameraController.setZone(part: BasePart?)
	zonePart = part
end

-- Interior rooms (NOD-90) pin their own composed shot; nil returns control
-- to the plaza chase.
function CameraController.setShot(cframe: CFrame?)
	shotOverride = cframe
end

function CameraController.init()
	RunService:BindToRenderStep("PinkPanicCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
