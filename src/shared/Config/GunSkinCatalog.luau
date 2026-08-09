--!strict
-- GunSkinCatalog — per-gun color skins (3 schemes x 32 roster guns = 96) and
-- the 10 universal camo textures (docs/GUNS_HANDOFF.md §5). Skins recolor
-- the imported mesh parts (Body/Panel/Grip/Hardware/Accent); camos set
-- MeshPart.TextureID and OVERRIDE the color skin (pending §8.1 confirmation).
-- Camos with a blank textureId are not yet purchasable (Studio upload pending).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type ColorSkinDef = {
	gunId: string,
	name: string,
	rarity: Rarity,
	price: number,
	colors: { [string]: Color3 }, -- by part name
}

export type CamoDef = {
	name: string,
	rarity: Rarity,
	price: number,
	textureId: string, -- "" until Studio upload (§2 step 4)
}

local GunSkinCatalog = {}

-- The three shared schemes; each gun gets all three as `<GunId>__<key>`.
local SCHEMES = {
	{
		key = "Rosewater",
		name = "Rosewater",
		rarity = "Common" :: Rarity,
		price = 100,
		colors = {
			Body = Color3.fromRGB(255, 245, 250),
			Panel = Color3.fromRGB(255, 214, 235),
			Grip = Color3.fromRGB(255, 160, 205),
			Hardware = Color3.fromRGB(150, 130, 145),
			Accent = Color3.fromRGB(255, 92, 168),
		},
	},
	{
		key = "MidnightCrush",
		name = "Midnight Crush",
		rarity = "Rare" :: Rarity,
		price = 150,
		colors = {
			Body = Color3.fromRGB(70, 55, 80),
			Panel = Color3.fromRGB(92, 72, 88),
			Grip = Color3.fromRGB(255, 92, 168),
			Hardware = Color3.fromRGB(45, 35, 52),
			Accent = Color3.fromRGB(255, 130, 190),
		},
	},
	{
		key = "PrincessGold",
		name = "Princess Gold",
		rarity = "Epic" :: Rarity,
		price = 300,
		colors = {
			Body = Color3.fromRGB(255, 214, 120),
			Panel = Color3.fromRGB(255, 245, 250),
			Grip = Color3.fromRGB(255, 130, 190),
			Hardware = Color3.fromRGB(122, 74, 18),
			Accent = Color3.fromRGB(255, 196, 88),
		},
	},
}

-- Generated: only roster guns (dropped lookalikes pruned by construction).
GunSkinCatalog.perGun = {} :: { [string]: ColorSkinDef }
for gunId in GunCatalog.guns do
	for _, scheme in SCHEMES do
		GunSkinCatalog.perGun[`{gunId}__{scheme.key}`] = {
			gunId = gunId,
			name = scheme.name,
			rarity = scheme.rarity,
			price = scheme.price,
			colors = scheme.colors,
		}
	end
end

GunSkinCatalog.universal = {
	CamoGingham = { name = "Gingham Picnic", rarity = "Rare", price = 250, textureId = "" },
	CamoCandyStripe = { name = "Candy Stripe", rarity = "Rare", price = 250, textureId = "" },
	CamoSweetheart = { name = "Sweetheart", rarity = "Epic", price = 400, textureId = "" },
	CamoSprinkles = { name = "Sprinkles", rarity = "Epic", price = 400, textureId = "" },
	CamoLeopardLuxe = { name = "Leopard Luxe", rarity = "Epic", price = 400, textureId = "" },
	CamoPinkCamo = { name = "Pink Camo", rarity = "Epic", price = 400, textureId = "" },
	CamoHexTech = { name = "Hex Tech", rarity = "Epic", price = 400, textureId = "" },
	CamoCowCutie = { name = "Cow Cutie", rarity = "Epic", price = 400, textureId = "" },
	CamoStarlight = { name = "Starlight", rarity = "Legendary", price = 600, textureId = "" },
	CamoGalaxyBerry = { name = "Galaxy Berry", rarity = "Legendary", price = 600, textureId = "" },
} :: { [string]: CamoDef }

-- Recolors an imported gun model's named parts. Missing parts (some guns
-- lack Panel/Accent) are skipped without erroring. Returns success.
function GunSkinCatalog.applyColorSkin(gun: Model, skinId: string?): boolean
	local def = if skinId then GunSkinCatalog.perGun[skinId] else nil
	if not def then
		return false
	end
	for partName, color in def.colors do
		local part = gun:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
			if part:IsA("MeshPart") then
				part.TextureID = "" -- clearing a camo restores the color skin
			end
		end
	end
	return true
end

-- Applies a universal camo texture to every MeshPart. Camo OVERRIDES the
-- color skin. Blank textureId (not yet uploaded) is a no-op. Returns success.
function GunSkinCatalog.applyUniversalCamo(gun: Model, camoId: string?): boolean
	local def = if camoId then GunSkinCatalog.universal[camoId] else nil
	if not def or def.textureId == "" then
		return false
	end
	local applied = false
	for _, part in gun:GetDescendants() do
		if part:IsA("MeshPart") then
			part.TextureID = def.textureId
			applied = true
		end
	end
	return applied
end

return GunSkinCatalog
