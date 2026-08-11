--!strict
-- Rarity — the eight tiers, and everything that makes one feel rarer than the
-- last (NOD-131).
--
-- This lives in shared/Config rather than the UI theme because rarity is game
-- data before it is presentation: the crate roller weights by it, drops grant
-- by it, and duplicate refunds scale with it. The colour is one field among
-- many, not the point.
--
-- Titus: "rares can be loud." So loudness is data — glow, particles, frame and
-- reveal sound all climb with the tier, and a Legendary pull is allowed to take
-- over the screen for a moment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Diagnostics = require(ReplicatedStorage.Shared.Diagnostics)

local SYSTEM = "Rarity"

export type Tier = "Common" | "Uncommon" | "Rare" | "SuperRare" | "Legendary" | "Exotic" | "Special" | "Limited"

export type TierDef = {
	id: Tier,
	displayName: string,

	-- Position on the ladder. Used for sorting and for "is this better than
	-- what I have" comparisons. Special and Limited sit at the end by
	-- convention, but see `rollable` — they are not simply rarer.
	order: number,

	-- Whether a standard crate can roll this tier at all.
	--
	-- Special and Limited are CATEGORICAL, not rarer. They are event,
	-- achievement and milestone grants with availability rules rather than
	-- probabilities. Treating them as "even rarer than Exotic" would quietly
	-- make Exotic feel worthless, which is the opposite of what an eighth tier
	-- is for.
	rollable: boolean,

	-- Relative crate weight. Only meaningful when rollable.
	weight: number?,

	-- Coins returned when you pull a duplicate. Never a dead pull.
	dupeRefund: number,

	-- Loudness, all scaling with the tier.
	color: Color3,
	glow: number, -- 0 = flat, 1 = maximum bloom
	particles: boolean,
	frame: string, -- card treatment id, consumed by the UI
	sound: string, -- reveal sound id, consumed by the crate opening
}

local Rarity = {}

-- Ordered lowest to highest. The array IS the ladder; nothing else defines it.
Rarity.ordered = {
	{
		id = "Common" :: Tier,
		displayName = "Common",
		order = 1,
		rollable = true,
		weight = 1000,
		dupeRefund = 25,
		color = Color3.fromRGB(178, 162, 172),
		glow = 0,
		particles = false,
		frame = "flat",
		sound = "reveal_common",
	},
	{
		id = "Uncommon" :: Tier,
		displayName = "Uncommon",
		order = 2,
		rollable = true,
		weight = 520,
		dupeRefund = 60,
		color = Color3.fromRGB(124, 214, 178),
		glow = 0.1,
		particles = false,
		frame = "flat",
		sound = "reveal_common",
	},
	{
		id = "Rare" :: Tier,
		displayName = "Rare",
		order = 3,
		rollable = true,
		weight = 240,
		dupeRefund = 140,
		color = Color3.fromRGB(96, 168, 236),
		glow = 0.25,
		particles = false,
		frame = "outline",
		sound = "reveal_rare",
	},
	{
		id = "SuperRare" :: Tier,
		displayName = "Super Rare",
		order = 4,
		rollable = true,
		weight = 100,
		dupeRefund = 320,
		color = Color3.fromRGB(176, 130, 246),
		glow = 0.45,
		particles = true,
		frame = "outline",
		sound = "reveal_rare",
	},
	{
		id = "Legendary" :: Tier,
		displayName = "Legendary",
		order = 5,
		rollable = true,
		weight = 34,
		dupeRefund = 750,
		color = Color3.fromRGB(255, 186, 92),
		glow = 0.7,
		particles = true,
		frame = "gilded",
		sound = "reveal_legendary",
	},
	{
		id = "Exotic" :: Tier,
		displayName = "Exotic",
		order = 6,
		rollable = true,
		weight = 6,
		dupeRefund = 1800,
		color = Color3.fromRGB(255, 84, 148),
		glow = 1,
		particles = true,
		frame = "prismatic",
		sound = "reveal_exotic",
	},

	-- Below here: granted, never rolled.
	{
		id = "Special" :: Tier,
		displayName = "Special",
		order = 7,
		rollable = false,
		weight = nil,
		dupeRefund = 0,
		color = Color3.fromRGB(94, 226, 226),
		glow = 0.8,
		particles = true,
		frame = "holo",
		sound = "reveal_special",
	},
	{
		id = "Limited" :: Tier,
		displayName = "Limited",
		order = 8,
		rollable = false,
		weight = nil,
		dupeRefund = 0,
		color = Color3.fromRGB(226, 62, 96),
		glow = 0.9,
		particles = true,
		frame = "shimmer",
		sound = "reveal_limited",
	},
} :: { TierDef }

local byId: { [string]: TierDef } = {}
for _, tier in Rarity.ordered do
	byId[tier.id] = tier
end

-- Unknown ids fall back to Common rather than erroring, because a missing
-- rarity should never be what stops an item rendering. The boot check below is
-- where a bad id gets reported.
function Rarity.get(id: string?): TierDef
	return (id and byId[id]) or byId.Common
end

function Rarity.color(id: string?): Color3
	return Rarity.get(id).color
end

function Rarity.isRollable(id: string?): boolean
	return Rarity.get(id).rollable
end

-- The crate pool: rollable tiers only, with their weights. Anything not in
-- here cannot come out of a standard crate, by construction rather than by a
-- check somewhere that could be forgotten.
function Rarity.rollableWeights(): { { id: Tier, weight: number } }
	local out = {}
	for _, tier in Rarity.ordered do
		if tier.rollable and tier.weight then
			table.insert(out, { id = tier.id, weight = tier.weight })
		end
	end
	return out
end

-- Published odds, as percentages, derived from the same weights the roller
-- uses. The UI renders THIS — odds and reality cannot drift apart because
-- there is only one number.
function Rarity.publishedOdds(): { { id: Tier, percent: number } }
	local weights = Rarity.rollableWeights()
	local total = 0
	for _, entry in weights do
		total += entry.weight
	end

	local out = {}
	for _, entry in weights do
		table.insert(out, { id = entry.id, percent = (entry.weight / total) * 100 })
	end
	return out
end

function Rarity.validate()
	local seenOrder: { [number]: string } = {}
	local problems: { string } = {}

	for _, tier in Rarity.ordered do
		if seenOrder[tier.order] then
			table.insert(problems, `order {tier.order} used by both {seenOrder[tier.order]} and {tier.id}`)
		end
		seenOrder[tier.order] = tier.id

		if tier.rollable and (not tier.weight or tier.weight <= 0) then
			table.insert(problems, `{tier.id} is rollable but has no positive weight`)
		end
		if not tier.rollable and tier.weight then
			table.insert(problems, `{tier.id} is not rollable but carries a weight — it would never be used`)
		end
	end

	if #problems > 0 then
		Diagnostics.dead(SYSTEM, table.concat(problems, "; "))
		return
	end

	local rollable = #Rarity.rollableWeights()
	Diagnostics.ok(SYSTEM, `{#Rarity.ordered} tiers, {rollable} rollable, {#Rarity.ordered - rollable} grant-only`)
end

return Rarity
