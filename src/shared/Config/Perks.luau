--!strict
-- Perks — data only. Empty on purpose (NOD-130).
--
-- The perk system itself is M8. This file exists now so the modifier pipeline
-- is REAL rather than stubbed: CombatStats already reads perks, already
-- validates their modifier names at boot, and already includes them in its
-- cache key. When M8 arrives it adds entries here and changes nothing else.
--
-- The alternative — a resolver that quietly ignores a perkIds argument until
-- some later milestone wires it up — is the exact silent-no-op this rebuild is
-- getting rid of. A pipeline with zero perks in it is honest. A pipeline that
-- pretends to apply perks is not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AttachmentConfig = require(ReplicatedStorage.Shared.Config.AttachmentConfig)

-- Perks and attachments modify stats through the SAME pipeline, so they share
-- the same modifier shape. One modifier path in this game, not three.
export type Modifier = AttachmentConfig.Modifier

export type PerkSlot = "Perk1" | "Perk2" | "Perk3"

export type PerkDef = {
	name: string,
	slot: PerkSlot,
	-- Statistical perks carry modifiers. Behavioural ones (Ghost, High Alert)
	-- carry none and get an explicit hook in their own system instead of being
	-- forced through stats.
	modifiers: { Modifier },
}

local Perks = {}

Perks.perks = {} :: { [string]: PerkDef }

function Perks.get(id: string): PerkDef?
	return Perks.perks[id]
end

return Perks
