--!strict
-- WeaponService — server-side combat for the gun-roster era (NOD-109):
-- loadout slots (Primary / Secondary / Knife), stats resolved through
-- CombatStats, real mesh models via GunModelLoader (part-built fallback),
-- per-slot ammo, validated firing with pellets and melee, reloads, and
-- switching. The client only *reports* a shot; the server re-raycasts the
-- world itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunModelLoader = require(ReplicatedStorage.Shared.Assets.GunModelLoader)
local CombatService = require(script.Parent.CombatService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RoundService = require(script.Parent.RoundService)

local FIRE_RATE_TOLERANCE = 0.9
local MAX_ORIGIN_DRIFT = 8

local SLOTS = { "Primary", "Secondary", "Knife" }

type WeaponState = {
	slot: string,
	guns: { [string]: string? }, -- slot -> gunId ("Knife" for the knife)
	ammo: { [string]: number }, -- by slot
	lastShotAt: number,
	reloadingUntil: number,
	reloadToken: number,
	switchedAt: number,
	-- Armory trial: session-memory ONLY, never written to the profile, so no
	-- exploit can convert a trial into ownership. Evaporates on expiry and on
	-- every resetState (respawn / round start), which rebuilds from profile.
	trialToken: number,
}

local WeaponService = {}

local states: { [Player]: WeaponState } = {}
local rng = Random.new()

local function currentGunId(state: WeaponState): string
	return state.guns[state.slot] or "Pistol_1"
end

local function currentStats(state: WeaponState): CombatStats.Resolved
	return CombatStats.resolve(currentGunId(state))
end

-- Resolves the player's persisted loadout, validating ownership so a stale
-- profile can never spawn a gun it doesn't own.
local function resolveLoadout(player: Player): { [string]: string? }
	local data = PlayerDataService.get(player)
	local primary: string? = nil
	local secondary = "Pistol_1"
	if data then
		local wanted = data.loadout.primary
		if wanted and table.find(data.ownedGuns, wanted) then
			local def = GunCatalog.get(wanted)
			if def and def.slot == "Primary" then
				primary = wanted
			end
		end
		local wantedSecondary = data.loadout.secondary
		if wantedSecondary and table.find(data.ownedGuns, wantedSecondary) then
			local def = GunCatalog.get(wantedSecondary)
			if def and def.slot == "Secondary" then
				secondary = wantedSecondary
			end
		end
	end
	return { Primary = primary, Secondary = secondary, Knife = "Knife" }
end

local function resetState(player: Player)
	local guns = resolveLoadout(player)
	local ammo: { [string]: number } = {}
	for _, slot in SLOTS do
		local gunId = guns[slot]
		ammo[slot] = if gunId then CombatStats.resolve(gunId).magSize else 0
	end
	local previous = states[player]
	states[player] = {
		slot = if guns.Primary then "Primary" else "Secondary",
		guns = guns,
		ammo = ammo,
		lastShotAt = 0,
		reloadingUntil = 0,
		reloadToken = 0,
		switchedAt = 0,
		trialToken = if previous then previous.trialToken + 1 else 0, -- kills pending trials
	}
end


local function pushAmmo(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local stats = currentStats(state)
	Remotes.event("AmmoChanged"):FireClient(player, {
		slot = state.slot,
		gunId = currentGunId(state),
		name = stats.name,
		ammo = state.ammo[state.slot],
		magSize = stats.magSize,
		reloading = os.clock() < state.reloadingUntil,
	})
end

local function cosmeticsFor(player: Player, gunId: string): GunModelLoader.Cosmetics?
	local data = PlayerDataService.get(player)
	local entry = data and data.gunCosmetics[gunId]
	return if entry then { skinId = entry.skinId, camoId = entry.camoId } else nil
end

-- Welds the current weapon to the character's hand so other players see it.
--
-- Nobody holds a weapon in the lobby. The plaza is the social space — shop,
-- armory, loadout, standing around — and a drawn gun reads as "match in
-- progress". Every entry into a round respawns the whole roster (RoundService
-- sets state = "Active" BEFORE respawnAll, and back off it before the RoundEnd
-- respawn), so CharacterAdded re-runs this at exactly the right moments and no
-- separate hand-out step is needed.
local function attachWorldGun(player: Player, character: Model)
	task.spawn(function()
		local existing = character:FindFirstChild("WorldGun")
		if existing then
			existing:Destroy()
		end
		if RoundService.getState() ~= "Active" then
			return
		end

		local state = states[player]
		local gunId = if state then currentGunId(state) else "Pistol_1"

		local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not hand or not hand:IsA("BasePart") or not root or not root:IsA("BasePart") then
			return
		end

		local gun = GunModelLoader.build(gunId, cosmeticsFor(player, gunId))
		gun.Name = "WorldGun"
		-- Most imported models run their barrel along +Z rather than the -Z
		-- CFrame.lookAlong produces, so add the recorded yaw or the gun points
		-- back at its owner.
		local grip = CFrame.lookAlong(hand.Position, root.CFrame.LookVector)
			* GunModelLoader.forwardOffset(gun)
			* CFrame.new(0, -0.1, -0.45)
		gun:PivotTo(grip)
		local primary = gun.PrimaryPart
		if primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = hand
			weld.Parent = primary
		end
		gun.Parent = character
	end)
end

local function aliveCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return character, character:FindFirstChild("Head") :: BasePart?
end

-- Projectile ballistics (NOD-111): every bullet is simulated server-side
-- with per-gun velocity and gravity drop, stepped each Heartbeat with
-- segment raycasts. Damage uses the shared falloff curve at TRAVELED
-- distance, so a shotgun pellet 70 studs downrange is confetti.
type Projectile = {
	shooter: Player,
	character: Model,
	stats: CombatStats.Resolved,
	position: Vector3,
	velocity: Vector3,
	traveled: number,
}
local projectiles: { Projectile } = {}
local MAX_PROJECTILES = 500

type HitTotal = { damage: number, position: Vector3, weaponName: string }

local function onFireWeapon(player: Player, origin: any, direction: any)
	if RoundService.getState() ~= "Active" then
		return
	end
	if not Guard.checkRate(player, "FireWeapon", 25, 1) then
		return
	end
	if not Guard.isVector3(origin) or not Guard.isUnitVector(direction) then
		return
	end
	local state = states[player]
	if not state then
		return
	end
	local character, head = aliveCharacter(player)
	if not character or not head then
		return
	end
	if (head.Position - origin).Magnitude > MAX_ORIGIN_DRIFT then
		return
	end

	local stats = currentStats(state)
	local isMelee = stats.kind == "Melee"
	local now = os.clock()
	if now - state.switchedAt < stats.equipTime * 0.85 then
		return
	end
	if now - state.lastShotAt < (1 / stats.fireRate) * FIRE_RATE_TOLERANCE then
		return
	end
	if not isMelee then
		if now < state.reloadingUntil or state.ammo[state.slot] <= 0 then
			return
		end
	end
	state.lastShotAt = now
	if not isMelee then
		state.ammo[state.slot] -= 1
		pushAmmo(player)
	end

	if stats.kind == "Melee" then
		-- Melee stays instant: short server raycast.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(origin, direction * stats.range, params)
		Remotes.event("ShotFired"):FireAllClients(player, origin, direction, 0, 0, stats.range, 1)
		if result then
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			local victim = hitModel and Players:GetPlayerFromCharacter(hitModel)
			if victim and victim ~= player then
				local damage = math.floor(stats.damageNear + 0.5)
				local applied, killed = CombatService.applyDamage(player, victim, damage, stats.name)
				if applied then
					Remotes.event("DamageDealt"):FireClient(player, damage, result.Position, killed)
				end
			end
		end
		return
	end

	-- Spawn simulated projectiles: bullet 1 flies exactly where the client
	-- aimed; extra pellets get server-rolled spread.
	local spreadRad = math.rad(stats.spreadDeg)
	for pellet = 1, stats.pellets do
		local dir: Vector3 = direction
		if pellet > 1 then
			dir = (CFrame.lookAlong(Vector3.zero, direction) * CFrame.Angles(
				rng:NextNumber(-spreadRad, spreadRad),
				rng:NextNumber(-spreadRad, spreadRad),
				0
			)).LookVector
		end
		if #projectiles < MAX_PROJECTILES then
			table.insert(projectiles, {
				shooter = player,
				character = character,
				stats = stats,
				position = origin,
				velocity = dir * stats.velocity,
				traveled = 0,
			})
		end
	end

	-- Everyone animates the shot with real ballistics.
	Remotes.event("ShotFired"):FireAllClients(
		player, origin, direction, stats.velocity, stats.drop, stats.travelMax, stats.pellets
	)
end

-- Steps all live projectiles; accumulates damage per victim per frame so a
-- shotgun blast lands as ONE damage event, not nine hitmarkers.
local function stepProjectiles(deltaTime: number)
	if #projectiles == 0 then
		return
	end
	local frameTotals: { [Player]: { [Player]: HitTotal } } = {}

	for index = #projectiles, 1, -1 do
		local p = projectiles[index]
		p.velocity += Vector3.new(0, -p.stats.drop * deltaTime, 0)
		local step = p.velocity * deltaTime
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { p.character }
		local result = workspace:Raycast(p.position, step, params)

		if result then
			local distance = p.traveled + (result.Position - p.position).Magnitude
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			local victim = hitModel and Players:GetPlayerFromCharacter(hitModel)
			if victim and victim ~= p.shooter then
				local pelletDamage = CombatStats.pelletDamageAt(p.stats, distance)
				if result.Instance.Name == "Head" then
					pelletDamage *= p.stats.headshotMult
				end
				local byShooter = frameTotals[p.shooter]
				if not byShooter then
					byShooter = {}
					frameTotals[p.shooter] = byShooter
				end
				local total = byShooter[victim]
				if total then
					total.damage += pelletDamage
					total.position = result.Position
				else
					byShooter[victim] = {
						damage = pelletDamage,
						position = result.Position,
						weaponName = p.stats.name,
					}
				end
			end
			table.remove(projectiles, index)
		else
			p.position += step
			p.traveled += step.Magnitude
			if p.traveled >= p.stats.travelMax then
				table.remove(projectiles, index)
			end
		end
	end

	for shooter, victims in frameTotals do
		for victim, total in victims do
			local damage = math.floor(total.damage + 0.5)
			if damage <= 0 then
				continue
			end
			local applied, killed = CombatService.applyDamage(shooter, victim, damage, total.weaponName)
			if applied then
				Remotes.event("DamageDealt"):FireClient(shooter, damage, total.position, killed)
			end
		end
	end
end

local function onReloadWeapon(player: Player)
	if not Guard.checkRate(player, "ReloadWeapon", 5, 1) then
		return
	end
	local state = states[player]
	if not state then
		return
	end
	local slot = state.slot
	local stats = currentStats(state)
	if stats.kind == "Melee" or stats.magSize <= 0 then
		return
	end
	local now = os.clock()
	if state.ammo[slot] >= stats.magSize or now < state.reloadingUntil then
		return
	end

	state.reloadToken += 1
	local token = state.reloadToken
	state.reloadingUntil = now + stats.reloadSeconds
	pushAmmo(player)
	task.delay(stats.reloadSeconds, function()
		if states[player] == state and state.reloadToken == token then
			state.ammo[slot] = stats.magSize
			state.reloadingUntil = 0
			pushAmmo(player)
		end
	end)
end

local function onSelectWeapon(player: Player, slotName: any)
	if not Guard.checkRate(player, "SelectWeapon", 10, 1) then
		return
	end
	if not Guard.isString(slotName, 20) or not table.find(SLOTS, slotName) then
		return
	end
	local state = states[player]
	if not state or state.slot == slotName or not state.guns[slotName] then
		return
	end

	state.slot = slotName :: string
	state.switchedAt = os.clock()
	state.reloadToken += 1
	state.reloadingUntil = 0
	pushAmmo(player)

	local character = aliveCharacter(player)
	if character then
		attachWorldGun(player, character)
	end
end

-- GunShopService hooks: apply loadout/cosmetic changes live (lobby).
function WeaponService.refreshLoadout(player: Player)
	local character = player.Character
	resetState(player)
	if character then
		attachWorldGun(player, character)
	end
	pushAmmo(player)
end

function WeaponService.refreshCosmetics(player: Player)
	local character = player.Character
	if character then
		attachWorldGun(player, character)
	end
end

-- Armory "try it in the range": temporarily slots the gun for TRIAL_SECONDS.
-- Session state only — the profile is untouched, so no exploit can convert a
-- trial into ownership; resetState (respawn, round start, loadout equip)
-- reverts it for free, and expiry restores the owned loadout.
local TRIAL_SECONDS = 60

function WeaponService.tryGun(player: Player, gunId: string): boolean
	local def = GunCatalog.get(gunId)
	local state = states[player]
	if not def or not state then
		return false
	end

	local slot = def.slot
	state.guns[slot] = gunId
	state.ammo[slot] = CombatStats.resolve(gunId).magSize
	state.slot = slot
	state.switchedAt = os.clock()
	state.reloadToken += 1
	state.reloadingUntil = 0
	state.trialToken += 1
	local token = state.trialToken

	pushAmmo(player)
	local character = player.Character
	if character then
		attachWorldGun(player, character)
	end

	task.delay(TRIAL_SECONDS, function()
		local current = states[player]
		if current == state and current.trialToken == token then
			WeaponService.refreshLoadout(player) -- back to owned guns
		end
	end)
	return true
end

function WeaponService.init()
	GunModelLoader.normalizeAll()

	local function hookPlayer(player: Player)
		resetState(player)
		player.CharacterAdded:Connect(function(character)
			resetState(player)
			attachWorldGun(player, character)
			task.delay(1, function()
				pushAmmo(player)
			end)
		end)
		if player.Character then
			attachWorldGun(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	game:GetService("RunService").Heartbeat:Connect(stepProjectiles)

	Remotes.event("FireWeapon").OnServerEvent:Connect(onFireWeapon)
	Remotes.event("ReloadWeapon").OnServerEvent:Connect(onReloadWeapon)
	Remotes.event("SelectWeapon").OnServerEvent:Connect(onSelectWeapon)
end

return WeaponService
