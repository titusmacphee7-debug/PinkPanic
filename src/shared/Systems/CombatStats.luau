--!strict
-- CombatStats — the one modifier pipeline (NOD-130).
--
-- Answers "what are this weapon's stats right now" for a gun plus its
-- attachments plus the player's perks. Client prediction and server truth call
-- THIS, identically, which is what makes drift structurally impossible instead
-- of merely unlikely.
--
-- Moved out of shared/Config because it is behaviour, not data (rule 1: a
-- config file containing an `if` is in the wrong folder).
--
-- Three things this fixes about the version it replaces:
--
--   1. **Unknown stat names were silently skipped.** `if MODIFIABLE[stat] and
--      type(r[stat]) == "number"` meant a typo'd modifier did nothing at all,
--      forever, with no error. Every modifier in the game is now validated at
--      BOOT and reported by name. Runtime stays quiet because the problem was
--      already shouted about once, where someone could act on it.
--
--   2. **Results depended on equip order.** Modifiers were applied one after
--      another, so a +5 and a ×1.2 gave different answers depending on which
--      attachment you equipped first. Now: base, then the SUM of all adds, then
--      the PRODUCT of all muls. Order-independent by construction.
--
--   3. **A fresh 24-field table every call**, including every render frame.
--      Now memoised on a key that sorts its inputs, so equip order does not
--      even cost a cache miss.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local AttachmentConfig = require(ReplicatedStorage.Shared.Config.AttachmentConfig)
local Perks = require(ReplicatedStorage.Shared.Config.Perks)

local SYSTEM = "CombatStats"

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

-- Stats a modifier is allowed to touch. Anything outside this set is a
-- configuration error, not a no-op.
--
-- `rpm` is accepted as an alias because gun stats are authored in rounds per
-- minute while the resolver works in shots per second. The alias is declared
-- here rather than handled with an `if` at the point of use, so the list of
-- legal names is one readable table.
local ALIASES: { [string]: string } = {
	rpm = "fireRate",
}

local MODIFIABLE: { [string]: boolean } = {
	damageNear = true,
	damageFar = true,
	rangeNear = true,
	rangeFar = true,
	headshotMult = true,
	fireRate = true,
	spreadDeg = true,
	adsSpreadDeg = true,
	recoilVert = true,
	recoilHoriz = true,
	recoilRecovery = true,
	magSize = true,
	reloadSeconds = true,
	velocity = true,
	drop = true,
	moveSpeedMult = true,
	equipTime = true,
	sprintToFire = true,
	adsTime = true,
}

-- Floors and ceilings so no stack of attachments can produce something absurd.
-- A negative ADS time is not a very good gun; it is a broken one, and it would
-- propagate into every timing check that trusts the number.
local CLAMPS: { [string]: { min: number, max: number? } } = {
	damageNear = { min = 1 },
	damageFar = { min = 1 },
	rangeNear = { min = 1 },
	rangeFar = { min = 2 },
	headshotMult = { min = 1 },
	fireRate = { min = 0.2, max = 60 },
	spreadDeg = { min = 0 },
	adsSpreadDeg = { min = 0 },
	recoilVert = { min = 0 },
	recoilHoriz = { min = 0 },
	recoilRecovery = { min = 0.1 },
	magSize = { min = 1 },
	reloadSeconds = { min = 0.1 },
	velocity = { min = 10 },
	drop = { min = 0 },
	moveSpeedMult = { min = 0.4, max = 1.6 },
	equipTime = { min = 0.05 },
	sprintToFire = { min = 0 },
	adsTime = { min = 0.02 },
}

local function canonical(stat: string): string
	return ALIASES[stat] or stat
end

-- ---------------------------------------------------------------------------
-- Modifier collection and application
-- ---------------------------------------------------------------------------

type Accum = { add: number, mul: number }

local function collect(
	acc: { [string]: Accum },
	modifiers: { AttachmentConfig.Modifier }
)
	for _, modifier in modifiers do
		local stat = canonical(modifier.stat)
		if not MODIFIABLE[stat] then
			-- Already reported by name at boot. Skipping quietly here is
			-- correct: shouting once per frame helps nobody.
			continue
		end

		local entry = acc[stat]
		if not entry then
			entry = { add = 0, mul = 1 }
			acc[stat] = entry
		end

		if modifier.add then
			entry.add += modifier.add
		end
		if modifier.mul then
			entry.mul *= modifier.mul
		end
	end
end

-- base -> + sum of adds -> x product of muls -> clamp.
--
-- Summing adds and multiplying muls separately is what makes the result
-- independent of equip order. Applying them one modifier at a time does not,
-- and that difference is invisible until two attachments disagree.
local function applyModifiers(resolved: Resolved, attachmentIds: { string }?, perkIds: { string }?)
	if not attachmentIds and not perkIds then
		return
	end

	local acc: { [string]: Accum } = {}

	if attachmentIds then
		for _, id in attachmentIds do
			local def = AttachmentConfig.get(id)
			if def then
				collect(acc, def.modifiers)
			end
		end
	end

	if perkIds then
		for _, id in perkIds do
			local def = Perks.get(id)
			if def then
				collect(acc, def.modifiers)
			end
		end
	end

	local r = resolved :: any
	for stat, entry in acc do
		local value = (r[stat] :: number + entry.add) * entry.mul

		local clamp = CLAMPS[stat]
		if clamp then
			value = math.max(value, clamp.min)
			if clamp.max then
				value = math.min(value, clamp.max)
			end
		end

		r[stat] = value
	end

	resolved.magSize = math.max(1, math.floor(resolved.magSize + 0.5))
	resolved.travelMax = resolved.rangeFar * 1.6
	resolved.range = resolved.travelMax
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

local function baseForGun(gunId: string): Resolved?
	local def = GunCatalog.get(gunId)
	if not def then
		return nil
	end

	local s = def.stats
	local travelMax = s.rangeFar * 1.6
	return {
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

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

local cache: { [string]: Resolved } = {}
local cacheHits, cacheMisses = 0, 0

-- Inputs are sorted into the key, so {Grip, Comp} and {Comp, Grip} are one
-- entry rather than two. That matters because the RESULT is the same for both,
-- and a cache that disagrees with that would be caching a lie.
local function cacheKey(gunId: string, attachmentIds: { string }?, perkIds: { string }?): string
	local function part(ids: { string }?): string
		if not ids or #ids == 0 then
			return ""
		end
		local copy = table.clone(ids)
		table.sort(copy)
		return table.concat(copy, ",")
	end
	return `{gunId}|{part(attachmentIds)}|{part(perkIds)}`
end

function CombatStats.resolve(id: string, attachmentIds: { string }?, perkIds: { string }?): Resolved
	local key = cacheKey(id, attachmentIds, perkIds)
	local hit = cache[key]
	if hit then
		cacheHits += 1
		return hit
	end
	cacheMisses += 1

	local resolved: Resolved
	if id == "Knife" then
		resolved = CombatStats.knife()
	else
		resolved = baseForGun(id) or CombatStats.knife()
		applyModifiers(resolved, attachmentIds, perkIds)
	end

	-- Frozen because it is SHARED. Every caller with the same loadout gets this
	-- exact table, so a caller that mutated it would silently change the stats
	-- of every other caller. Freezing turns that into an immediate error.
	table.freeze(resolved)
	cache[key] = resolved
	return resolved
end

function CombatStats.forGun(gunId: string, attachmentIds: { string }?, perkIds: { string }?): Resolved?
	if not GunCatalog.get(gunId) then
		return nil
	end
	return CombatStats.resolve(gunId, attachmentIds, perkIds)
end

-- Loadout changes do not invalidate anything: a different loadout is a
-- different key. This exists for tests and for hot-reloading balance in Studio.
function CombatStats.clearCache()
	cache = {}
	cacheHits, cacheMisses = 0, 0
end

function CombatStats.cacheStats(): (number, number)
	return cacheHits, cacheMisses
end

-- ---------------------------------------------------------------------------
-- Ballistics
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Boot validation
-- ---------------------------------------------------------------------------

-- Walks every modifier in the game and checks its stat name against
-- MODIFIABLE. This is the whole point: a typo'd modifier is found once, at
-- boot, named on both sides, instead of never.
function CombatStats.validate()
	local problems: { string } = {}
	local modifierCount = 0

	local function check(sourceLabel: string, id: string, modifiers: { AttachmentConfig.Modifier })
		for _, modifier in modifiers do
			modifierCount += 1
			local stat = canonical(modifier.stat)
			if not MODIFIABLE[stat] then
				table.insert(problems, `{sourceLabel} "{id}" modifies unknown stat "{modifier.stat}"`)
			elseif modifier.add == nil and modifier.mul == nil then
				table.insert(problems, `{sourceLabel} "{id}" modifier on "{modifier.stat}" has neither add nor mul`)
			end
		end
	end

	for id, def in AttachmentConfig.attachments do
		check("attachment", id, def.modifiers)
	end
	for id, def in Perks.perks do
		check("perk", id, def.modifiers)
	end

	local gunCount = 0
	for _ in GunCatalog.guns do
		gunCount += 1
	end

	if #problems > 0 then
		Diagnostics.dead(SYSTEM, table.concat(problems, "; "))
		return
	end

	Diagnostics.ok(SYSTEM, `{gunCount} guns, {modifierCount} modifiers, all stat names valid`)
end

return CombatStats
