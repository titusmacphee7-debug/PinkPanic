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

GunSockets.REQUIRED = REQUIRED
GunSockets.PURPOSE = PURPOSE

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

-- ---------------------------------------------------------------------------
-- The audit
-- ---------------------------------------------------------------------------

export type Row = {
	gunId: string,
	hasModel: boolean,
	missing: { string },
}

export type Report = {
	rows: { Row },
	total: number,
	withoutModel: number,
	fullyTagged: number,
	-- Socket name -> how many models are missing it. This is the number that
	-- says whether the roster needs one pass per socket or one pass per gun.
	missingBySocket: { [string]: number },
}

function GunSockets.audit(gunIds: { string }): Report
	local report: Report = {
		rows = {},
		total = #gunIds,
		withoutModel = 0,
		fullyTagged = 0,
		missingBySocket = {},
	}

	table.sort(gunIds)

	for _, gunId in gunIds do
		local model = GunSockets.model(gunId)
		if not model then
			report.withoutModel += 1
			table.insert(report.rows, { gunId = gunId, hasModel = false, missing = GunSockets.REQUIRED })
			continue
		end

		local gaps = GunSockets.missing(model)
		if #gaps == 0 then
			report.fullyTagged += 1
		end
		for _, name in gaps do
			report.missingBySocket[name] = (report.missingBySocket[name] or 0) + 1
		end
		table.insert(report.rows, { gunId = gunId, hasModel = true, missing = gaps })
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
		table.insert(lines, `  {row.gunId}  {table.concat(marks, "  ")}`)
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
end

return GunSockets
