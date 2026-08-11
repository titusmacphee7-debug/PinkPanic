--!strict
-- BallisticsConfig — the numbers the server's projectile simulation runs on
-- (NOD-133). Data only, no behaviour: every value here is read by
-- server/Systems/Ballistics.luau and never interpreted anywhere else.
--
-- Per-gun numbers do NOT live here. Damage, range, velocity, spread and drop
-- are `GunCatalog` stats resolved through `CombatStats`, because those are
-- balance and balance has one file. What lives here is the simulation's own
-- behaviour: how finely it steps, what it will shoot through, and the limits
-- that keep a hostile client from turning one remote into a server stall.

export type PenetrationRule = {
	-- Damage multiplier applied to whatever comes out the far side.
	damageMult: number,
	-- Studs of material the bullet is willing to cross. Thicker than this and
	-- it stops, which is what makes cover feel like cover.
	maxThickness: number,
}

return {
	-- -----------------------------------------------------------------------
	-- Stepping
	-- -----------------------------------------------------------------------

	-- NOTE: there is deliberately no gravity constant here.
	--
	-- A gun's `drop` stat in GunCatalog IS its downward acceleration in
	-- studs/s², not a multiplier on world gravity. The catalog's values run
	-- 17–60, which over a bullet's ~0.1s flight is a few tenths of a stud —
	-- an arc you can learn to lead with. Treating the same numbers as a
	-- multiplier on 196.2 gives 3,300–11,800 studs/s², which drops a rifle
	-- round 55 studs before it has crossed a large room. That was the first
	-- version of this file, and the falloff test is what caught it.
	--
	-- Bullets are not physically simulated parts either, so workspace.Gravity
	-- is intentionally not consulted: ballistics must not change because
	-- someone tuned a map's jump height.

	-- The longest frame the simulation will honour. A hitching server would
	-- otherwise advance a bullet hundreds of studs in one raycast, which is
	-- both wrong and a way to shoot through walls by lagging the server on
	-- purpose. Beyond this the bullet simply advances more slowly than real
	-- time, which is the safe direction to be wrong in.
	maxStepSeconds = 1 / 20,

	-- Hard cap on how far one raycast segment may cover, regardless of frame
	-- time or muzzle velocity. A 3000 stud/s round at 20fps would otherwise
	-- cast a 150-stud segment and skip anything thin inside it.
	maxSegmentStuds = 40,

	-- -----------------------------------------------------------------------
	-- Limits
	-- -----------------------------------------------------------------------

	-- Per PLAYER, deliberately. A global cap is worse than no cap: one client
	-- spamming fire starves everyone else's shots, and a shotgun blast gets
	-- silently truncated to however many pellets happened to fit. Per-player
	-- means a spammer only ever runs out of their own budget.
	maxProjectilesPerPlayer = 96,

	-- Bounded penetration passes within a single segment, so a bullet crossing
	-- a stack of thin parts cannot loop the server.
	maxPenetrationsPerBullet = 3,

	-- -----------------------------------------------------------------------
	-- Origin validation
	-- -----------------------------------------------------------------------

	-- How far the claimed muzzle position may sit from the shooter's head.
	-- Generous enough for any gun held at any pose, small enough that it can
	-- never be used to shoot from somewhere the player is not.
	maxOriginOffsetStuds = 4,

	-- Even a nearby origin is illegitimate if there is a wall between it and
	-- the head — that is how you shoot around a corner with your body safe.
	-- The head-to-origin ray must be clear.
	validateOriginSightline = true,

	-- Shots arriving faster than the gun's own fire rate are rejected. The
	-- tolerance absorbs honest network jitter without opening a window worth
	-- exploiting: at 600 RPM a 15% slack is 15ms, which buys a cheater
	-- nothing and stops a laggy player losing legitimate shots.
	fireRateTolerance = 0.15,

	-- -----------------------------------------------------------------------
	-- Hit zones
	-- -----------------------------------------------------------------------

	-- Torso is the reference at 1.0. Headshot multiplier is per gun (a sniper
	-- rewards it more than an SMG), so only the zones that are the same across
	-- every weapon are named here.
	limbMult = 0.9,

	-- Parts of the stock Roblox rig, mapped to zones. NOD-134 replaces this
	-- with a normalized hit volume whose parts carry an explicit `PPHitZone`
	-- attribute; the attribute always wins. This table only answers for an
	-- untagged character, which is exactly the R6/R15 rig a Studio playtest
	-- spawns with.
	rigZones = {
		Head = "Head",
		UpperTorso = "Torso",
		LowerTorso = "Torso",
		Torso = "Torso",
		HumanoidRootPart = "Torso",
	} :: { [string]: string },

	-- -----------------------------------------------------------------------
	-- Penetration
	-- -----------------------------------------------------------------------

	-- What a bullet will pass through, and what it costs. Anything not listed
	-- stops the bullet dead — the safe default, so a new material added to a
	-- map cannot silently become see-through.
	penetration = {
		[Enum.Material.Glass] = { damageMult = 0.9, maxThickness = 1.5 },
		[Enum.Material.Ice] = { damageMult = 0.8, maxThickness = 1.5 },
		[Enum.Material.Plastic] = { damageMult = 0.7, maxThickness = 1 },
		[Enum.Material.SmoothPlastic] = { damageMult = 0.7, maxThickness = 1 },
		[Enum.Material.Wood] = { damageMult = 0.6, maxThickness = 1.5 },
		[Enum.Material.WoodPlanks] = { damageMult = 0.6, maxThickness = 1.5 },
		[Enum.Material.Fabric] = { damageMult = 0.85, maxThickness = 2 },
		[Enum.Material.Foil] = { damageMult = 0.85, maxThickness = 1 },
		[Enum.Material.Cardboard] = { damageMult = 0.85, maxThickness = 2 },
	} :: { [Enum.Material]: PenetrationRule },
}
