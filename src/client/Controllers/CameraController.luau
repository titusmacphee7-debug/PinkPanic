--!strict
-- CameraController — two camera worlds:
--  · Lobby: Animal Crossing-style diorama cam — elevated, tilted down ~36°,
--    fixed facing, smoothly gliding after your character; walking into a
--    zone eases the camera into that building's framing.
--  · Rounds: standard first-person (zoom pinned), engine-driven.
-- All transitions are one exponential-smoothed CFrame chase, which makes
-- zone changes and mode hand-offs feel like one continuous camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientData = require(script.Parent.Parent.ClientData)

-- Elevated + pulled back toward the arena side; ~36° down-angle.
local FOLLOW_OFFSET = Vector3.new(0, 26, 36)
local CHASE_SPEED = 3.5 -- higher = snappier camera

local CameraController = {}

local zonePart: BasePart? = nil
local currentCFrame: CFrame? = nil
local combatApplied = false

local function lobbyFolder(): Folder?
	return workspace:FindFirstChild("PinkPanicLobby") :: Folder?
end

local function plazaCenter(): Vector3
	local lobby = lobbyFolder()
	local center = lobby and lobby:GetAttribute("PlazaCenter")
	return if typeof(center) == "Vector3" then center else Vector3.zero
end

local function desiredLobbyCFrame(): CFrame?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local zone = zonePart
	if zone then
		-- Frame the building: camera between it and the plaza, looking in.
		local zonePosition = zone.Position
		local toPlaza = plazaCenter() - zonePosition
		local flat = Vector3.new(toPlaza.X, 0, toPlaza.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		local eye = zonePosition + direction * 26 + Vector3.new(0, 13, 0)
		return CFrame.lookAt(eye, zonePosition + Vector3.new(0, 3, 0))
	end

	local eye = root.Position + FOLLOW_OFFSET
	return CFrame.lookAt(eye, root.Position + Vector3.new(0, 2, 0))
end

local function setCombatCamera()
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
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
		return
	end

	combatApplied = false
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 8
	player.CameraMaxZoomDistance = 60
	camera.CameraType = Enum.CameraType.Scriptable

	local desired = desiredLobbyCFrame()
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

function CameraController.init()
	RunService:BindToRenderStep("PinkPanicCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
