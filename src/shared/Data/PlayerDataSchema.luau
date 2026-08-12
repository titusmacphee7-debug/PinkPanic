--!strict
-- PlayerDataSchema — the single source of truth for what a player profile looks
-- like (NOD-132). Every system that touches persistent player state reads and
-- writes this shape and nothing else.
--
-- v3 is deliberately sized for the WHOLE feature list rather than for what
-- exists today. Empty tables cost nothing; a migration per milestone costs a
-- migration per milestone, and every one of them is a chance to destroy
-- somebody's collection. Classes, weapon levels, challenges, crates, pity
-- counters and all eight cosmetic categories have their home here now, even
-- though most of them will sit empty until M5–M8.
--
-- Bump VERSION and add a Migrations[n] entry whenever the shape changes.

export type EquippedLoadout = {
	weapon: string,
	-- Maps weaponId -> skinId / charmId, e.g. { Pistol = "SkinStrawberry" }
	skins: { [string]: string },
	charms: { [string]: string },
}

export type PlayerSettings = {
	sensitivity: number,
	volume: number,
	-- v3, added without a migration: `reconcile` fills keys that are nil, so a
	-- new field with a default costs nothing and a bump would be a chance to
	-- damage somebody's collection for no reason.
	fov: number,
}

export type LifetimeStats = {
	kills: number,
	deaths: number,
	roundsPlayed: number,
	roundsWon: number,
	-- v3
	headshots: number,
	assists: number,
	timePlayed: number,
}

export type GunCosmetics = {
	skinId: string?,
	camoId: string?,
}

-- ---------------------------------------------------------------------------
-- v3 shapes
-- ---------------------------------------------------------------------------

export type WeaponSlot = {
	gunId: string?,
	attachments: { string },
}

-- Create-A-Class (M5). Named by the player, five slots to start.
export type ClassLoadout = {
	name: string,
	primary: WeaponSlot,
	secondary: WeaponSlot,
	perks: { string }, -- up to 3, slot order
	lethal: string?,
	tactical: string?,
	fieldUpgrade: string?,
	scorestreaks: { string }, -- up to 3
}

-- Per-gun progression (M6). Weapon level is what drives attachment chase.
export type WeaponProgress = {
	xp: number,
	level: number,
	kills: number,
	unlockedAttachments: { string },
}

-- Ownership, one list per cosmetic category. All eight launch categories plus
-- the three deferred ones, so adding knife skins later is not a migration.
export type Owned = {
	guns: { string },
	gunSkins: { string },
	attachments: { string },

	camos: { string },
	outfits: { string },
	charms: { string },
	killEffects: { string },
	tracers: { string },
	emotes: { string },
	titles: { string },
	nameTags: { string },

	-- Deferred categories (§4.5). Present so they cost no migration.
	knifeSkins: { string },
	stickers: { string },
	deathEffects: { string },
}

export type EquippedCosmetics = {
	outfit: string?,
	title: string?,
	nameTag: string?,
	killEffect: string?,
	deathEffect: string?,
	tracer: string?,
	emoteWheel: { string }, -- 8 slots
	perGun: { [string]: GunCosmetics },
}

-- Crate history and pity (NOD-147, NOD-165). Pity counters are per crate line
-- per tier: how many rolls since that tier last landed.
export type CrateState = {
	owned: { [string]: number }, -- crateId -> count
	opened: { [string]: number }, -- crateId -> lifetime opens
	pity: { [string]: { [string]: number } }, -- crateId -> tier -> rolls since
}

export type PlayerData = {
	version: number,
	coins: number,
	gems: number,
	xp: number,
	level: number,

	-- Legacy four-weapon era. Kept because live profiles still carry it; no new
	-- system should read these.
	ownedWeapons: { string },
	ownedSkins: { string },
	ownedCharms: { string },
	equipped: EquippedLoadout,

	-- Gun roster era (v2).
	ownedGuns: { string },
	ownedGunSkins: { string },
	ownedCamos: { string },
	loadout: { primary: string?, secondary: string },
	gunCosmetics: { [string]: GunCosmetics },

	-- v3.
	classes: { ClassLoadout },
	activeClass: number,
	weaponProgress: { [string]: WeaponProgress },
	owned: Owned,
	equippedCosmetics: EquippedCosmetics,
	challenges: { [string]: number },
	crates: CrateState,
	-- Limited-tier provenance: when a Limited item was granted, so an event
	-- re-run can tell "earned it the first time" from "earned it again".
	limitedGrants: { [string]: number },

	settings: PlayerSettings,
	stats: LifetimeStats,
	firstJoinedAt: number,
	onboarded: boolean,
}

local CameraConfig = require(script.Parent.Parent.Config.CameraConfig)

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 3

local STARTER_GUN = "Pistol_1"

local function emptyClass(name: string): ClassLoadout
	return {
		name = name,
		primary = { gunId = nil, attachments = {} },
		secondary = { gunId = STARTER_GUN, attachments = {} },
		perks = {},
		lethal = nil,
		tactical = nil,
		fieldUpgrade = nil,
		scorestreaks = {},
	}
end

function PlayerDataSchema.default(): PlayerData
	return {
		version = PlayerDataSchema.VERSION,
		coins = 0,
		gems = 0,
		xp = 0,
		level = 1,

		ownedWeapons = { "Pistol" },
		ownedSkins = {},
		ownedCharms = {},
		equipped = {
			weapon = "Pistol",
			skins = {},
			charms = {},
		},

		ownedGuns = { STARTER_GUN },
		ownedGunSkins = {},
		ownedCamos = {},
		loadout = { primary = nil, secondary = STARTER_GUN },
		gunCosmetics = {},

		classes = { emptyClass("Class 1") },
		activeClass = 1,
		weaponProgress = {},
		owned = {
			guns = { STARTER_GUN },
			gunSkins = {},
			attachments = {},
			camos = {},
			outfits = {},
			charms = {},
			killEffects = {},
			tracers = {},
			emotes = {},
			titles = {},
			nameTags = {},
			knifeSkins = {},
			stickers = {},
			deathEffects = {},
		},
		equippedCosmetics = {
			outfit = nil,
			title = nil,
			nameTag = nil,
			killEffect = nil,
			deathEffect = nil,
			tracer = nil,
			emoteWheel = {},
			perGun = {},
		},
		challenges = {},
		crates = {
			owned = {},
			opened = {},
			pity = {},
		},
		limitedGrants = {},

		settings = {
			sensitivity = 1,
			volume = 1,
			-- From CameraConfig, not a literal. Two files each naming the default
			-- FOV is two answers to one question, and the one that drifts is
			-- always the one nobody is looking at.
			fov = CameraConfig.baseFov,
		},
		stats = {
			kills = 0,
			deaths = 0,
			roundsPlayed = 0,
			roundsWon = 0,
			headshots = 0,
			assists = 0,
			timePlayed = 0,
		},
		firstJoinedAt = os.time(),
		onboarded = false,
	}
end

-- Migrations[n] upgrades a profile from version n to n + 1.
local Migrations: { [number]: (any) -> () } = {}

-- v1 -> v2: the gun roster era.
--
-- BACKFILL ONLY — never assign unconditionally here. A genuine v1 profile has
-- none of these fields, so `or` is free; but a v2 profile that arrives with a
-- missing or non-numeric `version` is treated as v1 (see migrate below), and
-- a bare assignment would silently destroy every gun, skin, camo and loadout
-- the player owns while leaving coins and XP intact. It would then autosave
-- 60s later and the loss would be permanent.
Migrations[1] = function(data)
	if type(data.ownedGuns) ~= "table" then
		data.ownedGuns = { STARTER_GUN }
	end
	if type(data.ownedGunSkins) ~= "table" then
		data.ownedGunSkins = {}
	end
	if type(data.ownedCamos) ~= "table" then
		data.ownedCamos = {}
	end
	if type(data.loadout) ~= "table" then
		data.loadout = { primary = nil, secondary = STARTER_GUN }
	end
	if type(data.gunCosmetics) ~= "table" then
		data.gunCosmetics = {}
	end
end

-- v2 -> v3: classes, weapon progression, the eight cosmetic categories,
-- challenges, crates and pity.
--
-- Same rule as above, and it matters more here because v2 profiles are LIVE:
-- backfill only, never overwrite. The one piece of real translation is folding
-- the v2 flat ownership lists into `owned`, and even that copies rather than
-- moves — the v2 fields stay put so a rollback cannot orphan a collection.
Migrations[2] = function(data)
	if type(data.gems) ~= "number" then
		data.gems = 0
	end

	if type(data.owned) ~= "table" then
		data.owned = {}
	end
	local owned = data.owned

	-- Copy, do not move. If v3 turns out to be wrong we can roll back to a
	-- build that reads the v2 fields and nobody loses anything.
	local function seed(key: string, from: any)
		if type(owned[key]) ~= "table" then
			owned[key] = if type(from) == "table" then table.clone(from) else {}
		end
	end
	seed("guns", data.ownedGuns)
	seed("gunSkins", data.ownedGunSkins)
	seed("camos", data.ownedCamos)
	seed("charms", data.ownedCharms)
	for _, key in { "attachments", "outfits", "killEffects", "tracers", "emotes", "titles", "nameTags", "knifeSkins", "stickers", "deathEffects" } do
		seed(key, nil)
	end

	if type(data.classes) ~= "table" or #data.classes == 0 then
		-- Carry the v2 loadout into Class 1 so a returning player spawns with
		-- what they had, not with a default.
		local class = emptyClass("Class 1")
		if type(data.loadout) == "table" then
			class.primary.gunId = data.loadout.primary
			class.secondary.gunId = data.loadout.secondary or STARTER_GUN
		end
		data.classes = { class }
	end
	if type(data.activeClass) ~= "number" then
		data.activeClass = 1
	end

	-- Deliberately created EMPTY. Seeding it with `{ emoteWheel = {}, perGun = {} }`
	-- here makes the checks below see tables that already exist, so the
	-- carry-across from v2 never runs and every player silently loses the camo
	-- and skin they had equipped on each gun.
	if type(data.equippedCosmetics) ~= "table" then
		data.equippedCosmetics = {}
	end
	if type(data.equippedCosmetics.perGun) ~= "table" then
		-- v2 stored per-gun cosmetics separately; carry them across.
		data.equippedCosmetics.perGun = if type(data.gunCosmetics) == "table"
			then table.clone(data.gunCosmetics)
			else {}
	end
	if type(data.equippedCosmetics.emoteWheel) ~= "table" then
		data.equippedCosmetics.emoteWheel = {}
	end

	for _, key in { "weaponProgress", "challenges", "limitedGrants" } do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end

	if type(data.crates) ~= "table" then
		data.crates = { owned = {}, opened = {}, pity = {} }
	end
	for _, key in { "owned", "opened", "pity" } do
		if type(data.crates[key]) ~= "table" then
			data.crates[key] = {}
		end
	end

	if type(data.stats) == "table" then
		for _, key in { "headshots", "assists", "timePlayed" } do
			if type(data.stats[key]) ~= "number" then
				data.stats[key] = 0
			end
		end
	end
end

-- Fills in any missing keys from the default profile (new fields added in the
-- same version, partial saves) without touching data the player already has.
local function reconcile(data: any, template: any)
	for key, templateValue in template do
		if data[key] == nil then
			if type(templateValue) == "table" then
				local copy = {}
				reconcile(copy, templateValue)
				data[key] = copy
			else
				data[key] = templateValue
			end
		elseif type(templateValue) == "table" and type(data[key]) == "table" and #templateValue == 0 then
			-- Only reconcile into dictionaries; arrays (owned lists) are player data as-is.
			reconcile(data[key], templateValue)
		end
	end
end

-- Tables the rest of the codebase indexes without guards. reconcile() only
-- fills keys that are nil, so a field present with the WRONG type survives it
-- untouched — and a corrupt scalar here throws on the player's first spawn,
-- every spawn.
local MUST_BE_TABLE = {
	"ownedGuns",
	"ownedGunSkins",
	"ownedCamos",
	"ownedSkins",
	"ownedCharms",
	"gunCosmetics",
	"classes",
	"owned",
	"equippedCosmetics",
	"weaponProgress",
	"challenges",
	"crates",
	"limitedGrants",
}

-- Takes whatever came out of the DataStore and returns a valid, current-version profile.
function PlayerDataSchema.migrate(data: any): PlayerData
	if type(data) ~= "table" then
		return PlayerDataSchema.default()
	end

	local version = if type(data.version) == "number" then data.version else 1
	while version < PlayerDataSchema.VERSION do
		local step = Migrations[version]
		if not step then
			break
		end
		step(data)
		version += 1
	end
	data.version = PlayerDataSchema.VERSION

	for _, key in MUST_BE_TABLE do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end
	if type(data.loadout) ~= "table" then
		data.loadout = { primary = nil, secondary = STARTER_GUN }
	end
	if type(data.activeClass) ~= "number" then
		data.activeClass = 1
	end

	reconcile(data, PlayerDataSchema.default())
	return data :: PlayerData
end

return PlayerDataSchema
