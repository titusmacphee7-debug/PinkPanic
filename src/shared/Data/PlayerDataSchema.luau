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

export type PlayerData = {
	version: number,
	coins: number,
	xp: number,
	level: number,
	ownedWeapons: { string },
	ownedSkins: { string },
	ownedCharms: { string },
	equipped: EquippedLoadout,
	settings: PlayerSettings,
	stats: LifetimeStats,
	firstJoinedAt: number,
	onboarded: boolean,
}

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 1

function PlayerDataSchema.default(): PlayerData
	return {
		version = PlayerDataSchema.VERSION,
		coins = 0,
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

	reconcile(data, PlayerDataSchema.default())
	return data :: PlayerData
end

return PlayerDataSchema
