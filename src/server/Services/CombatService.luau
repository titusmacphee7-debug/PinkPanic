--!strict
-- CombatService — server-authoritative health, damage, death and killfeed
-- (NOD-13, NOD-15). The server owns Humanoid health; clients only display it.
-- All damage in the game flows through applyDamage so attribution and future
-- coin/score hooks live in exactly one place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local MAX_HEALTH = 100

type DamageRecord = { attacker: Player?, weaponId: string? }

local CombatService = {}

local lastDamage: { [Player]: DamageRecord } = {}

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	lastDamage[player] = {}

	humanoid.Died:Connect(function()
		local record = lastDamage[player] or {}
		Remotes.event("Killfeed"):FireAllClients({
			victim = player.Name,
			killer = if record.attacker then record.attacker.Name else nil,
			weaponId = record.weaponId,
		})
		-- M2 (NOD-21) hooks kill/score tracking here; M4 (NOD-30) hooks coins.
	end)
end

-- Applies damage from attacker to victim. Returns true if this damage killed.
function CombatService.applyDamage(attacker: Player, victim: Player, amount: number, weaponId: string): boolean
	local character = victim.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local record = lastDamage[victim]
	if record then
		record.attacker = attacker
		record.weaponId = weaponId
	end

	humanoid:TakeDamage(amount)
	return humanoid.Health <= 0
end

function CombatService.init()
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastDamage[player] = nil
	end)
end

return CombatService
