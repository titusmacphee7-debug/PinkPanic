--!strict
-- RoundService — the FFA round loop (NOD-19, NOD-21, NOD-22, NOD-24).
-- Waiting → Intermission → Active → RoundEnd → repeat. Kills only count while
-- Active; the round ends on score target or timer; late joiners are slotted
-- into the current state; leavers are cleaned out of the scoreboard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
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

-- Rounds NEVER start on their own. Two conditions, everywhere including
-- Studio: enough players, and someone pressed START GAME. No timer, no pad,
-- no solo exception — walking somewhere can't drop you into a match.
local function enoughPlayers(): boolean
	return #Players:GetPlayers() >= GameConfig.minPlayers
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

-- Set only by the START GAME button (client -> EnterPortal). Cleared as soon
-- as the round leaves Waiting, so one press buys exactly one round.
local startRequested = false

local function runLoop()
	while true do
		-- Waiting: hold here until there are enough players AND someone has
		-- pressed START GAME. Both, always.
		state = "Waiting"
		endsAt = 0
		startRequested = false
		broadcast()
		while not (enoughPlayers() and startRequested) do
			task.wait(1)
		end
		startRequested = false

		-- Intermission: countdown to the round.
		state = "Intermission"
		endsAt = now() + GameConfig.intermissionSeconds
		broadcast()
		task.wait(GameConfig.intermissionSeconds)
		if not enoughPlayers() then
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

	-- The START GAME button — the only way a round ever begins. Ignored unless
	-- we're actually waiting, so a press mid-round can't queue the next one.
	Remotes.event("EnterPortal").OnServerEvent:Connect(function(player)
		if not Guard.checkRate(player, "EnterPortal", 2, 1) then
			return
		end
		if state ~= "Waiting" or not enoughPlayers() then
			return
		end
		startRequested = true
	end)

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
