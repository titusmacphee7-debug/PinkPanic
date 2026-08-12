--!strict
-- Attachments — the slots, the five-of-eight limit, and the rule that makes
-- the system worth having (NOD-150).
--
-- **Every attachment has at least one downside.** If an attachment is simply
-- better than not having it, it is not a choice — it is a mandatory tax, every
-- build converges on the same five, and the system may as well not exist.
--
-- That rule is CHECKED at boot, not trusted. `validate()` walks every
-- attachment in the game and flags by name any whose modifier set contains no
-- penalty. It found one the first time it ran: LaserSight carried
-- `adsSpreadDeg mul = 1.0`, which looks like a downside written down and is a
-- no-op, so the laser was a free hipfire upgrade.
--
-- The direction of a modifier is not this file's to decide — `CombatStats`
-- owns which way is better for every stat, because the loadout's stat bars
-- need the same answer and two tables would disagree the first time a stat was
-- added (Rule 2).
--
-- Nothing here equips anything yet. The slots, the limit and the rule come
-- first because they are what the rest of NOD-150 is built on top of, and
-- because the check is worth having the moment the second attachment exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local AttachmentConfig = require(ReplicatedStorage.Shared.Config.AttachmentConfig)

local SYSTEM = "Attachments"

local Attachments = {}

-- Eight slots exist; five may be equipped. The gap is the design.
local SLOTS: { AttachmentConfig.AttachmentSlot } = {
	"Optic",
	"Muzzle",
	"Barrel",
	"Underbarrel",
	"Magazine",
	"Stock",
	"RearGrip",
	"Laser",
}

Attachments.SLOTS = SLOTS
Attachments.MAX_EQUIPPED = 5

-- ---------------------------------------------------------------------------
-- Legality
--
-- Everything here is a pure function of the ids, so the SERVER can call it on
-- the profile and reach the same answer the UI predicted. The limit is enforced
-- where it is derived from — never in the UI, which is a suggestion.
-- ---------------------------------------------------------------------------

export type Problem = { code: string, detail: string }

-- Why a set of attachment ids may not be equipped together, or nil if it may.
-- Returns the FIRST reason rather than all of them: this answers a yes/no
-- question at the point of equipping, and the UI is what explains the rules.
function Attachments.reject(ids: { string }): Problem?
	if #ids > Attachments.MAX_EQUIPPED then
		return {
			code = "TooMany",
			detail = `{#ids} attachments, limit is {Attachments.MAX_EQUIPPED}`,
		}
	end

	local usedSlot: { [string]: string } = {}
	for _, id in ids do
		local def = AttachmentConfig.get(id)
		if not def then
			return { code = "Unknown", detail = `no attachment "{id}"` }
		end
		local taken = usedSlot[def.slot]
		if taken then
			return {
				code = "SlotTaken",
				detail = `{def.name} and {taken} both want the {def.slot} slot`,
			}
		end
		usedSlot[def.slot] = def.name
	end

	return nil
end

function Attachments.legal(ids: { string }): boolean
	return Attachments.reject(ids) == nil
end

-- ---------------------------------------------------------------------------
-- The trade-off audit
-- ---------------------------------------------------------------------------

export type Audit = {
	id: string,
	name: string,
	slot: string,
	benefits: { string },
	penalties: { string },
	-- Modifiers that change nothing. Called out separately from "no penalty"
	-- because they are usually a penalty someone MEANT to write — a `mul = 1.0`
	-- is a number that was going to be tuned and never was.
	inert: { string },
}

local function describe(modifier: AttachmentConfig.Modifier): string
	local stat = CombatStats.canonical(modifier.stat)
	if modifier.mul then
		return `{stat} x{modifier.mul}`
	end
	return `{stat} {if (modifier.add or 0) >= 0 then "+" else ""}{modifier.add}`
end

function Attachments.audit(id: string): Audit?
	local def = AttachmentConfig.get(id)
	if not def then
		return nil
	end

	local audit: Audit = {
		id = id,
		name = def.name,
		slot = def.slot,
		benefits = {},
		penalties = {},
		inert = {},
	}

	for _, modifier in def.modifiers do
		local direction = CombatStats.direction(modifier)
		local text = describe(modifier)
		if direction > 0 then
			table.insert(audit.benefits, text)
		elseif direction < 0 then
			table.insert(audit.penalties, text)
		else
			table.insert(audit.inert, text)
		end
	end

	return audit
end

-- The table, for tuning attachments by looking at them:
--
--   require(game.ReplicatedStorage.Shared.Systems.Attachments).report()
function Attachments.report(): string
	local ids: { string } = {}
	for id in AttachmentConfig.attachments do
		table.insert(ids, id)
	end
	table.sort(ids)

	local lines = {
		``,
		`  ATTACHMENTS — {#ids} of them, {#SLOTS} slots, {Attachments.MAX_EQUIPPED} equippable`,
		``,
	}
	for _, id in ids do
		local audit = Attachments.audit(id)
		if audit then
			table.insert(lines, string.format("  %-16s %-12s", audit.name, audit.slot))
			table.insert(lines, `      + {table.concat(audit.benefits, ", ")}`)
			table.insert(
				lines,
				if #audit.penalties > 0
					then `      - {table.concat(audit.penalties, ", ")}`
					else `      - NOTHING — this is a strict upgrade`
			)
			if #audit.inert > 0 then
				table.insert(lines, `      ~ does nothing: {table.concat(audit.inert, ", ")}`)
			end
		end
	end
	table.insert(lines, ``)

	local text = table.concat(lines, "\n")
	print(text)
	return text
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

function Attachments.validate()
	local problems: { string } = {}
	local slotNames: { [string]: boolean } = {}
	for _, slot in SLOTS do
		slotNames[slot] = true
	end

	local count, inertCount = 0, 0
	local bySlot: { [string]: number } = {}

	for id, def in AttachmentConfig.attachments do
		count += 1
		if not slotNames[def.slot] then
			table.insert(problems, `{id} is in slot "{def.slot}", which is not one of the {#SLOTS}`)
		end
		bySlot[def.slot] = (bySlot[def.slot] or 0) + 1

		local audit = Attachments.audit(id)
		if audit then
			-- **The rule.** An attachment with no penalty is not a choice.
			if #audit.penalties == 0 then
				table.insert(problems, `{def.name} has NO downside — it is a strict upgrade, not a choice`)
			end
			if #audit.benefits == 0 then
				table.insert(problems, `{def.name} has no upside — nobody would ever equip it`)
			end
			inertCount += #audit.inert
		end
	end

	if inertCount > 0 then
		-- A warning rather than a failure on its own: a no-op modifier is not
		-- broken, it is unfinished. It only becomes a problem when it was the
		-- thing standing in for the downside, which the check above catches.
		table.insert(problems, `{inertCount} modifier(s) change nothing at all (mul = 1 or add = 0)`)
	end

	-- Slots with nothing in them are not an error — the roster is being built —
	-- but they are worth naming, because an empty slot is a slot the player
	-- cannot use and five-of-eight stops meaning anything if only five exist.
	local empty: { string } = {}
	for _, slot in SLOTS do
		if not bySlot[slot] then
			table.insert(empty, slot)
		end
	end

	if #problems > 0 then
		Diagnostics.warn(
			SYSTEM,
			`{table.concat(problems, " · ")} — for the table run `
				.. `require(game.ReplicatedStorage.Shared.Systems.Attachments).report()`
		)
		return
	end

	Diagnostics.ok(
		SYSTEM,
		`{count} attachments over {#SLOTS} slots, {Attachments.MAX_EQUIPPED} equippable · `
			.. `every one has a downside`
			.. (if #empty > 0 then ` · {#empty} slot(s) still empty: {table.concat(empty, ", ")}` else "")
	)
end

Attachments.init = Attachments.validate

return Attachments
