--!strict
-- EconomyConfig — earn rates and the level curve (NOD-30, NOD-31).

local EconomyConfig = {
	coinsPerKill = 10,
	coinsRoundPlayed = 25,
	coinsRoundWin = 100,
	xpPerKill = 20,
	xpRoundPlayed = 50,
	xpRoundWin = 100,
}

-- XP needed to go from `level` to `level + 1`. xp is stored as progress into
-- the current level, so leveling subtracts this and carries the remainder.
function EconomyConfig.xpRequired(level: number): number
	return math.floor(100 * level ^ 1.35)
end

return EconomyConfig
