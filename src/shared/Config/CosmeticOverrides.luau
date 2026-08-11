--!strict
-- CosmeticOverrides — data only. The exceptions, not the rule (NOD-145).
--
-- Cosmetics are discovered by AssetRegistry from the folder they live in, and
-- an item with NO entry here is a Common with no price — a perfectly good camo.
-- So a missing entry can never be why something fails to appear.
--
-- This file is for the ones that are special: a Legendary, something that
-- unlocks at a level, something that only comes from an event. Keeping it
-- optional is what makes adding the 300th camo cost nothing.
--
-- The one rule the registry enforces: **an item with a gem price must also have
-- a free path** — a coin price, a level unlock, a challenge, or a crate line.
-- Gems buy speed, never access.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)

export type Override = {
	displayName: string?, -- only when the derived name is wrong
	rarity: Rarity.Tier?,
	coinPrice: number?,
	gemPrice: number?,
	unlockLevel: number?,
	challenge: string?,
	crateLine: string?,
	-- Special and Limited: earned through events and achievements, never rolled
	-- and never sold.
	grantOnly: boolean?,
}

local CosmeticOverrides = {}

-- Keyed by the asset's instance name, exactly as it appears in the folder.
local overrides: { [string]: Override } = {
	-- Examples of the shape. These are inert until assets with these exact
	-- names exist — and the registry reports an override with no asset, so a
	-- stale entry here cannot sit unnoticed pretending to configure something.
	--
	-- Camo_StrawberryMilk = { rarity = "Rare", coinPrice = 1200 },
	-- Camo_HeartCheck     = { rarity = "Legendary", crateLine = "SweetheartCrate" },
	-- Title_FirstBlood    = { rarity = "Special", grantOnly = true },
}

function CosmeticOverrides.get(id: string): Override?
	return overrides[id]
end

function CosmeticOverrides.all(): { [string]: Override }
	return overrides
end

return CosmeticOverrides
