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
	Remotes.event("FireWeapon"):FireServer(camera.CFrame.Position, aim.LookVector)
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
