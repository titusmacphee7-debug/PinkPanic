--!strict
-- AssetRegistry — convention over configuration for cosmetics (NOD-145).
--
-- Titus is generating a very large number of camos. The engineering
-- requirement is therefore not "make camos work" — it is **make adding the
-- 300th camo cost nothing.**
--
-- So there is no per-camo code and no per-camo config entry. **A camo exists
-- because a texture exists.** Drop a file in the folder and it is in the game,
-- in the shop, previewable and equippable.
--
--   ReplicatedStorage/Assets/Camos/Camo_StrawberryMilk
--     id           = "Camo_StrawberryMilk"     (the instance name, verbatim)
--     displayName  = "Strawberry Milk"          (derived)
--     rarity/price = from an OPTIONAL override entry, defaults otherwise
--
-- The override table is optional on purpose. An item with no config entry is a
-- Common with no price, which is a perfectly good camo — so a missing entry can
-- never be the reason something fails to appear. Config is for the exceptions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local Overrides = require(ReplicatedStorage.Shared.Config.CosmeticOverrides)

local SYSTEM = "AssetRegistry"

export type Category =
	"Camos" | "Outfits" | "Charms" | "KillEffects" | "Tracers" | "Emotes" | "Titles" | "NameTags"

export type Item = {
	id: string,
	category: Category,
	displayName: string,
	rarity: Rarity.Tier,
	instance: Instance,

	-- Camos only. nil means universal — it uses the shared UV layout and maps
	-- onto any gun. A gun id means it was authored for that weapon's UV and
	-- must never be offered on another one.
	--
	-- Most camos are gun-specific; universal is the smaller set. Which is why
	-- this is derived from the folder rather than configured: the camo's
	-- location IS the answer, so it cannot be wrong or forgotten.
	gunId: string?,

	-- Acquisition. At least one FREE path must exist, always — see validate().
	coinPrice: number?,
	gemPrice: number?,
	unlockLevel: number?,
	challenge: string?,
	crateLine: string?,
	-- Grant-only items (Special / Limited) are earned through events and
	-- achievements, which is itself a free path.
	grantOnly: boolean?,
}

local CATEGORIES: { Category } = {
	"Camos",
	"Outfits",
	"Charms",
	"KillEffects",
	"Tracers",
	"Emotes",
	"Titles",
	"NameTags",
}

-- Category -> the prefix stripped from instance names for display.
local PREFIX: { [string]: string } = {
	Camos = "Camo_",
	Outfits = "Outfit_",
	Charms = "Charm_",
	KillEffects = "KillEffect_",
	Tracers = "Tracer_",
	Emotes = "Emote_",
	Titles = "Title_",
	NameTags = "NameTag_",
}

local AssetRegistry = {}

local items: { [string]: Item } = {} -- id -> item
local byCategory: { [string]: { Item } } = {}
local loaded = false

-- ---------------------------------------------------------------------------
-- Name derivation
-- ---------------------------------------------------------------------------

-- "Camo_StrawberryMilk" -> "Strawberry Milk"
-- "Camo_XOXOHeart"      -> "XOXO Heart"     (acronym kept intact)
-- "Camo_Heart2"         -> "Heart 2"
--
-- Written out rather than done with one clever pattern, because the acronym
-- case is the one that silently produces "X O X O" and nobody notices until a
-- shop screenshot.
local function humanise(name: string, prefix: string?): string
	local base = name
	if prefix and string.sub(base, 1, #prefix) == prefix then
		base = string.sub(base, #prefix + 1)
	end

	-- lower followed by Upper -> split.  "StrawberryMilk" -> "Strawberry Milk"
	base = string.gsub(base, "(%l)(%u)", "%1 %2")
	-- UPPER followed by Upper+lower -> split before the last capital, so an
	-- acronym stays whole.  "XOXOHeart" -> "XOXO Heart",  "Y2KFoil" -> "Y2K Foil"
	base = string.gsub(base, "(%u)(%u%l)", "%1 %2")
	-- Digits only break away from LOWERCASE letters. Splitting on any letter
	-- turned "Y2KFoil" into "Y 2 K Foil" — digits inside an acronym belong to
	-- it.  "Heart2" -> "Heart 2",  "Y2K" -> "Y2K"
	base = string.gsub(base, "(%l)(%d)", "%1 %2")
	base = string.gsub(base, "(%d)(%u%l)", "%1 %2")
	-- underscores and dashes are word breaks
	base = string.gsub(base, "[_%-]+", " ")
	-- collapse any doubles we introduced
	base = string.gsub(base, "%s+", " ")
	base = string.gsub(base, "^%s*(.-)%s*$", "%1")

	-- Title-case the first letter of each word, leaving the rest alone so
	-- acronyms survive: "sleepy clouds" -> "Sleepy Clouds", "MVP" stays "MVP".
	base = string.gsub(base, "(%S)(%S*)", function(first: string, rest: string)
		return string.upper(first) .. rest
	end)

	return base
end

AssetRegistry.humanise = humanise

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function makeItem(child: Instance, category: Category, gunId: string?): Item
	local id = child.Name
	local override = Overrides.get(id)
	return {
		id = id,
		category = category,
		displayName = if override and override.displayName
			then override.displayName
			else humanise(id, PREFIX[category]),
		rarity = if override and override.rarity then override.rarity else "Common",
		instance = child,
		gunId = gunId,
		coinPrice = override and override.coinPrice,
		gemPrice = override and override.gemPrice,
		unlockLevel = override and override.unlockLevel,
		challenge = override and override.challenge,
		crateLine = override and override.crateLine,
		grantOnly = override and override.grantOnly,
	}
end

-- Camos are nested: Universal/ and PerGun/<GunId>/. Everything else is flat.
local function scanCamos(folder: Instance): ({ Item }, { string }, { string })
	local list: { Item } = {}
	local duplicates: { string } = {}
	local problems: { string } = {}

	local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)

	local function take(child: Instance, gunId: string?)
		if items[child.Name] then
			table.insert(duplicates, child.Name)
			return
		end
		local item = makeItem(child, "Camos", gunId)
		items[child.Name] = item
		table.insert(list, item)
	end

	local universal = folder:FindFirstChild("Universal")
	if universal then
		for _, child in universal:GetChildren() do
			take(child, nil)
		end
	end

	local perGun = folder:FindFirstChild("PerGun")
	if perGun then
		for _, gunFolder in perGun:GetChildren() do
			-- Rule 4 again: the folder name IS the gun id. A camo filed under a
			-- gun that does not exist would simply never appear on anything,
			-- which is the silent failure this project keeps getting rid of.
			if not GunCatalog.get(gunFolder.Name) then
				local count = #gunFolder:GetChildren()
				if count > 0 then
					table.insert(problems, `{count} camo(s) filed under unknown gun "{gunFolder.Name}"`)
				end
				continue
			end
			for _, child in gunFolder:GetChildren() do
				take(child, gunFolder.Name)
			end
		end
	end

	-- Camos dropped straight into Camos/ rather than into a scope folder. Easy
	-- mistake, and they would otherwise be invisible forever.
	for _, child in folder:GetChildren() do
		if child.Name ~= "Universal" and child.Name ~= "PerGun" then
			table.insert(
				problems,
				`"{child.Name}" is loose in Camos/ — put it in Universal/ or PerGun/<GunId>/`
			)
		end
	end

	return list, duplicates, problems
end

local function scanCategory(root: Instance, category: Category): ({ Item }, { string }, { string })
	local list: { Item } = {}
	local duplicates: { string } = {}

	local folder = root:FindFirstChild(category)
	if not folder then
		-- AssetTree creates these at boot, so a missing one means the tree did
		-- not run — worth knowing, but not this module's failure to report.
		return list, duplicates, {}
	end

	if category == "Camos" then
		local camoList, camoDupes, camoProblems = scanCamos(folder)
		table.sort(camoList, function(a, b)
			return a.id < b.id
		end)
		return camoList, camoDupes, camoProblems
	end

	for _, child in folder:GetChildren() do
		if items[child.Name] then
			table.insert(duplicates, child.Name)
			continue
		end
		local item = makeItem(child, category, nil)
		items[child.Name] = item
		table.insert(list, item)
	end

	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list, duplicates, {}
end

function AssetRegistry.load()
	items = {}
	byCategory = {}
	loaded = false

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		Diagnostics.dead(SYSTEM, "ReplicatedStorage.Assets is missing — did AssetTree run?")
		return
	end

	local counts: { string } = {}
	local problems: { string } = {}
	local total = 0

	for _, category in CATEGORIES do
		local list, duplicates, categoryProblems = scanCategory(assets, category)
		byCategory[category] = list
		total += #list

		if category == "Camos" then
			local universal = 0
			for _, item in list do
				if not item.gunId then
					universal += 1
				end
			end
			table.insert(counts, `Camos {#list} ({universal} universal, {#list - universal} per-gun)`)
		else
			table.insert(counts, `{category} {#list}`)
		end

		if #duplicates > 0 then
			table.sort(duplicates)
			table.insert(problems, `duplicate id(s) in {category}: {table.concat(duplicates, ", ")}`)
		end
		for _, problem in categoryProblems do
			table.insert(problems, problem)
		end
	end

	loaded = true

	-- The free-to-play guarantee, enforced rather than trusted. Titus's rule is
	-- that anything purchasable is also obtainable free-to-play, and discipline
	-- holds that for the first fifty items — a boot check holds it for the four
	-- hundredth.
	local paywalled: { string } = {}
	for id, item in items do
		if item.gemPrice and not AssetRegistry.hasFreePath(item) then
			table.insert(paywalled, id)
		end
	end
	if #paywalled > 0 then
		table.sort(paywalled)
		table.insert(
			problems,
			`gem-priced with NO free path: {table.concat(paywalled, ", ")} — `
				.. `every purchasable item must also be earnable`
		)
	end

	-- An override for something that does not exist is dead config: it looks
	-- like the item is configured, and it is not.
	local orphanOverrides: { string } = {}
	for id in Overrides.all() do
		if not items[id] then
			table.insert(orphanOverrides, id)
		end
	end
	if #orphanOverrides > 0 then
		table.sort(orphanOverrides)
		table.insert(problems, `override(s) with no asset: {table.concat(orphanOverrides, ", ")}`)
	end

	if #problems > 0 then
		Diagnostics.dead(SYSTEM, `{total} items — {table.concat(problems, "; ")}`)
		return
	end

	Diagnostics.ok(SYSTEM, `{total} items · {table.concat(counts, " · ")}`)
end

-- An item is obtainable for free if it has a coin price, unlocks by level,
-- comes from a challenge, drops from a crate (crates are buyable with coins),
-- or is grant-only. Being purely free — no prices at all — also counts.
function AssetRegistry.hasFreePath(item: Item): boolean
	if item.grantOnly then
		return true
	end
	if item.coinPrice or item.unlockLevel or item.challenge or item.crateLine then
		return true
	end
	-- No acquisition data at all means it is not sold; it is just owned or
	-- awarded. That is free by definition.
	return item.gemPrice == nil
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

function AssetRegistry.get(id: string): Item?
	return items[id]
end

function AssetRegistry.list(category: Category): { Item }
	return byCategory[category] or {}
end

-- Every camo that may be shown on this gun: its own, plus the universal set.
-- The armory and shop call THIS rather than filtering themselves, so a
-- gun-specific camo can never leak onto a weapon it was not drawn for.
function AssetRegistry.camosFor(gunId: string): { Item }
	local out: { Item } = {}
	for _, item in byCategory.Camos or {} do
		if item.gunId == nil or item.gunId == gunId then
			table.insert(out, item)
		end
	end
	return out
end

function AssetRegistry.categories(): { Category }
	return CATEGORIES
end

function AssetRegistry.isLoaded(): boolean
	return loaded
end

function AssetRegistry.count(): number
	local n = 0
	for _ in items do
		n += 1
	end
	return n
end

return AssetRegistry
