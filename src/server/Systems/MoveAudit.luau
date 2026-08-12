--!strict
-- MoveAudit — is anyone moving faster than any legal state allows (NOD-139).
--
-- **Flag, do not rubber-band.** This is the whole design and it is deliberate
-- until M14 (NOD-161). A false positive that prints a line costs nothing; a
-- false positive that teleports a player back costs them a fight they were
-- winning, and right now there is no evidence about what normal looks like —
-- lifts, conveyors, knockback, a laggy client covering ground in bursts, and a
-- respawn are all legitimately fast, and none of them have been measured.
--
-- So this builds the evidence. When M14 decides to act, it will act on numbers
-- rather than on a guess about what a cheater looks like.
--
-- The speed ceiling is NOT defined here. It comes from Movement.maxSpeed, the
-- same function the client drives toward, because a check with its own idea of
-- the maximum is a check that goes off every time somebody tunes a speed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Movement = require(ReplicatedStorage.Shared.Systems.Movement)
local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)

local SYSTEM = "MoveAudit"

local MoveAudit = {}

type Sample = {
	position: Vector3,
	at: number,
	strikes: number,
	-- Worst planar speed seen this session, so the report has a number in it
	-- rather than only a verdict.
	fastest: number,
	flagged: boolean,
}

local samples: { [Player]: Sample } = {}
local clock = 0
local nextSampleAt = 0
local rng = Random.new()

-- Never the same gap twice.
--
-- A fixed sampling period can be phase-locked, and this is not theoretical: on
-- 2026-08-12 a character teleporting 260 studs back and forth every 0.25s was
-- sampled at exactly 0.5s and read as PERFECTLY STATIONARY, because every
-- sample landed on the same end of the trip. Zero studs moved, sixteen times in
-- a row, while it crossed half the lobby forty times.
--
-- Jitter removes the period to hide inside. It does not remove the underlying
-- limit — anything that leaves and returns between two samples is invisible to
-- position sampling by construction — and that limit is worth stating plainly
-- rather than being quietly assumed away. Catching it needs per-frame
-- observation, which is NOD-161's call to make with real traffic in front of it.
local function scheduleNext()
	local jitter = 1 + rng:NextNumber(-Config.auditIntervalJitter, Config.auditIntervalJitter)
	nextSampleAt = clock + Config.auditIntervalSeconds * jitter
end

-- How heavy the player's held weapon is, injected. A System requiring a Service
-- is the dependency direction backwards, and this one would drag the whole
-- weapon layer in to read a single multiplier.
local resolveWeight: ((Player) -> number?)? = nil

function MoveAudit.setWeightResolver(fn: (Player) -> number?)
	resolveWeight = fn
end

local function weightFor(player: Player): number
	local resolver = resolveWeight
	if not resolver then
		return 1
	end
	local ok, value = pcall(resolver, player)
	if ok and type(value) == "number" and value > 0 then
		return value
	end
	return 1
end

-- Public so a test can advance it without waiting real seconds — the same
-- reason Ballistics.step and Health.step are public.
function MoveAudit.step(deltaTime: number)
	clock += deltaTime
	if clock < nextSampleAt then
		return
	end
	scheduleNext()

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			-- A dead or half-loaded character has no meaningful position. Drop
			-- the sample rather than measuring against a stale one, which would
			-- report every respawn as a teleport.
			samples[player] = nil
			continue
		end

		local previous = samples[player]
		local position = root.Position
		if not previous then
			samples[player] = { position = position, at = clock, strikes = 0, fastest = 0, flagged = false }
			continue
		end

		local elapsed = clock - previous.at
		if elapsed <= 0 then
			continue
		end

		-- Planar only. Falling fast is not moving fast, and a check that cannot
		-- tell the difference flags every jump off every roof.
		local delta = position - previous.position
		local planar = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local speed = planar / elapsed

		local ceiling = Movement.maxSpeed(weightFor(player)) * Config.speedToleranceMultiplier
		local teleported = planar >= Config.teleportStuds

		if speed > previous.fastest then
			previous.fastest = speed
		end

		if speed > ceiling or teleported then
			previous.strikes += 1
			if previous.strikes >= Config.auditStrikes and not previous.flagged then
				previous.flagged = true
				Diagnostics.count(SYSTEM, "flagged")
				Diagnostics.warn(
					SYSTEM,
					`{player.Name} moved at {string.format("%.0f", speed)} studs/s across `
						.. `{Config.auditStrikes} consecutive samples — the fastest legal state allows `
						.. `{string.format("%.0f", ceiling)}. NOT corrected, on purpose: this is evidence for `
						.. `NOD-161, and lifts, knockback and lag all look like this too.`
				)
			end
		else
			-- Consecutive, not cumulative. One hitch is not an accusation, and
			-- a counter that only goes up eventually accuses everybody.
			previous.strikes = 0
		end

		previous.position = position
		previous.at = clock
	end
end

-- The fastest planar speed observed for a player this session, or nil if they
-- have never been sampled. For the overlay and for tests.
function MoveAudit.fastest(player: Player): number?
	local sample = samples[player]
	return sample and sample.fastest
end

function MoveAudit.init()
	RunService.Heartbeat:Connect(MoveAudit.step)

	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
	end)

	Diagnostics.ok(
		SYSTEM,
		`sampling every {Config.auditIntervalSeconds}s ±{math.floor(Config.auditIntervalJitter * 100)}% · `
			.. `ceiling {string.format("%.0f", Movement.maxSpeed(1))} x{Config.speedToleranceMultiplier} · `
			.. `flags after {Config.auditStrikes} strikes, never corrects`
	)
end

return MoveAudit
