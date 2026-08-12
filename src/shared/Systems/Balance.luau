--!strict
-- Balance — the TTK table, generated from the stats (NOD-148).
--
-- Titus: *"the balancing is bad, balance it like Call of Duty guns."* This is
-- the instrument that says whether it still is. Every number here is DERIVED
-- from `GunCatalog` through `CombatStats`, so it cannot drift from the game the
-- way a table pasted into a doc does the moment somebody edits a gun.
--
-- Two of the checks run at boot as part of the manifest, because the failures
-- they catch are invisible from inside a playtest:
--
--   * **A gun that wins every range band.** You cannot feel this. It reads as
--     "that gun is good", and you find out months later that nobody uses
--     anything else.
--   * **A gun whose TTK is flat from 10 to 100 studs.** Falloff that never
--     engages is the root failure NOD-148 was opened for — range stops being a
--     trade-off, and every class relationship downstream collapses with it.
--
-- The balance model, stated once so the numbers have something to be wrong
-- against: a gun may be excellent at TTK, at range, or at handling — never all
-- three. Anything in the top third of two of them is a gun that needs a reason.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local BallisticsConfig = require(ReplicatedStorage.Shared.Config.BallisticsConfig)
local HealthConfig = require(ReplicatedStorage.Shared.Config.HealthConfig)

local SYSTEM = "Balance"

local Balance = {}

export type Zone = "Head" | "Torso" | "Limb"

-- The four distances the roster is judged at. Chosen to sit either side of
-- where each class is supposed to stop working: 10 is knife-fight range, 30 is
-- where an SMG should already be losing, 60 is AR territory, 100 is a lane.
Balance.bands = { 10, 30, 60, 100 }

local function zoneMultiplier(stats: CombatStats.Resolved, zone: Zone): number
	if zone == "Head" then
		return stats.headshotMult
	elseif zone == "Limb" then
		return BallisticsConfig.limbMult
	end
	return 1
end

-- ---------------------------------------------------------------------------
-- The measurements
-- ---------------------------------------------------------------------------

-- Damage from one trigger pull at `distance` — every pellet, falloff applied,
-- zone applied. Shotguns are the reason this is per SHOT rather than per bullet:
-- eight pellets landing is one event to the player and one event to Health.
function Balance.damagePerShot(stats: CombatStats.Resolved, distance: number, zone: Zone): number
	local perPellet = CombatStats.pelletDamageAt(stats, distance) * zoneMultiplier(stats, zone)
	return perPellet * math.max(stats.pellets, 1)
end

function Balance.shotsToKill(stats: CombatStats.Resolved, distance: number, zone: Zone): number
	local damage = Balance.damagePerShot(stats, distance, zone)
	if damage <= 0 then
		return math.huge
	end
	return math.ceil(HealthConfig.maxHealth / damage)
end

-- Time from the first round leaving the barrel to the last one landing. The
-- first shot costs nothing — a one-shot kill is 0.00s, which is exactly the
-- thing the table should make impossible to miss.
--
-- Burst guns fire `burstCount` rounds at `burstRpm` inside a pull, and wait out
-- `fireRate` between pulls. Nothing in the roster bursts today; it is handled
-- here so that the day one does, the table does not quietly lie about it.
function Balance.ttk(stats: CombatStats.Resolved, distance: number, zone: Zone): number
	local shots = Balance.shotsToKill(stats, distance, zone)
	if shots == math.huge then
		return math.huge
	end
	if shots <= 1 then
		return 0
	end

	local burstCount = stats.burstCount
	local burstRpm = stats.burstRpm
	if burstCount and burstCount > 1 and burstRpm then
		local insideBurst = 60 / burstRpm
		local betweenBursts = 1 / stats.fireRate
		local fired, elapsed = 1, 0
		while fired < shots do
			if fired % burstCount == 0 then
				elapsed += betweenBursts
			else
				elapsed += insideBurst
			end
			fired += 1
		end
		return elapsed
	end

	return (shots - 1) / stats.fireRate
end

-- ---------------------------------------------------------------------------
-- Handling, as one number
--
-- The third corner of the triangle. Times are costs and mobility is a benefit,
-- so they cannot simply be summed — this returns "seconds of faff", where lower
-- is better, and the mobility bonus is expressed as time it gives back.
-- ---------------------------------------------------------------------------

function Balance.handlingCost(stats: CombatStats.Resolved): number
	local raw = stats.adsTime + stats.sprintToFire + stats.equipTime
	-- A gun that moves you 6% faster is worth roughly a tenth of a second of
	-- readiness. Rough on purpose: this is a sorting key, not a simulation.
	return raw - (stats.moveSpeedMult - 1) * 1.6
end

-- ---------------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------------

export type Row = {
	id: string,
	name: string,
	class: string,
	slot: string,
	ttk: { number }, -- one per band
	stk: { number },
	handling: number,
	flat: boolean,
}

local function rows(zone: Zone): { Row }
	local out: { Row } = {}
	for id, def in GunCatalog.guns do
		local stats = CombatStats.forGun(id)
		if stats then
			local ttk, stk = {}, {}
			for index, distance in Balance.bands do
				ttk[index] = Balance.ttk(stats, distance, zone)
				stk[index] = Balance.shotsToKill(stats, distance, zone)
			end
			table.insert(out, {
				id = id,
				name = stats.name,
				class = stats.class,
				slot = def.slot,
				ttk = ttk,
				stk = stk,
				handling = Balance.handlingCost(stats),
				-- Flat means the gun kills in the same number of rounds at 100
				-- studs as at 10. Measured in SHOTS rather than seconds because
				-- that is what the player experiences, and because a fractional
				-- difference in seconds with the same shot count is not falloff
				-- doing any work at all.
				flat = stk[1] == stk[#Balance.bands],
			})
		end
	end
	table.sort(out, function(a, b)
		if a.class ~= b.class then
			return a.class < b.class
		end
		return a.ttk[1] < b.ttk[1]
	end)
	return out
end

Balance.rows = rows

local function seconds(value: number): string
	if value == math.huge then
		return "  never"
	end
	return string.format("%6.2f", value)
end

-- The generated table NOD-148 asks for. `zone` defaults to Torso, which is the
-- honest default: it is where most bullets land and it is the reference the
-- headshot multiplier is expressed against.
function Balance.report(zone: Zone?): string
	local target: Zone = zone or "Torso"
	local list = rows(target)

	local lines = {
		``,
		`  TTK TABLE — {target}, {HealthConfig.maxHealth} hp, {#list} guns`,
		`  seconds to kill at each distance in studs · (n) = rounds needed`,
		``,
		string.format(
			"  %-16s %-9s %-10s %-12s %-12s %-12s %-12s  %s",
			"GUN",
			"CLASS",
			"SLOT",
			`@{Balance.bands[1]}`,
			`@{Balance.bands[2]}`,
			`@{Balance.bands[3]}`,
			`@{Balance.bands[4]}`,
			"FALLOFF"
		),
	}

	for _, row in list do
		local cells = {}
		for index in Balance.bands do
			local count = row.stk[index]
			table.insert(
				cells,
				string.format("%s(%s)", seconds(row.ttk[index]), if count == math.huge then "-" else tostring(count))
			)
		end
		table.insert(
			lines,
			string.format(
				"  %-16s %-9s %-10s %-12s %-12s %-12s %-12s  %s",
				row.name,
				row.class,
				row.slot,
				cells[1],
				cells[2],
				cells[3],
				cells[4],
				if row.flat then "FLAT — no falloff" else ""
			)
		)
	end

	table.insert(lines, ``)
	local text = table.concat(lines, "\n")
	print(text)
	return text
end

-- ---------------------------------------------------------------------------
-- The regression checks
-- ---------------------------------------------------------------------------

-- Guns in the top third of BOTH kill speed and handling. The triangle says a
-- gun may be excellent at two things at most, and TTK-plus-handling is the pair
-- that produces a gun with no counterplay — it wins the trade before you have
-- finished aiming and it kills you faster once you have.
function Balance.dominant(): { string }
	local list = rows("Torso")
	local byTtk = table.clone(list)
	local byHandling = table.clone(list)
	table.sort(byTtk, function(a, b)
		return a.ttk[1] < b.ttk[1]
	end)
	table.sort(byHandling, function(a, b)
		return a.handling < b.handling
	end)

	local third = math.max(math.floor(#list / 3), 1)
	local fastest: { [string]: boolean } = {}
	for index = 1, third do
		fastest[byTtk[index].id] = true
	end

	local flagged: { string } = {}
	for index = 1, third do
		local row = byHandling[index]
		if fastest[row.id] then
			table.insert(flagged, `{row.name} ({row.class})`)
		end
	end
	return flagged
end

function Balance.flat(): { string }
	local flagged: { string } = {}
	for _, row in rows("Torso") do
		if row.flat then
			table.insert(flagged, `{row.name} ({row.class}) {row.stk[1]} shots at every range`)
		end
	end
	return flagged
end

function Balance.validate()
	local list = rows("Torso")
	local flat = Balance.flat()
	local dominant = Balance.dominant()

	-- One-shot kills at the FURTHEST band. A gun that deletes you at 100 studs
	-- before you have heard it is the single worst thing to hand a new player,
	-- and it is a different failure from flat falloff even though the same guns
	-- usually have both.
	local snipeAnywhere: { string } = {}
	for _, row in list do
		if row.stk[#Balance.bands] <= 1 then
			table.insert(snipeAnywhere, row.name)
		end
	end

	local problems: { string } = {}
	if #flat > 0 then
		table.insert(problems, `{#flat}/{#list} guns have NO falloff (worst: {flat[1]})`)
	end
	if #dominant > 0 then
		table.insert(problems, `{#dominant} gun(s) top-third in both TTK and handling: {table.concat(dominant, ", ")}`)
	end
	if #snipeAnywhere > 0 then
		table.insert(
			problems,
			`{#snipeAnywhere} gun(s) one-shot at {Balance.bands[#Balance.bands]} studs: {table.concat(snipeAnywhere, ", ")}`
		)
	end

	if #problems > 0 then
		Diagnostics.warn(
			SYSTEM,
			`{table.concat(problems, " · ")} — for the table run `
				.. `require(game.ReplicatedStorage.Shared.Systems.Balance).report()`
		)
		return
	end

	local fastest, slowest = math.huge, 0
	for _, row in list do
		fastest = math.min(fastest, row.ttk[1])
		slowest = math.max(slowest, row.ttk[1])
	end
	Diagnostics.ok(
		SYSTEM,
		`{#list} guns · close TTK {string.format("%.2f", fastest)}-{string.format("%.2f", slowest)}s · `
			.. `every gun's falloff engages by {Balance.bands[#Balance.bands]} studs · `
			.. `nothing tops the third in both TTK and handling`
	)
end

Balance.init = Balance.validate

return Balance
