--!strict
-- ClassCharter — what each class is FOR, as numbers (NOD-148).
--
-- Titus: *"pretty balanced but not too balanced — you can make some guns better
-- than others but there can't just be a god gun."*
--
-- That is the whole design in one sentence, and it needs two different things
-- from this file. Guns are allowed to differ in POWER — a late unlock should
-- feel like a reward, not a sidegrade. What they are not allowed to do is leave
-- their CLASS: an LMG that kills as fast as a rifle is not a strong LMG, it is a
-- rifle with a hundred rounds, and the class it belonged to stops existing.
--
-- So this file draws a box per class per range band, and `Balance.charter()`
-- names anything outside its box at boot. Inside the box, spread freely: that
-- is where "some guns are better than others" lives.
--
-- Every window is TORSO TTK in seconds against 100hp. A missing band means the
-- class must NOT be able to kill at that range at all — that is how a shotgun's
-- death is specified rather than left to whatever `travelMax` happens to be.
--
-- Ranges are quoted in studs AND feet (Systems/Scale, 1 stud = 1.065 ft) because
-- "kills to 40 studs" is not a claim anybody can sanity-check and "kills to 43
-- feet" is.
--
-- Data only: the checks live in `Systems/Balance`.

local ClassCharter = {}

-- The distances every gun is judged at. 40 studs is in the list specifically
-- because it is the shotgun checkpoint (see `shotgunMaxShotsAt40` below) — a
-- band that exists to make one rule checkable is a band worth having.
--
--   10 studs =  11 ft   knife fight, round a corner
--   25 studs =  27 ft   across a room
--   40 studs =  43 ft   across a large room — where shotguns are supposed to
--                       still work and traditionally stop
--   70 studs =  75 ft   open ground
--  110 studs = 117 ft   a lane you need a scope for
ClassCharter.bands = { 10, 25, 40, 70, 110 }

export type Window = { min: number, max: number }

export type Spec = {
	-- Keyed by index into `bands`. A missing index means the class must be
	-- unable to kill at that distance — dead, not merely weak.
	ttk: { [number]: Window },
	-- Seconds of faff: adsTime + sprintToFire + equipTime, less the time a
	-- mobility bonus gives back. See Balance.handlingCost.
	handling: Window,
	-- travelMax — where the bullets stop existing. The one number falloff
	-- tuning cannot talk its way around.
	reach: Window,
	-- Classes exempt from the TTK box entirely, because their damage does not
	-- come from bullets hitting a torso.
	special: boolean?,
	note: string,
}

-- Titus: *"i dont want to struggle from vgss aka video game shot gun syndrome
-- where up to 5 feet your god then all the sudden your throwing mac and cheese
-- at them."*
--
-- The rule, as a number that can fail a boot check: at 40 studs (43 ft) no
-- shotgun may need more than THREE shots to kill. Not "shotguns should feel
-- better at range" — a threshold, at a stated distance, that a config edit can
-- break and the manifest will catch.
--
-- The lever is pellet WEIGHT, not pellet count. Eight heavy pellets in a tight
-- cone still land three or four at 43 ft; twelve light ones in a wide cone land
-- one, which is the mac-and-cheese cliff exactly.
ClassCharter.shotgunMaxShotsAt40 = 3

ClassCharter.classes = {
	Shotgun = {
		ttk = {
			[1] = { min = 0.00, max = 0.32 },
			[2] = { min = 0.28, max = 0.75 },
			[3] = { min = 0.50, max = 1.15 },
			[4] = { min = 1.10, max = 3.00 },
		},
		handling = { min = 1.20, max = 2.00 },
		reach = { min = 70, max = 100 },
		note = "Deletes people in a room and still works across one. Dies in the open, never at 43 ft.",
	},

	SMG = {
		ttk = {
			[1] = { min = 0.22, max = 0.32 },
			[2] = { min = 0.26, max = 0.40 },
			[3] = { min = 0.38, max = 0.62 },
			[4] = { min = 0.70, max = 1.20 },
		},
		-- The best hands in the game, and nothing else comes close: a rifle starts
		-- at 1.16. Titus: *"quick fire rate, low damage, great handling and
		-- movement."* Every SMG also moves you FASTER than standing still with a
		-- rifle would, which is the other half of the class.
		handling = { min = 0.68, max = 1.14 },
		reach = { min = 95, max = 135 },
		note = "Fastest kill in the game up close and the best handling. Bullets stop existing before 117 ft.",
	},

	MachinePistol = {
		-- The floor at [1] is 0.34 and not lower for a structural reason: a
		-- SECONDARY in the top third of close kill speed is a primary you did not
		-- have to choose, and `Balance.validate` fails the build for it. These sit
		-- deliberately just underneath the SMG class (0.22-0.32) — faster than any
		-- pistol, never competitive with the thing you brought as your main gun.
		ttk = {
			[1] = { min = 0.34, max = 0.48 },
			[2] = { min = 0.36, max = 0.58 },
			[3] = { min = 0.58, max = 0.95 },
		},
		handling = { min = 0.66, max = 0.92 },
		-- Under 70 studs on purpose: the class must be DEAD at the 70-stud band,
		-- and a bullet is only gone once `travelMax` is strictly below it.
		reach = { min = 58, max = 68 },
		note = "An SMG you carry as a sidearm. Nearly the speed, none of the range, and it stops existing at 75 ft.",
	},

	Pistol = {
		ttk = {
			[1] = { min = 0.42, max = 0.65 },
			[2] = { min = 0.45, max = 0.70 },
			[3] = { min = 0.58, max = 0.95 },
			[4] = { min = 0.90, max = 1.50 },
		},
		handling = { min = 0.78, max = 1.26 },
		-- Capped under 110 so the window cannot contradict the TTK table: a
		-- pistol whose bullets still exist at the last band would be required to
		-- be dead there and permitted to reach it at the same time.
		reach = { min = 80, max = 108 },
		note = "The gun you finish a fight with, never the one you start it with.",
	},

	Revolver = {
		ttk = {
			[1] = { min = 0.36, max = 0.58 },
			[2] = { min = 0.36, max = 0.58 },
			[3] = { min = 0.48, max = 0.80 },
			[4] = { min = 0.68, max = 1.10 },
			[5] = { min = 0.95, max = 1.70 },
		},
		handling = { min = 1.00, max = 1.68 },
		reach = { min = 110, max = 155 },
		note = "Two or three hits, and you feel every miss. The only secondary that reaches.",
	},

	Rifle = {
		-- The window that matters here is [5], and it is deliberately BRUTAL.
		--
		-- First pass had a rifle killing in five shots up close and seven at 117
		-- ft — a 50% penalty for crossing the whole map, which is not a penalty,
		-- it is a laser. Titus: *"the drop offs for the rifles arent big enough
		-- your gonna be able to laser someone from across the map if you can even
		-- slightly control the recoil."*
		--
		-- Recoil cannot be the answer, because recoil is a skill and a decent
		-- player beats it. Falloff is not a skill. So at 117 ft a rifle takes
		-- roughly TWICE as long to kill as it does in a room, which is what makes
		-- a marksman (flat 0.38-0.50 at every range) the correct pick out there
		-- instead of a rifle with a scope on it.
		ttk = {
			[1] = { min = 0.32, max = 0.46 },
			[2] = { min = 0.32, max = 0.46 },
			-- Flat to 43 ft is allowed: forcing falloff before then would push
			-- every rifle's `rangeNear` inside a large room, which is SMG
			-- territory and not what this class is for.
			[3] = { min = 0.32, max = 0.52 },
			[4] = { min = 0.46, max = 0.64 },
			[5] = { min = 0.62, max = 0.95 },
		},
		handling = { min = 1.16, max = 1.70 },
		-- Tightened with the falloff. A rifle whose bullets still exist at 200
		-- studs is a rifle somebody will try to snipe with, and the fact that it
		-- is bad at it is not obvious until they have lost the fight.
		reach = { min = 128, max = 172 },
		note = "Owns 11-50 ft and fades hard past 75. The gun you bring when you don't know, never the gun you bring when you do.",
	},

	BattleRifle = {
		ttk = {
			[1] = { min = 0.38, max = 0.52 },
			[2] = { min = 0.38, max = 0.52 },
			[3] = { min = 0.38, max = 0.52 },
			[4] = { min = 0.40, max = 0.56 },
			[5] = { min = 0.42, max = 0.60 },
		},
		-- Clearly worse than a rifle's 1.16-1.70, and that is the whole trade.
		-- Titus: *"don't make them have a fast fire rate or a near equal fire
		-- rate to the assault rifles — make the damage and range more, the fire
		-- rate less and the handling less."*
		handling = { min = 1.70, max = 2.15 },
		reach = { min = 190, max = 235 },
		note = "Loses the room, wins the courtyard. Beats a rifle past 75 ft and knows it.",
	},

	LMG = {
		ttk = {
			[1] = { min = 0.42, max = 0.58 },
			[2] = { min = 0.42, max = 0.58 },
			[3] = { min = 0.42, max = 0.58 },
			[4] = { min = 0.44, max = 0.62 },
			[5] = { min = 0.48, max = 0.70 },
		},
		-- By far the worst in the game, and most of it is the RELOAD: five to seven
		-- seconds, counted at quarter weight, is most of a second of pure cost
		-- that no other class carries. That is the LMG trade stated honestly —
		-- the magazine is the strength and the magazine is also the price.
		handling = { min = 2.95, max = 3.75 },
		reach = { min = 170, max = 215 },
		note = "Worst kill speed and worst handling in the game. Holds a lane nothing else can.",
	},

	Marksman = {
		ttk = {
			[1] = { min = 0.32, max = 0.48 },
			[2] = { min = 0.32, max = 0.48 },
			[3] = { min = 0.32, max = 0.48 },
			[4] = { min = 0.32, max = 0.48 },
			[5] = { min = 0.32, max = 0.48 },
		},
		handling = { min = 1.94, max = 2.52 },
		reach = { min = 220, max = 275 },
		note = "Flat everywhere: two or three hits at any distance, and no forgiveness for a miss.",
	},

	Sniper = {
		-- One shot, one kill, at every band including point blank. Titus:
		-- *"dont make snipers crazy weak at close range just dont give them crazy
		-- ads times and sprint to fire times."*
		--
		-- So the close-range answer is NOT damage. It is the handling window
		-- below, which is the widest and slowest in the game — a sniper caught in
		-- a room loses because it cannot get on target, not because its round
		-- stopped working at 11 ft.
		ttk = {
			[1] = { min = 0.00, max = 0.00 },
			[2] = { min = 0.00, max = 0.00 },
			[3] = { min = 0.00, max = 0.00 },
			[4] = { min = 0.00, max = 0.00 },
			[5] = { min = 0.00, max = 0.00 },
		},
		handling = { min = 3.00, max = 3.80 },
		reach = { min = 280, max = 380 },
		note = "One shot at any range. Paid for entirely in ADS time, sprint-to-fire and move speed.",
	},

	Launcher = {
		ttk = {},
		handling = { min = 1.15, max = 1.85 },
		reach = { min = 120, max = 210 },
		special = true,
		note = "Splash damage, one or two in the tube, no answer to anything that moves.",
	},

	Melee = {
		ttk = {},
		handling = { min = 0.15, max = 0.42 },
		reach = { min = 3, max = 7 },
		special = true,
		note = "Fastest thing you can be holding. You have to get there.",
	},
} :: { [string]: Spec }

return ClassCharter
