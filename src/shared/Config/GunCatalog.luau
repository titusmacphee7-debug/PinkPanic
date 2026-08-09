--!strict
-- GunCatalog — the 32-gun roster (docs/GUNS_HANDOFF.md §3). One entry per
-- gun; stats are playtest starting points where higher price buys a
-- different FEEL, not a straight upgrade. Balance passes tune numbers here
-- and nowhere else. PRICE_MULTIPLIER rescales the whole economy ladder in
-- one place — never hand-tune 32 prices.

export type GunClass = "Pistol" | "Revolver" | "SMG" | "Shotgun" | "Rifle" | "Carbine" | "Bullpup" | "Sniper"
export type GunSlot = "Primary" | "Secondary"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type GunStats = {
	damage: number, -- per bullet (per PELLET for shotguns)
	rpm: number,
	magSize: number,
	reloadSeconds: number,
	headshotMult: number,
	pellets: number?, -- shotguns only
	shellReload: number?, -- per-shell reload (pump shotguns)
	spreadDeg: number,
	rangeStuds: number,
}

export type GunDef = {
	name: string,
	class: GunClass,
	slot: GunSlot,
	rarity: Rarity,
	price: number, -- 0 = starter/free
	stats: GunStats,
}

local PRICE_MULTIPLIER = 1 -- OPEN QUESTION §3: economy scaling knob

-- Per-class handling baselines; per-gun overrides below where identity says.
local CLASS_SPREAD: { [GunClass]: number } = {
	Pistol = 0.9,
	Revolver = 0.55,
	SMG = 1.9,
	Shotgun = 5.5,
	Rifle = 1.5,
	Carbine = 1.2,
	Bullpup = 1.0,
	Sniper = 0.12,
}
local CLASS_RANGE: { [GunClass]: number } = {
	Pistol = 300,
	Revolver = 340,
	SMG = 230,
	Shotgun = 110,
	Rifle = 350,
	Carbine = 330,
	Bullpup = 340,
	Sniper = 600,
}

local GunCatalog = {}

local function gun(
	name: string,
	class: GunClass,
	slot: GunSlot,
	rarity: Rarity,
	price: number,
	stats: {
		damage: number,
		rpm: number,
		magSize: number,
		reloadSeconds: number,
		headshotMult: number,
		pellets: number?,
		shellReload: number?,
		spreadDeg: number?,
		rangeStuds: number?,
	}
): GunDef
	return {
		name = name,
		class = class,
		slot = slot,
		rarity = rarity,
		price = math.floor(price * PRICE_MULTIPLIER + 0.5),
		stats = {
			damage = stats.damage,
			rpm = stats.rpm,
			magSize = stats.magSize,
			reloadSeconds = stats.reloadSeconds,
			headshotMult = stats.headshotMult,
			pellets = stats.pellets,
			shellReload = stats.shellReload,
			spreadDeg = stats.spreadDeg or CLASS_SPREAD[class],
			rangeStuds = stats.rangeStuds or CLASS_RANGE[class],
		},
	}
end

GunCatalog.guns = {
	-- Secondaries — Pistols
	Pistol_1 = gun("Pip", "Pistol", "Secondary", "Common", 0, -- starter
		{ damage = 25, rpm = 380, magSize = 12, reloadSeconds = 1.6, headshotMult = 1.5 }),
	Pistol_6 = gun("Dolly", "Pistol", "Secondary", "Common", 500,
		{ damage = 24, rpm = 400, magSize = 14, reloadSeconds = 1.6, headshotMult = 1.5 }),
	Pistol_3 = gun("Stiletto", "Pistol", "Secondary", "Rare", 1200,
		{ damage = 30, rpm = 300, magSize = 10, reloadSeconds = 1.7, headshotMult = 1.6, rangeStuds = 340 }),
	Pistol_5 = gun("Pixie", "Pistol", "Secondary", "Epic", 4000,
		{ damage = 18, rpm = 560, magSize = 18, reloadSeconds = 1.8, headshotMult = 1.4, spreadDeg = 1.3 }),
	Pistol_4 = gun("Jawbreaker", "Pistol", "Secondary", "Epic", 4500,
		{ damage = 50, rpm = 150, magSize = 7, reloadSeconds = 2.2, headshotMult = 1.8, spreadDeg = 0.6 }),

	-- Secondaries — Revolvers
	Revolver_4 = gun("Smooch", "Revolver", "Secondary", "Common", 400,
		{ damage = 40, rpm = 190, magSize = 5, reloadSeconds = 2.2, headshotMult = 1.8, rangeStuds = 280 }),
	Revolver_1 = gun("Heartbreaker", "Revolver", "Secondary", "Rare", 1600,
		{ damage = 45, rpm = 180, magSize = 6, reloadSeconds = 2.4, headshotMult = 2.0 }),
	Revolver_3 = gun("Longing", "Revolver", "Secondary", "Epic", 4400,
		{ damage = 48, rpm = 160, magSize = 6, reloadSeconds = 2.5, headshotMult = 2.0, spreadDeg = 0.4, rangeStuds = 380 }),
	Revolver_5 = gun("Drama Queen", "Revolver", "Secondary", "Epic", 4200,
		{ damage = 55, rpm = 130, magSize = 5, reloadSeconds = 2.7, headshotMult = 2.0 }),

	-- Primaries — SMGs
	SubmachineGun_1 = gun("Chatterbox", "SMG", "Primary", "Common", 700,
		{ damage = 15, rpm = 850, magSize = 32, reloadSeconds = 1.9, headshotMult = 1.3 }),
	SubmachineGun_2 = gun("Bubbler", "SMG", "Primary", "Rare", 1500,
		{ damage = 18, rpm = 720, magSize = 30, reloadSeconds = 2.0, headshotMult = 1.35, spreadDeg = 1.6 }),
	SubmachineGun_3 = gun("Zoomie", "SMG", "Primary", "Rare", 2200,
		{ damage = 14, rpm = 950, magSize = 25, reloadSeconds = 1.7, headshotMult = 1.3, spreadDeg = 2.1 }),
	SubmachineGun_4 = gun("Jitterbug", "SMG", "Primary", "Epic", 5200,
		{ damage = 16, rpm = 880, magSize = 40, reloadSeconds = 2.2, headshotMult = 1.3 }),

	-- Primaries — Shotguns (damage is PER PELLET)
	Shotgun_1 = gun("Big Boop", "Shotgun", "Primary", "Common", 900,
		{ damage = 8, pellets = 9, rpm = 70, magSize = 6, reloadSeconds = 3.6, shellReload = 0.6, headshotMult = 1.3 }),
	Shotgun_ShortStock = gun("Scrunchie", "Shotgun", "Primary", "Rare", 1400,
		{ damage = 8, pellets = 8, rpm = 80, magSize = 5, reloadSeconds = 2.75, shellReload = 0.55, headshotMult = 1.3 }),
	Shotgun_SawedOff = gun("Shortcake", "Shotgun", "Primary", "Rare", 1800,
		{ damage = 9, pellets = 10, rpm = 90, magSize = 2, reloadSeconds = 2.3, headshotMult = 1.2, spreadDeg = 7.5, rangeStuds = 80 }),
	Shotgun_4 = gun("Double Trouble", "Shotgun", "Primary", "Epic", 4000,
		{ damage = 9, pellets = 9, rpm = 110, magSize = 2, reloadSeconds = 2.5, headshotMult = 1.3 }),
	Shotgun_3 = gun("Homemaker", "Shotgun", "Primary", "Epic", 6000,
		{ damage = 8, pellets = 10, rpm = 65, magSize = 7, reloadSeconds = 4.2, shellReload = 0.6, headshotMult = 1.35, spreadDeg = 4.2 }),

	-- Primaries — Rifles (AK family)
	AssaultRifle_2 = gun("Gumdrop", "Rifle", "Primary", "Rare", 2000,
		{ damage = 24, rpm = 570, magSize = 30, reloadSeconds = 2.3, headshotMult = 1.4 }),
	AssaultRifle_3 = gun("Cherry Bomb", "Rifle", "Primary", "Epic", 5000,
		{ damage = 26, rpm = 540, magSize = 30, reloadSeconds = 2.4, headshotMult = 1.45, spreadDeg = 1.7 }),
	AssaultRifle_4 = gun("Picnic Punch", "Rifle", "Primary", "Epic", 6000,
		{ damage = 24, rpm = 590, magSize = 30, reloadSeconds = 2.2, headshotMult = 1.4 }),
	AssaultRifle_1 = gun("Grump", "Rifle", "Primary", "Epic", 6800,
		{ damage = 28, rpm = 500, magSize = 25, reloadSeconds = 2.5, headshotMult = 1.5, spreadDeg = 1.2, rangeStuds = 400 }),

	-- Primaries — Carbines (M4 family)
	AssaultRifle2_1 = gun("Sweet Talker", "Carbine", "Primary", "Epic", 5500,
		{ damage = 21, rpm = 680, magSize = 30, reloadSeconds = 2.1, headshotMult = 1.4, spreadDeg = 1.0 }),
	AssaultRifle2_3 = gun("Sprinkler", "Carbine", "Primary", "Rare", 2800,
		{ damage = 19, rpm = 720, magSize = 30, reloadSeconds = 2.1, headshotMult = 1.35, spreadDeg = 1.5 }),
	AssaultRifle2_4 = gun("Chunky", "Carbine", "Primary", "Legendary", 9000,
		{ damage = 23, rpm = 650, magSize = 35, reloadSeconds = 2.3, headshotMult = 1.45 }),

	-- Primaries — Bullpups
	Bullpup_1 = gun("Marshmallow", "Bullpup", "Primary", "Rare", 2500,
		{ damage = 20, rpm = 660, magSize = 36, reloadSeconds = 2.4, headshotMult = 1.4, spreadDeg = 0.8 }),
	Bullpup_2 = gun("Toastie", "Bullpup", "Primary", "Epic", 4800,
		{ damage = 22, rpm = 620, magSize = 36, reloadSeconds = 2.5, headshotMult = 1.45 }),

	-- Primaries — Snipers
	SniperRifle_1 = gun("Whisper", "Sniper", "Primary", "Rare", 3000,
		{ damage = 70, rpm = 55, magSize = 5, reloadSeconds = 2.8, headshotMult = 2.0 }),
	SniperRifle_3 = gun("Scout's Honor", "Sniper", "Primary", "Epic", 5800,
		{ damage = 60, rpm = 75, magSize = 6, reloadSeconds = 2.6, headshotMult = 2.0 }),
	SniperRifle_2 = gun("Long Kiss", "Sniper", "Primary", "Epic", 6500,
		{ damage = 90, rpm = 45, magSize = 5, reloadSeconds = 3.0, headshotMult = 2.0 }),
	-- OPEN QUESTION §8.3: 100 = exactly lethal body shot; nerf to 95 if too strong.
	SniperRifle_4 = gun("Star Crossed", "Sniper", "Primary", "Legendary", 10000,
		{ damage = 100, rpm = 38, magSize = 4, reloadSeconds = 3.2, headshotMult = 2.0 }),
	SniperRifle_5 = gun("Heartstopper", "Sniper", "Primary", "Legendary", 12000,
		{ damage = 85, rpm = 55, magSize = 6, reloadSeconds = 2.9, headshotMult = 2.1 }),
} :: { [string]: GunDef }

function GunCatalog.get(gunId: string): GunDef?
	return GunCatalog.guns[gunId]
end

-- Stable listing for UI: by slot, then price ascending, then name.
function GunCatalog.sorted(): { { id: string, def: GunDef } }
	local list = {}
	for id, def in GunCatalog.guns do
		table.insert(list, { id = id, def = def })
	end
	table.sort(list, function(a, b)
		if a.def.slot ~= b.def.slot then
			return a.def.slot == "Primary"
		end
		if a.def.price ~= b.def.price then
			return a.def.price < b.def.price
		end
		return a.def.name < b.def.name
	end)
	return list
end

return GunCatalog
