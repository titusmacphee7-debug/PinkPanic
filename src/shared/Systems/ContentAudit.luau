--!strict
-- ContentAudit — enforces the rule that an asset folder name IS its config id
-- (NOD-128, rule 4).
--
-- Config and content are maintained in two different places by two different
-- people: I write the config, Titus builds the models. Nothing connects them
-- except a matching string, and a mismatched string fails in the quietest
-- possible way — the item exists in the shop, has a price and a rarity, and
-- renders as nothing at all.
--
-- So both directions are checked, because they are different bugs:
--
--   config id with no asset   → the item is buyable and invisible
--   asset with no config id   → work was done that the game will never show
--
-- The second one is the reason this reports rather than just warning on the
-- first: an orphaned model is somebody's afternoon that nobody noticed was
-- wasted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

local SYSTEM = "ContentAudit"

-- How many names to print before truncating. Long enough to act on, short
-- enough that the manifest stays readable when something is badly wrong.
local MAX_NAMED = 8

local ContentAudit = {}

export type Result = {
	label: string,
	matched: number,
	missingAssets: { string },
	orphanAssets: { string },
}

local function nameList(names: { string }): string
	table.sort(names)
	if #names <= MAX_NAMED then
		return table.concat(names, ", ")
	end
	local shown = table.move(names, 1, MAX_NAMED, 1, {})
	return `{table.concat(shown, ", ")} … and {#names - MAX_NAMED} more`
end

-- Compares a set of config ids against the children of a content folder.
-- `folders` is a list because content can legitimately live in more than one
-- place during a migration — the legacy GunModels folder and the new
-- Assets/Guns folder both count as "the model exists".
function ContentAudit.compare(label: string, configIds: { [string]: any }, folders: { Instance? }): Result
	local present: { [string]: boolean } = {}
	for _, folder in folders do
		if folder then
			for _, child in folder:GetChildren() do
				present[child.Name] = true
			end
		end
	end

	local matched = 0
	local missingAssets: { string } = {}
	local declared: { [string]: boolean } = {}

	for id in configIds do
		declared[id] = true
		if present[id] then
			matched += 1
		else
			table.insert(missingAssets, id)
		end
	end

	local orphanAssets: { string } = {}
	for name in present do
		if not declared[name] then
			table.insert(orphanAssets, name)
		end
	end

	return {
		label = label,
		matched = matched,
		missingAssets = missingAssets,
		orphanAssets = orphanAssets,
	}
end

function ContentAudit.run()
	local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local results: { Result } = {
		ContentAudit.compare("guns", GunCatalog.guns, {
			ReplicatedStorage:FindFirstChild("GunModels"),
			assets and assets:FindFirstChild("Guns"),
		}),
	}

	-- Cosmetic categories are deliberately absent for now. Their ids come FROM
	-- the folder, not from a config (that is the whole point of the registry in
	-- NOD-145), so there is no second list to disagree with. They join this
	-- audit only if they ever gain a config side.

	local problems: { string } = {}
	local summary: { string } = {}

	for _, r in results do
		table.insert(summary, `{r.label} {r.matched}/{r.matched + #r.missingAssets}`)

		if #r.missingAssets > 0 then
			table.insert(problems, `{r.label} in config with NO model: {nameList(r.missingAssets)}`)
		end
		if #r.orphanAssets > 0 then
			table.insert(problems, `{r.label} models with NO config entry: {nameList(r.orphanAssets)}`)
		end
	end

	if #problems > 0 then
		Diagnostics.warn(SYSTEM, `{table.concat(summary, " · ")} — {table.concat(problems, "; ")}`)
		return
	end

	Diagnostics.ok(SYSTEM, `{table.concat(summary, " · ")} matched`)
end

return ContentAudit
