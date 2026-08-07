--!strict
-- WeaponController — input + firing on the client (NOD-12 client half).
-- Applies spread locally and reports origin/direction to the server, which
-- makes the real hit decision. Local cooldown mirrors the server's fire rate
-- so honest clients rarely see rejected shots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local EffectsController = require(script.Parent.EffectsController)

local Players = game:GetService("Players")

local WeaponController = {}

local rng = Random.new()
local weaponId = "Pistol" -- loadout selection replaces this in M3
local triggerHeld = false
local lastShotAt = 0

local function shoot()
	local config = WeaponConfig[weaponId]
	local now = os.clock()
	if now - lastShotAt < 1 / config.fireRate then
		return
	end
	lastShotAt = now

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local spread = math.rad(config.spread)
	local aim = camera.CFrame
		* CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)
	local origin = camera.CFrame.Position
	Remotes.event("FireWeapon"):FireServer(origin, aim.LookVector)

	-- Immediate local feedback; the server independently decides the real hit.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local result = workspace:Raycast(origin, aim.LookVector * config.range, params)
	local endpoint = if result then result.Position else origin + aim.LookVector * config.range
	-- Start the tracer just off-center (down-right) so it reads as a shot, not
	-- a line drawn in your eye.
	local muzzle = origin + camera.CFrame.RightVector * 0.6 - camera.CFrame.UpVector * 0.4
	EffectsController.drawTracer(muzzle, endpoint)
	EffectsController.playShotSound(0.6)
end

function WeaponController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
			shoot()
		elseif input.KeyCode == Enum.KeyCode.R then
			Remotes.event("ReloadWeapon"):FireServer()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	-- Automatic weapons (rifle, M3) keep firing while the trigger is held.
	RunService.Heartbeat:Connect(function()
		if triggerHeld and WeaponConfig[weaponId].auto then
			shoot()
		end
	end)
end

return WeaponController
