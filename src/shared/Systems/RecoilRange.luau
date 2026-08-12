--!strict
-- RecoilRange — the recoil authoring harness (NOD-144).
--
-- "Fire 30 rounds at a wall and plot the grouping, so patterns can be tuned by
-- looking at them." This is that wall.
--
-- Nothing here runs at boot and nothing requires it. It is a tool you call by
-- hand from the Command Bar, in Edit mode, while tuning `Config/RecoilConfig`:
--
--     local Range = require(game.ReplicatedStorage.Shared.Systems.RecoilRange)
--     Range.chart("ar_sweetheart")        -- ASCII in Output, no geometry
--     Range.plot("ar_sweetheart")         -- a real board with real holes
--     Range.compare("ar_sweetheart")      -- same seed twice: identical?
--     Range.sweep()                       -- every gun, one line each
--     Range.clear()                       -- take the board back down
--
-- It draws NO bullets and fires NO weapons. It reads the same `Recoil.simulate`
-- the game runs, so a pattern that looks right here is the pattern you get —
-- there is no second implementation to drift.
--
-- **It only ever destroys the folder it made**, identified by the marker
-- attribute it sets, never by name alone. The place file is not in git.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local Recoil = require(ReplicatedStorage.Shared.Systems.Recoil)

local RecoilRange = {}

local FOLDER_NAME = "RecoilRange"
local MARKER = "PPRecoilRange"

-- Colours are literal here on purpose. `UI/Theme` is the rule for chrome the
-- player sees; this is a diagnostic board that only ever exists in Edit mode on
-- a developer's screen, and Theme lives in the client tree a shared module
-- cannot reach anyway.
local EARLY = Color3.fromRGB(255, 214, 235) -- shot 1: pale
local LATE = Color3.fromRGB(214, 32, 120) -- last shot: hot
local BOARD = Color3.fromRGB(38, 30, 38)

export type Options = {
	-- The seed is the whole point of the harness: pass one and the same call
	-- twice draws the same shape. Omit it and you get the spread of shapes a
	-- player would actually see across a match.
	seed: number?,
	-- Runs on the game's own shared generator instead of a seeded one. The point
	-- of it is that `compare` MUST fail with this set: a repeatability test that
	-- cannot fail is not measuring anything, and "identical twice" would be
	-- equally true of a pattern with no jitter in it at all.
	unseeded: boolean?,
	shots: number?,
	-- How far the wall is. Recoil is measured in degrees; a grouping is measured
	-- in studs, and the conversion is the distance.
	distanceStuds: number?,
	-- 0 = hip, 1 = fully aimed. Same number Handling produces.
	aim: number?,
	moveState: string?,
	scale: number?,
	origin: CFrame?,
}

local DEFAULT_SHOTS = 30
local DEFAULT_DISTANCE = 30
local DEFAULT_SEED = 20260812

-- ---------------------------------------------------------------------------
-- Where the shots land
-- ---------------------------------------------------------------------------

-- `x`/`y` are where the bullet went, in studs on the wall. `kickX`/`kickY` are
-- where the camera was thrown immediately after — the jolt you see, which on a
-- slow gun has recovered long before the next round and is therefore invisible
-- in the impacts alone.
export type Impact = { shot: number, x: number, y: number, kickX: number, kickY: number }

-- Degrees of camera offset become studs on a wall `distance` away. Tangent, not
-- the small-angle approximation: a shotgun aimed from the hip is 8.5° off and
-- the error there is real.
local function impacts(
	stats: CombatStats.Resolved,
	shots: number,
	distance: number,
	options: Options
): { Impact }
	local points = Recoil.simulate(stats, shots, {
		rng = if options.unseeded then nil else Random.new(options.seed or DEFAULT_SEED),
		modifier = Recoil.modifier(options.aim or 0, options.moveState, options.scale),
	})

	local out: { Impact } = {}
	for _, point in points do
		table.insert(out, {
			shot = point.shot,
			x = distance * math.tan(math.rad(point.yaw)),
			y = distance * math.tan(math.rad(point.pitch)),
			kickX = distance * math.tan(math.rad(point.kickYaw)),
			kickY = distance * math.tan(math.rad(point.kickPitch)),
		})
	end
	return out
end

local function resolve(gunId: string): CombatStats.Resolved
	local stats = CombatStats.forGun(gunId)
	if not stats then
		error(`RecoilRange: no gun "{gunId}" — try one of: {table.concat(RecoilRange.guns(), ", ")}`, 2)
	end
	return stats
end

function RecoilRange.guns(): { string }
	local ids: { string } = {}
	for id in GunCatalog.guns do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- ---------------------------------------------------------------------------
-- The ASCII chart
--
-- Deliberately first, and deliberately the one that needs no geometry: it works
-- from the Command Bar, from a cloud session, and in a bug report you can paste
-- into Linear. Looking at the shape is the whole job.
-- ---------------------------------------------------------------------------

local GLYPHS = "123456789abcdefghijklmnopqrstuvwxyz"

local function glyph(shot: number): string
	if shot <= #GLYPHS then
		return GLYPHS:sub(shot, shot)
	end
	return "*"
end

function RecoilRange.chart(gunId: string, options: Options?): string
	local settings: Options = options or {}
	local stats = resolve(gunId)
	local shots = settings.shots or DEFAULT_SHOTS
	local distance = settings.distanceStuds or DEFAULT_DISTANCE
	local hits = impacts(stats, shots, distance, settings)

	local width, height = 61, 25
	local centreColumn = math.floor(width / 2) + 1

	-- Square the axes — the same studs per cell both ways. A grid scaled
	-- independently per axis makes a straight vertical climb look like a diagonal,
	-- which is exactly the judgement the harness exists to support. Terminal cells
	-- are about twice as tall as they are wide, so that ratio is the conversion.
	local CELL_ASPECT = 2
	local right, top, bottom = 0.001, 0.001, 0
	for _, hit in hits do
		right = math.max(right, math.abs(hit.x))
		top = math.max(top, hit.y)
		bottom = math.min(bottom, hit.y)
	end

	-- Recoil goes UP, so a grid centred vertically spends half its rows empty.
	-- The origin sits two rows off the bottom instead, and the window grows to
	-- whatever the burst needs.
	local perColumn = math.max(right * 1.15 / (centreColumn - 1), (top - bottom) * 1.1 / ((height - 3) * CELL_ASPECT))
	local perRow = perColumn * CELL_ASPECT
	local centreRow = height - 2 + math.round(bottom / perRow)

	local grid: { { string } } = {}
	for row = 1, height do
		local line: { string } = {}
		for column = 1, width do
			line[column] = " "
		end
		grid[row] = line
	end

	for row = 1, height do
		grid[row][centreColumn] = "|"
	end
	if centreRow >= 1 and centreRow <= height then
		for column = 1, width do
			grid[centreRow][column] = "-"
		end
		grid[centreRow][centreColumn] = "+"
	end

	-- Later shots overwrite earlier ones on a collision, so a burst that walks
	-- off the top still reads in order.
	for _, hit in hits do
		local column = centreColumn + math.round(hit.x / perColumn)
		-- Screen rows run downward and pitch runs upward.
		local row = centreRow - math.round(hit.y / perRow)
		if column >= 1 and column <= width and row >= 1 and row <= height then
			grid[row][column] = glyph(hit.shot)
		end
	end

	local last = hits[#hits]
	local lines = {
		``,
		`  {stats.name}  ({stats.class})  ·  {shots} rounds  ·  wall at {distance} studs`,
		`  pattern "{stats.recoilPattern or "(class default)"}"  ·  aim {math.floor((settings.aim or 0) * 100)}%`
			.. `  ·  seed {settings.seed or DEFAULT_SEED}`,
		`  grid is {string.format("%.2f", perColumn * (width - 1))} studs across, `
			.. `{string.format("%.2f", perRow * (height - 1))} tall — axes square`,
		``,
	}
	for row = 1, height do
		table.insert(lines, "  " .. table.concat(grid[row]))
	end
	table.insert(lines, ``)
	table.insert(
		lines,
		`  last round sits {string.format("%.2f", last.y)} up, {string.format("%.2f", last.x)} right`
			.. `  ·  1-9 then a-z in firing order`
	)
	table.insert(lines, ``)

	local text = table.concat(lines, "\n")
	print(text)
	return text
end

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

local function container(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		if existing:GetAttribute(MARKER) ~= true then
			error(
				`RecoilRange: workspace.{FOLDER_NAME} exists but is not mine (no {MARKER} attribute). `
					.. `Refusing to touch it — rename yours or rename me.`,
				2
			)
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder:SetAttribute(MARKER, true)
	folder:SetAttribute("Purpose", "Recoil authoring harness (NOD-144). Debug only — delete freely.")
	folder.Parent = Workspace
	return folder
end

-- In front of whatever you are looking at, so the board appears where you can
-- see it without anyone typing a CFrame.
local function defaultOrigin(distance: number): CFrame
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.CFrame * CFrame.new(0, 0, -distance)
	end
	return CFrame.new(0, 20, -distance)
end

function RecoilRange.plot(gunId: string, options: Options?): Folder
	local settings: Options = options or {}
	local stats = resolve(gunId)
	local shots = settings.shots or DEFAULT_SHOTS
	local distance = settings.distanceStuds or DEFAULT_DISTANCE
	local hits = impacts(stats, shots, distance, settings)

	local origin = settings.origin or defaultOrigin(distance)
	local folder = container()

	local extent = 1
	for _, hit in hits do
		extent = math.max(extent, math.abs(hit.x), math.abs(hit.y))
	end
	local size = math.ceil(extent * 2.4)

	local board = Instance.new("Part")
	board.Name = "Board"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.Size = Vector3.new(size, size, 0.4)
	board.CFrame = origin
	board.Color = BOARD
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = folder

	-- The point you were aiming at before the trigger. Everything on the board is
	-- read relative to this, so it gets to be a different shape.
	local centre = Instance.new("Part")
	centre.Name = "Centre"
	centre.Anchored = true
	centre.CanCollide = false
	centre.CanQuery = false
	centre.Shape = Enum.PartType.Cylinder
	centre.Size = Vector3.new(0.1, 0.9, 0.9)
	centre.CFrame = origin * CFrame.new(0, 0, -0.25) * CFrame.Angles(0, math.rad(90), 0)
	centre.Color = Color3.fromRGB(255, 255, 255)
	centre.Material = Enum.Material.Neon
	centre.Transparency = 0.35
	centre.Parent = folder

	for _, hit in hits do
		local hole = Instance.new("Part")
		hole.Name = `Shot{hit.shot}`
		hole.Anchored = true
		hole.CanCollide = false
		hole.CanQuery = false
		hole.Shape = Enum.PartType.Ball
		hole.Size = Vector3.new(0.34, 0.34, 0.34)
		hole.CFrame = origin * CFrame.new(hit.x, hit.y, -0.3)
		hole.Material = Enum.Material.Neon
		-- Pale on the first round, hot on the last, so the ORDER of the climb is
		-- visible in a still screenshot. A grouping with no order in it can't
		-- tell you whether the gun is learnable.
		local t = if #hits > 1 then (hit.shot - 1) / (#hits - 1) else 0
		hole.Color = EARLY:Lerp(LATE, t)
		hole:SetAttribute("Shot", hit.shot)
		hole:SetAttribute("UpStuds", hit.y)
		hole:SetAttribute("RightStuds", hit.x)
		hole.Parent = folder
	end

	print(
		`[RecoilRange] {stats.name}: {shots} rounds on a {size}x{size} board {distance} studs out. `
			.. `Select a hole and read Shot/UpStuds/RightStuds. RecoilRange.clear() removes it.`
	)
	return folder
end

function RecoilRange.clear()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if not existing then
		return
	end
	if existing:GetAttribute(MARKER) ~= true then
		warn(`[RecoilRange] workspace.{FOLDER_NAME} is not mine — leaving it alone.`)
		return
	end
	existing:Destroy()
end

-- ---------------------------------------------------------------------------
-- Repeatability
--
-- NOD-144's done-when, as an assertion: "same gun, same 30 shots, twice —
-- identical grouping shape". Squinting at two screenshots is not a test.
-- ---------------------------------------------------------------------------

function RecoilRange.compare(gunId: string, options: Options?): (boolean, number)
	local settings: Options = options or {}
	local stats = resolve(gunId)
	local shots = settings.shots or DEFAULT_SHOTS
	local distance = settings.distanceStuds or DEFAULT_DISTANCE

	local first = impacts(stats, shots, distance, settings)
	local second = impacts(stats, shots, distance, settings)

	local worst = 0
	for index, a in first do
		local b = second[index]
		worst = math.max(worst, math.abs(a.x - b.x), math.abs(a.y - b.y))
	end
	return worst == 0, worst
end

-- Every gun, one line each. This is the check to run after touching
-- RecoilConfig: it says which guns changed shape and by how much.
function RecoilRange.sweep(options: Options?): boolean
	local settings: Options = options or {}
	local shots = settings.shots or DEFAULT_SHOTS
	local failures = 0
	-- Guns whose two UNSEEDED runs came out identical. That is the false-pass
	-- case: it means the seed is not what is pinning the shape, so the seeded
	-- result below proves nothing.
	local inert = 0
	local lines = {
		``,
		`  RECOIL SWEEP — {shots} rounds, seed {settings.seed or DEFAULT_SEED}, wall at `
			.. `{settings.distanceStuds or DEFAULT_DISTANCE} studs`,
		`  kick = the jolt off one shot · climb/drift = where the BULLETS went · `
			.. `a slow gun has all kick and no climb, which is correct`,
		``,
	}

	for _, id in RecoilRange.guns() do
		local stats = resolve(id)
		local identical, worst = RecoilRange.compare(id, settings)
		local loose = table.clone(settings)
		loose.unseeded = true
		local sameLoose = RecoilRange.compare(id, loose)
		if sameLoose then
			inert += 1
		end
		local hits = impacts(stats, shots, settings.distanceStuds or DEFAULT_DISTANCE, settings)
		local last = hits[#hits]
		local climb, drift, kick = 0, 0, 0
		for _, hit in hits do
			climb = math.max(climb, hit.y)
			drift = math.max(drift, math.abs(hit.x))
			-- How far the camera was thrown past where that bullet landed. On a
			-- sniper this is the entire recoil and `climb` is zero.
			kick = math.max(kick, hit.kickY - hit.y)
		end
		if not identical then
			failures += 1
		end
		table.insert(
			lines,
			string.format(
				"  %-22s %-10s kick %5.2f  climb %5.2f  drift %5.2f  ends %5.2f up %6.2f right  %s",
				stats.name,
				stats.recoilPattern or stats.class,
				kick,
				climb,
				drift,
				last.y,
				last.x,
				if identical then "repeatable" else `DIFFERS BY {worst}`
			)
		)
	end

	local total = #RecoilRange.guns()
	table.insert(lines, ``)
	table.insert(
		lines,
		if failures == 0
			then `  all {total} guns draw the same shape twice from the same seed`
			else `  {failures} gun(s) did NOT repeat — the pattern is reading something outside the seed`
	)
	table.insert(
		lines,
		if inert == 0
			then `  and all {total} draw a DIFFERENT shape unseeded — so the seed is what pinned it`
			else `  {inert} gun(s) repeated even unseeded — their jitter is dead, so "identical" proves nothing`
	)
	table.insert(lines, ``)
	print(table.concat(lines, "\n"))
	return failures == 0 and inert == 0
end

return RecoilRange
