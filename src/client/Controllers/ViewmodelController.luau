--!strict
-- ViewmodelController — the in-hand first-person gun (NOD-16/NOD-109):
-- builds whatever the current slot holds via GunModelLoader (real meshes
-- with part-built fallback), applies the player's cosmetics, and runs sway,
-- walk bob, recoil kick, sprint held-up pose, and slide cant. Longer weapon
-- classes sit further out via per-class offsets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local GunModelLoader = require(ReplicatedStorage.Shared.Assets.GunModelLoader)
local ClientData = require(script.Parent.Parent.ClientData)
local MovementController = require(script.Parent.MovementController)

local BASE_OFFSET = CFrame.new(1.05, -0.85, -1.55)
-- Aimed-in: the gun rides centered under the crosshair.
local ADS_OFFSET = CFrame.new(0, -0.6, -1.15)
local CLASS_OFFSET: { [string]: CFrame } = {
	SMG = CFrame.new(0, 0, -0.1),
	Rifle = CFrame.new(0.05, 0, -0.25),
	Carbine = CFrame.new(0.05, 0, -0.2),
	Bullpup = CFrame.new(0.05, 0, -0.15),
	Shotgun = CFrame.new(0.05, 0, -0.25),
	Sniper = CFrame.new(0.1, -0.05, -0.4),
}
local SWAY_LIMIT = 0.06
local KICK_PER_SHOT = 0.075 -- multiplied by the gun's recoilVert
local KICK_MAX = 0.3

local ViewmodelController = {}

local model: Model? = nil
local currentWeapon = "Pistol_1"
local recoil = 0
local swayX = 0
local swayY = 0
local loweredAlpha = 0
local cantAlpha = 0
-- Procedural animation state (equip raise, reload choreography, landing dip)
local equipStartedAt = 0
local equipDuration = 0.3
local reloadEndsAt = 0
local reloadDuration = 1
local landKick = 0
-- ADS blend pushed by WeaponController (0 = hip, 1 = aimed).
local adsAlpha = 0

local function localCharacterAlive(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function myCosmetics(): GunModelLoader.Cosmetics?
	local snapshot = ClientData.snapshot
	local all = snapshot and snapshot.gunCosmetics
	local entry = if type(all) == "table" then all[currentWeapon] else nil
	return if type(entry) == "table" then { skinId = entry.skinId, camoId = entry.camoId } else nil
end

local function classOffset(): CFrame
	local def = GunCatalog.get(currentWeapon)
	return if def then (CLASS_OFFSET[def.class] or CFrame.identity) else CFrame.identity
end

local function ensureModel(): Model
	local current = model
	if current and current.Parent then
		return current
	end
	local built = GunModelLoader.build(currentWeapon, myCosmetics())
	built.Name = "Viewmodel"
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	built.Parent = workspace.CurrentCamera
	model = built
	return built
end

local function hideModel()
	if model then
		model:Destroy()
		model = nil
	end
end

local function update(dt: number)
	if ClientData.inLobby() or not localCharacterAlive() then
		hideModel()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local gun = ensureModel()

	local delta = UserInputService:GetMouseDelta()
	local blend = math.min(dt * 12, 1)
	-- Aiming in steadies the hands: sway and bob fade with the ADS blend.
	local steady = 1 - 0.65 * adsAlpha
	swayX += (math.clamp(-delta.X * 0.0025, -SWAY_LIMIT, SWAY_LIMIT) * steady - swayX) * blend
	swayY += (math.clamp(delta.Y * 0.002, -SWAY_LIMIT, SWAY_LIMIT) * steady - swayY) * blend

	local bob = 0
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.AssemblyLinearVelocity.Magnitude > 2 then
		bob = math.sin(os.clock() * 10) * 0.025 * steady
	end

	recoil = math.max(0, recoil - recoil * math.min(dt * 10, 1))

	local poseBlend = math.min(dt * 9, 1)
	loweredAlpha += ((if MovementController.isSprinting() then 1 else 0) - loweredAlpha) * poseBlend
	cantAlpha += ((if MovementController.isSliding() then 1 else 0) - cantAlpha) * poseBlend

	local sprintPose = CFrame.new(-0.45 * loweredAlpha, -0.12 * loweredAlpha, 0.18 * loweredAlpha)
		* CFrame.Angles(0.28 * loweredAlpha, 0.7 * loweredAlpha, 0.12 * loweredAlpha)

	-- Pull-out: the gun sweeps up from low-right over the weapon's equipTime.
	local now = os.clock()
	local equipRemaining = 1 - math.clamp((now - equipStartedAt) / equipDuration, 0, 1)
	local e = equipRemaining * equipRemaining -- ease-out on the way up
	local equipPose = CFrame.new(0.2 * e, -1.15 * e, 0.3 * e)
		* CFrame.Angles(-0.9 * e, 0.55 * e, 0.2 * e)

	-- Reload: dip in -> mag-swap wobble -> confident return, spanning the
	-- weapon's exact reloadSeconds so animation and gameplay always agree.
	local reloadPose = CFrame.identity
	if now < reloadEndsAt then
		local p = 1 - (reloadEndsAt - now) / reloadDuration
		local inAmount = math.sin(math.min(p / 0.22, 1) * math.pi / 2)
		local outAmount = if p > 0.82 then 1 - (p - 0.82) / 0.18 else 1
		local amount = inAmount * math.max(outAmount, 0)
		local wobble = math.sin(p * math.pi * 5) * 0.07 * amount
		reloadPose = CFrame.new(0.05 * amount, -0.55 * amount, 0.18 * amount)
			* CFrame.Angles(-0.38 * amount + wobble, 0.22 * amount, 0.55 * amount)
	end

	-- Landing dip: the gun sinks and recovers when you hit the ground.
	landKick = math.max(0, landKick - dt * 4)
	local landPose = CFrame.new(0, -0.35 * landKick, 0) * CFrame.Angles(-0.2 * landKick, 0, 0)

	-- ADS pulls the gun to center; class push-out fades with it so every
	-- gun lands in the same aimed pose.
	local mount = BASE_OFFSET:Lerp(ADS_OFFSET, adsAlpha)
		* CFrame.identity:Lerp(classOffset(), 1 - adsAlpha)
	local cframe = camera.CFrame
		* mount
		* CFrame.new(swayX, swayY + bob, recoil * 0.4)
		* sprintPose
		* equipPose
		* reloadPose
		* landPose
		* CFrame.Angles(recoil, swayX * 0.5, cantAlpha * 0.35)
	gun:PivotTo(cframe)
end

-- Called on slot switches and server slot pushes; rebuilds next frame.
function ViewmodelController.setWeapon(weaponId: string)
	if weaponId == currentWeapon then
		return
	end
	currentWeapon = weaponId
	hideModel()
	-- Pull-out animation paced by the weapon's own equip stat.
	equipDuration = math.max(CombatStats.resolve(weaponId).equipTime, 0.15)
	equipStartedAt = os.clock()
	reloadEndsAt = 0
end

-- WeaponController relays the server's reload state so the choreography
-- spans the weapon's exact reload window.
function ViewmodelController.setReloading(active: boolean, duration: number?)
	if active then
		reloadDuration = math.max(duration or 1, 0.2)
		reloadEndsAt = os.clock() + reloadDuration
	else
		reloadEndsAt = 0
	end
end

-- Cosmetic changes re-dress the in-hand gun.
function ViewmodelController.refreshCosmetics()
	local gun = model
	if gun then
		GunModelLoader.applyCosmetics(gun, currentWeapon, myCosmetics())
	end
end

-- Visual kick scaled by the gun's real recoil stat (degrees of climb per
-- shot), so the viewmodel and the camera agree about how mean the gun is.
function ViewmodelController.kick(recoilVert: number?)
	local strength = math.max(recoilVert or 1, 0.4)
	recoil = math.min(recoil + KICK_PER_SHOT * strength, KICK_MAX)
end

function ViewmodelController.setAdsAlpha(alpha: number)
	adsAlpha = math.clamp(alpha, 0, 1)
end

-- Where shells pop out: the right side of the in-hand gun's receiver.
function ViewmodelController.getEjectCFrame(): CFrame?
	local gun = model
	local primary = gun and gun.PrimaryPart
	if primary then
		return primary.CFrame * CFrame.new(primary.Size.X / 2 + 0.04, primary.Size.Y * 0.25, primary.Size.Z * 0.1)
	end
	return nil
end

-- Where tracers start: the viewmodel's muzzle, or a camera-relative fallback.
function ViewmodelController.getMuzzlePosition(): Vector3?
	local gun = model
	local primary = gun and gun.PrimaryPart
	local muzzle = primary and primary:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return nil
end

function ViewmodelController.init()
	RunService:BindToRenderStep("PinkPanicViewmodel", Enum.RenderPriority.Camera.Value + 1, update)

	-- Landing dip hookup (re-hooked per character).
	local function hookCharacter(model: Model)
		local humanoid = model:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.Landed then
					landKick = 0.7
				end
			end)
		end
	end
	local existing = Players.LocalPlayer.Character
	if existing then
		task.spawn(hookCharacter, existing)
	end
	Players.LocalPlayer.CharacterAdded:Connect(function(model)
		equipStartedAt = os.clock() -- fresh spawn raises the gun too
		task.spawn(hookCharacter, model)
	end)
end

return ViewmodelController
