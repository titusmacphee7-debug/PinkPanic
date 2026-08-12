--!strict
-- GunCatalog — the roster, assembled from `Config/Guns/` (NOD-148).
--
-- **One file per gun, and the file name IS the gun id.** Same rule as the asset
-- folders: `Guns/Grump.luau` is the gun `Grump`, so there is no second place to
-- keep them in sync and no way to typo one of them apart. Drop a file in, it is
-- in the game; the boot count says how many arrived.
--
-- The roster used to live here as one 400-line table. It moved because balance
-- is not read, it is MEASURED — `Systems/Balance.report()` prints the TTK table
-- at every range band, which is the thing you actually compare guns with. Once
-- comparison stopped meaning "scroll and squint", one gun per file became the
-- better shape: a gun is a small self-contained argument for its own existence.
--
-- Ballistics model: bullets are projectiles with per-gun velocity (studs/s) and
-- drop (studs/s^2). Damage is per BULLET (per PELLET for shotguns): full
-- `damageNear` until `rangeNear` studs, linear falloff to `damageFar` at
-- `rangeFar`, flat after — and the bullet ceases to exist at `travelMax`
-- (`rangeFar` x 1.6), which is what makes a shotgun DEAD past its range rather
-- than merely weak. `moveSpeedMult` scales walk/sprint while the gun is held.
--
-- Recoil model (no bloom, ever): spread is FIXED per gun — hip vs ADS — and
-- never grows while firing. Sustained fire climbs the CAMERA along a learnable
-- pattern instead (see `Config/RecoilConfig`). The crosshair always tells the
-- truth: bullets go where it points, recoil moves it, taps stay laser-accurate.
--
-- PRICE_MULTIPLIER rescales the whole economy ladder in one place.

-- Nine classes, each with a job no other class does (NOD-148). Carbine and
-- Bullpup are gone: they were AR variants wearing different names, which is
-- three classes doing one job and the reason "every class is the same gun" was
-- true. What replaced them is BattleRifle (an AR that reaches, at the cost of
-- ADS), LMG (suppress and hold, worst handling, huge magazine) and Marksman
-- (semi-auto precision, flat damage, two or three rounds).
-- Twelve now, not nine (NOD-148). MachinePistol, Launcher and Melee joined when
-- the roster went to 50: a full-auto sidearm is not a pistol with a higher rpm,
-- it is a different decision at the loadout screen, and that is the test for
-- whether something deserves to be a class.
export type GunClass =
	"Pistol"
	| "MachinePistol"
	| "Revolver"
	| "SMG"
	| "Shotgun"
	| "Rifle"
	| "BattleRifle"
	| "LMG"
	| "Marksman"
	| "Sniper"
	| "Launcher"
	| "Melee"
export type GunSlot = "Primary" | "Secondary"
local RarityConfig = require(script.Parent.Rarity)

export type Rarity = RarityConfig.Tier

export type GunStats = {
	damageNear: number,
	damageFar: number,
	rangeNear: number,
	rangeFar: number,
	pellets: number?,
	headshotMult: number,
	rpm: number,
	auto: boolean,
	magSize: number,
	reloadSeconds: number,
	shellReload: number?, -- set = the gun loads one shell at a time
	-- Burst. `burstCount` is shots per trigger pull; `burstRpm` is the cadence
	-- INSIDE the burst, which is not the gun's rpm — rpm governs the gap
	-- between bursts. Absent on every gun today: the mode exists and is tested
	-- so that making one burst is a line here rather than a firing rewrite.
	burstCount: number?,
	burstRpm: number?,
	spreadDeg: number, -- hipfire aim error (and the pellet cone on shotguns)
	adsSpreadDeg: number, -- aim error while aimed in — always tighter than hip
	recoilVert: number, -- degrees of camera climb per shot
	recoilHoriz: number, -- random left/right degrees per shot
	recoilRecovery: number, -- settle speed; higher snaps back to center faster
	velocity: number, -- studs/s
	drop: number, -- studs/s^2 of bullet gravity
	moveSpeedMult: number,
	-- Sprint speed, separately from walk. Absent means the same as
	-- `moveSpeedMult`. Name it when a gun should be fine to shuffle with and
	-- bad to run with — which is most of the heavy end of the roster.
	sprintSpeedMult: number?,
	equipTime: number,
	sprintToFire: number,
	adsTime: number,
	-- Optional handling overrides (NOD-143). Leave them out and they are derived
	-- from the four above by the ratios in FiringConfig.derive, which is how a
	-- roster this size avoids hundreds of hand-typed numbers. Name one only when
	-- a gun should break the pattern on purpose.
	holsterTime: number?,
	reloadEmptyTime: number?,
	reloadCancelTime: number?,
	tacSprintToFire: number?,
	slideToFire: number?,
	-- Which recoil shape this gun climbs in, by name from RecoilConfig.patterns
	-- (NOD-144). Absent means the one its CLASS uses, which is what most guns
	-- should do — a pattern is a family trait, and hand-authoring one per gun is
	-- one chance per gun to author it badly and never notice.
	recoilPattern: string?,
}

export type GunDef = {
	name: string,
	-- The real weapon this is. Kept next to the joke name because the joke is
	-- what players read and the archetype is what the model has to look like —
	-- "Bestie" tells an artist nothing, "M4A1" tells them everything.
	archetype: string,
	class: GunClass,
	slot: GunSlot,
	rarity: Rarity,
	price: number,
	-- The level this unlocks at. Buying is gated on it server-side; TRYING is
	-- not, deliberately — Titus: *"if you gatekeep trials by levels it defeats
	-- the purpose because when you unlock the trial you unlock the gun."* The
	-- trial is the shop window for a gun you cannot have yet.
	unlockLevel: number,
	-- **Why you would pick this over its neighbour, in one sentence.** Not
	-- flavour text: it is the design justification, and a gun without one is a
	-- gun that does not ship. `validate()` enforces that at boot rather than
	-- leaving it to whoever reviews the pull request.
	why: string,
	stats: GunStats,
}

local PRICE_MULTIPLIER = 1

local GunCatalog = {}

-- How long a gun trial lasts. Long enough to shoot a magazine through it and
-- decide; short enough that trialling on a loop is worse than buying.
--
-- A trial NEVER grants ownership and never touches the profile. That is not a
-- balance decision to be revisited — it is the one rule this feature has.
GunCatalog.trialSeconds = 60

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local loaded: { [string]: GunDef } = {}
local failures: { string } = {}

for _, module in script.Parent.Guns:GetChildren() do
	if module:IsA("ModuleScript") then
		-- Guarded per gun. One gun with a syntax error should cost you that gun
		-- and a named line in the manifest, not the entire roster — an unguarded
		-- require here would take the whole catalog down and every system that
		-- reads it with it.
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			local def = result :: GunDef
			-- `archetype` and `unlockLevel` are defaulted rather than required
			-- while the roster rework (NOD-148) runs one class at a time. A gun
			-- that still has neither is a gun that has not been reworked yet,
			-- which `GunCatalog.unconverted()` reports at boot — that is a
			-- progress readout, not an error, and it disappears on its own as
			-- the last class lands.
			loaded[module.Name] = {
				name = def.name,
				archetype = def.archetype or "",
				class = def.class,
				slot = def.slot,
				rarity = def.rarity,
				price = math.floor(def.price * PRICE_MULTIPLIER + 0.5),
				unlockLevel = def.unlockLevel or 1,
				why = def.why,
				stats = def.stats,
			}
		else
			table.insert(failures, `{module.Name}: {tostring(result)}`)
		end
	end
end

GunCatalog.guns = loaded

-- Guns that failed to load, for the boot report. Empty is the only good answer.
function GunCatalog.failures(): { string }
	return failures
end

-- Guns still on the pre-rework roster: no `archetype`, so nobody has decided
-- what real weapon they are. Shrinks to zero as NOD-148 lands class by class.
function GunCatalog.unconverted(): { string }
	local list: { string } = {}
	for id, def in loaded do
		if def.archetype == "" then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

function GunCatalog.get(gunId: string): GunDef?
	return GunCatalog.guns[gunId]
end

function GunCatalog.sorted(): { { id: string, def: GunDef } }
	local list = {}
	for id, def in GunCatalog.guns do
		table.insert(list, { id = id, def = def })
	end
	table.sort(list, function(a, b)
		if a.def.slot ~= b.def.slot then
			return a.def.slot == "Primary"
		end
		if a.def.price ~= b.def.price then
			return a.def.price < b.def.price
		end
		return a.def.name < b.def.name
	end)
	return list
end

return GunCatalog
