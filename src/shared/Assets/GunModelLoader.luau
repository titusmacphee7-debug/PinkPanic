--!strict
-- GunModelLoader — turns imported gun meshes into ready combat models.
-- Finds templates in ReplicatedStorage.GunModels OR
-- ReplicatedStorage.Shared.Assets.GunModels (either location works — the
-- second is what the handoff said, but it's inside the Rojo-managed tree;
-- if Rojo ever eats it, drag the folder to ReplicatedStorage root).
--
-- Templates are normalized ONCE, in place, lazily (idempotent): PrimaryPart
-- chosen (part named "Body", else largest), a "Muzzle" attachment placed at
-- the bounding box's -Z tip, parts welded and given combat-safe properties.
-- Server normalizes first at boot; clients see the normalized replica.
--
-- build() clones a template and applies the player's cosmetics: color skin
-- first, then camo on top (camo overrides skin; blank textureId = no camo).
-- Missing templates fall back to the part-built WeaponModels so a missing
-- import can never break a spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local WeaponModels = require(ReplicatedStorage.Shared.Assets.WeaponModels)

local GunModelLoader = {}

local function templatesFolder(): Instance?
	local direct = ReplicatedStorage:FindFirstChild("GunModels")
	if direct then
		return direct
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local assets = shared and shared:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("GunModels")
end

local function normalize(model: Model)
	-- Idempotence marker: a Muzzle on the PrimaryPart means we're done.
	local primary = model.PrimaryPart
	if primary and primary:FindFirstChild("Muzzle") then
		return
	end

	local body = model:FindFirstChild("Body")
	local largest: BasePart? = if body and body:IsA("BasePart") then body else nil
	if not largest then
		local largestVolume = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local size = part.Size
				local volume = size.X * size.Y * size.Z
				if volume > largestVolume then
					largestVolume = volume
					largest = part
				end
			end
		end
	end
	if not largest then
		return
	end
	model.PrimaryPart = largest

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			if part ~= largest then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = largest
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	-- Every consumer (world gun, viewmodel, muzzle flash, shell ejection,
	-- viewport previews) assumes the barrel points along -Z. The imported
	-- models don't agree: measured across the roster, 19 of 25 point +Z. That
	-- is why guns were held backwards and why the "Muzzle" attachment landed
	-- on the stock.
	--
	-- Rather than special-case each model, normalise the geometry: the grip
	-- always sits BEHIND the barrel, so if it measures forward of centre the
	-- model is reversed and gets spun 180° about its own bounding-box centre.
	-- Runtime-only — templates live in ReplicatedStorage and this never
	-- touches the saved place file.
	local grip = model:FindFirstChild("Grip", true) or model:FindFirstChild("Mag", true)
	if grip and grip:IsA("BasePart") then
		local bounds = model:GetBoundingBox()
		local gripZ = bounds:PointToObjectSpace(grip.Position).Z
		if gripZ < -0.05 then
			local spin = CFrame.new(bounds.Position)
				* CFrame.Angles(0, math.pi, 0)
				* CFrame.new(-bounds.Position)
			model:PivotTo(spin * model:GetPivot())
		end
	end

	local boundsCF, boundsSize = model:GetBoundingBox()
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.WorldCFrame = boundsCF * CFrame.new(0, 0, -boundsSize.Z / 2)
	muzzle.Parent = largest
end

-- Normalizes every imported template (call once from the server at boot;
-- safe to call again anywhere).
function GunModelLoader.normalizeAll()
	local folder = templatesFolder()
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			normalize(child)
		end
	end
end

local function fallbackModel(gunId: string): Model
	if gunId == "Knife" then
		return WeaponModels.build("Knife")
	end
	local def = GunCatalog.get(gunId)
	local legacy = if def and def.slot == "Secondary"
		then "Pistol"
		elseif def and def.class == "Shotgun" then "Shotgun"
		else "Rifle"
	return WeaponModels.build(legacy)
end

export type Cosmetics = { skinId: string?, camoId: string? }

function GunModelLoader.applyCosmetics(gun: Model, gunId: string, cosmetics: Cosmetics?)
	if not cosmetics then
		return
	end
	local skins = GunSkinCatalog.perGun[gunId]
	local skinDef = if skins and cosmetics.skinId then skins[cosmetics.skinId] else nil
	if skinDef then
		GunSkinCatalog.applyColorSkin(gun, skinDef)
	end
	local camoDef = if cosmetics.camoId then GunSkinCatalog.universal[cosmetics.camoId] else nil
	if camoDef and camoDef.textureId ~= "" then
		GunSkinCatalog.applyUniversalCamo(gun, camoDef)
	end
end

-- Clones a combat-ready model for the gun (world or viewmodel use).
function GunModelLoader.build(gunId: string, cosmetics: Cosmetics?): Model
	local folder = templatesFolder()
	local template = folder and folder:FindFirstChild(gunId)
	local model: Model
	if template and template:IsA("Model") then
		normalize(template)
		model = template:Clone()
	else
		model = fallbackModel(gunId)
	end
	model.Name = gunId
	GunModelLoader.applyCosmetics(model, gunId, cosmetics)
	return model
end

return GunModelLoader
