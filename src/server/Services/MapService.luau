--!strict
-- MapService — decides which arena a round is played in.
--
-- ⚠️ THIS FILE STILL CONTAINS A MAP GENERATOR, AND IT SHOULD NOT.
--
-- CLAUDE.md is unambiguous: "Never generate lobbies or maps. Earlier versions
-- built a placeholder plaza and arena procedurally; it got baked into saved
-- place files and kept coming back after Titus built his own. All generator
-- code was deleted on purpose. Do not reintroduce it."
--
-- This one survived the wipe. It builds a full "Pink Mall" — floor, walls,
-- fountain, kiosks, two walkways, ramps and ten spawn pads — into
-- workspace.PinkPanicMap, and it does so on EVERY boot where no hand-built
-- Arena exists. For a long time it reported "OK" with no detail while doing
-- it, which is the exact silent-success the boot manifest exists to end.
--
-- It is kept only as a place to stand while the real map is built, and it is
-- now LOUD about being a placeholder. Delete `buildFloorAndWalls` and
-- everything it calls the day a real Arena is finished — the selection logic
-- at the bottom is the part worth keeping.
--
-- A Workspace folder named exactly "Arena" wins over it, always.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

local SYSTEM = "MapService"
local MAP_NAME = "PinkPanicMap"

-- The arena generates FAR from the world origin so it can never overlap or
-- interfere with hand-built content (the lobby town lives near origin).
-- Players only ever reach it via round spawns, so distance is free.
local ARENA_ORIGIN = Vector3.new(0, 0, 1400)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local BUBBLEGUM = Color3.fromRGB(255, 130, 190)
local BLUSH = Color3.fromRGB(255, 227, 240)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)
local PLUM_DARK = Color3.fromRGB(92, 72, 88)

local MapService = {}

local folder: Folder? = nil

type PartProps = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	shape: ("Block" | "Cylinder" | "Ball" | "Wedge")?,
}

local function mk(props: PartProps): BasePart
	local part: BasePart
	if props.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if props.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif props.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end
	part.Name = props.name
	part.Size = props.size
	part.CFrame = CFrame.new(ARENA_ORIGIN) * props.cframe
	part.Color = props.color
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = true
	part.Parent = folder
	return part
end

-- Vertical cylinder (Roblox cylinders lie on the X axis by default).
local function column(name: string, diameter: number, height: number, position: Vector3, color: Color3): BasePart
	return mk({
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		shape = "Cylinder",
	})
end

local function buildFloorAndWalls()
	mk({ name = "Floor", size = Vector3.new(210, 1, 150), cframe = CFrame.new(0, 0, 0), color = PINK_WHITE })
	column("Plaza", 60, 0.2, Vector3.new(0, 0.6, 0), BLUSH)

	-- Perimeter walls with a pink trim band.
	local walls = {
		{ size = Vector3.new(2, 24, 150), pos = Vector3.new(105, 12, 0) },
		{ size = Vector3.new(2, 24, 150), pos = Vector3.new(-105, 12, 0) },
		{ size = Vector3.new(210, 24, 2), pos = Vector3.new(0, 12, 75) },
		{ size = Vector3.new(210, 24, 2), pos = Vector3.new(0, 12, -75) },
	}
	for index, wall in walls do
		mk({ name = `Wall{index}`, size = wall.size, cframe = CFrame.new(wall.pos), color = PINK_WHITE })
		local trimSize = if wall.size.X > wall.size.Z
			then Vector3.new(wall.size.X, 1.2, 2.4)
			else Vector3.new(2.4, 1.2, wall.size.Z)
		mk({ name = `Trim{index}`, size = trimSize, cframe = CFrame.new(wall.pos.X, 10, wall.pos.Z), color = HOT_PINK })
	end

	-- "PINK PANIC" sign on the north wall's inner face.
	local sign = mk({
		name = "Sign",
		size = Vector3.new(60, 10, 0.4),
		cframe = CFrame.new(0, 16, 73.6),
		color = BLUSH,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 100)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = HOT_PINK
	label.Text = "🎀 PINK PANIC 🎀"
	label.Parent = gui
	gui.Parent = sign
end

local function buildFountain()
	column("FountainBase", 20, 2, Vector3.new(0, 1.5, 0), PINK_WHITE)
	column("FountainWater", 17, 0.6, Vector3.new(0, 2.6, 0), BLUSH)
	column("FountainMid", 11, 3, Vector3.new(0, 4, 0), BUBBLEGUM)
	column("FountainTop", 6, 4, Vector3.new(0, 7.5, 0), PINK_WHITE)
	mk({
		name = "FountainHeart",
		size = Vector3.new(3, 3, 3),
		cframe = CFrame.new(0, 11, 0),
		color = HOT_PINK,
		material = Enum.Material.Neon,
		shape = "Ball",
	})

	-- Planter ring around the fountain: cover that breaks mid sightlines.
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 30)
		local x = math.cos(angle) * 24
		local z = math.sin(angle) * 24
		mk({
			name = "FountainPlanter",
			size = Vector3.new(6, 3, 6),
			cframe = CFrame.new(x, 2, z) * CFrame.Angles(0, -angle, 0),
			color = BUBBLEGUM,
		})
	end
end

-- One long side of the mall: raised shop platform + kiosks + upper walkway.
local function buildWing(sign: number)
	local z = sign
	mk({
		name = "ShopPlatform",
		size = Vector3.new(190, 2, 18),
		cframe = CFrame.new(0, 1.5, 64 * z),
		color = BLUSH,
	})
	-- Step up onto the platform along its inner edge.
	mk({
		name = "ShopStep",
		size = Vector3.new(190, 1, 3),
		cframe = CFrame.new(0, 1, 53.5 * z),
		color = PINK_WHITE,
	})

	for index, x in { -70, -25, 25, 70 } do
		mk({
			name = "Kiosk",
			size = Vector3.new(12, 9, 12),
			cframe = CFrame.new(x, 7, 64 * z),
			color = if index % 2 == 0 then PINK_WHITE else BUBBLEGUM,
		})
		mk({
			name = "KioskAwning",
			size = Vector3.new(14, 0.8, 14),
			cframe = CFrame.new(x, 11.8, 64 * z),
			color = HOT_PINK,
		})
	end

	-- Second-floor walkway with railing, held up by columns.
	mk({
		name = "Walkway",
		size = Vector3.new(180, 2, 12),
		cframe = CFrame.new(0, 14, 58 * z),
		color = PINK_WHITE,
	})
	mk({
		name = "WalkwayRail",
		size = Vector3.new(180, 2.6, 0.6),
		cframe = CFrame.new(0, 16, 51.8 * z),
		color = HOT_PINK,
		transparency = 0.2,
	})
	for _, x in { -80, -40, 0, 40, 80 } do
		column("WalkwayColumn", 3, 13, Vector3.new(x, 6.5, 52.5 * z), PINK_WHITE)
	end

	-- Corner ramps up to the walkway. WedgePart slopes rise toward its back
	-- (+Z) face, so the north ramp uses default yaw and the south flips 180°.
	for _, x in { -78, 78 } do
		local yaw = if z > 0 then 0 else math.rad(180)
		mk({
			name = "WalkwayRamp",
			size = Vector3.new(12, 14.5, 28),
			cframe = CFrame.new(x, 7.75, 38 * z) * CFrame.Angles(0, yaw, 0),
			color = BLUSH,
			shape = "Wedge",
		})
	end
end

local function buildCenterCover()
	for _, x in { -30, 30 } do
		for _, z in { -20, 20 } do
			mk({
				name = "CenterKiosk",
				size = Vector3.new(8, 6, 8),
				cframe = CFrame.new(x, 3.5, z),
				color = PINK_WHITE,
			})
			mk({
				name = "CenterAwning",
				size = Vector3.new(9.5, 0.6, 9.5),
				cframe = CFrame.new(x, 6.8, z),
				color = BUBBLEGUM,
			})
		end
	end
	for _, x in { -55, 55 } do
		mk({ name = "Bench", size = Vector3.new(3, 2, 10), cframe = CFrame.new(x, 1.5, 0), color = BUBBLEGUM })
	end
	for _, x in { -65, 65 } do
		for _, z in { -32, 32 } do
			mk({ name = "Planter", size = Vector3.new(5, 4, 5), cframe = CFrame.new(x, 2.5, z), color = HOT_PINK })
		end
	end
	-- Decorative arch gates near each short end.
	for _, x in { -92, 92 } do
		for _, z in { -12, 12 } do
			column("GatePillar", 4, 20, Vector3.new(x, 10, z), PINK_WHITE)
		end
		mk({ name = "GateLintel", size = Vector3.new(4, 4, 30), cframe = CFrame.new(x, 21, 0), color = HOT_PINK })
	end
end

local function buildSpawns()
	local positions = {
		Vector3.new(85, 1.3, 45),
		Vector3.new(-85, 1.3, 45),
		Vector3.new(85, 1.3, -45),
		Vector3.new(-85, 1.3, -45),
		Vector3.new(96, 1.3, 0),
		Vector3.new(-96, 1.3, 0),
		Vector3.new(50, 15.6, 58),
		Vector3.new(-50, 15.6, 58),
		Vector3.new(50, 15.6, -58),
		Vector3.new(-50, 15.6, -58),
	}
	for index, position in positions do
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = `Spawn{index}`
		spawnLocation.Size = Vector3.new(6, 0.6, 6)
		spawnLocation.CFrame = CFrame.new(position + ARENA_ORIGIN)
		spawnLocation.Color = HOT_PINK
		spawnLocation.Material = Enum.Material.Neon
		spawnLocation.Transparency = 0.4
		spawnLocation.Anchored = true
		spawnLocation.CanCollide = true
		spawnLocation.Neutral = true
		spawnLocation.Duration = 0 -- CombatService applies its own protection window
		spawnLocation.Parent = folder
	end
end

-- Counts what a map actually offers to spawn on, so the manifest can say
-- "your Arena has no spawn points" instead of a round quietly dropping
-- everyone at the world origin.
local function countSpawns(container: Instance): number
	local count = 0
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("SpawnLocation") or descendant:GetAttribute("PPSpawn") then
			count += 1
		end
	end
	return count
end

function MapService.init()
	local existing = workspace:FindFirstChild(MAP_NAME)

	-- A hand-built map named "Arena" replaces the generated mall entirely:
	-- put SpawnLocations or PPSpawn-tagged parts inside it and rounds happen
	-- there. Any saved generated mall gets cleaned up.
	local arena = workspace:FindFirstChild("Arena")
	if arena then
		local removed = ""
		if existing then
			existing:Destroy()
			removed = ", removed a leftover generated mall"
		end

		local spawns = countSpawns(arena)
		if spawns == 0 then
			Diagnostics.warn(
				SYSTEM,
				`hand-built Arena in use{removed} — but it has NO spawn points. `
					.. "Add SpawnLocations, or parts with a PPSpawn attribute."
			)
			return
		end

		Diagnostics.ok(SYSTEM, `hand-built Arena, {spawns} spawn point(s){removed}`)
		return
	end

	-- A mall saved from an older session at the wrong location (or without
	-- the origin stamp) is stale: destroy and regenerate in place.
	if existing then
		if existing:GetAttribute("ArenaOrigin") == ARENA_ORIGIN then
			Diagnostics.warn(
				SYSTEM,
				`running on the GENERATED placeholder mall ({countSpawns(existing)} spawns). `
					.. "Build a Workspace folder named exactly 'Arena' to replace it — see CLAUDE.md."
			)
			return
		end
		existing:Destroy()
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = MAP_NAME
	newFolder:SetAttribute("ArenaOrigin", ARENA_ORIGIN)
	folder = newFolder

	buildFloorAndWalls()
	buildFountain()
	buildWing(1)
	buildWing(-1)
	buildCenterCover()
	buildSpawns()

	newFolder.Parent = workspace

	-- Retire stray spawns (e.g. the Baseplate's) — but NEVER touch the
	-- hand-built lobby's spawn pads; LobbyService owns those.
	local lobby = workspace:FindFirstChild("Lobby")
	for _, descendant in workspace:GetDescendants() do
		if
			descendant:IsA("SpawnLocation")
			and not descendant:IsDescendantOf(newFolder)
			and not (lobby and descendant:IsDescendantOf(lobby))
		then
			descendant.Enabled = false
		end
	end

	-- Loud on purpose, every boot, until a real Arena exists. This generator
	-- is the thing CLAUDE.md says was deleted; a silent OK is how it survived
	-- long enough to be generating a mall nobody knew about.
	Diagnostics.warn(
		SYSTEM,
		`GENERATED a placeholder mall ({countSpawns(newFolder)} spawns) because no Arena exists. `
			.. "Build a Workspace folder named exactly 'Arena' and this stops — see CLAUDE.md."
	)
end

return MapService
