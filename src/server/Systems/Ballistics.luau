--!strict
-- Ballistics — server-simulated projectiles (NOD-133).
--
-- **The client never reports a hit.** It sends intent — "I fired, from here,
-- pointing there" — and this module decides everything that follows: whether
-- the shot was legal, where the spread put each pellet, what it crossed on the
-- way, who it hit and for how much. A modified client that claims a headshot
-- changes nothing, because nothing here reads a claim.
--
-- What this module does NOT do is apply damage. It resolves *hits*; Health
-- (NOD-134) turns hits into health loss. Keeping that seam means the thing
-- that owns "was this shot real" and the thing that owns "how much health does
-- this player have" can be reasoned about, and tested, separately.
--
-- Deliberate choices that look like details and are not:
--
--   · Spread is rolled for EVERY pellet including the first. The old build
--     skipped pellet 1 as an optimisation, which meant a client sending an
--     unrotated look vector got a pinpoint first shot out of every gun in the
--     game — the single most valuable thing a cheat could ask for, free.
--   · The projectile cap is per player. A global cap is worse than none: one
--     spammer starves everyone, and a shotgun blast silently becomes 6 pellets
--     of 10 with no error anywhere.
--   · Damage accumulates per victim per frame, so a shotgun lands as one hit
--     event rather than eight. Eight events is eight hitmarkers, eight sounds,
--     and eight chances to kill someone who was already dead after the third.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Config = require(ReplicatedStorage.Shared.Config.BallisticsConfig)

local SYSTEM = "Ballistics"

export type HitZone = "Head" | "Torso" | "Limb"

-- What Health (NOD-134) receives. One of these per victim per frame, with the
-- damage already summed and falloff already applied.
export type Hit = {
	victim: Model,
	victimPlayer: Player?,
	attacker: Player,
	weaponId: string,
	damage: number,
	zone: HitZone, -- the best zone landed this frame
	pellets: number,
	position: Vector3,
	distance: number, -- studs travelled by the pellet that landed
}

type Projectile = {
	shooter: Player,
	weaponId: string,
	stats: CombatStats.Resolved,
	origin: Vector3, -- kept for the tracer, which is drawn muzzle-to-impact
	position: Vector3,
	velocity: Vector3,
	traveled: number,
	damageScale: number, -- reduced by every surface penetrated
	lead: boolean, -- pellet 1: the one that draws the tracer
	filter: { Instance },
}

local Ballistics = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local projectiles: { Projectile } = {}
local liveByPlayer: { [Player]: number } = {}
local lastShotAt: { [Player]: number } = {}

local rng = Random.new()

-- One RaycastParams, reused. Allocating a fresh one per projectile per frame
-- is a table of garbage per bullet per frame, which at shotgun volume is the
-- difference between a flat frame time and a sawtooth.
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.IgnoreWater = true

-- Separate params for the penetration probe, because it uses Include and
-- swapping FilterType back and forth on one object is how you end up
-- accidentally casting against the wrong set.
local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Include
probeParams.IgnoreWater = true

-- Set by Health in NOD-134. Until then hits are resolved and counted but
-- nothing applies them, and the manifest says so rather than letting "combat
-- does nothing" look like a ballistics failure.
local hitHandler: ((Hit) -> ())? = nil

function Ballistics.setHitHandler(handler: (Hit) -> ())
	hitHandler = handler
	-- Clears init's warning. Health registers a moment AFTER this system's
	-- init runs, so the warning is true when it is written and stale by the
	-- time the manifest prints. A manifest that reports a resolved problem is
	-- the same failure as one that hides a real one — both teach you to stop
	-- reading it.
	Diagnostics.ok(SYSTEM, "simulating, damage handler attached")
end

-- ---------------------------------------------------------------------------
-- Geometry helpers
-- ---------------------------------------------------------------------------

-- A random direction inside a cone of half-angle `spreadDeg` around `direction`.
--
-- Uniform over the cone's AREA, not over the angle: sampling the angle linearly
-- clusters shots at the centre and makes a 5° cone behave like a 3° one. The
-- sqrt is what fixes that, and it is the difference between spread that matches
-- its number on paper and spread that quietly shoots tighter than advertised.
local function spreadDirection(direction: Vector3, spreadDeg: number): Vector3
	if spreadDeg <= 0 then
		return direction
	end

	-- Any vector not parallel to the aim works as a seed for the basis. Y is
	-- the natural choice; straight up or down is the one case it fails, and
	-- that case is real (shooting at your own feet).
	local seed = if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = direction:Cross(seed).Unit
	local up = right:Cross(direction).Unit

	local theta = math.rad(spreadDeg) * math.sqrt(rng:NextNumber())
	local phi = rng:NextNumber() * math.pi * 2
	local offset = math.tan(theta)

	return (direction + right * (offset * math.cos(phi)) + up * (offset * math.sin(phi))).Unit
end

local function characterOf(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- The zone a part represents. An explicit `PPHitZone` attribute always wins —
-- that is what NOD-134's normalized hit volume will carry, and tagged content
-- beats inference everywhere else in this project too. The rig-name table
-- below is not a guess about our own content: it reads Roblox's own R6/R15
-- part names, which is what a Studio playtest spawns with before the hit
-- volume exists.
local function zoneOf(part: BasePart): HitZone
	local tagged = part:GetAttribute("PPHitZone")
	if tagged == "Head" or tagged == "Torso" or tagged == "Limb" then
		return tagged :: HitZone
	end
	local mapped = Config.rigZones[part.Name]
	if mapped == "Head" or mapped == "Torso" then
		return mapped :: HitZone
	end
	return "Limb"
end

local ZONE_RANK: { [string]: number } = { Limb = 1, Torso = 2, Head = 3 }

-- Where a bullet leaves a part it entered, or nil when the part is thicker
-- than the material allows.
--
-- Probing backwards from a point past the far face is the only reliable way to
-- get an exit: Roblox raycasts do not register a hit when they start inside
-- geometry, so casting forward from the entry point finds nothing. That same
-- property is what makes "no result" mean "too thick" — the probe started
-- inside the part, which is exactly the case we want to stop.
local function exitPoint(part: BasePart, entry: Vector3, direction: Vector3, maxThickness: number): Vector3?
	local reach = maxThickness + 0.05
	probeParams.FilterDescendantsInstances = { part }
	local back = workspace:Raycast(entry + direction * reach, -direction * reach, probeParams)
	return if back then back.Position else nil
end

-- ---------------------------------------------------------------------------
-- Firing
-- ---------------------------------------------------------------------------

local function removeAt(index: number)
	local projectile = projectiles[index]
	local shooter = projectile.shooter
	liveByPlayer[shooter] = math.max((liveByPlayer[shooter] or 1) - 1, 0)

	-- Swap-remove. table.remove from the middle shifts every element after it,
	-- which under shotgun spam is O(n²) per frame over a list that is mostly
	-- being removed from the middle.
	local last = #projectiles
	projectiles[index] = projectiles[last]
	projectiles[last] = nil
end

-- Validates and spawns one shot's worth of projectiles. Returns false (and the
-- reason) when the shot is rejected, so callers and tests can see WHY rather
-- than watching nothing happen.
function Ballistics.fire(shooter: Player, weaponId: string, origin: Vector3, direction: Vector3): (boolean, string?)
	local stats = CombatStats.forGun(weaponId)
	if not stats then
		return false, `unknown weapon "{weaponId}"`
	end

	local character = shooter.Character
	local head = character and character:FindFirstChild("Head")
	if not character or not head or not head:IsA("BasePart") then
		return false, "no character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "dead"
	end

	-- Origin must be somewhere the player's head actually is. Without this the
	-- client picks its own muzzle position and can fire from anywhere on the
	-- map, which no amount of downstream validation recovers from.
	if (origin - head.Position).Magnitude > Config.maxOriginOffsetStuds then
		return false, "origin too far from head"
	end

	-- ...and there must be nothing between the head and that origin. A muzzle
	-- three studs ahead is legitimate standing in the open and is a wallhack
	-- standing behind cover: it puts the bullet's start point on the far side
	-- of the wall the shooter is hiding behind.
	if Config.validateOriginSightline then
		castParams.FilterDescendantsInstances = { character }
		local blocked = workspace:Raycast(head.Position, origin - head.Position, castParams)
		if blocked then
			return false, "origin is through geometry"
		end
	end

	-- The gun's own fire rate is the rate limit. A generic per-remote limit
	-- cannot know that an LMG may fire eight times a second and a sniper may
	-- not, so it has to be set loose enough for the fastest gun — which leaves
	-- every other gun unguarded.
	local now = os.clock()
	local minInterval = (1 / stats.fireRate) * (1 - Config.fireRateTolerance)
	local previous = lastShotAt[shooter]
	if previous and now - previous < minInterval then
		return false, "faster than the weapon's fire rate"
	end
	lastShotAt[shooter] = now

	local live = liveByPlayer[shooter] or 0
	local budget = Config.maxProjectilesPerPlayer - live
	if budget <= 0 then
		return false, "projectile budget exhausted"
	end

	local pellets = math.min(stats.pellets, budget)
	local spread = stats.spreadDeg
	local filter = { character }

	for index = 1, pellets do
		-- Every pellet, including the first. See the header.
		local aim = spreadDirection(direction, spread)
		table.insert(projectiles, {
			shooter = shooter,
			weaponId = weaponId,
			stats = stats,
			origin = origin,
			position = origin,
			velocity = aim * stats.velocity,
			traveled = 0,
			damageScale = 1,
			lead = index == 1,
			filter = filter,
		})
	end
	liveByPlayer[shooter] = live + pellets

	for _, listener in fireListeners do
		local ok = pcall(listener, shooter)
		if not ok then
			Diagnostics.count(SYSTEM, "fireListenerErrors")
		end
	end

	Diagnostics.count(SYSTEM, "shots")
	return true
end

-- ---------------------------------------------------------------------------
-- Stepping
-- ---------------------------------------------------------------------------

type Pending = {
	victim: Model,
	victimPlayer: Player?,
	attacker: Player,
	weaponId: string,
	damage: number,
	zone: HitZone,
	pellets: number,
	position: Vector3,
	distance: number,
}

-- Rebuilt each frame rather than allocated per hit. Keyed by attacker AND
-- victim: two players shooting the same target in one frame are two hits, not
-- one from whoever happened to resolve first.
local pending: { [string]: Pending } = {}
local pendingOrder: { string } = {}

local function accumulate(
	projectile: Projectile,
	victim: Model,
	zone: HitZone,
	damage: number,
	position: Vector3
)
	local key = `{projectile.shooter.UserId}|{victim:GetFullName()}`
	local entry = pending[key]

	if not entry then
		pending[key] = {
			victim = victim,
			victimPlayer = Players:GetPlayerFromCharacter(victim),
			attacker = projectile.shooter,
			weaponId = projectile.weaponId,
			damage = damage,
			zone = zone,
			pellets = 1,
			position = position,
			distance = projectile.traveled,
		}
		table.insert(pendingOrder, key)
		return
	end

	entry.damage += damage
	entry.pellets += 1
	-- Report the best zone landed. A shotgun that puts one pellet in the head
	-- and five in the chest is a headshot as far as the killfeed is concerned,
	-- which is both what players expect and what the damage already reflects.
	if ZONE_RANK[zone] > ZONE_RANK[entry.zone] then
		entry.zone = zone
		entry.position = position
	end
end

local function flush()
	local handler = hitHandler
	for _, key in pendingOrder do
		local entry = pending[key]
		Diagnostics.count(SYSTEM, "hits")
		if handler then
			handler(entry :: any)
		end
	end
	table.clear(pending)
	table.clear(pendingOrder)
end

-- Advances one projectile by one segment. Returns false when it is finished.
local function stepProjectile(projectile: Projectile, deltaTime: number): boolean
	local stats = projectile.stats

	-- `drop` is the gun's own downward acceleration in studs/s², applied
	-- directly. It is not a multiplier on world gravity — see the note at the
	-- top of BallisticsConfig for why that distinction cost a debugging pass.
	if stats.drop > 0 then
		projectile.velocity += Vector3.new(0, -stats.drop * deltaTime, 0)
	end

	local segment = projectile.velocity * deltaTime
	local length = segment.Magnitude
	if length > Config.maxSegmentStuds then
		segment = segment.Unit * Config.maxSegmentStuds
		length = Config.maxSegmentStuds
	end
	if length <= 0 then
		return false
	end

	local direction = segment.Unit
	local remaining = length
	local from = projectile.position

	for _ = 1, Config.maxPenetrationsPerBullet + 1 do
		castParams.FilterDescendantsInstances = projectile.filter
		local result = workspace:Raycast(from, direction * remaining, castParams)

		if not result then
			projectile.position = from + direction * remaining
			projectile.traveled += remaining
			return projectile.traveled < stats.travelMax
		end

		local travelledToHit = (result.Position - from).Magnitude
		projectile.traveled += travelledToHit
		projectile.position = result.Position

		if projectile.traveled >= stats.travelMax then
			return false
		end

		local part = result.Instance
		local victim = characterOf(part)

		if victim then
			-- The shooter's own character is already filtered out, so anything
			-- with a Humanoid here is somebody else.
			local zone = if part:IsA("BasePart") then zoneOf(part) else "Limb"
			local base = CombatStats.pelletDamageAt(stats, projectile.traveled)
			local multiplier = if zone == "Head"
				then stats.headshotMult
				elseif zone == "Limb" then Config.limbMult
				else 1
			accumulate(projectile, victim, zone, base * multiplier * projectile.damageScale, result.Position)
			return false
		end

		-- World geometry. Penetrable materials cost damage and continue;
		-- anything unlisted stops the bullet, which is the safe default —
		-- a material nobody thought about must never be see-through.
		local rule = Config.penetration[result.Material]
		if not rule or not part:IsA("BasePart") then
			return false
		end

		local exit = exitPoint(part, result.Position, direction, rule.maxThickness)
		if not exit then
			return false -- thicker than this material allows
		end

		local crossed = (exit - result.Position).Magnitude
		remaining -= travelledToHit + crossed
		if remaining <= 0 then
			projectile.position = exit
			projectile.traveled += crossed
			return projectile.traveled < stats.travelMax
		end

		projectile.damageScale *= rule.damageMult
		projectile.traveled += crossed
		projectile.position = exit
		from = exit + direction * 0.01
	end

	return true
end

-- Public, and deliberately so. `init` binds this to Heartbeat, but a simulation
-- only reachable through Heartbeat can only be tested by waiting real seconds
-- and hoping the frame rate cooperates. Driven directly it is deterministic:
-- the same shot advanced by the same dt lands in the same place every time,
-- which is the difference between a test that proves something and a test that
-- usually passes.
function Ballistics.step(deltaTime: number)
	-- Clamped so a server hitch cannot teleport every bullet through the walls
	-- it should have stopped at.
	local dt = math.min(deltaTime, Config.maxStepSeconds)

	-- Backwards, because removal swaps the last element into the current slot:
	-- iterating forwards would skip whatever got swapped in.
	for index = #projectiles, 1, -1 do
		local projectile = projectiles[index]
		local alive = stepProjectile(projectile, dt)
		if not alive then
			if projectile.lead then
				-- One tracer per shot, not one per pellet. Eight tracers from a
				-- shotgun is visual noise and eight times the network traffic
				-- for a worse-looking result.
				Remotes.fireAllClients("ShotFired", projectile.shooter, projectile.origin, projectile.position)
			end
			removeAt(index)
		end
	end

	flush()
end

-- ---------------------------------------------------------------------------
-- Remote
-- ---------------------------------------------------------------------------

-- The weapon is read from the SERVER's copy of the loadout, never from the
-- request. A client that could name its own weapon could name the one with the
-- best stats regardless of what it owns or holds.
local resolveWeapon: ((Player) -> string?)? = nil

function Ballistics.setWeaponResolver(resolver: (Player) -> string?)
	resolveWeapon = resolver
end

-- Notified on every accepted shot. Spawn protection uses this to end the
-- moment you fire: protection that survives your first shot is a free opening
-- trade, which is worse than no protection at all.
local fireListeners: { (Player) -> () } = {}

function Ballistics.onFire(listener: (Player) -> ())
	table.insert(fireListeners, listener)
end

local function onFireWeapon(player: Player, origin: any, direction: any)
	-- A coarse ceiling above any legitimate fire rate, purely to stop a flood
	-- of malformed calls reaching the real validation. The per-gun rate check
	-- inside fire() is the one that matters.
	if not Guard.checkRate(player, "FireWeapon", 30, 1) then
		return
	end
	if not Guard.isVector3(origin) or not Guard.isUnitVector(direction) then
		return
	end

	local resolver = resolveWeapon
	local weaponId = if resolver then resolver(player) else nil
	if not weaponId then
		return
	end

	Ballistics.fire(player, weaponId, origin, direction)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function Ballistics.liveCount(): number
	return #projectiles
end

function Ballistics.init()
	Remotes.handleEvent("FireWeapon", onFireWeapon)
	RunService.Heartbeat:Connect(Ballistics.step)

	Players.PlayerRemoving:Connect(function(player)
		liveByPlayer[player] = nil
		lastShotAt[player] = nil
		for index = #projectiles, 1, -1 do
			if projectiles[index].shooter == player then
				removeAt(index)
			end
		end
	end)

	if not hitHandler then
		-- Not a failure — Health is NOD-134 and lands next. Saying so keeps
		-- "shots resolve but nobody loses health" from reading as a ballistics
		-- bug, which is exactly the kind of misattribution this manifest exists
		-- to prevent.
		Diagnostics.warn(SYSTEM, "simulating, but no damage handler yet — Health (NOD-134) has not landed")
		return
	end

	Diagnostics.ok(SYSTEM, "simulating")
end

return Ballistics
