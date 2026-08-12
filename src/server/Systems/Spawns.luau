--!strict
-- Spawns — where you come back, and when (NOD-135).
--
-- Titus's rules: ~5s respawn, never spawn on the enemy, spawns can switch
-- sides, and they can be loud.
--
-- Every spawn point is scored each time somebody needs one, and the highest
-- wins. That is how CoD stops you materialising in front of a gun, and it is
-- why this is a scoring problem rather than a "pick the farthest one" problem:
-- distance alone puts you alone in a corner behind the enemy team, and
-- distance-plus-sightline-plus-recent-deaths puts you behind your own line.
--
-- Spawn points are CONTENT. They are SpawnLocations, or parts carrying a
-- PPSpawn attribute, inside the live arena — placed by Titus, never generated.
-- Both are accepted on purpose: SpawnLocation is what you get by dragging one
-- out of the toolbox, and PPSpawn is what you use when you want a spawn that
-- is not a glowing pad. Requiring the tag would mean a map full of perfectly
-- good SpawnLocations reports as having nowhere to spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Config = require(ReplicatedStorage.Shared.Config.SpawnConfig)

local SYSTEM = "Spawns"

export type Point = {
	instance: BasePart,
	position: Vector3,
	cframe: CFrame,
	zone: string?,
	team: string?,
}

type DeathMark = {
	position: Vector3,
	at: number,
}

local Spawns = {}

local recentDeaths: { DeathMark } = {}
local protectedUntil: { [Player]: number } = {}

-- Same accumulated clock as Health, and for the same reason: a decay window
-- measured against os.clock() cannot be advanced by a test without waiting
-- real seconds.
local clock = 0

-- Reused rather than allocated per sightline check. A 10-player lobby with 12
-- spawn points is 120 raycasts per respawn, and a fresh RaycastParams for each
-- is 120 tables of garbage at the exact moment the server is also building a
-- character.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true

-- ---------------------------------------------------------------------------
-- Finding the points
-- ---------------------------------------------------------------------------

-- The arena currently in play. A hand-built Arena always wins; the generated
-- placeholder is a fallback that MapService already warns about.
local function activeArena(): Instance?
	return workspace:FindFirstChild("Arena") or workspace:FindFirstChild("PinkPanicMap")
end

function Spawns.points(): { Point }
	local arena = activeArena()
	if not arena then
		return {}
	end

	local points: { Point } = {}
	for _, descendant in arena:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if not (descendant:IsA("SpawnLocation") or descendant:GetAttribute("PPSpawn")) then
			continue
		end

		local zone = descendant:GetAttribute("SpawnZone")
		local team = descendant:GetAttribute("SpawnTeam")
		table.insert(points, {
			instance = descendant,
			position = descendant.Position + Vector3.new(0, Config.spawnHeightOffset, 0),
			cframe = descendant.CFrame + Vector3.new(0, Config.spawnHeightOffset, 0),
			zone = if type(zone) == "string" then zone else nil,
			team = if type(team) == "string" then team else nil,
		})
	end
	return points
end

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------

type Occupant = {
	player: Player,
	position: Vector3,
	look: Vector3,
	enemy: boolean,
}

local function occupants(forPlayer: Player): { Occupant }
	local list: { Occupant } = {}
	for _, other in Players:GetPlayers() do
		if other == forPlayer then
			continue
		end
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end

		-- Neutral players are on nobody's team, so in FFA everyone is an
		-- enemy. Without this every point scores as though the map were empty
		-- and spawn selection silently stops working in the mode we ship first.
		local sameTeam = not other.Neutral
			and not forPlayer.Neutral
			and other.Team ~= nil
			and other.Team == forPlayer.Team

		table.insert(list, {
			player = other,
			position = root.Position,
			look = root.CFrame.LookVector,
			enemy = not sameTeam,
		})
	end
	return list
end

local function canSee(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	sightParams.FilterDescendantsInstances = ignore
	local direction = to - from
	-- A blocked ray means no sightline. Nil means nothing was in the way.
	return workspace:Raycast(from, direction, sightParams) == nil
end

-- Returns the score, and nil when the point is disqualified outright.
function Spawns.score(point: Point, forPlayer: Player, others: { Occupant }): number?
	local weights = Config.weights
	local score = 0

	local nearestEnemy = math.huge
	local nearestFriendly = math.huge

	local ignore: { Instance } = {}
	for _, occupant in others do
		local character = occupant.player.Character
		if character then
			table.insert(ignore, character)
		end
	end

	for _, occupant in others do
		local offset = occupant.position - point.position
		local distance = offset.Magnitude

		if occupant.enemy then
			-- The hard floor. A disqualifier rather than a large penalty,
			-- because a penalty can always be outweighed by enough of
			-- something else, and "spawned four studs from an enemy but every
			-- other point scored worse" is not a defensible outcome.
			if distance < Config.minimumEnemyDistance then
				return nil
			end
			nearestEnemy = math.min(nearestEnemy, distance)

			-- Seeing the point is far worse than being near it: 30 studs
			-- behind a wall is fine, 30 studs down an open lane is death.
			if canSee(occupant.position, point.position, ignore) then
				score += weights.visiblePenalty

				-- ...and an enemy already facing this way is about to be
				-- looking at you. Scaled by how directly, so someone with
				-- their back turned costs nothing.
				if distance > 0.01 then
					local facing = occupant.look:Dot(offset.Unit * -1)
					if facing > 0 then
						score += weights.facingPenalty * facing
					end
				end
			end
		else
			nearestFriendly = math.min(nearestFriendly, distance)
		end
	end

	if nearestEnemy < math.huge then
		score += nearestEnemy * weights.enemyDistance
	end
	if nearestFriendly < math.huge then
		-- Negative weight on distance: closer to a teammate scores higher.
		-- Capped so a teammate across the map is not treated as support.
		score += math.min(nearestFriendly, Config.friendlyDistanceCap) * weights.friendlyDistance
	end

	-- Somewhere you just died is somewhere the fight still is. Decays to
	-- nothing over the window rather than dropping off a cliff, so a point
	-- does not become good again the instant a timer expires.
	for _, mark in recentDeaths do
		local age = clock - mark.at
		if age >= Config.recentDeathSeconds then
			continue
		end
		local distance = (mark.position - point.position).Magnitude
		if distance < Config.recentDeathRadius then
			local proximity = 1 - (distance / Config.recentDeathRadius)
			local freshness = 1 - (age / Config.recentDeathSeconds)
			score += weights.recentDeathPenalty * proximity * freshness
		end
	end

	return score
end

-- ---------------------------------------------------------------------------
-- Choosing
-- ---------------------------------------------------------------------------

-- The best point for this player right now, or nil if the map has none.
--
-- Falls back to the least-bad disqualified point rather than returning nil
-- when everything is disqualified — on a small map with enough players, every
-- point can be inside the minimum enemy distance, and refusing to spawn
-- someone is worse than spawning them badly.
function Spawns.choose(player: Player): Point?
	local points = Spawns.points()
	if #points == 0 then
		return nil
	end

	local others = occupants(player)

	local best: Point? = nil
	local bestScore = -math.huge
	local fallback: Point? = nil
	local fallbackEnemyDistance = -math.huge

	for _, point in points do
		local score = Spawns.score(point, player, others)
		if score then
			if score > bestScore then
				bestScore, best = score, point
			end
		else
			-- Disqualified. Keep the one that was at least farthest from
			-- anyone, in case they all are.
			local nearest = math.huge
			for _, occupant in others do
				if occupant.enemy then
					nearest = math.min(nearest, (occupant.position - point.position).Magnitude)
				end
			end
			if nearest > fallbackEnemyDistance then
				fallbackEnemyDistance, fallback = nearest, point
			end
		end
	end

	if best then
		return best
	end

	if fallback then
		Diagnostics.count(SYSTEM, "compromised")
	end
	return fallback
end

-- ---------------------------------------------------------------------------
-- Death and respawn
-- ---------------------------------------------------------------------------

function Spawns.markDeath(position: Vector3)
	table.insert(recentDeaths, { position = position, at = clock })
end

function Spawns.isProtected(player: Player): boolean
	local until_ = protectedUntil[player]
	return until_ ~= nil and clock < until_
end

-- Called when the player fires. Spawn protection that survives your first shot
-- is a free opening trade, which is worse than no protection at all.
function Spawns.clearProtection(player: Player)
	protectedUntil[player] = nil
end

-- Places an already-spawned character at a scored point. Separate from the
-- respawn timer so the match loop (M9) can use it for the initial spawn too.
function Spawns.place(player: Player): boolean
	local point = Spawns.choose(player)
	local character = player.Character
	if not point or not character then
		return false
	end

	character:PivotTo(point.cframe)
	protectedUntil[player] = clock + Config.protectionSeconds
	Diagnostics.count(SYSTEM, "placed")
	return true
end

function Spawns.step(deltaTime: number)
	clock += deltaTime

	-- Retire death marks past the window so the list cannot grow all match.
	for index = #recentDeaths, 1, -1 do
		if clock - recentDeaths[index].at >= Config.recentDeathSeconds then
			local last = #recentDeaths
			recentDeaths[index] = recentDeaths[last]
			recentDeaths[last] = nil
		end
	end
end

function Spawns.init()
	Players.PlayerRemoving:Connect(function(player)
		protectedUntil[player] = nil
	end)

	local points = Spawns.points()
	if #points == 0 then
		Diagnostics.warn(
			SYSTEM,
			"no spawn points in the arena — add SpawnLocations or PPSpawn-tagged parts inside "
				.. "the Workspace folder named 'Arena'"
		)
		return
	end

	local zoned, teamed = 0, 0
	for _, point in points do
		if point.zone then
			zoned += 1
		end
		if point.team then
			teamed += 1
		end
	end

	Diagnostics.ok(SYSTEM, `{#points} spawn point(s) · {zoned} zoned · {teamed} team-assigned`)
end

return Spawns
