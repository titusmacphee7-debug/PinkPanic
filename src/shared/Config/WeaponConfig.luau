--!strict
-- WeaponConfig — every weapon is a config on the shared framework (NOD-11).
-- Adding a weapon = adding an entry here (+ assets later). No new systems.

export type WeaponStats = {
	displayName: string,
	kind: "Ranged" | "Melee",
	damage: number,
	headshotMultiplier: number,
	fireRate: number, -- shots per second
	auto: boolean,
	spread: number, -- max deviation in degrees
	magSize: number,
	reloadTime: number, -- seconds
	range: number, -- studs
	falloffStart: number, -- distance where damage starts dropping
	falloffEndDamage: number, -- damage at max range
	pellets: number, -- >1 for shotguns (M3)
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
}

return WeaponConfig
