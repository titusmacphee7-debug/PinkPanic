--!strict
-- Health — the one place that owns how much health a player has and who took
-- it away (NOD-134).
--
-- Ballistics (NOD-133) resolves hits. This turns them into health loss. That
-- seam is deliberate: "was this shot real" and "how much health does this
-- player have" are separate questions, and keeping them separate is what lets
-- either be reasoned about or tested without the other.
--
-- Two rules that sound obvious and are the ones that break in practice:
--
--   1. **A player dies exactly once.** A shotgun lands as one hit event, but a
--      round can still arrive from two shooters in the same frame, and Roblox
--      will happily let both drive Health below zero. Whoever's damage crossed
--      the line gets the kill; the second is not a second kill, and neither is
--      the ragdoll's own fall damage a moment later.
--
--   2. **Death is detected in exactly one place.** Every downstream system —
--      score, killfeed, respawn, streaks — reads this, rather than each
--      watching Humanoid.Died and deriving its own answer about who did it.
--      Three systems each deciding what a kill was is three systems that
--      disagree the first time something unusual happens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Config = require(ReplicatedStorage.Shared.Config.HealthConfig)

local SYSTEM = "Health"

export type Source = {
	attacker: Player?,
	weaponId: string?,
	zone: string?,
	-- How far the shot travelled. Carried so scoring can price a longshot
	-- (NOD-138) without re-deriving a distance that Ballistics already knew
	-- exactly — measuring it again from two positions after the fact gets a
	-- different answer, because by then both of them have moved.
	distance: number?,
}

-- Who else shot the victim, and for how much.
--
-- The DAMAGE is here and the threshold is not. Health's job is to say what
-- happened; whether 12 damage is worth crediting is a scoring rule, and rules
-- belong in the system that owns them.
export type Assist = {
	player: Player,
	damage: number,
}

-- The victim is a CHARACTER, and the player is optional.
--
-- Keying this on Player looked right and was wrong: a scorestreak turret, a
-- training dummy or a bot dying would then be a death this system detected and
-- reported to nobody, which puts every downstream system back to watching
-- Humanoid.Died and deriving its own answer — the exact duplication this type
-- exists to prevent. Scoring reads `victimPlayer` and ignores the rest.
export type Kill = {
	victim: Model,
	victimPlayer: Player?,
	killer: Player?,
	weaponId: string?,
	zone: string?,
	distance: number?,
	assists: { Assist },
}

type Record = {
	character: Model,
	humanoid: Humanoid,
	dead: boolean,
	lastDamagedAt: number,
	-- Damage each attacker has done to this life, for assists. Reset on
	-- respawn, because a contribution to a previous life is not an assist.
	contributions: { [Player]: { damage: number, at: number } },
	lastAttacker: Player?,
}

local Health = {}

local records: { [Model]: Record } = {}
local friendlyFire = Config.friendlyFire

-- Simulation time at which each player last DEALT damage to anybody. The
-- inverse of a record's contributions, and the only thing that can answer
-- "was this player already in a fight when they died".
local lastDealtAt: { [Player]: number } = {}

-- Simulation time, advanced by step() rather than read from os.clock().
--
-- Two reasons, and the second is the one that matters. It makes regen and the
-- assist window deterministic — a test can advance five seconds in five
-- hundred calls instead of waiting five real ones, which is the difference
-- between testing the delay and hoping it works. And it ties both to the same
-- clock the simulation actually runs on, so a server that hitches does not
-- hand out free regen for time during which nothing else moved.
local clock = 0

-- A LIST, not a single handler. Several systems legitimately care that
-- somebody died — respawn, score, the killfeed, streaks — and a single slot
-- means the second one to register silently replaces the first. That is a bug
-- that presents as "the killfeed works but nobody respawns", with nothing
-- anywhere saying why.
--
-- Each is called in its own pcall so one broken listener cannot stop the
-- others: a scoring error must not also mean the dead never come back.
local killListeners: { (Kill) -> () } = {}

function Health.onKill(listener: (Kill) -> ())
	table.insert(killListeners, listener)
end

-- Vetoes. Any filter returning false rejects the damage entirely.
--
-- This is how spawn protection becomes real rather than a number in a config
-- file that nothing reads. It is a list for the same reason kills are: godmode
-- for testing, a mode with a damage-immune phase and spawn protection are all
-- legitimate vetoes, and the second one to register must not delete the first.
local damageFilters: { (character: Model, amount: number, source: Source?) -> boolean } = {}

function Health.addDamageFilter(filter: (character: Model, amount: number, source: Source?) -> boolean)
	table.insert(damageFilters, filter)
end

-- Team modes own this (M9). Until then it is off, because the safe default is
-- that you cannot kill your own team by accident.
function Health.setFriendlyFire(enabled: boolean)
	friendlyFire = enabled
end

-- Health's simulation clock, exposed so a system that wants to age one of the
-- timestamps below measures it against the same clock that produced it. Reading
-- os.clock() instead would compare two different clocks and get an answer that
-- drifts every time the server hitches.
function Health.now(): number
	return clock
end

-- When this player last damaged anybody, or nil if they never have this
-- session. The saviour bonus is the only caller today: a victim who was mid-
-- fight when they died was a threat to somebody, and killing them was worth
-- more than killing someone idle.
function Health.lastDealt(player: Player): number?
	return lastDealtAt[player]
end

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

local function recordFor(character: Model): Record?
	local existing = records[character]
	if existing then
		return existing
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local record: Record = {
		character = character,
		humanoid = humanoid,
		dead = humanoid.Health <= 0,
		lastDamagedAt = -math.huge,
		contributions = {},
		lastAttacker = nil,
	}
	records[character] = record
	return record
end

local function sameTeam(a: Player?, b: Player?): boolean
	if not a or not b or a == b then
		return false
	end
	-- Neutral players are not on a team, so they are never teammates. Without
	-- this an FFA lobby (everyone neutral) would be entirely friendly fire
	-- immune, which reads as bullets doing nothing.
	if a.Neutral or b.Neutral then
		return false
	end
	return a.Team ~= nil and a.Team == b.Team
end

-- ---------------------------------------------------------------------------
-- Damage
-- ---------------------------------------------------------------------------

local function assistsFor(record: Record, killer: Player?): { Assist }
	local list: { Assist } = {}
	for player, contribution in record.contributions do
		if player ~= killer and clock - contribution.at <= Config.assistWindowSeconds then
			table.insert(list, { player = player, damage = contribution.damage })
		end
	end
	-- Biggest contributor first, so a consumer that only wants "the" assist
	-- gets the one that mattered rather than whatever the hash order gave it.
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)
	return list
end

-- Returns whether this damage killed the victim.
--
-- The return value exists so no caller ever has to guess. The alternative —
-- every caller reading Humanoid.Health afterwards and deciding for itself —
-- is a race the moment two things damage the same player in one frame, and
-- the symptom is a double kill nobody can reproduce.
function Health.applyDamage(character: Model, amount: number, source: Source?): boolean
	if amount < Config.minimumDamage then
		return false
	end

	-- Vetoes first, before anything is recorded. A blocked hit must leave no
	-- trace: no contribution toward an assist, no reset of the regen delay,
	-- and no hitmarker telling the shooter it landed.
	for _, filter in damageFilters do
		local ok, allowed = pcall(filter, character, amount, source)
		if ok and allowed == false then
			return false
		end
	end

	local record = recordFor(character)
	if not record then
		return false
	end

	-- Already dead. This is the guard that stops one frame's worth of pellets
	-- killing someone twice: the first pellet crosses zero, the rest arrive at
	-- a corpse and are dropped here rather than each firing a kill.
	if record.dead or record.humanoid.Health <= 0 then
		record.dead = true
		return false
	end

	local attacker = source and source.attacker
	local victimPlayer = Players:GetPlayerFromCharacter(character)

	if attacker and victimPlayer then
		if attacker == victimPlayer then
			-- Self-damage is allowed (explosives, M8) but never counts as an
			-- attacker for the killfeed.
			attacker = nil
		elseif not friendlyFire and sameTeam(attacker, victimPlayer) then
			return false
		end
	end

	record.lastDamagedAt = clock

	if attacker then
		record.lastAttacker = attacker
		-- When this player last hurt somebody, for the saviour bonus: killing
		-- someone who was mid-fight with a third party is worth more than
		-- killing someone standing still, and this is the only place that
		-- knows it happened.
		lastDealtAt[attacker] = clock
		local contribution = record.contributions[attacker]
		if contribution then
			contribution.damage += amount
			contribution.at = clock
		else
			record.contributions[attacker] = { damage = amount, at = clock }
		end

	end

	local remaining = record.humanoid.Health - amount
	Diagnostics.count(SYSTEM, "damage", math.floor(amount + 0.5))

	local killed = remaining <= 0

	if attacker then
		-- Hit feedback to the shooter, not to everyone. The hitmarker is the
		-- single most important piece of feedback in a shooter — it is how you
		-- learn whether your aim was right — so it is sent the moment the
		-- server knows, rather than inferred client-side from a health bar.
		--
		-- `killed` rides along rather than arriving separately with the kill
		-- event, because the marker that says you FINISHED someone has to be
		-- the same marker, one frame, one sound. Two events racing to draw two
		-- hitmarkers over each other is how you get a double flash on the last
		-- shot of every fight.
		Remotes.fireClient("DamageDealt", attacker, amount, source and source.zone or "Torso", killed)
	end

	if not killed then
		record.humanoid.Health = remaining
		return false
	end

	-- The kill. Marked dead BEFORE Health is written, because setting Health to
	-- zero fires Humanoid.Died synchronously — and anything that reacts to it
	-- by damaging this character again would otherwise find a record that still
	-- says alive.
	record.dead = true
	record.humanoid.Health = 0

	Diagnostics.count(SYSTEM, "deaths")

	if #killListeners > 0 then
		local kill: Kill = {
			victim = character,
			victimPlayer = victimPlayer,
			killer = attacker,
			weaponId = source and source.weaponId,
			zone = source and source.zone,
			distance = source and source.distance,
			assists = assistsFor(record, attacker),
		}
		for _, listener in killListeners do
			local ok, err = pcall(listener, kill)
			if not ok then
				Diagnostics.warn(SYSTEM, `a kill listener errored — {err}`)
			end
		end
	end

	return true
end

-- ---------------------------------------------------------------------------
-- Regeneration
-- ---------------------------------------------------------------------------

-- Public so it can be stepped deterministically in a test rather than only by
-- waiting real seconds — the same reason Ballistics.step is public.
function Health.step(deltaTime: number)
	clock += deltaTime

	for character, record in records do
		if record.dead or record.humanoid.Health <= 0 then
			continue
		end
		if character.Parent == nil then
			records[character] = nil
			continue
		end
		if clock - record.lastDamagedAt < Config.regenDelaySeconds then
			continue
		end

		local maxHealth = record.humanoid.MaxHealth
		if record.humanoid.Health >= maxHealth then
			continue
		end

		record.humanoid.Health = math.min(maxHealth, record.humanoid.Health + Config.regenPerSecond * deltaTime)
	end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.MaxHealth = Config.maxHealth
	humanoid.Health = Config.maxHealth

	local record = recordFor(character)
	if record then
		record.dead = false
		record.lastDamagedAt = -math.huge
		table.clear(record.contributions)
	end

	-- Deaths we did not cause — falling, drowning, a scorestreak that kills
	-- through the Humanoid directly. Recorded so the record agrees with
	-- reality, but NOT routed to the kill handler as an unattributed kill: the
	-- attacker would be whoever last shot them, which is exactly the kind of
	-- guess that produces a killfeed nobody trusts.
	humanoid.Died:Connect(function()
		local r = records[character]
		if r then
			r.dead = true
		end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterRemoving:Connect(function(character)
		records[character] = nil
	end)
end

function Health.init()
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
	Players.PlayerAdded:Connect(watch)

	-- Player keys never expire on their own, so a busy server would otherwise
	-- hold one entry per player who ever fired, forever.
	Players.PlayerRemoving:Connect(function(player)
		lastDealtAt[player] = nil
	end)

	RunService.Heartbeat:Connect(Health.step)

	-- The seam Ballistics has been WARNing about since NOD-133 shipped.
	local Ballistics = require(script.Parent.Ballistics)
	Ballistics.setHitHandler(function(hit)
		Health.applyDamage(hit.victim, hit.damage, {
			attacker = hit.attacker,
			weaponId = hit.weaponId,
			zone = hit.zone,
			distance = hit.distance,
		})
	end)

	Diagnostics.ok(
		SYSTEM,
		`{Config.maxHealth} hp · regen {Config.regenPerSecond}/s after {Config.regenDelaySeconds}s · `
			.. `friendly fire {if friendlyFire then "on" else "off"}`
	)
end

return Health
