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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local ClientData = require(script.Parent.Parent.ClientData)
local CameraRig = require(script.Parent.Parent.Camera.CameraRig)

local SYSTEM = "CameraController"

-- Tuning knobs (all feel-related feedback lands here):
local FOLLOW_OFFSET = Vector3.new(0, 11, 34) -- low + pulled back: ~15° down-angle
local LOOK_HEIGHT = 2.5 -- aim point above the character's root
local CHASE_SPEED = 6 -- camera position responsiveness (higher = snappier)
local LEAD_SECONDS = 0.25 -- how far ahead of your velocity the camera drifts
local LEAD_MAX = 5 -- studs of maximum lead
local LEAD_SMOOTHING = 4 -- how quickly the lead itself eases in/out
-- How close counts as arrived. Well under a pixel at any sane FOV, and the
-- point of it is that the jitter test reads exactly zero rather than "small".
local SNAP_STUDS = 0.002
local SNAP_DOT = 0.9999999

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local CameraController = {}

local zonePart: BasePart? = nil
local shotOverride: CFrame? = nil -- interiors (NOD-90) will set fixed shots here
local currentCFrame: CFrame? = nil
local smoothedLead = Vector3.zero
local combatApplied = false
local wasFighting = false

local function lobbyFolder(): Folder?
	return workspace:FindFirstChild("PinkPanicLobby") :: Folder?
end

-- Which camera the lobby gets is decided by whether a tagged part exists, so
-- the manifest has to say which one is live — otherwise "the lobby camera is
-- wrong" and "there is no CameraAnchor" look identical from the outside.
--
-- Reported on the first frame the anchor resolves rather than at init, because
-- init reliably loses the race with workspace.Lobby replicating: the honest
-- answer at boot is "not yet", and a manifest line that says "no CameraAnchor"
-- about a lobby that has one is worse than no line at all.
local anchorReported = false

local function reportAnchor(anchor: BasePart?)
	if anchorReported then
		return
	end
	anchorReported = true

	local detail
	if anchor then
		local yaw = anchor:GetAttribute("MaxYawDeg")
		local pitch = anchor:GetAttribute("MaxPitchDeg")
		detail = `CameraAnchor found · yaw ±{if type(yaw) == "number" then yaw else 20}° `
			.. `pitch ±{if type(pitch) == "number" then pitch else 10}°`
	else
		detail = "no CameraAnchor — using the follow camera"
	end

	Diagnostics.ok(SYSTEM, detail)
	-- The manifest has usually already printed by the time this resolves, so
	-- the answer has to reach the log on its own or it reaches nobody.
	if Diagnostics.hasReported() then
		print(`[PinkPanic] ✅ {SYSTEM}: {detail}`)
	end
end

-- Titus's hand-built lobby (workspace.Lobby) supplies a CameraAnchor part:
-- its position is the camera eye, its facing is the base view, and the
-- camera PIVOTS in place to follow you — clamped (MaxYawDeg / MaxPitchDeg
-- attributes) so it can never swing far enough to reveal unbuilt areas.
local function cameraAnchor(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	-- Recursive: the anchor works nested anywhere inside the lobby build.
	local anchor = lobby and lobby:FindFirstChild("CameraAnchor", true)
	local resolved = if anchor and anchor:IsA("BasePart") then anchor else nil
	if resolved then
		reportAnchor(resolved)
	end
	return resolved
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

	-- Fixed-pivot mode: hand-built lobby with an authored camera position.
	local anchor = cameraAnchor()
	if anchor then
		local eye = anchor.Position
		local target = root.Position + Vector3.new(0, 2, 0)
		local toTarget = (target - eye)
		if toTarget.Magnitude < 0.5 then
			return anchor.CFrame
		end
		-- Express the desired look direction in the anchor's space, clamp
		-- yaw/pitch offsets, rebuild.
		local localDir = anchor.CFrame:VectorToObjectSpace(toTarget.Unit)
		local yaw = math.atan2(-localDir.X, -localDir.Z)
		local pitch = math.asin(math.clamp(localDir.Y, -1, 1))
		local maxYaw = math.rad((anchor:GetAttribute("MaxYawDeg") :: number?) or 20)
		local maxPitch = math.rad((anchor:GetAttribute("MaxPitchDeg") :: number?) or 10)
		yaw = math.clamp(yaw, -maxYaw, maxYaw)
		pitch = math.clamp(pitch, -maxPitch, maxPitch)
		local look = (anchor.CFrame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
		return CFrame.lookAlong(eye, look)
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

	-- `fighting()` rather than `not inLobby()`. The round loop is deleted until
	-- M9 and `inLobby()` is permanently true, so this used to mean the arena got
	-- the LOBBY camera: you could shoot people while looking at a fixed
	-- cinematic shot of the storefront row, and every first-person camera effect
	-- was unreachable code. Standing in the arena is standing in a fight, and it
	-- is the same answer the trigger uses.
	local fighting = ClientData.fighting()

	-- The cursor follows the same line. It used to be re-evaluated only when a
	-- menu opened or the round state changed, neither of which happens when you
	-- WALK into the arena — so you arrived in first person with a free mouse
	-- pointer floating over the middle of the screen.
	if fighting ~= wasFighting then
		wasFighting = fighting
		ClientData.updateMouseUnlock()
	end

	-- The rig's roll, tilt, dip and FOV kicks are all effects about a view you
	-- look THROUGH. The lobby shot is one you look AT, so it is told which world
	-- it is in rather than guessing from the camera type.
	CameraRig.setCombat(fighting)

	if fighting then
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

	-- Roblox's default TransparencyController keeps fading the local character
	-- via LocalTransparencyModifier even while CameraType is Scriptable, which
	-- left the player see-through in the lobby (measured at 0.76 on 24 of 29
	-- parts, with Transparency itself still 0). It re-asserts every frame, so
	-- we re-assert back. Only writes when it has actually drifted.
	if characterModel then
		for _, part in characterModel:GetDescendants() do
			if part:IsA("BasePart") and part.LocalTransparencyModifier > 0.01 then
				part.LocalTransparencyModifier = 0
			end
		end
	end

	local desired = desiredLobbyCFrame(deltaTime)
	if not desired then
		return
	end
	local alpha = 1 - math.exp(-deltaTime * CHASE_SPEED)
	local current = currentCFrame
	if not current then
		currentCFrame = desired
	elseif
		(desired.Position - current.Position).Magnitude < SNAP_STUDS
		and math.abs(desired.LookVector:Dot(current.LookVector)) > SNAP_DOT
	then
		-- Arrived. An exponential chase converges but never actually gets there,
		-- so a camera watching a player who is standing perfectly still keeps
		-- moving forever by ever-smaller amounts. Sub-pixel — measured worst
		-- 0.028 falling to nothing — but it makes "is the camera stable?"
		-- unanswerable, and the answer to that question should be a flat zero.
		currentCFrame = desired
	else
		currentCFrame = current:Lerp(desired, alpha)
	end
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
	-- Through the rig, not straight at RunService. The chain's order is the rig's
	-- to own (NOD-142) — this file asks for the Base slot and does not get to
	-- know, or accidentally change, what number that is.
	CameraRig.claim("Base", SYSTEM, update)

	-- One attempt now so a lobby that has already replicated reports inside the
	-- manifest; if it hasn't, the render step reports the moment it does. Give
	-- up after a few seconds and say so, otherwise a genuinely missing anchor
	-- would sit as PENDING forever.
	cameraAnchor()
	task.delay(5, function()
		reportAnchor(cameraAnchor())
	end)
end

return CameraController
