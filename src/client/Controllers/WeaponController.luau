--!strict
-- WeaponController — input, firing, and slot switching for the gun-roster
-- era (NOD-109 client half). Keys: 1 Primary, 2 Secondary, 3 Knife.
-- Stats resolve through the same CombatStats module the server uses, from
-- the loadout in the ClientData snapshot. The server remains the authority
-- on the held slot (AmmoChanged pushes) and on every hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local EffectsController = require(script.Parent.EffectsController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local MovementController = require(script.Parent.MovementController)
local ClientData = require(script.Parent.Parent.ClientData)

local KEY_TO_SLOT: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Primary",
	[Enum.KeyCode.Two] = "Secondary",
	[Enum.KeyCode.Three] = "Knife",
}

local WeaponController = {}

local rng = Random.new()
local currentSlot = "Secondary"
local triggerHeld = false
local lastShotAt = 0
local equipReadyAt = 0

local function slotGunId(slot: string): string?
	if slot == "Knife" then
		return "Knife"
	end
	local snapshot = ClientData.snapshot
	local loadout = snapshot and snapshot.loadout
	if slot == "Primary" then
		return if type(loadout) == "table" then loadout.primary else nil
	end
	return if type(loadout) == "table" and type(loadout.secondary) == "string"
		then loadout.secondary
		else "Pistol_1"
end

local function currentStats(): CombatStats.Resolved
	return CombatStats.resolve(slotGunId(currentSlot) or "Pistol_1")
end

local function selectSlot(slot: string)
	if slot == currentSlot or not slotGunId(slot) then
		return
	end
	currentSlot = slot
	equipReadyAt = os.clock() + currentStats().equipTime
	ViewmodelController.setWeapon(slotGunId(slot) or "Pistol_1")
	Remotes.event("SelectWeapon"):FireServer(slot)
end

local function shoot()
	if ClientData.menuOpen() or ClientData.inLobby() then
		return
	end
	local stats = currentStats()
	if not MovementController.canFire() then
		MovementController.noteFireAttempt(stats.sprintToFire)
		return
	end
	local now = os.clock()
	if now < equipReadyAt then
		return
	end
	if now - lastShotAt < 1 / stats.fireRate then
		return
	end
	lastShotAt = now

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local spread = math.rad(stats.spreadDeg)
	local aim = camera.CFrame
		* CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)
	local origin = camera.CFrame.Position
	Remotes.event("FireWeapon"):FireServer(origin, aim.LookVector)

	ViewmodelController.kick()
	if stats.kind == "Melee" then
		EffectsController.playShotSound(0.45)
		return
	end
	EffectsController.playShotSound(0.6)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local muzzle = ViewmodelController.getMuzzlePosition()
		or origin + camera.CFrame.RightVector * 0.6 - camera.CFrame.UpVector * 0.4
	local tracerCount = math.min(stats.pellets, 3)
	for pellet = 1, tracerCount do
		local dir = aim.LookVector
		if pellet > 1 then
			dir = (aim * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
		end
		local result = workspace:Raycast(origin, dir * stats.range, params)
		local endpoint = if result then result.Position else origin + dir * stats.range
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
			local slot = KEY_TO_SLOT[input.KeyCode]
			if slot then
				selectSlot(slot)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		if triggerHeld and currentStats().auto then
			shoot()
		end
	end)

	-- The server is the authority on the held slot (persisted loadout on
	-- spawn, validated switches). Adopt whatever it reports.
	Remotes.event("AmmoChanged").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.slot) == "string" then
			if data.slot ~= currentSlot then
				currentSlot = data.slot
			end
			if type(data.gunId) == "string" then
				ViewmodelController.setWeapon(data.gunId)
			end
		end
	end)

	-- Loadout/cosmetic changes re-dress the current viewmodel.
	ClientData.changed:Connect(function()
		local gunId = slotGunId(currentSlot)
		if gunId then
			ViewmodelController.setWeapon(gunId)
			ViewmodelController.refreshCosmetics()
		end
	end)
end

return WeaponController
