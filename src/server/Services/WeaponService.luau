--!strict
-- WeaponService — server-side firing: validation, hit registration, ammo,
-- reload (NOD-12, NOD-14). The client only *reports* a shot (origin +
-- direction); the server re-raycasts the world itself, so spoofed hits,
-- wall-bangs and impossible fire rates are rejected here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local PistolModel = require(ReplicatedStorage.Shared.Assets.PistolModel)
local WeaponCosmetics = require(ReplicatedStorage.Shared.Assets.WeaponCosmetics)
local CombatService = require(script.Parent.CombatService)
local PlayerDataService = require(script.Parent.PlayerDataService)

-- Allow slightly faster than nominal fire rate so honest clients with jitter
-- aren't rejected, without letting macros double the rate.
local FIRE_RATE_TOLERANCE = 0.9
-- Client fires from the camera; the camera sits near the head, so a reported
-- origin far from the head means teleported/spoofed shots.
local MAX_ORIGIN_DRIFT = 8

type WeaponState = {
	ammo: number,
	lastShotAt: number,
	reloadingUntil: number,
}

local WeaponService = {}

local states: { [Player]: WeaponState } = {}

-- M1: everyone carries the pistol. Loadout selection replaces this in M3.
local function equippedWeaponId(_player: Player): string
	return "Pistol"
end

local function resetState(player: Player)
	local config = WeaponConfig[equippedWeaponId(player)]
	states[player] = {
		ammo = config.magSize,
		lastShotAt = 0,
		reloadingUntil = 0,
	}
end

-- Welds a pistol to the character's hand so other players see the weapon.
-- The shooter sees their own viewmodel instead (first-person hides the body).
local function attachWorldGun(player: Player, character: Model)
	task.spawn(function()
		local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not hand or not hand:IsA("BasePart") or not root or not root:IsA("BasePart") then
			return
		end
		if character:FindFirstChild("WorldGun") then
			return
		end

		local gun = PistolModel.build()
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

local function onFireWeapon(player: Player, origin: any, direction: any)
	-- Cheap rejections first: spam, malformed args, dead/absent character.
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

	local config = WeaponConfig[equippedWeaponId(player)]
	local now = os.clock()
	if now - state.lastShotAt < (1 / config.fireRate) * FIRE_RATE_TOLERANCE then
		return
	end
	if now < state.reloadingUntil or state.ammo <= 0 then
		return
	end
	state.lastShotAt = now
	state.ammo -= 1

	-- The server's own raycast is the hit decision (NOD-14): walls block it,
	-- range caps it, and the shooter's character is excluded.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, direction * config.range, params)

	-- Everyone else sees/hears the validated shot (the shooter already played
	-- their own local effects at fire time).
	local endpoint = if result then result.Position else origin + direction * config.range
	Remotes.event("ShotFired"):FireAllClients(player, origin, endpoint)

	if not result then
		return
	end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	local victim = hitModel and Players:GetPlayerFromCharacter(hitModel)
	if not victim or victim == player then
		return
	end

	local distance = (result.Position - origin).Magnitude
	local damage = damageAtDistance(config, distance)
	if result.Instance.Name == "Head" then
		damage *= config.headshotMultiplier
	end
	damage = math.floor(damage + 0.5)

	local applied, killed = CombatService.applyDamage(player, victim, damage, equippedWeaponId(player))
	if applied then
		Remotes.event("DamageDealt"):FireClient(player, damage, result.Position, killed)
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
	local config = WeaponConfig[equippedWeaponId(player)]
	local now = os.clock()
	if state.ammo >= config.magSize or now < state.reloadingUntil then
		return
	end
	state.reloadingUntil = now + config.reloadTime
	task.delay(config.reloadTime, function()
		-- Identity check: a respawn creates a fresh state table, cancelling this reload.
		if states[player] == state then
			state.ammo = config.magSize
		end
	end)
end

function WeaponService.init()
	local function hookPlayer(player: Player)
		resetState(player)
		player.CharacterAdded:Connect(function(character)
			resetState(player)
			attachWorldGun(player, character)
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
end

return WeaponService
