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
	assists: { Player },
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

-- Simulation time, advanced by step() rather than read from os.clock().
--
-- Two reasons, and the second is the one that matters. It makes regen and the
-- assist window deterministic — a test can advance five seconds in five
-- hundred calls instead of waiting five real ones, which is the difference
-- between testing the delay and hoping it works. And it ties both to the same
-- clock the simulation actually runs on, so a server that hitches does not
-- hand out free regen for time during which nothing else moved.
local clock = 0

-- Set by scoring (M1) and the match loop (M9). Same pattern as Ballistics'
-- hit handler: this system knows a player died and who did it, and nothing
-- about what that is worth.
local killHandler: ((Kill) -> ())? = nil

function Health.setKillHandler(handler: (Kill) -> ())
	killHandler = handler
end

-- Team modes own this (M9). Until then it is off, because the safe default is
-- that you cannot kill your own team by accident.
function Health.setFriendlyFire(enabled: boolean)
	friendlyFire = enabled
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

local function assistsFor(record: Record, killer: Player?): { Player }
	local list: { Player } = {}
	for player, contribution in record.contributions do
		if player ~= killer and clock - contribution.at <= Config.assistWindowSeconds then
			table.insert(list, player)
		end
	end
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
		local contribution = record.contributions[attacker]
		if contribution then
			contribution.damage += amount
			contribution.at = clock
		else
			record.contributions[attacker] = { damage = amount, at = clock }
		end

		-- Hit feedback to the shooter, not to everyone. The hitmarker is the
		-- single most important piece of feedback in a shooter — it is how you
		-- learn whether your aim was right — so it is sent the moment the
		-- server knows, rather than inferred client-side from a health bar.
		Remotes.fireClient("DamageDealt", attacker, amount, source and source.zone or "Torso")
	end

	local remaining = record.humanoid.Health - amount
	Diagnostics.count(SYSTEM, "damage", math.floor(amount + 0.5))

	if remaining > 0 then
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

	local handler = killHandler
	if handler then
		local kill: Kill = {
			victim = character,
			victimPlayer = victimPlayer,
			killer = attacker,
			weaponId = source and source.weaponId,
			zone = source and source.zone,
			assists = assistsFor(record, attacker),
		}
		local ok, err = pcall(handler, kill)
		if not ok then
			Diagnostics.warn(SYSTEM, `kill handler errored — {err}`)
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

	RunService.Heartbeat:Connect(Health.step)

	-- The seam Ballistics has been WARNing about since NOD-133 shipped.
	local Ballistics = require(script.Parent.Ballistics)
	Ballistics.setHitHandler(function(hit)
		Health.applyDamage(hit.victim, hit.damage, {
			attacker = hit.attacker,
			weaponId = hit.weaponId,
			zone = hit.zone,
		})
	end)

	Diagnostics.ok(
		SYSTEM,
		`{Config.maxHealth} hp · regen {Config.regenPerSecond}/s after {Config.regenDelaySeconds}s · `
			.. `friendly fire {if friendlyFire then "on" else "off"}`
	)
end

return Health
