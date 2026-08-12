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
local Scale = require(ReplicatedStorage.Shared.Systems.Scale)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local ClassCharter = require(ReplicatedStorage.Shared.Config.ClassCharter)
local BallisticsConfig = require(ReplicatedStorage.Shared.Config.BallisticsConfig)
local HealthConfig = require(ReplicatedStorage.Shared.Config.HealthConfig)

local SYSTEM = "Balance"

local Balance = {}

export type Zone = "Head" | "Torso" | "Limb"

-- The distances the roster is judged at. Owned by ClassCharter, because a band
-- the charter does not have a window for is a band nothing can be checked at —
-- two lists of distances that drift apart would silently disable the check.
Balance.bands = ClassCharter.bands

-- Classes whose falloff is FLAT by design, so the flat-TTK check does not flag
-- them forever. A marksman rifle that hit softer at distance would have no job,
-- and a sniper is balanced on handling and precision rather than on range.
--
-- Named rather than inferred, because "this gun is flat on purpose" and "this
-- gun is flat because nobody set its range bands" look identical in the data
-- and are the two ends of the bug NOD-148 exists to fix.
Balance.falloffExempt = { Sniper = true, Marksman = true } :: { [string]: boolean }

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
	-- Past `travelMax` the bullet does not exist. `pelletDamageAt` answers for any
	-- distance you hand it — it is a falloff curve, not a range check — so asking
	-- it about 60 studs for a shotgun whose pellets die at 40 gets you a confident
	-- number for a shot that never lands. That is the difference between "dead
	-- past 25 studs" and "weak past 25 studs", which is the entire shotgun design.
	if distance > stats.travelMax then
		return 0
	end
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

-- Reloading is real time on the clock, but you do it between fights far more
-- often than inside one, so it counts at a quarter. Leaving it out entirely was
-- the bug: a gun could buy a fast ADS with a four-second reload and this model
-- called it nimble.
local RELOAD_WEIGHT = 0.25

function Balance.handlingCost(stats: CombatStats.Resolved): number
	local raw = stats.adsTime + stats.sprintToFire + stats.equipTime
	raw += stats.reloadSeconds * RELOAD_WEIGHT

	-- Mobility is a benefit, expressed as the time it gives back. Walk and
	-- sprint are counted separately because they are authored separately —
	-- a gun you can carry but not run with is a real design, and one number
	-- could not say it.
	local mobility = (stats.moveSpeedMult - 1) * 1.6 + (stats.sprintSpeedMult - 1) * 1.2
	return raw - mobility
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
	reach: number, -- travelMax: where the bullets stop existing
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
				reach = stats.travelMax,
				-- Flat means the gun kills in the same number of rounds at 100
				-- studs as at 10. Measured in SHOTS rather than seconds because
				-- that is what the player experiences, and because a fractional
				-- difference in seconds with the same shot count is not falloff
				-- doing any work at all.
				flat = stk[1] == stk[#Balance.bands] and not Balance.falloffExempt[stats.class],
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

-- Guns in the top third of kill speed, handling AND reach — all three corners
-- of the triangle at once.
--
-- All THREE, not two. The first version of this check flagged the top third of
-- TTK and handling together, and it was wrong in a way that matters: an SMG is
-- *supposed* to be both. Killing fastest up close while handling best is the
-- entire class, and what pays for it is that its bullets do not reach. A check
-- that flags the design working as intended is a check everybody learns to
-- ignore, and then it is not there for the gun that really is broken.
--
-- Reach is `travelMax` — literally how far the bullets go — because it is the
-- one number no amount of falloff tuning can talk its way around.
function Balance.dominant(): { string }
	local list = rows("Torso")

	local function topThird(compare: (Row, Row) -> boolean): { [string]: boolean }
		local sorted = table.clone(list)
		table.sort(sorted, compare)
		local set: { [string]: boolean } = {}
		for index = 1, math.max(math.floor(#list / 3), 1) do
			set[sorted[index].id] = true
		end
		return set
	end

	local fastest = topThird(function(a, b)
		return a.ttk[1] < b.ttk[1]
	end)
	local slickest = topThird(function(a, b)
		return a.handling < b.handling
	end)
	local longest = topThird(function(a, b)
		return a.reach > b.reach
	end)

	local flagged: { string } = {}
	for _, row in list do
		if fastest[row.id] and slickest[row.id] and longest[row.id] then
			table.insert(flagged, `{row.name} ({row.class})`)
		end
	end
	return flagged
end

-- ---------------------------------------------------------------------------
-- The charter check
--
-- Every gun must sit inside its class's window at every band. This is what
-- makes "some guns are better than others, but there's no god gun" a property
-- of the build rather than an intention: power varies freely INSIDE the box,
-- and leaving the box is a boot warning with the gun's name on it.
--
-- Reports the miss in seconds and in feet, because "Bestie is 0.06s over at
-- band 5" is not actionable and "Bestie takes 0.78s at 117 ft, window is
-- 0.62-0.72" is.
-- ---------------------------------------------------------------------------

function Balance.charter(): { string }
	local problems: { string } = {}

	for _, row in rows("Torso") do
		local spec = ClassCharter.classes[row.class]
		if not spec then
			table.insert(problems, `{row.name}: class "{row.class}" has no charter entry`)
			continue
		end

		if not spec.special then
			for index, distance in Balance.bands do
				local window = spec.ttk[index]
				local ttk = row.ttk[index]
				local at = Scale.describe(distance)

				if not window then
					-- No window means the class must be DEAD here. This is how a
					-- shotgun's death gets specified rather than left to
					-- whatever travelMax happened to be.
					if ttk ~= math.huge then
						table.insert(
							problems,
							`{row.name} ({row.class}) still kills at {at} — its class must not reach that far`
						)
					end
				elseif ttk == math.huge then
					table.insert(problems, `{row.name} ({row.class}) cannot kill at {at} — its class must`)
				elseif ttk < window.min - 1e-6 or ttk > window.max + 1e-6 then
					table.insert(
						problems,
						`{row.name} ({row.class}) {string.format("%.2f", ttk)}s at {at}, `
							.. `window {string.format("%.2f", window.min)}-{string.format("%.2f", window.max)}`
					)
				end
			end
		end

		if row.handling < spec.handling.min - 1e-6 or row.handling > spec.handling.max + 1e-6 then
			table.insert(
				problems,
				`{row.name} ({row.class}) handling {string.format("%.2f", row.handling)}, `
					.. `window {string.format("%.2f", spec.handling.min)}-{string.format("%.2f", spec.handling.max)}`
			)
		end

		if row.reach < spec.reach.min - 1e-6 or row.reach > spec.reach.max + 1e-6 then
			table.insert(
				problems,
				`{row.name} ({row.class}) reach {Scale.describe(row.reach)}, `
					.. `window {math.floor(spec.reach.min)}-{math.floor(spec.reach.max)} studs`
			)
		end
	end

	return problems
end

-- Titus's anti-VGSS rule as a number: no shotgun may need more than three shots
-- to kill at 40 studs (43 ft). *"up to 5 feet your god then all the sudden your
-- throwing mac and cheese at them."*
function Balance.shotgunReach(): { string }
	local problems: { string } = {}
	local index = table.find(Balance.bands, 40)
	if not index then
		return { "no 40-stud band, so the shotgun rule cannot be checked" }
	end

	for _, row in rows("Torso") do
		if row.class ~= "Shotgun" then
			continue
		end
		local shots = row.stk[index]
		if shots > ClassCharter.shotgunMaxShotsAt40 then
			table.insert(
				problems,
				`{row.name} needs {if shots == math.huge then "∞" else tostring(shots)} shots at `
					.. `{Scale.describe(40)}, limit is {ClassCharter.shotgunMaxShotsAt40}`
			)
		end
	end
	return problems
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

	-- One-shot kills on a LIMB. A sniper one-shotting a chest is the class doing
	-- its job; the same round deleting you through a foot is the thing that makes
	-- a lobby quit, because there was nothing the victim could have done
	-- differently. This is the check, rather than "one-shots at 100 studs" — that
	-- would flag every sniper in the game forever and teach everyone to ignore it.
	local limbDeleters: { string } = {}
	for _, row in list do
		local stats = CombatStats.forGun(row.id)
		if stats and Balance.shotsToKill(stats, Balance.bands[1], "Limb") <= 1 then
			table.insert(limbDeleters, row.name)
		end
	end

	local problems: { string } = {}

	-- A gun that did not load is a gun the shop will sell and the game cannot
	-- fire. One file per gun made that possible, so it gets a check.
	local failures = GunCatalog.failures()
	if #failures > 0 then
		table.insert(problems, `{#failures} gun file(s) failed to load: {table.concat(failures, " · ")}`)
	end

	-- "One sentence per gun: why pick this over its neighbour. If that sentence
	-- doesn't exist, the gun doesn't ship." That is a rule with a check behind
	-- it, or it is a rule that survives exactly as long as somebody is watching.
	local unjustified: { string } = {}
	for id, def in GunCatalog.guns do
		if type(def.why) ~= "string" or #def.why < 20 then
			table.insert(unjustified, def.name or id)
		end
	end
	if #unjustified > 0 then
		table.insert(problems, `{#unjustified} gun(s) with no reason to exist: {table.concat(unjustified, ", ")}`)
	end

	local charter = Balance.charter()
	if #charter > 0 then
		table.insert(problems, `{#charter} charter violation(s): {table.concat(charter, " · ")}`)
	end

	local shotguns = Balance.shotgunReach()
	if #shotguns > 0 then
		table.insert(problems, `VGSS: {table.concat(shotguns, " · ")}`)
	end

	if #flat > 0 then
		table.insert(problems, `{#flat}/{#list} guns have NO falloff (worst: {flat[1]})`)
	end
	if #dominant > 0 then
		table.insert(
			problems,
			`{#dominant} gun(s) top-third in TTK, handling AND reach: {table.concat(dominant, ", ")}`
		)
	end
	if #limbDeleters > 0 then
		table.insert(problems, `{#limbDeleters} gun(s) one-shot a LIMB: {table.concat(limbDeleters, ", ")}`)
	end

	-- A secondary in the top third of close-range kill speed is a primary you did
	-- not have to choose.
	--
	-- Stated as "top third overall" rather than the obvious "slower than every
	-- primary", because the obvious version is wrong: a pistol SHOULD out-kill a
	-- marksman rifle at 10 studs, and that is the entire reason you carry one
	-- next to a scope. What must not happen is a sidearm competing with the guns
	-- that own close range, and that is what this measures.
	local closeRanked = table.clone(list)
	table.sort(closeRanked, function(a, b)
		return a.ttk[1] < b.ttk[1]
	end)
	local competing: { string } = {}
	for index = 1, math.max(math.floor(#list / 3), 1) do
		local row = closeRanked[index]
		if row.slot == "Secondary" then
			table.insert(competing, `{row.name} ({string.format("%.2f", row.ttk[1])}s)`)
		end
	end
	if #competing > 0 then
		table.insert(problems, `{#competing} secondary(s) in the top third of close TTK: {table.concat(competing, ", ")}`)
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
	local classes: { [string]: number } = {}
	local classCount = 0
	for _, row in list do
		if not classes[row.class] then
			classCount += 1
		end
		classes[row.class] = (classes[row.class] or 0) + 1
	end

	Diagnostics.ok(
		SYSTEM,
		`{#list} guns in {classCount} classes · close TTK {string.format("%.2f", fastest)}-{string.format("%.2f", slowest)}s · `
			.. `falloff engages by {Balance.bands[#Balance.bands]} studs on every class that should have it · `
			.. `nothing tops the third in TTK, handling and reach at once · nothing one-shots a limb · `
			.. `no secondary competes up close`
	)
end

Balance.init = Balance.validate

return Balance
