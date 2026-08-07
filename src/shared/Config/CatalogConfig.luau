--!strict
-- CatalogConfig — the shop catalog (NOD-32): every purchasable cosmetic with
-- price and rarity. Prices are tuned against EconomyConfig earn rates
-- (a decent round nets ~75–200 coins).

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type SkinDef = {
	name: string,
	price: number,
	rarity: Rarity,
	slide: Color3,
	grip: Color3,
	accent: Color3,
}

export type CharmDef = {
	name: string,
	price: number,
	rarity: Rarity,
	color: Color3,
	shape: "Heart" | "Bow" | "Star",
}

local CatalogConfig = {}

CatalogConfig.skins = {
	SkinDefault = {
		name = "Strawberry Milk",
		price = 0,
		rarity = "Common",
		slide = Color3.fromRGB(250, 244, 249),
		grip = Color3.fromRGB(255, 130, 190),
		accent = Color3.fromRGB(255, 130, 190),
	},
	SkinBubblegum = {
		name = "Bubblegum Pop",
		price = 100,
		rarity = "Common",
		slide = Color3.fromRGB(255, 170, 210),
		grip = Color3.fromRGB(255, 105, 180),
		accent = Color3.fromRGB(255, 255, 255),
	},
	SkinLavender = {
		name = "Lavender Dream",
		price = 150,
		rarity = "Rare",
		slide = Color3.fromRGB(220, 200, 255),
		grip = Color3.fromRGB(170, 140, 235),
		accent = Color3.fromRGB(255, 200, 230),
	},
	SkinMint = {
		name = "Mint Crush",
		price = 150,
		rarity = "Rare",
		slide = Color3.fromRGB(200, 245, 225),
		grip = Color3.fromRGB(120, 210, 175),
		accent = Color3.fromRGB(255, 180, 215),
	},
	SkinMidnight = {
		name = "Midnight Cutie",
		price = 300,
		rarity = "Epic",
		slide = Color3.fromRGB(70, 55, 80),
		grip = Color3.fromRGB(255, 92, 168),
		accent = Color3.fromRGB(255, 92, 168),
	},
	SkinGold = {
		name = "Princess Gold",
		price = 500,
		rarity = "Legendary",
		slide = Color3.fromRGB(255, 214, 120),
		grip = Color3.fromRGB(255, 245, 250),
		accent = Color3.fromRGB(255, 196, 88),
	},
} :: { [string]: SkinDef }

CatalogConfig.charms = {
	CharmHeart = {
		name = "Heart Charm",
		price = 75,
		rarity = "Common",
		color = Color3.fromRGB(255, 92, 168),
		shape = "Heart",
	},
	CharmBow = {
		name = "Bow Charm",
		price = 150,
		rarity = "Rare",
		color = Color3.fromRGB(255, 170, 210),
		shape = "Bow",
	},
	CharmStar = {
		name = "Star Charm",
		price = 250,
		rarity = "Epic",
		color = Color3.fromRGB(255, 214, 120),
		shape = "Star",
	},
} :: { [string]: CharmDef }

-- Returns ("skin"|"charm", def) for a valid item id, or nil for junk input.
function CatalogConfig.get(itemId: string): (string?, any)
	local skin = CatalogConfig.skins[itemId]
	if skin then
		return "skin", skin
	end
	local charm = CatalogConfig.charms[itemId]
	if charm then
		return "charm", charm
	end
	return nil, nil
end

return CatalogConfig
