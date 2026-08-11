--!strict
-- WeaponCosmetics — applies skins (recolors) and charms (hanging trinkets)
-- to a built PistolModel (NOD-38/NOD-39 first pass). Used by the server for
-- world guns and by the client for the viewmodel, so everyone sees the same
-- thing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogConfig = require(ReplicatedStorage.Shared.Config.CatalogConfig)

local DARK = Color3.fromRGB(92, 72, 88)

local WeaponCosmetics = {}

-- Recolors the gun's parts to the skin, falling back to the default skin for
-- nil/unknown ids so a bad save can never produce an invisible gun.
function WeaponCosmetics.applySkin(gun: Model, skinId: string?)
	local def = (if skinId then CatalogConfig.skins[skinId] else nil) or CatalogConfig.skins.SkinDefault
	local mapping: { [string]: Color3 } = {
		Slide = def.slide,
		Grip = def.grip,
		Barrel = DARK,
		Guard = DARK,
		Charm = def.accent,
	}
	for partName, color in mapping do
		local part = gun:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

-- Hangs a charm below the grip (or removes it for nil). Shapes are simple
-- part primitives until real meshes land in M5.
function WeaponCosmetics.applyCharm(gun: Model, charmId: string?)
	local existing = gun:FindFirstChild("HangingCharm")
	if existing then
		existing:Destroy()
	end
	local def = if charmId then CatalogConfig.charms[charmId] else nil
	if not def then
		return
	end
	local grip = gun:FindFirstChild("Grip")
	if not grip or not grip:IsA("BasePart") then
		return
	end

	local charm = Instance.new("Part")
	charm.Name = "HangingCharm"
	charm.Color = def.color
	charm.Material = Enum.Material.SmoothPlastic
	charm.CanCollide = false
	charm.CanQuery = false
	charm.CanTouch = false
	charm.CastShadow = false
	charm.Massless = true
	charm.Anchored = grip.Anchored -- match the gun (anchored viewmodel vs welded world gun)

	if def.shape == "Heart" then
		charm.Shape = Enum.PartType.Ball
		charm.Size = Vector3.new(0.26, 0.26, 0.26)
	elseif def.shape == "Star" then
		charm.Shape = Enum.PartType.Cylinder
		charm.Size = Vector3.new(0.1, 0.3, 0.3)
		charm.Material = Enum.Material.Neon
	else -- Bow
		charm.Size = Vector3.new(0.34, 0.16, 0.12)
	end

	charm.CFrame = grip.CFrame * CFrame.new(0, -0.62, 0.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = charm
	weld.Parent = charm
	charm.Parent = gun
end

return WeaponCosmetics
