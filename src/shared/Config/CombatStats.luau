--!strict
-- CombatStats — resolves any carried weapon (roster gun or the legacy knife)
-- into one unified combat-stats shape both client and server compute
-- identically. GunCatalog stores per-pellet damage and RPM; combat wants
-- totals and shots/second; class tables supply handling and falloff feel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)

export type Resolved = {
	id: string,
	name: string,
	class: string,
	kind: "Ranged" | "Melee",
	totalDamage: number,
	pellets: number,
	headshotMult: number,
	fireRate: number, -- shots per second
	auto: boolean,
	spreadDeg: number,
	magSize: number,
	reloadSeconds: number,
	range: number,
	falloffStart: number,
	falloffEndDamage: number,
	equipTime: number,
	sprintToFire: number,
	adsTime: number,
}

type Handling = { equip: number, s2f: number, ads: number, auto: boolean }
local CLASS_HANDLING: { [string]: Handling } = {
	Pistol = { equip = 0.25, s2f = 0.15, ads = 0.18, auto = false },
	Revolver = { equip = 0.3, s2f = 0.2, ads = 0.22, auto = false },
	SMG = { equip = 0.35, s2f = 0.2, ads = 0.24, auto = true },
	Shotgun = { equip = 0.5, s2f = 0.3, ads = 0.3, auto = false },
	Rifle = { equip = 0.45, s2f = 0.25, ads = 0.3, auto = true },
	Carbine = { equip = 0.4, s2f = 0.22, ads = 0.26, auto = true },
	Bullpup = { equip = 0.42, s2f = 0.24, ads = 0.28, auto = true },
	Sniper = { equip = 0.55, s2f = 0.35, ads = 0.4, auto = false },
}

-- Falloff character per class: where damage starts dropping (fraction of
-- range) and what fraction of total damage remains at max range.
local FALLOFF: { [string]: { start: number, endFactor: number } } = {
	Shotgun = { start = 0.2, endFactor = 0.3 },
	Sniper = { start = 0.5, endFactor = 0.85 },
}
local FALLOFF_DEFAULT = { start = 0.35, endFactor = 0.45 }

local CombatStats = {}

function CombatStats.forGun(gunId: string): Resolved?
	local def = GunCatalog.get(gunId)
	if not def then
		return nil
	end
	local stats = def.stats
	local handling = CLASS_HANDLING[def.class] or CLASS_HANDLING.Pistol
	local falloff = FALLOFF[def.class] or FALLOFF_DEFAULT
	local pellets = stats.pellets or 1
	local total = stats.damage * pellets
	return {
		id = gunId,
		name = def.name,
		class = def.class,
		kind = "Ranged",
		totalDamage = total,
		pellets = pellets,
		headshotMult = stats.headshotMult,
		fireRate = stats.rpm / 60,
		-- Machine pistols (Pixie) go auto by RPM even in a semi class.
		auto = handling.auto or stats.rpm >= 500,
		spreadDeg = stats.spreadDeg,
		magSize = stats.magSize,
		-- Shell-by-shell reloads are a polish item; full reload for now.
		reloadSeconds = stats.reloadSeconds,
		range = stats.rangeStuds,
		falloffStart = stats.rangeStuds * falloff.start,
		falloffEndDamage = total * falloff.endFactor,
		equipTime = handling.equip,
		sprintToFire = handling.s2f,
		adsTime = handling.ads,
	}
end

function CombatStats.knife(): Resolved
	local config = WeaponConfig.Knife
	return {
		id = "Knife",
		name = "Knife",
		class = "Melee",
		kind = "Melee",
		totalDamage = config.damage,
		pellets = 1,
		headshotMult = config.headshotMultiplier,
		fireRate = config.fireRate,
		auto = false,
		spreadDeg = 0,
		magSize = 0,
		reloadSeconds = 0,
		range = config.range,
		falloffStart = config.range,
		falloffEndDamage = config.damage,
		equipTime = config.equipTime,
		sprintToFire = config.sprintToFire,
		adsTime = config.adsTime,
	}
end

-- One resolver for anything a slot can hold.
function CombatStats.resolve(id: string): Resolved
	if id == "Knife" then
		return CombatStats.knife()
	end
	return CombatStats.forGun(id) or CombatStats.forGun("Pistol_1") :: Resolved
end

return CombatStats
