--!strict
-- AttachmentConfig — the attachment framework (future feature, wired now so
-- adding attachments later is pure data). An attachment occupies a slot and
-- carries stat modifiers; CombatStats.resolve(gunId, attachmentIds) applies
-- them: `mul` multiplies, `add` adds, in listed order, against the resolved
-- stat names (damageNear, rpm, magSize, reloadSeconds, spreadDeg,
-- adsSpreadDeg, recoilVert, recoilHoriz, recoilRecovery, velocity, drop,
-- moveSpeedMult, equipTime, sprintToFire, adsTime, rangeNear, rangeFar,
-- headshotMult).
--
-- RECOIL is the attachment system's centerpiece: barrels and grips trade
-- handling/mobility for a calmer or snappier kick, so "make this gun easier
-- to control" is the main thing players will build toward.
--
-- NOTHING here is purchasable or equippable yet — schema/UI/shop for
-- attachments come with their own issue. The examples below are the shape
-- proof and starting balance sketches.

export type Modifier = { stat: string, mul: number?, add: number? }
export type AttachmentSlot = "Barrel" | "Grip" | "Mag" | "Stock" | "Sight"

export type AttachmentDef = {
	name: string,
	slot: AttachmentSlot,
	modifiers: { Modifier },
}

local AttachmentConfig = {}

AttachmentConfig.attachments = {
	-- Examples (inert until the attachments feature ships):
	Compensator = {
		name = "Compensator 💨",
		slot = "Barrel",
		modifiers = {
			{ stat = "recoilVert", mul = 0.8 }, -- calmer climb
			{ stat = "moveSpeedMult", add = -0.01 },
		},
	},
	AngledGrip = {
		name = "Angled Grip 🎀",
		slot = "Grip",
		modifiers = {
			{ stat = "recoilHoriz", mul = 0.6 }, -- kills the side jitter
			{ stat = "adsTime", mul = 1.08 },
		},
	},
	RecoilSpring = {
		name = "Recoil Spring 🌸",
		slot = "Stock",
		modifiers = {
			{ stat = "recoilRecovery", mul = 1.3 }, -- snaps back to center faster
			{ stat = "equipTime", mul = 1.08 },
		},
	},
	LongBarrel = {
		name = "Long Barrel 💫",
		slot = "Barrel",
		modifiers = {
			{ stat = "velocity", mul = 1.15 },
			{ stat = "rangeNear", mul = 1.2 },
			{ stat = "rangeFar", mul = 1.2 },
			{ stat = "recoilVert", mul = 1.1 }, -- more reach, more mule
			{ stat = "moveSpeedMult", add = -0.02 },
		},
	},
	ExtendedMag = {
		name = "Extended Mag 🍬",
		slot = "Mag",
		modifiers = {
			{ stat = "magSize", mul = 1.4 },
			{ stat = "reloadSeconds", mul = 1.15 },
			{ stat = "equipTime", mul = 1.1 },
		},
	},
	QuickdrawGrip = {
		name = "Quickdraw Grip ⚡",
		slot = "Grip",
		modifiers = {
			{ stat = "equipTime", mul = 0.8 },
			{ stat = "sprintToFire", mul = 0.8 },
			{ stat = "adsTime", mul = 0.85 },
			{ stat = "recoilVert", mul = 1.12 }, -- fast hands, wilder kick
		},
	},
	LaserSight = {
		name = "Laser Sight 💘",
		slot = "Sight",
		modifiers = {
			{ stat = "spreadDeg", mul = 0.75 }, -- tighter from the hip
			{ stat = "adsSpreadDeg", mul = 1.0 },
		},
	},
} :: { [string]: AttachmentDef }

function AttachmentConfig.get(id: string): AttachmentDef?
	return AttachmentConfig.attachments[id]
end

return AttachmentConfig
