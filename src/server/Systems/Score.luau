--!strict
-- Score — the single authority for what a kill is worth (NOD-138).
--
-- Health says who died and who did it. This says what that was worth, in three
-- separate ledgers that are deliberately not the same number:
--
--   STREAK SCORE  resets on death. This is scorestreak progress (M7), and the
--                 reason it resets is the entire reason streaks are exciting.
--   MATCH SCORE   resets at match start. The leaderboard.
--   XP / COINS    never reset. Levels and cosmetics, paid out through
--                 EconomyService, which remains the only thing that touches a
--                 profile.
--
-- **Nothing in this file can be reached from the client.** There is no remote
-- handler here, only two broadcasts out. Score arrives as a consequence of a
-- kill the server itself resolved, and there is no request a modified client
-- could send that would mint any of it.
--
-- The payout is a SEAM rather than a require. A System reaching into a Service
-- is the dependency direction backwards (rule 3), and this one would drag the
-- whole DataStore layer in behind it — so init.server injects it, the same way
-- WeaponService gets its loadout resolver.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Config = require(ReplicatedStorage.Shared.Config.ScoreConfig)
local Health = require(script.Parent.Health)

local SYSTEM = "Score"

export type Ledger = {
	-- Toward the next scorestreak. Gone the moment you die.
	streakScore: number,
	-- The leaderboard. Survives death, resets with the match.
	matchScore: number,
	kills: number,
	deaths: number,
	assists: number,
	-- Consecutive kills without dying.
	streak: number,
	bestStreak: number,
	-- How far up the milestone list this life has already been paid, so a
	-- streak that passes 3 and then 5 is paid for each exactly once.
	milestoneIndex: number,
}

local Score = {}

local ledgers: { [Player]: Ledger } = {}
local firstBloodTaken = false

-- Injected. Until it is, score still accrues and the HUD still updates — only
-- the profile write is missing, which is much better than the reverse.
local payout: ((player: Player, xp: number, coins: number) -> ())? = nil
local killEffectResolver: ((player: Player) -> string?)? = nil

-- Same accumulated clock the rest of combat runs on, for the rate guard below.
local clock = 0
local windowStart = 0
local windowEvents = 0

local function blank(): Ledger
	return {
		streakScore = 0,
		matchScore = 0,
		kills = 0,
		deaths = 0,
		assists = 0,
		streak = 0,
		bestStreak = 0,
		milestoneIndex = 0,
	}
end

local function ledgerFor(player: Player): Ledger
	local existing = ledgers[player]
	if existing then
		return existing
	end
	local fresh = blank()
	ledgers[player] = fresh
	return fresh
end

-- ---------------------------------------------------------------------------
-- Awarding
-- ---------------------------------------------------------------------------

function Score.setPayout(fn: (player: Player, xp: number, coins: number) -> ())
	payout = fn
end

-- The equipped kill effect, resolved SERVER-side from the killer's profile.
--
-- A cosmetic is the one kind of thing a client could plausibly be trusted to
-- report about itself, and that is exactly the argument that ends with players
-- wearing items they never bought. The id crosses the wire only after the
-- server has looked it up and confirmed ownership; a client that sends one is
-- sending it to nobody, because there is no remote here that reads one.
function Score.setKillEffectResolver(fn: (player: Player) -> string?)
	killEffectResolver = fn
end

local function killEffectFor(player: Player?): string?
	if not player or not killEffectResolver then
		return nil
	end
	local ok, id = pcall(killEffectResolver, player)
	if not ok then
		Diagnostics.warn(SYSTEM, `kill effect resolver errored — {id}`)
		return nil
	end
	return if type(id) == "string" then id else nil
end

-- The one mint. Every award in the game goes through here, which is what makes
-- the events-per-minute guard below meaningful: a double-award anywhere is a
-- doubled count here.
function Score.award(player: Player, label: string, award: Config.Award, multiplier: number?)
	local scale = multiplier or 1
	local score = math.floor(award.score * scale + 0.5)
	local xp = math.floor(award.xp * scale + 0.5)
	local coins = math.floor(award.coins * scale + 0.5)

	local ledger = ledgerFor(player)
	ledger.streakScore += score
	ledger.matchScore += score

	if payout and (xp > 0 or coins > 0) then
		local ok, err = pcall(payout, player, xp, coins)
		if not ok then
			Diagnostics.warn(SYSTEM, `payout failed for {player.Name} — {err}`)
		end
	end

	windowEvents += 1
	Diagnostics.count(SYSTEM, "events")
	Diagnostics.count(SYSTEM, "score", score)

	-- Named, so the HUD can say what it was for. "+100" tells you nothing you
	-- did not already know; "+100 HEADSHOT" is the game teaching you something.
	Remotes.fireClient("ScoreEvent", player, label, score, xp, coins, ledger.streak)
end

-- ---------------------------------------------------------------------------
-- Kills
-- ---------------------------------------------------------------------------

-- Distance past which a shot with this gun counts as a longshot. Derived from
-- the gun's own rangeNear — the distance its damage starts dropping — so a
-- sniper does not collect a permanent bonus for shooting at ranges it was
-- built for, and a shotgun is not shut out of the bonus entirely.
--
-- Read from the BASE gun rather than the killer's attachments: a barrel that
-- extends rangeNear would otherwise RAISE its owner's longshot threshold, and
-- being paid less for the same shot because you spent money on the gun is the
-- wrong lesson.
local function longshotThreshold(weaponId: string?): number?
	if not weaponId then
		return nil
	end
	local stats = CombatStats.forGun(weaponId)
	if not stats then
		return nil
	end
	return stats.rangeNear * Config.longshotMultiplier
end

-- Was the victim mid-fight with somebody else when they died?
local function wasSaviour(victim: Player?, killer: Player): boolean
	if not victim or victim == killer then
		return false
	end
	local dealt = Health.lastDealt(victim)
	if not dealt then
		return false
	end
	return Health.now() - dealt <= Config.saviourWindowSeconds
end

local function payMilestones(player: Player, ledger: Ledger)
	for index, milestone in Config.streakMilestones do
		if index <= ledger.milestoneIndex then
			continue
		end
		if ledger.streak < milestone.kills then
			break -- the list is sorted; nothing after this qualifies either
		end
		ledger.milestoneIndex = index
		Score.award(player, string.upper(milestone.name), milestone.award)
	end
end

local function creditKiller(kill: Health.Kill, killer: Player)
	local ledger = ledgerFor(killer)
	ledger.kills += 1
	ledger.streak += 1
	if ledger.streak > ledger.bestStreak then
		ledger.bestStreak = ledger.streak
	end

	Score.award(killer, "KILL", Config.events.kill)

	if kill.zone == "Head" then
		Score.award(killer, "HEADSHOT", Config.events.headshotBonus)
	end

	local threshold = longshotThreshold(kill.weaponId)
	if threshold and kill.distance and kill.distance >= threshold then
		Score.award(killer, "LONGSHOT", Config.events.longshotBonus)
	end

	if wasSaviour(kill.victimPlayer, killer) then
		Score.award(killer, "SAVIOUR", Config.events.saviourBonus)
	end

	if not firstBloodTaken then
		firstBloodTaken = true
		Score.award(killer, "FIRST BLOOD", Config.events.firstBlood)
	end

	-- Ending someone's run, priced by how long the run was. Read BEFORE the
	-- victim's ledger is reset below, which is the whole reason the order in
	-- recordKill is killer-first.
	local victim = kill.victimPlayer
	if victim then
		local victimLedger = ledgers[victim]
		if victimLedger and victimLedger.streak >= Config.shutdownMinimumStreak then
			local over = victimLedger.streak - Config.shutdownMinimumStreak
			local multiplier = math.min(Config.shutdownMaxMultiplier, 1 + over * Config.shutdownPerKill)
			Score.award(killer, "SHUTDOWN", Config.events.shutdown, multiplier)
		end
	end

	payMilestones(killer, ledger)
end

local function creditAssists(kill: Health.Kill, killer: Player?)
	for _, assist in kill.assists do
		if assist.player == killer or assist.player.Parent ~= Players then
			continue
		end
		-- The threshold lives here, not in Health. Health's job is to say what
		-- happened; whether 12 damage was worth crediting is a scoring rule.
		if assist.damage < Config.assistMinimumDamage then
			continue
		end
		local ledger = ledgerFor(assist.player)
		ledger.assists += 1
		Score.award(assist.player, "ASSIST", Config.events.assist)
	end
end

-- The kill listener. Public so a test can drive it without staging a shooting.
function Score.recordKill(kill: Health.Kill)
	local killer = kill.killer
	if killer and killer.Parent == Players then
		creditKiller(kill, killer)
	end

	creditAssists(kill, killer)

	local victim = kill.victimPlayer
	if victim then
		local ledger = ledgerFor(victim)
		ledger.deaths += 1
		-- Streak progress is gone. The leaderboard score is not: losing points
		-- for dying makes the player already having a bad time have a worse
		-- one, and Config.events.death is zero for the same reason.
		ledger.streakScore = 0
		ledger.streak = 0
		ledger.milestoneIndex = 0
	end

	-- Names, not players. A player who leaves in the second between the shot
	-- landing and this line would otherwise arrive at the killfeed as nil.
	--
	-- One table rather than four positional arguments, because `killer` is
	-- legitimately absent (fall damage, a scorestreak) and a nil in the middle
	-- of a remote's argument list is the kind of thing that works until it
	-- doesn't. A field that is simply missing cannot shift anything.
	-- Where the kill effect plays. The victim's root, read now rather than
	-- sent as a character reference: five seconds from now that character is
	-- gone and the position would resolve to nothing.
	local root = kill.victim:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else nil

	Remotes.fireAllClients("Killfeed", {
		killer = if killer then killer.Name else nil,
		victim = if victim then victim.Name else kill.victim.Name,
		weaponId = kill.weaponId,
		headshot = kill.zone == "Head",
		effect = killEffectFor(killer),
		at = at,
	})

	Diagnostics.count(SYSTEM, "kills")
end

-- ---------------------------------------------------------------------------
-- Reading and resetting
-- ---------------------------------------------------------------------------

function Score.ledger(player: Player): Ledger
	return ledgerFor(player)
end

function Score.streakOf(player: Player): number
	local ledger = ledgers[player]
	return if ledger then ledger.streak else 0
end

-- Match start (M2). Everything resets except the profile, which never does.
function Score.resetMatch()
	for player in ledgers do
		ledgers[player] = blank()
	end
	firstBloodTaken = false
	Diagnostics.count(SYSTEM, "matches")
end

export type Row = {
	player: Player,
	score: number,
	kills: number,
	deaths: number,
	assists: number,
}

-- Sorted highest first, for the scoreboard and the round-end payout.
function Score.leaderboard(): { Row }
	local rows: { Row } = {}
	for player, ledger in ledgers do
		if player.Parent ~= Players then
			continue
		end
		table.insert(rows, {
			player = player,
			score = ledger.matchScore,
			kills = ledger.kills,
			deaths = ledger.deaths,
			assists = ledger.assists,
		})
	end
	table.sort(rows, function(a, b)
		if a.score == b.score then
			return a.kills > b.kills
		end
		return a.score > b.score
	end)
	return rows
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

function Score.step(deltaTime: number)
	clock += deltaTime
end

-- Events per player per minute. A player cannot legitimately earn faster than
-- they can kill, so a number above the configured ceiling means something is
-- awarding twice — the bug that is invisible until someone notices a week
-- later that the leaderboard is nonsense.
function Score.eventsPerMinute(): number?
	local minutes = (clock - windowStart) / 60
	if minutes < 0.5 then
		return nil -- too short a window to mean anything
	end
	local population = math.max(#Players:GetPlayers(), 1)
	return windowEvents / minutes / population
end

-- Long, because the rate only means anything over minutes of play and a
-- warning that repeats every few seconds is one people learn to scroll past.
local REPORT_INTERVAL_SECONDS = 60

function Score.report()
	local rate = Score.eventsPerMinute()
	if not rate then
		return
	end

	if rate > Config.eventsPerMinuteWarn then
		Diagnostics.warn(
			SYSTEM,
			`{string.format("%.0f", rate)} score events per player per minute — above {Config.eventsPerMinuteWarn}. `
				.. `Something is awarding twice; every award goes through Score.award, so start there.`
		)
	end

	windowStart = clock
	windowEvents = 0
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function Score.init()
	-- A LISTENER, alongside respawn and the killfeed. Registering as the
	-- handler would silently replace whoever got there first.
	Health.onKill(Score.recordKill)

	Players.PlayerRemoving:Connect(function(player)
		ledgers[player] = nil
	end)

	RunService.Heartbeat:Connect(Score.step)

	-- A `report` function nothing ever calls is the same thing as no report at
	-- all, so it gets its caller in the same commit.
	task.spawn(function()
		while true do
			task.wait(REPORT_INTERVAL_SECONDS)
			Score.report()
		end
	end)

	local milestones = #Config.streakMilestones
	Diagnostics.ok(
		SYSTEM,
		`kill {Config.events.kill.score}/{Config.events.kill.xp}xp/{Config.events.kill.coins}c · `
			.. `assist ≥{Config.assistMinimumDamage} dmg · {milestones} streak milestones`
	)
end

return Score
