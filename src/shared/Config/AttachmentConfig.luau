--!strict
-- AttachmentConfig — the attachment framework (future feature, wired now so
-- adding attachments later is pure data). An attachment occupies a slot and
-- carries stat modifiers; CombatStats.resolve(gunId, attachmentIds) applies
-- them: `mul` multiplies, `add` adds, in listed order, against the resolved
-- stat names (damageNear, rpm, magSize, reloadSeconds, spreadDeg, velocity,
-- drop, moveSpeedMult, equipTime, sprintToFire, adsTime, rangeNear,
-- rangeFar, headshotMult).
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
		name = "Quickdraw Grip 🎀",
		slot = "Grip",
		modifiers = {
			{ stat = "equipTime", mul = 0.8 },
			{ stat = "sprintToFire", mul = 0.8 },
			{ stat = "adsTime", mul = 0.85 },
		},
	},
	LongBarrel = {
		name = "Long Barrel 💫",
		slot = "Barrel",
		modifiers = {
			{ stat = "velocity", mul = 1.15 },
			{ stat = "rangeNear", mul = 1.2 },
			{ stat = "rangeFar", mul = 1.2 },
			{ stat = "moveSpeedMult", add = -0.02 },
		},
	},
	FeatherStock = {
		name = "Feather Stock ☁️",
		slot = "Stock",
		modifiers = {
			{ stat = "moveSpeedMult", add = 0.03 },
			{ stat = "spreadDeg", mul = 1.15 },
		},
	},
} :: { [string]: AttachmentDef }

function AttachmentConfig.get(id: string): AttachmentDef?
	return AttachmentConfig.attachments[id]
end

return AttachmentConfig
