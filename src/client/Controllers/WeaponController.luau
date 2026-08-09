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

-- ADS: hold right mouse. The blend eases over the gun's adsTime.
local adsHeld = false
local adsAlpha = 0
local ADS_ZOOM: { [string]: number } = {
	Pistol = 8, Revolver = 9, SMG = 8, Shotgun = 6,
	Rifle = 10, Carbine = 10, Bullpup = 10, Sniper = 26,
}

-- Recoil: fixed spread never grows (no bloom, ever) — sustained fire
-- climbs the CAMERA instead, and the crosshair always tells the truth.
local recoilPitch = 0 -- radians of climb currently applied
local recoilYaw = 0
local RECOIL_PITCH_MAX = math.rad(6.5)
local RECOIL_YAW_MAX = math.rad(2.5)

-- Aim-error feel knobs (per-gun numbers live in GunCatalog).
local MOVE_SPREAD_DEG = 0.3 -- tiny penalty at full stride; barely noticeable
local CROUCH_SPREAD_MULT = 0.8
local CROUCH_RECOIL_MULT = 0.9

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

	-- Aim error: hip vs ADS (fixed — never grows), a whisper of movement
	-- penalty, and a crouch discount. Shotgun pellet cones stay separate.
	local crouched = MovementController.isCrouching()
	local aimSpreadDeg = stats.spreadDeg + (stats.adsSpreadDeg - stats.spreadDeg) * adsAlpha
	local strideFactor = math.clamp(MovementController.getHorizontalSpeed() / 24, 0, 1)
	aimSpreadDeg += MOVE_SPREAD_DEG * strideFactor * (1 - 0.5 * adsAlpha)
	if crouched then
		aimSpreadDeg *= CROUCH_SPREAD_MULT
	end
	local spread = math.rad(aimSpreadDeg)
	local aim = camera.CFrame
		* CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)
	local origin = camera.CFrame.Position
	Remotes.event("FireWeapon"):FireServer(origin, aim.LookVector)

	ViewmodelController.kick(stats.recoilVert)
	if stats.kind == "Melee" then
		EffectsController.playShotSound(0.45)
		return
	end

	-- Camera recoil for the NEXT shot: vertical climb with light sideways
	-- jitter, calmer while aimed or crouched.
	local calm = (1 - 0.25 * adsAlpha) * (if crouched then CROUCH_RECOIL_MULT else 1)
	recoilPitch = math.min(
		recoilPitch + math.rad(stats.recoilVert) * rng:NextNumber(0.9, 1.1) * calm,
		RECOIL_PITCH_MAX
	)
	recoilYaw = math.clamp(
		recoilYaw + math.rad(stats.recoilHoriz) * rng:NextNumber(-1, 1) * calm,
		-RECOIL_YAW_MAX,
		RECOIL_YAW_MAX
	)

	EffectsController.playShotSound(0.6)

	-- One shell per shot pops from the in-hand gun and stays on the floor.
	EffectsController.ejectShell(
		ViewmodelController.getEjectCFrame()
			or camera.CFrame * CFrame.new(0.95, -0.65, -1.3)
	)

	local muzzle = ViewmodelController.getMuzzlePosition()
		or origin + camera.CFrame.RightVector * 0.6 - camera.CFrame.UpVector * 0.4
	-- Extra pellets scatter in the gun's fixed pellet cone (the server rolls
	-- its own; these are just the local visuals).
	local pelletSpread = math.rad(stats.spreadDeg)
	local tracerCount = math.min(stats.pellets, 3)
	for pellet = 1, tracerCount do
		local dir = aim.LookVector
		if pellet > 1 then
			dir = (aim * CFrame.Angles(
				rng:NextNumber(-pelletSpread, pelletSpread),
				rng:NextNumber(-pelletSpread, pelletSpread),
				0
			)).LookVector
		end
		EffectsController.launchProjectileVisual(muzzle, dir, stats.velocity, stats.drop, stats.travelMax)
	end
end

-- Weapon weight: heavy guns slow you down, light ones speed you up.
local function pushSpeedMult()
	MovementController.setWeaponSpeedMult(currentStats().moveSpeedMult)
end

function WeaponController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
			shoot()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			adsHeld = true
		elseif input.KeyCode == Enum.KeyCode.R then
			Remotes.event("ReloadWeapon"):FireServer()
		else
			local slot = KEY_TO_SLOT[input.KeyCode]
			if slot then
				selectSlot(slot)
				pushSpeedMult()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			adsHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		if triggerHeld and currentStats().auto then
			shoot()
		end
	end)

	-- Per-frame aim step, after the engine camera (+1) and before the slide
	-- roll (+3): blend ADS over the gun's adsTime, settle recoil, and apply
	-- the climb to the camera so the crosshair points where bullets go.
	RunService:BindToRenderStep("PinkPanicAim", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local stats = currentStats()
		local inCombat = not ClientData.inLobby() and not ClientData.menuOpen()

		local target = if adsHeld and inCombat and stats.kind ~= "Melee" then 1 else 0
		local step = dt / math.max(stats.adsTime, 0.06)
		adsAlpha = math.clamp(
			adsAlpha + (if target > adsAlpha then step else -step * 1.5),
			0,
			1
		)
		ViewmodelController.setAdsAlpha(adsAlpha)
		MovementController.setAds(adsAlpha, ADS_ZOOM[stats.class] or 10)

		local settle = math.exp(-dt * stats.recoilRecovery / 2.2)
		recoilPitch *= settle
		recoilYaw *= settle
		if inCombat and (recoilPitch > 1e-4 or math.abs(recoilYaw) > 1e-4) then
			local camera = workspace.CurrentCamera
			if camera then
				camera.CFrame = camera.CFrame * CFrame.Angles(recoilPitch, recoilYaw, 0)
			end
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
				ViewmodelController.setReloading(
					data.reloading == true,
					CombatStats.resolve(data.gunId).reloadSeconds
				)
				pushSpeedMult()
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
