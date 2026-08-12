--!strict
-- SpawnConfig — how a spawn point is chosen, and how long you wait for it
-- (NOD-135). Data only; the scoring lives in server/Systems/Spawns.luau.
--
-- Every weight here is tunable without touching code, because spawn feel is
-- the kind of thing that gets adjusted from playtest notes rather than
-- reasoned about in advance.

return {
	-- Titus: ~5s respawn, longer for some modes. Modes (M9) override it.
	respawnSeconds = 5,

	-- Brief invulnerability so you cannot be shot before your screen has
	-- finished loading. It ENDS THE MOMENT YOU FIRE — otherwise it is a free
	-- opening trade, and spawn protection that can be used offensively is
	-- worse than none at all.
	protectionSeconds = 2,

	-- ---------------------------------------------------------------------
	-- Scoring
	-- ---------------------------------------------------------------------
	--
	-- Every candidate starts at zero and accumulates. Highest wins. The units
	-- are arbitrary and only meaningful relative to each other.
	weights = {
		-- Farther from the nearest enemy is better, per stud. Deliberately the
		-- dominant term: "not next to someone" is most of what a good spawn is.
		enemyDistance = 1.0,

		-- An enemy who can SEE the point is far worse than one who is merely
		-- near it. This is the difference between spawning behind a wall 30
		-- studs away — fine — and spawning in an open lane 30 studs away,
		-- which is death.
		visiblePenalty = -400,

		-- Near a teammate is mildly good: you spawn into support rather than
		-- alone behind the enemy line.
		friendlyDistance = -0.35,

		-- An enemy already pointing this way is about to be looking at you.
		-- Scaled by how directly they face it.
		facingPenalty = -180,

		-- Somewhere you just died is somewhere the fight still is.
		recentDeathPenalty = -250,
	},

	-- Below this, a point is not scored at all — it is removed from
	-- consideration. A hard floor rather than a large penalty, because a
	-- penalty can always be outweighed by enough of something else, and
	-- "spawned four studs from an enemy but the rest of the map was worse" is
	-- not a defensible outcome.
	minimumEnemyDistance = 45,

	-- How long a death keeps penalising the point nearest to it, and how far
	-- that penalty reaches.
	recentDeathSeconds = 15,
	recentDeathRadius = 30,

	-- Friendly proximity stops helping past this: a teammate across the map is
	-- not support, and without a cap the term quietly becomes a second, weaker
	-- copy of the enemy-distance term with the sign flipped.
	friendlyDistanceCap = 60,

	-- Raised above the pad so the character does not spawn intersecting it.
	spawnHeightOffset = 3.5,
}
