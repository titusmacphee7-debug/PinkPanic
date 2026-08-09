--!strict
-- CombatStats — resolves any carried weapon (roster gun or knife) into the
-- unified combat-stats shape both client and server compute identically,
-- with optional attachment modifiers applied (AttachmentConfig). Ballistics
-- helpers (per-pellet damage at distance) live here so the falloff curve has
-- exactly one implementation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local AttachmentConfig = require(ReplicatedStorage.Shared.Config.AttachmentConfig)

export type Resolved = {
	id: string,
	name: string,
	class: string,
	kind: "Ranged" | "Melee",
	damageNear: number, -- per bullet/pellet
	damageFar: number,
	rangeNear: number,
	rangeFar: number,
	travelMax: number, -- bullets die here
	pellets: number,
	headshotMult: number,
	fireRate: number, -- shots per second
	auto: boolean,
	spreadDeg: number, -- hipfire (and shotgun pellet cone)
	adsSpreadDeg: number,
	recoilVert: number,
	recoilHoriz: number,
	recoilRecovery: number,
	magSize: number,
	reloadSeconds: number,
	velocity: number,
	drop: number,
	moveSpeedMult: number,
	equipTime: number,
	sprintToFire: number,
	adsTime: number,
	range: number, -- alias of travelMax for client visuals
}

local CombatStats = {}

local MODIFIABLE = {
	damageNear = true, damageFar = true, rangeNear = true, rangeFar = true,
	headshotMult = true, fireRate = true, spreadDeg = true, adsSpreadDeg = true,
	recoilVert = true, recoilHoriz = true, recoilRecovery = true, magSize = true,
	reloadSeconds = true, velocity = true, drop = true, moveSpeedMult = true,
	equipTime = true, sprintToFire = true, adsTime = true,
}

local function applyAttachments(resolved: Resolved, attachmentIds: { string }?)
	if not attachmentIds then
		return
	end
	local r = resolved :: any
	for _, id in attachmentIds do
		local def = AttachmentConfig.get(id)
		if not def then
			continue
		end
		for _, modifier in def.modifiers do
			local stat = modifier.stat
			-- rpm convenience: modifiers may target rpm; map to fireRate.
			if stat == "rpm" then
				stat = "fireRate"
			end
			if MODIFIABLE[stat] and type(r[stat]) == "number" then
				if modifier.mul then
					r[stat] *= modifier.mul
				end
				if modifier.add then
					r[stat] += modifier.add
				end
			end
		end
	end
	resolved.magSize = math.max(1, math.floor(resolved.magSize + 0.5))
	resolved.travelMax = resolved.rangeFar * 1.6
	resolved.range = resolved.travelMax
end

function CombatStats.forGun(gunId: string, attachmentIds: { string }?): Resolved?
	local def = GunCatalog.get(gunId)
	if not def then
		return nil
	end
	local s = def.stats
	local travelMax = s.rangeFar * 1.6
	local resolved: Resolved = {
		id = gunId,
		name = def.name,
		class = def.class,
		kind = "Ranged",
		damageNear = s.damageNear,
		damageFar = s.damageFar,
		rangeNear = s.rangeNear,
		rangeFar = s.rangeFar,
		travelMax = travelMax,
		pellets = s.pellets or 1,
		headshotMult = s.headshotMult,
		fireRate = s.rpm / 60,
		auto = s.auto,
		spreadDeg = s.spreadDeg,
		adsSpreadDeg = s.adsSpreadDeg,
		recoilVert = s.recoilVert,
		recoilHoriz = s.recoilHoriz,
		recoilRecovery = s.recoilRecovery,
		magSize = s.magSize,
		reloadSeconds = s.reloadSeconds,
		velocity = s.velocity,
		drop = s.drop,
		moveSpeedMult = s.moveSpeedMult,
		equipTime = s.equipTime,
		sprintToFire = s.sprintToFire,
		adsTime = s.adsTime,
		range = travelMax,
	}
	applyAttachments(resolved, attachmentIds)
	return resolved
end

function CombatStats.knife(): Resolved
	local config = WeaponConfig.Knife
	return {
		id = "Knife",
		name = "Knife",
		class = "Melee",
		kind = "Melee",
		damageNear = config.damage,
		damageFar = config.damage,
		rangeNear = config.range,
		rangeFar = config.range,
		travelMax = config.range,
		pellets = 1,
		headshotMult = config.headshotMultiplier,
		fireRate = config.fireRate,
		auto = false,
		spreadDeg = 0,
		adsSpreadDeg = 0,
		recoilVert = 0, -- knives don't kick
		recoilHoriz = 0,
		recoilRecovery = 20,
		magSize = 0,
		reloadSeconds = 0,
		velocity = 0,
		drop = 0,
		moveSpeedMult = 1.06, -- knife feet: classic
		equipTime = config.equipTime,
		sprintToFire = config.sprintToFire,
		adsTime = config.adsTime,
		range = config.range,
	}
end

function CombatStats.resolve(id: string, attachmentIds: { string }?): Resolved
	if id == "Knife" then
		return CombatStats.knife()
	end
	return CombatStats.forGun(id, attachmentIds) or CombatStats.knife()
end

-- Per-bullet (per-pellet) damage after falloff at a traveled distance.
function CombatStats.pelletDamageAt(stats: Resolved, distance: number): number
	if distance <= stats.rangeNear then
		return stats.damageNear
	end
	if distance >= stats.rangeFar then
		return stats.damageFar
	end
	local alpha = (distance - stats.rangeNear) / math.max(stats.rangeFar - stats.rangeNear, 1)
	return stats.damageNear + (stats.damageFar - stats.damageNear) * alpha
end

return CombatStats
