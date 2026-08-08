--!strict
-- WeaponController — input, firing, and weapon switching on the client
-- (NOD-12/NOD-29 client half). Applies spread locally and reports
-- origin/direction; the server makes the real hit decision. Keys 1–4 switch
-- weapons, R reloads, left-click fires (held for automatics).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local EffectsController = require(script.Parent.EffectsController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local ClientData = require(script.Parent.Parent.ClientData)

local KEY_TO_WEAPON: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Pistol",
	[Enum.KeyCode.Two] = "Rifle",
	[Enum.KeyCode.Three] = "Shotgun",
	[Enum.KeyCode.Four] = "Knife",
}

local WeaponController = {}

local rng = Random.new()
local currentWeapon = "Pistol"
local triggerHeld = false
local lastShotAt = 0

local function selectWeapon(weaponId: string)
	if weaponId == currentWeapon then
		return
	end
	currentWeapon = weaponId
	ViewmodelController.setWeapon(weaponId)
	Remotes.event("SelectWeapon"):FireServer(weaponId)
end

local function shoot()
	if ClientData.menuOpen() or ClientData.inLobby() then
		return
	end
	local config = WeaponConfig[currentWeapon]
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
	ViewmodelController.kick()
	if config.kind == "Melee" then
		EffectsController.playShotSound(0.45) -- swing swish placeholder
		return
	end
	EffectsController.playShotSound(0.6)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local muzzle = ViewmodelController.getMuzzlePosition()
		or origin + camera.CFrame.RightVector * 0.6 - camera.CFrame.UpVector * 0.4
	-- Shotguns draw a few visual pellets; the server rolls the real pattern.
	local tracerCount = math.min(config.pellets, 3)
	for pellet = 1, tracerCount do
		local dir = aim.LookVector
		if pellet > 1 then
			dir = (aim * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
		end
		local result = workspace:Raycast(origin, dir * config.range, params)
		local endpoint = if result then result.Position else origin + dir * config.range
		EffectsController.drawTracer(muzzle, endpoint)
	end
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
		else
			local weaponId = KEY_TO_WEAPON[input.KeyCode]
			if weaponId then
				selectWeapon(weaponId)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		if triggerHeld and WeaponConfig[currentWeapon].auto then
			shoot()
		end
	end)

	-- The server is the authority on the held weapon (persisted loadout choice
	-- on spawn, validated switches). Adopt whatever it reports.
	Remotes.event("AmmoChanged").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.weaponId) == "string" and WeaponConfig[data.weaponId] then
			if data.weaponId ~= currentWeapon then
				currentWeapon = data.weaponId
				ViewmodelController.setWeapon(data.weaponId)
			end
		end
	end)
end

return WeaponController
