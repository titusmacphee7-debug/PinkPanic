--!strict
-- WeaponConfig — every weapon is a config on the shared framework (NOD-11).
-- Adding a weapon = adding an entry here (+ a model in WeaponModels).
-- Notes: `damage` is TOTAL per shot; shotguns split it across pellets.
-- Melee weapons ignore ammo/reload and use a short range.

export type WeaponStats = {
	displayName: string,
	kind: "Ranged" | "Melee",
	damage: number,
	headshotMultiplier: number,
	fireRate: number, -- shots (or swings) per second
	auto: boolean,
	spread: number, -- max deviation in degrees
	magSize: number, -- 0 = no ammo (melee)
	reloadTime: number, -- seconds
	range: number, -- studs
	falloffStart: number, -- distance where damage starts dropping
	falloffEndDamage: number, -- total damage at max range
	pellets: number,
}

local WeaponConfig: { [string]: WeaponStats } = {
	Pistol = {
		displayName = "Pistol",
		kind = "Ranged",
		damage = 34,
		headshotMultiplier = 1.5,
		fireRate = 5,
		auto = false,
		spread = 0.8,
		magSize = 12,
		reloadTime = 1.4,
		range = 300,
		falloffStart = 60,
		falloffEndDamage = 20,
		pellets = 1,
	},
	Rifle = {
		displayName = "Rifle",
		kind = "Ranged",
		damage = 18,
		headshotMultiplier = 1.4,
		fireRate = 9,
		auto = true,
		spread = 1.6,
		magSize = 25,
		reloadTime = 1.9,
		range = 350,
		falloffStart = 80,
		falloffEndDamage = 10,
		pellets = 1,
	},
	Shotgun = {
		displayName = "Shotgun",
		kind = "Ranged",
		damage = 72,
		headshotMultiplier = 1.2,
		fireRate = 1.2,
		auto = false,
		spread = 5,
		magSize = 5,
		reloadTime = 2.2,
		range = 120,
		falloffStart = 15,
		falloffEndDamage = 12,
		pellets = 6,
	},
	Knife = {
		displayName = "Knife",
		kind = "Melee",
		damage = 45,
		headshotMultiplier = 1,
		fireRate = 1.6,
		auto = false,
		spread = 0,
		magSize = 0,
		reloadTime = 0,
		range = 9,
		falloffStart = 9,
		falloffEndDamage = 45,
		pellets = 1,
	},
}

return WeaponConfig
