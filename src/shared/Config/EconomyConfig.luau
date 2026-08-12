--!strict
-- EconomyConfig — earn rates and the level curve (NOD-30, NOD-31).

-- Per-kill rates moved to ScoreConfig with NOD-138 and are NOT duplicated here.
-- A kill is worth score, xp and coins at three different rates plus bonuses for
-- how it was taken; a `coinsPerKill` constant sitting next to that would be a
-- second answer to a question that already has one.
local EconomyConfig = {
	coinsRoundPlayed = 25,
	coinsRoundWin = 100,
	xpRoundPlayed = 50,
	xpRoundWin = 100,
}

-- XP needed to go from `level` to `level + 1`. xp is stored as progress into
-- the current level, so leveling subtracts this and carries the remainder.
function EconomyConfig.xpRequired(level: number): number
	return math.floor(100 * level ^ 1.35)
end

return EconomyConfig
