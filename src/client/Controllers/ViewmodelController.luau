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
local GunModelLoader = require(ReplicatedStorage.Shared.Assets.GunModelLoader)
local ClientData = require(script.Parent.Parent.ClientData)
local MovementController = require(script.Parent.MovementController)

local BASE_OFFSET = CFrame.new(1.05, -0.85, -1.55)
local CLASS_OFFSET: { [string]: CFrame } = {
	SMG = CFrame.new(0, 0, -0.1),
	Rifle = CFrame.new(0.05, 0, -0.25),
	Carbine = CFrame.new(0.05, 0, -0.2),
	Bullpup = CFrame.new(0.05, 0, -0.15),
	Shotgun = CFrame.new(0.05, 0, -0.25),
	Sniper = CFrame.new(0.1, -0.05, -0.4),
}
local SWAY_LIMIT = 0.06
local KICK_PER_SHOT = 0.09
local KICK_MAX = 0.22

local ViewmodelController = {}

local model: Model? = nil
local currentWeapon = "Pistol_1"
local recoil = 0
local swayX = 0
local swayY = 0
local loweredAlpha = 0
local cantAlpha = 0

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
	swayX += (math.clamp(-delta.X * 0.0025, -SWAY_LIMIT, SWAY_LIMIT) - swayX) * blend
	swayY += (math.clamp(delta.Y * 0.002, -SWAY_LIMIT, SWAY_LIMIT) - swayY) * blend

	local bob = 0
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.AssemblyLinearVelocity.Magnitude > 2 then
		bob = math.sin(os.clock() * 10) * 0.025
	end

	recoil = math.max(0, recoil - recoil * math.min(dt * 10, 1))

	local poseBlend = math.min(dt * 9, 1)
	loweredAlpha += ((if MovementController.isSprinting() then 1 else 0) - loweredAlpha) * poseBlend
	cantAlpha += ((if MovementController.isSliding() then 1 else 0) - cantAlpha) * poseBlend

	local sprintPose = CFrame.new(-0.45 * loweredAlpha, -0.12 * loweredAlpha, 0.18 * loweredAlpha)
		* CFrame.Angles(0.28 * loweredAlpha, 0.7 * loweredAlpha, 0.12 * loweredAlpha)
	local cframe = camera.CFrame
		* BASE_OFFSET
		* classOffset()
		* CFrame.new(swayX, swayY + bob, recoil * 0.4)
		* sprintPose
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
end

-- Cosmetic changes re-dress the in-hand gun.
function ViewmodelController.refreshCosmetics()
	local gun = model
	if gun then
		GunModelLoader.applyCosmetics(gun, currentWeapon, myCosmetics())
	end
end

function ViewmodelController.kick()
	recoil = math.min(recoil + KICK_PER_SHOT, KICK_MAX)
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
end

return ViewmodelController
