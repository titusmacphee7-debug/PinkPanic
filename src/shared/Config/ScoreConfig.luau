--!strict
-- ScoreConfig — what every combat event is worth (NOD-138).
--
-- Three ledgers, and keeping them separate now is far cheaper than untangling
-- them in M7 when scorestreaks arrive:
--
--   SCORE  resets on death (streaks) and on match end (leaderboard). Spends on
--          scorestreaks. This is the number that makes you play differently.
--   XP     never resets. Levels and weapon unlocks.
--   COINS  never reset. Crates and cosmetics.
--
-- A kill is worth all three at once and they are NOT the same number, which is
-- the whole reason this file exists rather than one `coinsPerKill` constant.
-- Coin and XP RATES stay in EconomyConfig, which already owns the level curve;
-- what is here is the per-event table combat awards from.
--
-- Data only.

local ScoreConfig = {}

export type Award = {
	score: number,
	xp: number,
	coins: number,
}

local function award(score: number, xp: number, coins: number): Award
	return { score = score, xp = xp, coins = coins }
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- A kill is the baseline everything else is priced against. The bonuses are
-- deliberately small next to it: a headshot is worth doing, not worth
-- exclusively hunting, because a new player who cannot reliably hit heads
-- should not feel like they are earning a fraction of what everyone else is.
ScoreConfig.events = {
	kill = award(100, 20, 10),
	-- Added ON TOP of the kill, not instead of it.
	headshotBonus = award(25, 5, 2),
	longshotBonus = award(25, 5, 2),
	-- Killing someone who was already shooting somebody else.
	saviourBonus = award(50, 10, 5),
	-- Half a kill's score. An assist that pays nothing teaches people not to
	-- shoot at anything they cannot finish, which in an FFA is most things.
	assist = award(50, 10, 5),
	-- The first kill of a match. One player, once.
	firstBlood = award(150, 30, 15),
	-- Ending someone else's streak, scaled by how long it was (see below).
	shutdown = award(50, 10, 5),
	-- Dying costs nothing. A death spiral where the losing player also earns
	-- less is how a match stops being fun for exactly the person who needs it
	-- to be.
	death = award(0, 0, 0),
}

-- What counts as a longshot, per weapon class. A 60-stud shot is a long one
-- with a shotgun and a normal one with a sniper, so a single distance for the
-- whole roster would hand snipers a permanent bonus and shotguns none.
--
-- Expressed as a multiple of the gun's own rangeNear, which is the distance
-- its damage starts dropping — "further than this gun is comfortable at".
ScoreConfig.longshotMultiplier = 1.6

-- How recently the victim must have damaged someone else for the kill to count
-- as a save.
ScoreConfig.saviourWindowSeconds = 3

-- ---------------------------------------------------------------------------
-- Assists
-- ---------------------------------------------------------------------------

-- Minimum damage before a contribution is an assist. Below this it is a
-- graze — and crediting a graze devalues the assists that were real work.
ScoreConfig.assistMinimumDamage = 20

-- ---------------------------------------------------------------------------
-- Streaks
-- ---------------------------------------------------------------------------

-- Milestone -> extra award, granted once as the streak passes it. Kept as a
-- sorted list rather than a map so the order it is announced in is the order
-- it is written in.
ScoreConfig.streakMilestones = {
	{ kills = 3, name = "Sugar Rush", award = award(50, 10, 5) },
	{ kills = 5, name = "Sweetheart", award = award(100, 25, 15) },
	{ kills = 8, name = "Heartbreaker", award = award(200, 50, 30) },
	{ kills = 12, name = "Panic", award = award(400, 100, 60) },
	{ kills = 20, name = "Pink Panic", award = award(800, 200, 120) },
}

-- Ending a streak pays `shutdown` scaled by how long the streak was, capped so
-- ending a 30-kill run is not a match-winning payout by itself.
ScoreConfig.shutdownMinimumStreak = 3
ScoreConfig.shutdownPerKill = 0.25
ScoreConfig.shutdownMaxMultiplier = 3

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

-- Score events per player per minute above which something is wrong. A player
-- cannot legitimately earn faster than they can kill, so a rate above this is
-- a double-award somewhere — which is exactly the bug that is invisible until
-- someone notices the leaderboard is nonsense a week later.
ScoreConfig.eventsPerMinuteWarn = 90

return ScoreConfig
