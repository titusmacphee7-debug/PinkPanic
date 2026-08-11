--!strict
-- PlayerDataSchema — the single source of truth for what a player profile looks like (NOD-7).
-- Every system that touches persistent player state reads/writes this shape and nothing else.
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
}

export type LifetimeStats = {
	kills: number,
	deaths: number,
	roundsPlayed: number,
	roundsWon: number,
}

export type GunCosmetics = {
	skinId: string?,
	camoId: string?,
}

export type PlayerData = {
	version: number,
	coins: number,
	xp: number,
	level: number,
	ownedWeapons: { string },
	ownedSkins: { string },
	ownedCharms: { string },
	equipped: EquippedLoadout,
	-- Gun roster era (schema v2, docs/GUNS_HANDOFF.md §4.2):
	ownedGuns: { string },
	ownedGunSkins: { string },
	ownedCamos: { string },
	loadout: { primary: string?, secondary: string },
	gunCosmetics: { [string]: GunCosmetics },
	settings: PlayerSettings,
	stats: LifetimeStats,
	firstJoinedAt: number,
	onboarded: boolean,
}

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 2

function PlayerDataSchema.default(): PlayerData
	return {
		version = PlayerDataSchema.VERSION,
		coins = 0,
		xp = 0,
		level = 1,
		ownedWeapons = { "Pistol" },
		ownedSkins = {},
		ownedCharms = {},
		ownedGuns = { "Pistol_1" },
		ownedGunSkins = {},
		ownedCamos = {},
		loadout = { primary = nil, secondary = "Pistol_1" },
		gunCosmetics = {},
		equipped = {
			weapon = "Pistol",
			skins = {},
			charms = {},
		},
		settings = {
			sensitivity = 1,
			volume = 1,
		},
		stats = {
			kills = 0,
			deaths = 0,
			roundsPlayed = 0,
			roundsWon = 0,
		},
		firstJoinedAt = os.time(),
		onboarded = false,
	}
end

-- Migrations[n] upgrades a profile from version n to n + 1.
local Migrations: { [number]: (any) -> () } = {}

-- v1 -> v2: the gun roster era (docs/GUNS_HANDOFF.md §4.2). Everyone gets
-- the free starter and empty collections; the legacy four-weapon fields
-- remain untouched until Phase C retires them.
--
-- BACKFILL ONLY — never assign unconditionally here. A genuine v1 profile has
-- none of these fields, so `or` is free; but a v2 profile that arrives with a
-- missing or non-numeric `version` is treated as v1 (see migrate below), and
-- a bare assignment would silently destroy every gun, skin, camo and loadout
-- the player owns while leaving coins and XP intact. It would then autosave
-- 60s later and the loss would be permanent.
Migrations[1] = function(data)
	if type(data.ownedGuns) ~= "table" then
		data.ownedGuns = { "Pistol_1" }
	end
	if type(data.ownedGunSkins) ~= "table" then
		data.ownedGunSkins = {}
	end
	if type(data.ownedCamos) ~= "table" then
		data.ownedCamos = {}
	end
	if type(data.loadout) ~= "table" then
		data.loadout = { primary = nil, secondary = "Pistol_1" }
	end
	if type(data.gunCosmetics) ~= "table" then
		data.gunCosmetics = {}
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

	-- reconcile() only fills keys that are nil, so a field present with the
	-- WRONG type survives untouched. The server indexes these without guards
	-- (WeaponService.resolveLoadout, every table.find in GunShopService), so a
	-- corrupt scalar here throws on the player's first spawn, every spawn.
	-- Coerce the shapes the rest of the codebase is entitled to assume.
	for _, key in { "ownedGuns", "ownedGunSkins", "ownedCamos", "ownedSkins", "ownedCharms" } do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end
	if type(data.loadout) ~= "table" then
		data.loadout = { primary = nil, secondary = "Pistol_1" }
	end
	if type(data.gunCosmetics) ~= "table" then
		data.gunCosmetics = {}
	end

	reconcile(data, PlayerDataSchema.default())
	return data :: PlayerData
end

return PlayerDataSchema
