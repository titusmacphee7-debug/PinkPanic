--!strict
-- GunModelLoader — turns imported gun meshes into ready combat models.
-- Finds templates in ReplicatedStorage.GunModels OR
-- ReplicatedStorage.Shared.Loaders.GunModels (either location works — the
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
local GunSockets = require(ReplicatedStorage.Shared.Loaders.GunSockets)
local WeaponModels = require(ReplicatedStorage.Shared.Loaders.WeaponModels)

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

-- Bumped whenever normalize's output changes. The old idempotence check was
-- "does a Muzzle exist" — but Muzzle attachments get baked into the place file
-- if the game is ever saved while running, so that check made normalize a
-- permanent no-op on stale models. Pistol_1 was found carrying a Muzzle at
-- Z +36 on a model 3.2 studs deep, and no later fix could ever run.
--
-- The flip below is decided from live geometry, so re-running is safe: an
-- already-correct model measures correct and is left alone.
--
-- v3 (NOD-137): authored sockets win. Generated muzzles are flagged
-- PPGenerated so a pass can replace its own guess without ever destroying a
-- tagged one, and PPSocketed records which branch a model took.
local NORMALIZE_VERSION = 3

local function normalize(model: Model)
	if model:GetAttribute("PPNormalized") == NORMALIZE_VERSION then
		return
	end

	-- Clear anything a previous pass left behind before rebuilding it.
	--
	-- ONLY our own output. An authored Muzzle — the tagged socket NOD-137 is
	-- about — carries no PPGenerated flag and is left exactly where whoever
	-- built the model put it. Destroying content to replace it with a guess is
	-- the wrong direction for this to run in.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "Muzzle" and descendant:GetAttribute("PPGenerated") then
			descendant:Destroy()
		end
	end

	local primary = model.PrimaryPart

	-- Pick the physically biggest part, NOT the one named "Body".
	--
	-- "Body" is a SKIN REGION (Body / Panel / Grip / Hardware / Accent are
	-- paint zones, per CLAUDE.md), not the gun's structure — on Pistol_1 it is
	-- 0.1 x 0.4 x 0.3 studs while the Slide is 3.2 long, and on AssaultRifle_2
	-- it is a sliver next to a 6.4-stud Hardware. Pivoting the whole weapon
	-- around that fragment is why guns sat wrong in the hand: the pivot's
	-- orientation had nothing to do with the barrel.
	local largest: BasePart? = nil
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
	-- Which way does this model actually point?
	--
	-- Do NOT try to fix this by rotating the model: PivotTo moves the geometry
	-- AND the pivot together, so the grip's position in the model's own object
	-- space is unchanged and every consumer orients by that same pivot. It
	-- rotates the world and the ruler at once and changes nothing.
	--
	-- Instead record it. The grip always sits behind the barrel, so a grip
	-- measuring forward of centre means the barrel runs +Z rather than the -Z
	-- everything assumes, and callers add a 180° yaw.
	-- TAGGED SOCKETS WIN (NOD-137).
	--
	-- With an authored Muzzle and an authored Grip there is nothing left to
	-- guess: the barrel runs from the hand to the muzzle, and which way that
	-- points in the model's own space is a subtraction, not an inference. This
	-- branch is the one the whole roster should be on once the models carry
	-- their six attachments; everything below it is the old guess, kept only so
	-- an untagged model still produces a gun rather than an error.
	local socketMuzzle = GunSockets.get(model, "Muzzle")
	local socketGrip = GunSockets.get(model, "Grip")
	if socketMuzzle and socketGrip then
		local axis = model:GetPivot():VectorToObjectSpace(socketMuzzle.WorldPosition - socketGrip.WorldPosition)
		model:SetAttribute("PPFlipped", axis.Z > 0)
		model:SetAttribute("PPSocketed", true)
		model:SetAttribute("PPNormalized", NORMALIZE_VERSION)
		return
	end
	model:SetAttribute("PPSocketed", false)

	local flipped = false
	local grip = model:FindFirstChild("Grip", true) or model:FindFirstChild("Mag", true)
	if grip and grip:IsA("BasePart") then
		flipped = model:GetBoundingBox():PointToObjectSpace(grip.Position).Z < -0.05
	end
	model:SetAttribute("PPFlipped", flipped)

	-- Only when nobody authored one. See the note above.
	if not socketMuzzle then
		local boundsCF, boundsSize = model:GetBoundingBox()
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		-- Flagged so the next normalize pass knows this one is a guess and may
		-- replace it, and an authored one is never touched.
		muzzle:SetAttribute("PPGenerated", true)
		-- Parent FIRST. Attachment.WorldCFrame is relative to its parent, so
		-- assigning it while unparented stores a local CFrame that then gets
		-- multiplied by the part's own CFrame — which is how Pistol_1 ended up
		-- with its muzzle 36 studs away on a model 3.2 studs deep.
		muzzle.Parent = largest
		local halfDepth = if flipped then boundsSize.Z / 2 else -boundsSize.Z / 2
		muzzle.WorldCFrame = boundsCF * CFrame.new(0, 0, halfDepth)
	end

	model:SetAttribute("PPNormalized", NORMALIZE_VERSION)
end

-- The extra yaw a caller must apply to point this model's barrel forward.
function GunModelLoader.forwardOffset(model: Model): CFrame
	return if model:GetAttribute("PPFlipped") then CFrame.Angles(0, math.pi, 0) else CFrame.identity
end

-- Where a socket actually is in the world, for a built gun.
--
-- Callers should ask for this rather than deriving a point from the model's
-- geometry, because geometry is the thing that was wrong. Returns nil when the
-- model has no such socket, so a caller can choose its own fallback and know
-- that it is falling back.
function GunModelLoader.socketCFrame(gun: Model, name: string): CFrame?
	local attachment = GunSockets.get(gun, name)
	return if attachment then attachment.WorldCFrame else nil
end

-- True when this model's direction came from tagged attachments rather than
-- from measuring its bounding box and hoping.
function GunModelLoader.isSocketed(model: Model): boolean
	return model:GetAttribute("PPSocketed") == true
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
