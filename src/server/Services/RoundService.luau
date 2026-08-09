--!strict
-- RoundService — the FFA round loop (NOD-19, NOD-21, NOD-22, NOD-24).
-- Waiting → Intermission → Active → RoundEnd → repeat. Kills only count while
-- Active; the round ends on score target or timer; late joiners are slotted
-- into the current state; leavers are cleaned out of the scoreboard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CombatService = require(script.Parent.CombatService)
local LobbyService = require(script.Parent.LobbyService)

type Score = { kills: number, deaths: number }

local RoundService = {}

-- EconomyService assigns this to pay out round rewards (finalScores, winnerName).
RoundService.onRoundEnd = nil :: (({ any }, string?) -> ())?

local state = "Waiting"
local endsAt = 0
local scores: { [Player]: Score } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Solo Studio playtests still cycle rounds (lobby -> arena -> lobby);
-- real servers keep the configured minimum.
local function minPlayers(): number
	return if RunService:IsStudio() then 1 else GameConfig.minPlayers
end

-- Combat gating (WeaponService): real shots only land during a live round.
function RoundService.getState(): string
	return state
end

local function respawnAll()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

local function serializeScores(): { any }
	local rows = {}
	for player, score in scores do
		table.insert(rows, {
			name = player.Name,
			userId = player.UserId,
			kills = score.kills,
			deaths = score.deaths,
		})
	end
	table.sort(rows, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.deaths < b.deaths
	end)
	return rows
end

local function payload(extra: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = {
		state = state,
		endsAt = endsAt,
		scoreTarget = GameConfig.scoreTarget,
		scores = serializeScores(),
	}
	if extra then
		for key, value in extra do
			data[key] = value
		end
	end
	return data
end

local function broadcast(extra: { [string]: any }?)
	Remotes.event("RoundStateChanged"):FireAllClients(payload(extra))
end

local function topEntry(): any?
	local rows = serializeScores()
	return rows[1]
end

local function onDeath(victim: Player, attacker: Player?, _weaponId: string?)
	if state ~= "Active" then
		return
	end
	local victimScore = scores[victim]
	if victimScore then
		victimScore.deaths += 1
	end
	if attacker and attacker ~= victim then
		local attackerScore = scores[attacker]
		if attackerScore then
			attackerScore.kills += 1
		end
	end
	Remotes.event("ScoreUpdated"):FireAllClients(serializeScores())
end

local function runLoop()
	while true do
		-- Waiting: not enough players for a match.
		state = "Waiting"
		endsAt = 0
		broadcast()
		while #Players:GetPlayers() < minPlayers() do
			task.wait(1)
		end

		-- Intermission: countdown to the round.
		state = "Intermission"
		endsAt = now() + GameConfig.intermissionSeconds
		broadcast()
		task.wait(GameConfig.intermissionSeconds)
		if #Players:GetPlayers() < minPlayers() then
			continue -- someone left during the countdown; back to Waiting
		end

		-- Active: fresh scores, fresh characters, fight.
		scores = {}
		for _, player in Players:GetPlayers() do
			scores[player] = { kills = 0, deaths = 0 }
		end
		state = "Active"
		endsAt = now() + GameConfig.roundSeconds
		broadcast()
		LobbyService.setArenaActive(true)
		respawnAll()
		while now() < endsAt do
			local top = topEntry()
			if top and top.kills >= GameConfig.scoreTarget then
				break
			end
			task.wait(0.5)
		end

		-- RoundEnd: results screen, payouts, then loop.
		state = "RoundEnd"
		endsAt = now() + GameConfig.roundEndSeconds
		local winner = topEntry()
		local winnerName = if winner then winner.name else nil
		local onRoundEnd = RoundService.onRoundEnd
		if onRoundEnd then
			task.spawn(onRoundEnd, serializeScores(), winnerName)
		end
		broadcast({ winner = winnerName })
		-- Everyone back to the plaza for the results + intermission.
		LobbyService.setArenaActive(false)
		respawnAll()
		task.wait(GameConfig.roundEndSeconds)
	end
end

function RoundService.init()
	CombatService.onDeathConnect(onDeath)

	Players.PlayerAdded:Connect(function(player)
		if state == "Active" then
			scores[player] = { kills = 0, deaths = 0 }
		end
		-- Late joiner: tell them the current state once their client is up.
		task.delay(3, function()
			if player.Parent == Players then
				Remotes.event("RoundStateChanged"):FireClient(player, payload())
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		scores[player] = nil
	end)

	task.spawn(runLoop)
end

return RoundService
