--!strict
-- GunCatalog — the 32-gun roster with full COD-style ballistics (NOD-111
-- balance pass). Every gun has ONE main identity axis — velocity, handling,
-- mobility, sustain, choke, burst, reach — never just damage-vs-RPM.
--
-- Ballistics model: bullets are projectiles with per-gun velocity (studs/s)
-- and drop (studs/s^2). Damage is per BULLET (per PELLET for shotguns):
-- full damageNear until rangeNear studs, linear falloff to damageFar at
-- rangeFar, flat after; bullets die at travelMax (rangeFar x ~1.6).
-- moveSpeedMult scales walk/sprint while held (heavy guns are heavy).
-- PRICE_MULTIPLIER rescales the whole economy ladder in one place.

export type GunClass = "Pistol" | "Revolver" | "SMG" | "Shotgun" | "Rifle" | "Carbine" | "Bullpup" | "Sniper"
export type GunSlot = "Primary" | "Secondary"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

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
	shellReload: number?,
	spreadDeg: number,
	velocity: number, -- studs/s
	drop: number, -- studs/s^2 of bullet gravity
	moveSpeedMult: number,
	equipTime: number,
	sprintToFire: number,
	adsTime: number,
}

export type GunDef = {
	name: string,
	class: GunClass,
	slot: GunSlot,
	rarity: Rarity,
	price: number,
	stats: GunStats,
}

local PRICE_MULTIPLIER = 1

local GunCatalog = {}

local function gun(name: string, class: GunClass, slot: GunSlot, rarity: Rarity, price: number, stats: GunStats): GunDef
	return {
		name = name,
		class = class,
		slot = slot,
		rarity = rarity,
		price = math.floor(price * PRICE_MULTIPLIER + 0.5),
		stats = stats,
	}
end

GunCatalog.guns = {
	-- ============ SECONDARIES — PISTOLS ============
	-- Pip: the honest starter. Good at everything, great at nothing.
	Pistol_1 = gun("Pip", "Pistol", "Secondary", "Common", 0, {
		damageNear = 26, damageFar = 17, rangeNear = 55, rangeFar = 140,
		headshotMult = 1.6, rpm = 380, auto = false, magSize = 12, reloadSeconds = 1.5,
		spreadDeg = 1.0, velocity = 620, drop = 60, moveSpeedMult = 1.02,
		equipTime = 0.22, sprintToFire = 0.12, adsTime = 0.16,
	}),
	-- Dolly: HANDLING — fastest draw/reload in the game, low ceiling.
	Pistol_6 = gun("Dolly", "Pistol", "Secondary", "Common", 500, {
		damageNear = 24, damageFar = 16, rangeNear = 50, rangeFar = 130,
		headshotMult = 1.5, rpm = 420, auto = false, magSize = 14, reloadSeconds = 1.3,
		spreadDeg = 1.1, velocity = 600, drop = 60, moveSpeedMult = 1.03,
		equipTime = 0.16, sprintToFire = 0.09, adsTime = 0.13,
	}),
	-- Stiletto: REACH — a secondary that still bites at rifle ranges.
	Pistol_3 = gun("Stiletto", "Pistol", "Secondary", "Rare", 1200, {
		damageNear = 30, damageFar = 24, rangeNear = 80, rangeFar = 220,
		headshotMult = 1.7, rpm = 270, auto = false, magSize = 10, reloadSeconds = 1.7,
		spreadDeg = 0.7, velocity = 800, drop = 45, moveSpeedMult = 1.0,
		equipTime = 0.28, sprintToFire = 0.16, adsTime = 0.2,
	}),
	-- Pixie: AUTO — the only full-auto secondary; falls off a cliff past 30m.
	Pistol_5 = gun("Pixie", "Pistol", "Secondary", "Epic", 4000, {
		damageNear = 17, damageFar = 11, rangeNear = 40, rangeFar = 100,
		headshotMult = 1.4, rpm = 650, auto = true, magSize = 18, reloadSeconds = 1.9,
		spreadDeg = 1.9, velocity = 520, drop = 70, moveSpeedMult = 1.03,
		equipTime = 0.2, sprintToFire = 0.1, adsTime = 0.15,
	}),
	-- Jawbreaker: BURST — the deagle. Pays for it in speed everywhere.
	Pistol_4 = gun("Jawbreaker", "Pistol", "Secondary", "Epic", 4500, {
		damageNear = 48, damageFar = 30, rangeNear = 60, rangeFar = 150,
		headshotMult = 1.9, rpm = 150, auto = false, magSize = 7, reloadSeconds = 2.3,
		spreadDeg = 0.8, velocity = 700, drop = 55, moveSpeedMult = 0.96,
		equipTime = 0.35, sprintToFire = 0.22, adsTime = 0.28,
	}),

	-- ============ SECONDARIES — REVOLVERS ============
	-- Smooch: SNAP — quickest heavy-hit in a holster; short legs.
	Revolver_4 = gun("Smooch", "Revolver", "Secondary", "Common", 400, {
		damageNear = 38, damageFar = 22, rangeNear = 45, rangeFar = 110,
		headshotMult = 1.9, rpm = 200, auto = false, magSize = 5, reloadSeconds = 2.1,
		spreadDeg = 1.0, velocity = 600, drop = 65, moveSpeedMult = 1.01,
		equipTime = 0.22, sprintToFire = 0.14, adsTime = 0.18,
	}),
	-- Heartbreaker: the classic — two headshots, honest everywhere.
	Revolver_1 = gun("Heartbreaker", "Revolver", "Secondary", "Rare", 1600, {
		damageNear = 45, damageFar = 28, rangeNear = 60, rangeFar = 150,
		headshotMult = 2.0, rpm = 175, auto = false, magSize = 6, reloadSeconds = 2.4,
		spreadDeg = 0.6, velocity = 700, drop = 55, moveSpeedMult = 1.0,
		equipTime = 0.3, sprintToFire = 0.18, adsTime = 0.22,
	}),
	-- Longing: PRECISION — laser velocity and reach; slowest cylinder.
	Revolver_3 = gun("Longing", "Revolver", "Secondary", "Epic", 4400, {
		damageNear = 46, damageFar = 34, rangeNear = 90, rangeFar = 230,
		headshotMult = 2.0, rpm = 150, auto = false, magSize = 6, reloadSeconds = 2.5,
		spreadDeg = 0.4, velocity = 850, drop = 40, moveSpeedMult = 0.99,
		equipTime = 0.34, sprintToFire = 0.2, adsTime = 0.26,
	}),
	-- Drama Queen: ONE-TAP HEAD up close (55 x 1.85 = 102); pays everywhere else.
	Revolver_5 = gun("Drama Queen", "Revolver", "Secondary", "Epic", 4200, {
		damageNear = 55, damageFar = 34, rangeNear = 55, rangeFar = 140,
		headshotMult = 1.85, rpm = 125, auto = false, magSize = 5, reloadSeconds = 2.8,
		spreadDeg = 0.7, velocity = 680, drop = 60, moveSpeedMult = 0.95,
		equipTime = 0.4, sprintToFire = 0.26, adsTime = 0.3,
	}),

	-- ============ PRIMARIES — SMGs ============
	-- Chatterbox: MOBILITY — fastest feet in the game, sprays from the hip.
	SubmachineGun_1 = gun("Chatterbox", "SMG", "Primary", "Common", 700, {
		damageNear = 15, damageFar = 10, rangeNear = 45, rangeFar = 110,
		headshotMult = 1.3, rpm = 850, auto = true, magSize = 32, reloadSeconds = 1.9,
		spreadDeg = 1.8, velocity = 450, drop = 75, moveSpeedMult = 1.05,
		equipTime = 0.3, sprintToFire = 0.14, adsTime = 0.2,
	}),
	-- Bubbler: CONTROL — the accurate, well-behaved SMG.
	SubmachineGun_2 = gun("Bubbler", "SMG", "Primary", "Rare", 1500, {
		damageNear = 18, damageFar = 12, rangeNear = 55, rangeFar = 130,
		headshotMult = 1.35, rpm = 700, auto = true, magSize = 30, reloadSeconds = 2.0,
		spreadDeg = 1.2, velocity = 560, drop = 65, moveSpeedMult = 1.02,
		equipTime = 0.32, sprintToFire = 0.16, adsTime = 0.22,
	}),
	-- Zoomie: RPM — 1000 rounds a minute; useless past 25m.
	SubmachineGun_3 = gun("Zoomie", "SMG", "Primary", "Rare", 2200, {
		damageNear = 13, damageFar = 8, rangeNear = 35, rangeFar = 90,
		headshotMult = 1.3, rpm = 1000, auto = true, magSize = 26, reloadSeconds = 1.65,
		spreadDeg = 2.2, velocity = 430, drop = 80, moveSpeedMult = 1.04,
		equipTime = 0.28, sprintToFire = 0.13, adsTime = 0.19,
	}),
	-- Jitterbug: SUSTAIN — 42 rounds of commitment; sluggish handling.
	SubmachineGun_4 = gun("Jitterbug", "SMG", "Primary", "Epic", 5200, {
		damageNear = 16, damageFar = 11, rangeNear = 50, rangeFar = 120,
		headshotMult = 1.3, rpm = 880, auto = true, magSize = 42, reloadSeconds = 2.4,
		spreadDeg = 1.7, velocity = 480, drop = 72, moveSpeedMult = 1.0,
		equipTime = 0.4, sprintToFire = 0.2, adsTime = 0.26,
	}),

	-- ============ PRIMARIES — SHOTGUNS (damage per PELLET) ============
	-- Realistic pattern: full damage inside ~9m, confetti by ~23m.
	-- Big Boop: the standard pump — one-pump in the face (81), honest range.
	Shotgun_1 = gun("Big Boop", "Shotgun", "Primary", "Common", 900, {
		damageNear = 9, damageFar = 2, rangeNear = 28, rangeFar = 70, pellets = 9,
		headshotMult = 1.2, rpm = 75, auto = false, magSize = 6,
		reloadSeconds = 3.3, shellReload = 0.55,
		spreadDeg = 5.5, velocity = 380, drop = 90, moveSpeedMult = 0.98,
		equipTime = 0.42, sprintToFire = 0.26, adsTime = 0.3,
	}),
	-- Scrunchie: HANDLING pump — snappy, mobile, slightly lighter hit.
	Shotgun_ShortStock = gun("Scrunchie", "Shotgun", "Primary", "Rare", 1400, {
		damageNear = 8, damageFar = 2, rangeNear = 26, rangeFar = 65, pellets = 8,
		headshotMult = 1.2, rpm = 90, auto = false, magSize = 5,
		reloadSeconds = 2.5, shellReload = 0.5,
		spreadDeg = 5.0, velocity = 380, drop = 90, moveSpeedMult = 1.0,
		equipTime = 0.3, sprintToFire = 0.18, adsTime = 0.24,
	}),
	-- Shortcake: POINT-BLANK — 110 in the face, nothing past 15m, two shells.
	Shotgun_SawedOff = gun("Shortcake", "Shotgun", "Primary", "Rare", 1800, {
		damageNear = 11, damageFar = 1, rangeNear = 18, rangeFar = 50, pellets = 10,
		headshotMult = 1.15, rpm = 100, auto = false, magSize = 2, reloadSeconds = 2.2,
		spreadDeg = 8.5, velocity = 340, drop = 100, moveSpeedMult = 1.02,
		equipTime = 0.25, sprintToFire = 0.15, adsTime = 0.2,
	}),
	-- Double Trouble: TWO FAST SHOTS — the duelist's double barrel.
	Shotgun_4 = gun("Double Trouble", "Shotgun", "Primary", "Epic", 4000, {
		damageNear = 10, damageFar = 2, rangeNear = 30, rangeFar = 75, pellets = 9,
		headshotMult = 1.25, rpm = 140, auto = false, magSize = 2, reloadSeconds = 2.4,
		spreadDeg = 5.8, velocity = 400, drop = 85, moveSpeedMult = 0.99,
		equipTime = 0.36, sprintToFire = 0.2, adsTime = 0.26,
	}),
	-- Homemaker: CHOKE — tightest pattern, real reach for a shotgun, slow.
	Shotgun_3 = gun("Homemaker", "Shotgun", "Primary", "Epic", 6000, {
		damageNear = 10, damageFar = 3, rangeNear = 40, rangeFar = 95, pellets = 8,
		headshotMult = 1.3, rpm = 65, auto = false, magSize = 7,
		reloadSeconds = 4.2, shellReload = 0.6,
		spreadDeg = 3.6, velocity = 420, drop = 80, moveSpeedMult = 0.96,
		equipTime = 0.5, sprintToFire = 0.3, adsTime = 0.34,
	}),

	-- ============ PRIMARIES — RIFLES (AK family) ============
	-- Gumdrop: the thumpy baseline AK. 4-tap near.
	AssaultRifle_2 = gun("Gumdrop", "Rifle", "Primary", "Rare", 2000, {
		damageNear = 25, damageFar = 18, rangeNear = 70, rangeFar = 180,
		headshotMult = 1.4, rpm = 570, auto = true, magSize = 30, reloadSeconds = 2.3,
		spreadDeg = 1.5, velocity = 760, drop = 55, moveSpeedMult = 0.98,
		equipTime = 0.42, sprintToFire = 0.24, adsTime = 0.28,
	}),
	-- Cherry Bomb: DAMAGE — hits harder, kicks wider, handles slower.
	AssaultRifle_3 = gun("Cherry Bomb", "Rifle", "Primary", "Epic", 5000, {
		damageNear = 28, damageFar = 19, rangeNear = 65, rangeFar = 170,
		headshotMult = 1.45, rpm = 520, auto = true, magSize = 30, reloadSeconds = 2.5,
		spreadDeg = 1.8, velocity = 800, drop = 52, moveSpeedMult = 0.97,
		equipTime = 0.46, sprintToFire = 0.27, adsTime = 0.32,
	}),
	-- Picnic Punch: HANDLING AK — folding stock, moves and swaps like a carbine.
	AssaultRifle_4 = gun("Picnic Punch", "Rifle", "Primary", "Epic", 6000, {
		damageNear = 24, damageFar = 17, rangeNear = 65, rangeFar = 170,
		headshotMult = 1.4, rpm = 590, auto = true, magSize = 30, reloadSeconds = 2.0,
		spreadDeg = 1.5, velocity = 740, drop = 56, moveSpeedMult = 1.0,
		equipTime = 0.32, sprintToFire = 0.18, adsTime = 0.24,
	}),
	-- Grump: REACH — the moody DMR-ish AK; slow tap-fire, rifle-sniper hybrid.
	AssaultRifle_1 = gun("Grump", "Rifle", "Primary", "Epic", 6800, {
		damageNear = 32, damageFar = 26, rangeNear = 100, rangeFar = 260,
		headshotMult = 1.55, rpm = 420, auto = true, magSize = 25, reloadSeconds = 2.6,
		spreadDeg = 1.0, velocity = 900, drop = 40, moveSpeedMult = 0.96,
		equipTime = 0.48, sprintToFire = 0.28, adsTime = 0.34,
	}),

	-- ============ PRIMARIES — CARBINES + BULLPUPS ============
	-- Sweet Talker: ADS ACCURACY — smooth, precise, quick to the eye.
	AssaultRifle2_1 = gun("Sweet Talker", "Carbine", "Primary", "Epic", 5500, {
		damageNear = 22, damageFar = 15, rangeNear = 75, rangeFar = 190,
		headshotMult = 1.4, rpm = 680, auto = true, magSize = 30, reloadSeconds = 2.1,
		spreadDeg = 0.9, velocity = 820, drop = 50, moveSpeedMult = 0.99,
		equipTime = 0.36, sprintToFire = 0.2, adsTime = 0.2,
	}),
	-- Sprinkler: HIPFIRE — run-and-gun carbine that barely needs sights.
	AssaultRifle2_3 = gun("Sprinkler", "Carbine", "Primary", "Rare", 2800, {
		damageNear = 19, damageFar = 13, rangeNear = 55, rangeFar = 140,
		headshotMult = 1.35, rpm = 740, auto = true, magSize = 30, reloadSeconds = 2.1,
		spreadDeg = 1.3, velocity = 760, drop = 55, moveSpeedMult = 1.02,
		equipTime = 0.3, sprintToFire = 0.16, adsTime = 0.24,
	}),
	-- Chunky: THE ALL-ROUNDER — legendary because it has no weakness (and no spike).
	AssaultRifle2_4 = gun("Chunky", "Carbine", "Primary", "Legendary", 9000, {
		damageNear = 23, damageFar = 17, rangeNear = 70, rangeFar = 180,
		headshotMult = 1.45, rpm = 660, auto = true, magSize = 35, reloadSeconds = 2.25,
		spreadDeg = 1.1, velocity = 800, drop = 50, moveSpeedMult = 0.99,
		equipTime = 0.34, sprintToFire = 0.19, adsTime = 0.24,
	}),
	-- Marshmallow: VELOCITY — squishy-looking, laser-beam ballistics.
	Bullpup_1 = gun("Marshmallow", "Bullpup", "Primary", "Rare", 2500, {
		damageNear = 20, damageFar = 15, rangeNear = 85, rangeFar = 210,
		headshotMult = 1.4, rpm = 640, auto = true, magSize = 36, reloadSeconds = 2.4,
		spreadDeg = 0.7, velocity = 950, drop = 42, moveSpeedMult = 1.0,
		equipTime = 0.38, sprintToFire = 0.22, adsTime = 0.26,
	}),
	-- Toastie: the spicy sibling — damage-range hybrid, handling tax.
	Bullpup_2 = gun("Toastie", "Bullpup", "Primary", "Epic", 4800, {
		damageNear = 23, damageFar = 17, rangeNear = 75, rangeFar = 190,
		headshotMult = 1.5, rpm = 600, auto = true, magSize = 36, reloadSeconds = 2.55,
		spreadDeg = 1.0, velocity = 880, drop = 46, moveSpeedMult = 0.97,
		equipTime = 0.44, sprintToFire = 0.25, adsTime = 0.3,
	}),

	-- ============ PRIMARIES — SNIPERS ============
	-- All one-tap the head; bodies vary. Least drop in the game, real travel time.
	-- Whisper: HANDLING scout — fastest sniper to the shoulder.
	SniperRifle_1 = gun("Whisper", "Sniper", "Primary", "Rare", 3000, {
		damageNear = 70, damageFar = 58, rangeNear = 120, rangeFar = 320,
		headshotMult = 1.5, rpm = 55, auto = false, magSize = 5, reloadSeconds = 2.8,
		spreadDeg = 0.15, velocity = 1050, drop = 38, moveSpeedMult = 0.97,
		equipTime = 0.45, sprintToFire = 0.3, adsTime = 0.32,
	}),
	-- Scout's Honor: CYCLE — quickest follow-up shot, lightest body hit.
	SniperRifle_3 = gun("Scout's Honor", "Sniper", "Primary", "Epic", 5800, {
		damageNear = 62, damageFar = 50, rangeNear = 110, rangeFar = 300,
		headshotMult = 1.65, rpm = 80, auto = false, magSize = 6, reloadSeconds = 2.5,
		spreadDeg = 0.2, velocity = 1000, drop = 40, moveSpeedMult = 0.99,
		equipTime = 0.42, sprintToFire = 0.28, adsTime = 0.28,
	}),
	-- Long Kiss: VELOCITY — 1400 studs/s, least lead, least drop. The classic.
	SniperRifle_2 = gun("Long Kiss", "Sniper", "Primary", "Epic", 6500, {
		damageNear = 88, damageFar = 70, rangeNear = 150, rangeFar = 400,
		headshotMult = 1.3, rpm = 45, auto = false, magSize = 5, reloadSeconds = 3.1,
		spreadDeg = 0.1, velocity = 1400, drop = 28, moveSpeedMult = 0.94,
		equipTime = 0.55, sprintToFire = 0.34, adsTime = 0.42,
	}),
	-- Star Crossed: ONE-TAP BODY inside 170 studs only; glacial everything.
	-- (Resolves the open question: the power fantasy exists, but only close-mid.)
	SniperRifle_4 = gun("Star Crossed", "Sniper", "Primary", "Legendary", 10000, {
		damageNear = 102, damageFar = 78, rangeNear = 170, rangeFar = 380,
		headshotMult = 1.2, rpm = 36, auto = false, magSize = 4, reloadSeconds = 3.4,
		spreadDeg = 0.1, velocity = 1200, drop = 32, moveSpeedMult = 0.92,
		equipTime = 0.6, sprintToFire = 0.38, adsTime = 0.5,
	}),
	-- Heartstopper: the flagship — best cycle+handling of the heavies.
	SniperRifle_5 = gun("Heartstopper", "Sniper", "Primary", "Legendary", 12000, {
		damageNear = 84, damageFar = 68, rangeNear = 140, rangeFar = 360,
		headshotMult = 1.45, rpm = 60, auto = false, magSize = 6, reloadSeconds = 2.9,
		spreadDeg = 0.12, velocity = 1250, drop = 30, moveSpeedMult = 0.95,
		equipTime = 0.5, sprintToFire = 0.3, adsTime = 0.36,
	}),
} :: { [string]: GunDef }

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
