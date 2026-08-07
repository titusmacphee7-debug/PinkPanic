--!strict
-- WeaponService — server-side arsenal: per-weapon ammo, firing validation,
-- pellets, melee, reload, and switching (NOD-12, NOD-14, NOD-25..27, NOD-29).
-- The client only *reports* a shot (origin + direction); the server
-- re-raycasts the world itself, so spoofed hits, wall-bangs and impossible
-- fire rates are rejected here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local WeaponModels = require(ReplicatedStorage.Shared.Assets.WeaponModels)
local WeaponCosmetics = require(ReplicatedStorage.Shared.Assets.WeaponCosmetics)
local CombatService = require(script.Parent.CombatService)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Allow slightly faster than nominal fire rate so honest clients with jitter
-- aren't rejected, without letting macros double the rate.
local FIRE_RATE_TOLERANCE = 0.9
-- Client fires from the camera; the camera sits near the head, so a reported
-- origin far from the head means teleported/spoofed shots.
local MAX_ORIGIN_DRIFT = 8

-- Everyone carries the full MVP arsenal; the loadout choice picks which one
-- you spawn holding.
local LOADOUT = GameConfig.loadout

type WeaponState = {
	current: string,
	ammo: { [string]: number },
	lastShotAt: number,
	reloadingUntil: number,
	reloadToken: number,
}

local WeaponService = {}

local states: { [Player]: WeaponState } = {}
local rng = Random.new()

local function resetState(player: Player)
	local ammo: { [string]: number } = {}
	for _, weaponId in LOADOUT do
		ammo[weaponId] = WeaponConfig[weaponId].magSize
	end

	-- Spawn holding the persisted loadout choice (NOD-28).
	local data = PlayerDataService.get(player)
	local starting = data and data.equipped.weapon
	if not starting or not table.find(LOADOUT, starting) then
		starting = "Pistol"
	end

	states[player] = {
		current = starting,
		ammo = ammo,
		lastShotAt = 0,
		reloadingUntil = 0,
		reloadToken = 0,
	}
end

local function pushAmmo(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local config = WeaponConfig[state.current]
	Remotes.event("AmmoChanged"):FireClient(player, {
		weaponId = state.current,
		ammo = state.ammo[state.current],
		magSize = config.magSize,
		reloading = os.clock() < state.reloadingUntil,
	})
end

-- Welds the current weapon to the character's hand so other players see it.
-- The owner sees their own viewmodel instead (first-person hides the body).
local function attachWorldGun(player: Player, character: Model)
	task.spawn(function()
		local state = states[player]
		local weaponId = if state then state.current else "Pistol"

		local existing = character:FindFirstChild("WorldGun")
		if existing then
			existing:Destroy()
		end

		local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not hand or not hand:IsA("BasePart") or not root or not root:IsA("BasePart") then
			return
		end

		local gun = WeaponModels.build(weaponId)
		gun.Name = "WorldGun"
		local data = PlayerDataService.get(player)
		if data then
			WeaponCosmetics.applySkin(gun, data.equipped.skins.Pistol)
			WeaponCosmetics.applyCharm(gun, data.equipped.charms.Pistol)
		end
		local grip = CFrame.lookAlong(hand.Position, root.CFrame.LookVector) * CFrame.new(0, -0.1, -0.45)
		gun:PivotTo(grip)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = gun.PrimaryPart
		weld.Part1 = hand
		weld.Parent = gun.PrimaryPart
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

local function damageAtDistance(config: WeaponConfig.WeaponStats, distance: number): number
	if distance <= config.falloffStart then
		return config.damage
	end
	local span = math.max(config.range - config.falloffStart, 1)
	local alpha = math.clamp((distance - config.falloffStart) / span, 0, 1)
	return config.damage + (config.falloffEndDamage - config.damage) * alpha
end

type HitTotal = { damage: number, position: Vector3 }

local function onFireWeapon(player: Player, origin: any, direction: any)
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

	local config = WeaponConfig[state.current]
	local isMelee = config.kind == "Melee"
	local now = os.clock()
	if now - state.lastShotAt < (1 / config.fireRate) * FIRE_RATE_TOLERANCE then
		return
	end
	if not isMelee then
		if now < state.reloadingUntil or state.ammo[state.current] <= 0 then
			return
		end
	end
	state.lastShotAt = now
	if not isMelee then
		state.ammo[state.current] -= 1
		pushAmmo(player)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	-- Pellet 1 flies exactly where the client aimed; extra pellets get
	-- server-rolled spread so clients can't choose their own pattern.
	local totals: { [Player]: HitTotal } = {}
	local firstEndpoint: Vector3? = nil
	local spreadRad = math.rad(config.spread)
	for pellet = 1, config.pellets do
		local dir: Vector3 = direction
		if pellet > 1 then
			dir = (CFrame.lookAlong(Vector3.zero, direction) * CFrame.Angles(
				rng:NextNumber(-spreadRad, spreadRad),
				rng:NextNumber(-spreadRad, spreadRad),
				0
			)).LookVector
		end

		local result = workspace:Raycast(origin, dir * config.range, params)
		local endpoint = if result then result.Position else origin + dir * config.range
		if not firstEndpoint then
			firstEndpoint = endpoint
		end
		if not result then
			continue
		end

		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
		local victim = hitModel and Players:GetPlayerFromCharacter(hitModel)
		if not victim or victim == player then
			continue
		end

		local distance = (result.Position - origin).Magnitude
		local pelletDamage = damageAtDistance(config, distance) / config.pellets
		if result.Instance.Name == "Head" then
			pelletDamage *= config.headshotMultiplier
		end
		local total = totals[victim]
		if total then
			total.damage += pelletDamage
			total.position = result.Position
		else
			totals[victim] = { damage = pelletDamage, position = result.Position }
		end
	end

	Remotes.event("ShotFired"):FireAllClients(player, origin, firstEndpoint or origin + direction * config.range)

	for victim, total in totals do
		local damage = math.floor(total.damage + 0.5)
		if damage <= 0 then
			continue
		end
		local applied, killed = CombatService.applyDamage(player, victim, damage, state.current)
		if applied then
			Remotes.event("DamageDealt"):FireClient(player, damage, total.position, killed)
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
	local weaponId = state.current
	local config = WeaponConfig[weaponId]
	if config.kind == "Melee" or config.magSize <= 0 then
		return
	end
	local now = os.clock()
	if state.ammo[weaponId] >= config.magSize or now < state.reloadingUntil then
		return
	end

	state.reloadToken += 1
	local token = state.reloadToken
	state.reloadingUntil = now + config.reloadTime
	pushAmmo(player)
	task.delay(config.reloadTime, function()
		-- A respawn (fresh state table) or a weapon switch (bumped token)
		-- cancels the pending refill.
		if states[player] == state and state.reloadToken == token then
			state.ammo[weaponId] = config.magSize
			state.reloadingUntil = 0
			pushAmmo(player)
		end
	end)
end

local function onSelectWeapon(player: Player, weaponId: any)
	if not Guard.checkRate(player, "SelectWeapon", 10, 1) then
		return
	end
	if not Guard.isString(weaponId, 30) or not table.find(LOADOUT, weaponId) then
		return
	end
	local state = states[player]
	if not state or state.current == weaponId then
		return
	end

	state.current = weaponId
	state.reloadToken += 1 -- cancels any in-flight reload
	state.reloadingUntil = 0
	pushAmmo(player)

	local character = aliveCharacter(player)
	if character then
		attachWorldGun(player, character)
	end
end

function WeaponService.init()
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

	Remotes.event("FireWeapon").OnServerEvent:Connect(onFireWeapon)
	Remotes.event("ReloadWeapon").OnServerEvent:Connect(onReloadWeapon)
	Remotes.event("SelectWeapon").OnServerEvent:Connect(onSelectWeapon)
end

return WeaponService
