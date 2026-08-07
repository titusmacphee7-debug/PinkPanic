--!strict
-- ViewmodelController — the in-hand first-person gun (NOD-16 first pass):
-- camera-attached pistol with sway, walk bob, and recoil kick. Skins/charms
-- render onto this same model in M5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponModels = require(ReplicatedStorage.Shared.Assets.WeaponModels)
local WeaponCosmetics = require(ReplicatedStorage.Shared.Assets.WeaponCosmetics)
local ClientData = require(script.Parent.Parent.ClientData)

local BASE_OFFSET = CFrame.new(1.05, -0.85, -1.55)
local SWAY_LIMIT = 0.06
local KICK_PER_SHOT = 0.09
local KICK_MAX = 0.22

local ViewmodelController = {}

local model: Model? = nil
local currentWeapon = "Pistol"
local recoil = 0
local swayX = 0
local swayY = 0

local function localCharacterAlive(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function applyCosmetics(gun: Model)
	WeaponCosmetics.applySkin(gun, ClientData.equippedSkin())
	WeaponCosmetics.applyCharm(gun, ClientData.equippedCharm())
end

local function ensureModel(): Model
	local current = model
	if current and current.Parent then
		return current
	end
	local built = WeaponModels.build(currentWeapon)
	built.Name = "Viewmodel"
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	applyCosmetics(built)
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
	if not localCharacterAlive() then
		hideModel()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local gun = ensureModel()

	-- Sway lags the camera slightly; bob kicks in while moving.
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

	local cframe = camera.CFrame
		* BASE_OFFSET
		* CFrame.new(swayX, swayY + bob, recoil * 0.4)
		* CFrame.Angles(recoil, swayX * 0.5, 0)
	gun:PivotTo(cframe)
end

-- Called by WeaponController on weapon switch; rebuilds next frame.
function ViewmodelController.setWeapon(weaponId: string)
	if weaponId == currentWeapon then
		return
	end
	currentWeapon = weaponId
	hideModel()
end

-- Called by WeaponController on each shot.
function ViewmodelController.kick()
	recoil = math.min(recoil + KICK_PER_SHOT, KICK_MAX)
end

-- Where tracers start: the viewmodel's muzzle, or a camera-relative fallback.
function ViewmodelController.getMuzzlePosition(): Vector3?
	local gun = model
	local slide = gun and gun.PrimaryPart
	local muzzle = slide and slide:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return nil
end

function ViewmodelController.init()
	RunService:BindToRenderStep("PinkPanicViewmodel", Enum.RenderPriority.Camera.Value + 1, update)

	-- Equip changes re-dress the in-hand gun live.
	ClientData.changed:Connect(function()
		if model then
			applyCosmetics(model)
		end
	end)
end

return ViewmodelController
