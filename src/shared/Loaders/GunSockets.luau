--!strict
-- GunSockets — the socket contract every gun model must satisfy (NOD-137).
--
-- A gun is not a mesh. It is a mesh plus six named points that the rest of the
-- game asks questions of: where do bullets leave, where do shells come out,
-- where do the hands go, where does an optic mount, where does the magazine
-- sit. **Every one of them is tagged content. Nothing is inferred.**
--
-- The loader this replaces guessed. It picked the pivot by volume, put the
-- muzzle at whichever end of the bounding box looked forward, and decided
-- orientation from whether a part happened to be named `Grip`. Seven of the
-- thirty-two imported models had neither a Grip nor a Mag, so they pointed
-- backwards forever — and nothing anywhere said so, because a guess does not
-- know it guessed.
--
-- The difference this module makes is not that guessing is impossible. It is
-- that a missing socket has a NAME, appears in the boot manifest as a row in a
-- table, and can be fixed by the person who owns the model instead of debugged
-- by the person who owns the code.
--
-- Two modes:
--
--   · `GunSockets.get(model, name)` returns nil when a socket is absent, for
--     callers that have a sensible fallback (a tracer can start at the model's
--     nose and look almost right).
--   · `GunSockets.demand(model, name)` throws with the model's name, the
--     socket's name and what it is for. Used where a wrong answer is worse
--     than no answer — hands, and anything that decides which way a gun faces.
--
-- STRICT is off while the roster is still untagged. Turning it on makes the
-- whole game refuse to build a gun that is missing a socket, which is where
-- this should end up once the models carry them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunSockets = {}

-- Flip to true once every model in the roster is tagged. Until then it would
-- take combat from working to dead, which is a worse outcome than a gun that
-- ejects a shell from slightly the wrong place.
GunSockets.STRICT = false

export type SocketName = "Muzzle" | "EjectPort" | "Grip" | "LeftGrip" | "Sight" | "MagWell"

-- Order matters: this is the order the audit table prints in, and it runs
-- roughly from "combat is wrong without it" to "a cosmetic sits oddly".
--
-- Annotated as locals and then assigned. Luau has no type annotation on a
-- field assignment — `GunSockets.REQUIRED: { SocketName } = {...}` is a parse
-- error, not a slightly wrong type.
local REQUIRED: { SocketName } = { "Muzzle", "Grip", "EjectPort", "LeftGrip", "Sight", "MagWell" }

-- What each one is FOR, in the error message. A missing socket is a job for
-- whoever builds the model, and "Sight missing" tells them nothing they can
-- act on; "Sight — where an optic mounts" tells them where to put it.
local PURPOSE: { [string]: string } = {
	Muzzle = "where bullets leave and the flash spawns",
	EjectPort = "where shells come out",
	Grip = "where the right hand goes",
	LeftGrip = "where the left hand goes",
	Sight = "where an optic mounts",
	MagWell = "where the magazine sits",
}

-- Attachment mount points (NOD-149). Optional, and reported rather than
-- demanded: a gun with no under-barrel rail is a design decision, not a broken
-- model. What the report is for is telling you WHICH attachment slots a gun can
-- physically accept before M4 tries to hang something off a socket that is not
-- there.
local MOUNTS: { string } = {
	"Mount_Optic",
	"Mount_Barrel",
	"Mount_Under",
	"Mount_Laser",
	"Mount_Stock",
	"Mount_Charm",
}

-- ---------------------------------------------------------------------------
-- Skin regions (NOD-149)
--
-- **A camo textures part of the gun and colours the rest.** Like CoD, but pink:
-- there are no grey-and-metal weapons in this game. `Body` and `Panel` take the
-- camo texture; `Grip`, `Hardware` and `Accent` take the camo's palette, or the
-- equipped skin's colour when the camo does not name one.
--
-- The consequence is a MODELLING requirement, which is why it is checked here
-- and not in the shop: if a modeller merges the grip into the body to save a
-- part, that grip gets textured with the receiver, the skin under it disappears,
-- and there is no layer left to make it pink. Regions must survive into the
-- built model as separate parts, so the validator counts them.
local TEXTURED: { string } = { "Body", "Panel" }
local COLOURED: { string } = { "Grip", "Hardware", "Accent" }

-- The parts the viewmodel cycles: slide blowback, pump strokes, cylinder
-- notches, mag drops on reload. A part that is not named does not move.
-- Optional per gun — a revolver has no slide — so these are reported, never
-- demanded.
local MOVING: { string } = { "Slide", "Bolt", "Pump", "Cylinder", "Mag" }

GunSockets.REQUIRED = REQUIRED
GunSockets.PURPOSE = PURPOSE
GunSockets.MOUNTS = MOUNTS
GunSockets.TEXTURED = TEXTURED
GunSockets.COLOURED = COLOURED
GunSockets.MOVING = MOVING

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- Attachments only. A PART named "Muzzle" is not a muzzle — it is a piece of
-- geometry someone named hopefully, and treating it as a socket is how the
-- previous loader ended up placing a muzzle inside a stock.
function GunSockets.get(model: Instance, name: string): Attachment?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

function GunSockets.demand(model: Instance, name: string): Attachment
	local attachment = GunSockets.get(model, name)
	if attachment then
		return attachment
	end
	error(
		`[PinkPanic] gun model "{model.Name}" has no "{name}" attachment — `
			.. `{GunSockets.PURPOSE[name] or "required socket"}. `
			.. `Add an Attachment with that exact name inside the model, in Studio.`,
		2
	)
end

-- Every socket a model is missing, in REQUIRED order.
function GunSockets.missing(model: Instance): { string }
	local gaps: { string } = {}
	for _, name in GunSockets.REQUIRED do
		if not GunSockets.get(model, name) then
			table.insert(gaps, name)
		end
	end
	return gaps
end

function GunSockets.tagged(model: Instance): boolean
	return #GunSockets.missing(model) == 0
end

-- Which mount points a model actually carries, so M4 knows what it may offer.
function GunSockets.mounts(model: Instance): { string }
	local found: { string } = {}
	for _, name in MOUNTS do
		if GunSockets.get(model, name) then
			table.insert(found, name)
		end
	end
	return found
end

-- Parts, not attachments. A region IS geometry — that is the whole point of
-- requiring it to survive as its own part — so unlike the sockets this looks
-- for BaseParts and honours the per-part `TakesCamo` override.
local function partsNamed(model: Instance, names: { string }): { string }
	local wanted: { [string]: boolean } = {}
	for _, name in names do
		wanted[name] = true
	end
	local seen: { [string]: boolean } = {}
	local found: { string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and wanted[descendant.Name] and not seen[descendant.Name] then
			seen[descendant.Name] = true
			table.insert(found, descendant.Name)
		end
	end
	return found
end

export type Regions = {
	textured: { string },
	coloured: { string },
	moving: { string },
	-- The two failure modes NOD-149 names, both of which produce a gun that is
	-- in the shop and cannot be dressed:
	problems: { string },
}

function GunSockets.regions(model: Instance): Regions
	local textured = partsNamed(model, TEXTURED)
	local coloured = partsNamed(model, COLOURED)
	local problems: { string } = {}

	if #textured == 0 then
		table.insert(problems, "no Body or Panel — this gun can never wear a camo")
	end
	if #coloured == 0 then
		table.insert(problems, "no Grip/Hardware/Accent — nothing for a palette to colour, so it reads as bare metal")
	end

	return {
		textured = textured,
		coloured = coloured,
		moving = partsNamed(model, MOVING),
		problems = problems,
	}
end

-- ---------------------------------------------------------------------------
-- Attachment models (NOD-149 / NOD-150)
--
-- Attachments are commissioned as their own models and welded to a gun's
-- `Mount_*` socket at runtime — which means a mounted attachment becomes a
-- DESCENDANT of the gun, and every scan in this file finds parts and
-- attachments by name. So an attachment carrying a part named `Body` is counted
-- as one of the gun's camo regions, and one carrying an `Attachment` named
-- `Muzzle` becomes the gun's muzzle.
--
-- That is a naming collision that only appears once something is equipped, on
-- a model that validated perfectly on its own. It is checked here instead.
-- ---------------------------------------------------------------------------

-- Every name the gun scans reserve. An attachment may use none of them.
local RESERVED: { string } = {
	"Muzzle",
	"Grip",
	"EjectPort",
	"LeftGrip",
	"Sight",
	"MagWell",
	"Body",
	"Panel",
	"Hardware",
	"Accent",
	"Slide",
	"Bolt",
	"Pump",
	"Cylinder",
	"Mag",
}

GunSockets.RESERVED = RESERVED

export type AttachmentReport = {
	id: string,
	hasAnchor: boolean,
	hasAimPoint: boolean,
	collisions: { string },
	problems: { string },
}

-- `isOptic` decides whether `AimPoint` is demanded. Passed in rather than
-- inferred from the model, because the slot is config (`AttachmentConfig`) and
-- this file reads content — guessing "it has a lens so it is an optic" is
-- exactly the kind of inference that put seven guns backwards.
function GunSockets.auditAttachment(model: Instance, isOptic: boolean): AttachmentReport
	local report: AttachmentReport = {
		id = model.Name,
		hasAnchor = GunSockets.get(model, "Anchor") ~= nil,
		hasAimPoint = GunSockets.get(model, "AimPoint") ~= nil,
		collisions = {},
		problems = {},
	}

	local reserved: { [string]: boolean } = {}
	for _, name in RESERVED do
		reserved[name] = true
	end
	local seen: { [string]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if reserved[descendant.Name] and not seen[descendant.Name] then
			seen[descendant.Name] = true
			table.insert(report.collisions, descendant.Name)
		end
	end

	if not report.hasAnchor then
		table.insert(report.problems, "no Anchor — nothing to weld to the mount, and no orientation to weld it in")
	end
	if isOptic and not report.hasAimPoint then
		table.insert(
			report.problems,
			"no AimPoint — aiming through this optic has no eye position, and there is no number to tune later"
		)
	end
	if #report.collisions > 0 then
		table.insert(
			report.problems,
			`uses reserved name(s) {table.concat(report.collisions, ", ")} — once mounted these are read as the GUN's`
		)
	end

	return report
end

-- ---------------------------------------------------------------------------
-- Where the models live
-- ---------------------------------------------------------------------------

function GunSockets.folder(): Instance?
	local direct = ReplicatedStorage:FindFirstChild("GunModels")
	if direct then
		return direct
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Guns")
end

function GunSockets.model(gunId: string): Model?
	local folder = GunSockets.folder()
	local found = folder and folder:FindFirstChild(gunId)
	return if found and found:IsA("Model") then found else nil
end

function GunSockets.attachmentFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Attachments")
end

function GunSockets.attachmentModel(id: string): Model?
	local folder = GunSockets.attachmentFolder()
	local found = folder and folder:FindFirstChild(id)
	return if found and found:IsA("Model") then found else nil
end

-- Every attachment in the config, against its model. Printed on its own rather
-- than folded into the gun table: they are a different commission, delivered in
-- a different batch, and "which guns are missing sockets" and "which
-- attachments are missing an AimPoint" are two different jobs for two different
-- people.
function GunSockets.printAttachmentReport()
	local AttachmentConfig = require(ReplicatedStorage.Shared.Config.AttachmentConfig)

	local ids: { string } = {}
	for id in AttachmentConfig.attachments do
		table.insert(ids, id)
	end
	table.sort(ids)

	local missing, clean = 0, 0
	local lines: { string } = {}
	for _, id in ids do
		local def = AttachmentConfig.get(id)
		local model = GunSockets.attachmentModel(id)
		if not model then
			missing += 1
			table.insert(lines, `  {id}  — NO MODEL`)
			continue
		end
		local report = GunSockets.auditAttachment(model, def ~= nil and def.slot == "Optic")
		if #report.problems == 0 then
			clean += 1
			table.insert(lines, `  {id}  ok`)
		else
			for _, problem in report.problems do
				table.insert(lines, `  {id}  {problem}`)
			end
		end
	end

	print(`[PinkPanic] attachment models — {clean}/{#ids} clean, {missing} with no model at all`)
	for _, line in lines do
		print(line)
	end
	print(`  spec: docs/GUN_MODEL_SPEC.md section 7`)
end

-- ---------------------------------------------------------------------------
-- The audit
-- ---------------------------------------------------------------------------

export type Row = {
	gunId: string,
	hasModel: boolean,
	missing: { string },
	regions: Regions?,
	mounts: { string }?,
}

export type Report = {
	rows: { Row },
	total: number,
	withoutModel: number,
	fullyTagged: number,
	-- Socket name -> how many models are missing it. This is the number that
	-- says whether the roster needs one pass per socket or one pass per gun.
	missingBySocket: { [string]: number },
	-- Models that can never be dressed: no camo-taking region, or nothing left
	-- for a palette to colour. Separate from sockets because it is a different
	-- job for the modeller — splitting a merged part, not adding an attachment.
	regionProblems: { string },
}

function GunSockets.audit(gunIds: { string }): Report
	local report: Report = {
		rows = {},
		total = #gunIds,
		withoutModel = 0,
		fullyTagged = 0,
		missingBySocket = {},
		regionProblems = {},
	}

	table.sort(gunIds)

	for _, gunId in gunIds do
		local model = GunSockets.model(gunId)
		if not model then
			report.withoutModel += 1
			-- Cloned, not aliased. Handing out REQUIRED itself means any caller
			-- that sorts or trims a row's `missing` list silently rewrites the
			-- socket spec for the rest of the session.
			table.insert(report.rows, { gunId = gunId, hasModel = false, missing = table.clone(REQUIRED) })
			continue
		end

		local gaps = GunSockets.missing(model)
		if #gaps == 0 then
			report.fullyTagged += 1
		end
		for _, name in gaps do
			report.missingBySocket[name] = (report.missingBySocket[name] or 0) + 1
		end

		local regions = GunSockets.regions(model)
		for _, problem in regions.problems do
			table.insert(report.regionProblems, `{gunId}: {problem}`)
		end

		table.insert(report.rows, {
			gunId = gunId,
			hasModel = true,
			missing = gaps,
			regions = regions,
			mounts = GunSockets.mounts(model),
		})
	end

	return report
end

-- The table, as text. Printed rather than returned as data because the point
-- of it is to be READ by the person who has to add the attachments.
function GunSockets.formatReport(report: Report): { string }
	local lines: { string } = {}

	local header = "  gun"
	for _, name in GunSockets.REQUIRED do
		header ..= `  {name}`
	end
	table.insert(lines, header)

	for _, row in report.rows do
		if not row.hasModel then
			table.insert(lines, `  {row.gunId}  — NO MODEL`)
			continue
		end
		local marks: { string } = {}
		local gaps: { [string]: boolean } = {}
		for _, name in row.missing do
			gaps[name] = true
		end
		for _, name in GunSockets.REQUIRED do
			table.insert(marks, if gaps[name] then `{name}?` else name)
		end
		local line = `  {row.gunId}  {table.concat(marks, "  ")}`

		local regions = row.regions
		if regions then
			line ..= `  |  skin {#regions.textured}T/{#regions.coloured}C`
			if #regions.moving > 0 then
				line ..= ` · moves: {table.concat(regions.moving, ",")}`
			end
			if #row.mounts :: number > 0 then
				line ..= ` · mounts: {#row.mounts :: number}/{#GunSockets.MOUNTS}`
			end
		end
		table.insert(lines, line)
	end

	if #report.regionProblems > 0 then
		table.insert(lines, "")
		table.insert(lines, "  CANNOT BE DRESSED — these need a part split, not an attachment:")
		for _, problem in report.regionProblems do
			table.insert(lines, `    {problem}`)
		end
	end

	return lines
end

-- The whole thing, from nothing, in one Command Bar line:
--
--   require(game.ReplicatedStorage.Shared.Loaders.GunSockets).printReport()
--
-- Zero arguments on purpose. The boot warning names this call, and a warning
-- that names a call you then have to work out the arguments for is a warning
-- most people do not run.
function GunSockets.printReport()
	local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
	local ids: { string } = {}
	for gunId in GunCatalog.guns do
		table.insert(ids, gunId)
	end

	local report = GunSockets.audit(ids)
	print(
		`[PinkPanic] gun sockets — {report.fullyTagged}/{report.total - report.withoutModel} models fully tagged`
			.. (if report.withoutModel > 0 then `, {report.withoutModel} with no model at all` else "")
	)
	for _, line in GunSockets.formatReport(report) do
		print(line)
	end
	print("  a name followed by ? is the socket that model is missing")
	print("  skin nT/nC = how many camo-TEXTURED and palette-COLOURED regions survived as separate parts")
	print(`  spec: docs/GUN_MODEL_SPEC.md`)
end

return GunSockets
