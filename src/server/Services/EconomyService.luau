--!strict
-- EconomyService — coins and XP, fully server-authoritative (NOD-30, NOD-31).
-- Kills and round results are the only mints; the client can't request
-- currency at all, it only receives DataChanged snapshots to display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EconomyService = {}

-- Sends the client everything it needs to render coins, level bar, and shop
-- ownership/equip state. Public so ShopService can push after purchases.
function EconomyService.push(player: Player)
	local data = PlayerDataService.get(player)
	if not data then
		return
	end
	Remotes.fireClient("DataChanged", player, {
		coins = data.coins,
		xp = data.xp,
		level = data.level,
		xpToNext = EconomyConfig.xpRequired(data.level),
		ownedSkins = data.ownedSkins,
		ownedCharms = data.ownedCharms,
		equipped = data.equipped,
		settings = data.settings,
		ownedGuns = data.ownedGuns,
		ownedGunSkins = data.ownedGunSkins,
		ownedCamos = data.ownedCamos,
		loadout = data.loadout,
		gunCosmetics = data.gunCosmetics,
	})
end

local push = EconomyService.push

local function grant(player: Player, coins: number, xp: number)
	local changed = PlayerDataService.update(player, function(data)
		data.coins += coins
		data.xp += xp
		while data.xp >= EconomyConfig.xpRequired(data.level) do
			data.xp -= EconomyConfig.xpRequired(data.level)
			data.level += 1
		end
	end)
	if changed then
		push(player)
	end
end

-- Payout seams for the rebuilt game loop.
--
-- These used to be wired straight into CombatService.onDeathConnect and
-- RoundService.onRoundEnd. Both of those were deleted with the combat rewrite,
-- so the hooks are public now and the new loop calls them directly. The rules
-- themselves (coins, XP, level-ups, K/D, rounds played/won) are unchanged and
-- still the ONLY way currency is minted — the client cannot request it.
function EconomyService.awardKill(victim: Player, attacker: Player?, _weaponId: string?)
	PlayerDataService.update(victim, function(data)
		data.stats.deaths += 1
	end)
	if attacker and attacker ~= victim then
		PlayerDataService.update(attacker, function(data)
			data.stats.kills += 1
		end)
		grant(attacker, EconomyConfig.coinsPerKill, EconomyConfig.xpPerKill)
	end
end

function EconomyService.awardRoundEnd(finalScores: { any }, winnerName: string?)
	for _, row in finalScores do
		local player = Players:GetPlayerByUserId(row.userId)
		if not player then
			continue
		end
		local won = row.name == winnerName
		PlayerDataService.update(player, function(data)
			data.stats.roundsPlayed += 1
			if won then
				data.stats.roundsWon += 1
			end
		end)
		grant(
			player,
			EconomyConfig.coinsRoundPlayed + (if won then EconomyConfig.coinsRoundWin else 0),
			EconomyConfig.xpRoundPlayed + (if won then EconomyConfig.xpRoundWin else 0)
		)
	end
end

-- Profiles load asynchronously; poll briefly so the HUD gets its first
-- snapshot soon after join.
local function pushWhenLoaded(player: Player)
	task.spawn(function()
		for _ = 1, 60 do
			if player.Parent ~= Players then
				return
			end
			local data = PlayerDataService.get(player)
			if data then
				-- New-player onboarding (NOD-43): starter coins, exactly once.
				if not data.onboarded then
					PlayerDataService.update(player, function(profile)
						profile.onboarded = true
						profile.coins += 100
					end)
				end
				push(player)
				return
			end
			task.wait(0.5)
		end
	end)
end

function EconomyService.init()
	Players.PlayerAdded:Connect(pushWhenLoaded)
	for _, player in Players:GetPlayers() do
		pushWhenLoaded(player)
	end
end

return EconomyService
