--!strict
-- LobbyService — the hand-built lobby's server half (NOD-41, NOD-42).
-- Titus's town in workspace.Lobby IS the lobby; this service dresses its
-- attribute-tagged pads with floating name signs, owns which spawn set is
-- live (lobby vs arena), and validates the cosmetic click-to-shoot pops.
--
-- The old code-generated placeholder plaza is GONE — deleted, not disabled.
-- Any copy of it saved into a place file gets destroyed at boot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)

local LEGACY_LOBBY_NAME = "PinkPanicLobby" -- retired generated plaza
local ARENA_NAMES = { "PinkPanicMap", "Arena" }

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)

local LobbyService = {}

local poppedTargets: { [BasePart]: boolean } = {}

local function sign(text: string, position: Vector3, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = CFrame.new(position)
	anchor.Color = PINK_WHITE
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(340, 56)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 220
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = HOT_PINK
	label.TextStrokeColor3 = PINK_WHITE
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard
	billboard.Parent = anchor

	anchor.Parent = parent
end

-- Round flow: arena spawns live only while a round is Active. Works with the
-- generated mall OR a hand-built map folder named "Arena".
function LobbyService.setArenaActive(active: boolean)
	for _, containerName in ARENA_NAMES do
		local arena = workspace:FindFirstChild(containerName)
		if arena then
			for _, child in arena:GetDescendants() do
				if child:IsA("SpawnLocation") then
					child.Enabled = active
				end
			end
		end
	end
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		for _, child in lobby:GetDescendants() do
			if child:IsA("SpawnLocation") then
				child.Enabled = not active
			end
		end
	end
end

local function onLobbyShot(player: Player, hitPosition: any, hitInstance: any)
	if not Guard.checkRate(player, "LobbyShot", 6, 1) then
		return
	end
	if not Guard.isVector3(hitPosition) then
		return
	end

	-- Everyone sees the tracer from the shooter's held gun.
	local character = player.Character
	local gun = character and character:FindFirstChild("WorldGun")
	local origin = if gun and gun:IsA("Model") and gun.PrimaryPart
		then gun.PrimaryPart.Position
		else (if character and character.PrimaryPart then character.PrimaryPart.Position else nil)
	if not origin then
		return
	end
	if (hitPosition - origin).Magnitude > 250 then
		return
	end
	Remotes.event("ShotFired"):FireAllClients(player, origin, hitPosition)

	-- Balloon pops: any part tagged LobbyTarget inside the lobby (so a
	-- hand-built range works the same as the old generated one).
	local lobby = workspace:FindFirstChild("Lobby")
	if
		typeof(hitInstance) == "Instance"
		and hitInstance:IsA("BasePart")
		and lobby
		and hitInstance:IsDescendantOf(lobby)
		and hitInstance:GetAttribute("LobbyTarget")
		and not poppedTargets[hitInstance]
		and (hitInstance.Position - hitPosition).Magnitude < 8
	then
		local balloon = hitInstance
		poppedTargets[balloon] = true
		Remotes.event("TargetPopped"):FireAllClients(balloon.Position, balloon.Color)
		balloon.Transparency = 1
		balloon.CanQuery = false
		task.delay(2.5, function()
			balloon.Transparency = 0
			balloon.CanQuery = true
			poppedTargets[balloon] = nil
		end)
	end
end

-- Measures the hand-built lobby: the floor level and the horizontal extent
-- of everything in it, so generated pieces land on the ground and frame the
-- whole town instead of guessing at coordinates.
local function lobbyBounds(lobby: Instance): (Vector3, Vector3)?
	local min: Vector3? = nil
	local max: Vector3? = nil
	for _, child in lobby:GetDescendants() do
		if child:IsA("BasePart") then
			local half = child.Size / 2
			local lo = child.Position - half
			local hi = child.Position + half
			min = if min then Vector3.new(math.min(min.X, lo.X), math.min(min.Y, lo.Y), math.min(min.Z, lo.Z)) else lo
			max = if max then Vector3.new(math.max(max.X, hi.X), math.max(max.Y, hi.Y), math.max(max.Z, hi.Z)) else hi
		end
	end
	if not min or not max then
		return nil
	end
	return min, max
end

-- Drops a spawn pad on the ground at a position (raycast down to whatever
-- the town is built on, so pads never float or sink).
local function groundedY(lobby: Instance, x: number, z: number, fromY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -(fromY + 500), 0), params)
	return if hit then hit.Position.Y + 0.4 else 3
end

-- Safety net: a lobby with no spawn pads drops players at the world origin.
-- Plants a small ring of pads in the middle of the town instead.
local function ensureLobbySpawns(lobby: Instance)
	for _, child in lobby:GetDescendants() do
		if child:IsA("SpawnLocation") then
			return
		end
	end
	local bounds = { lobbyBounds(lobby) }
	local min, max = bounds[1], bounds[2]
	if not min or not max then
		return
	end
	local center = (min + max) / 2
	local radius = math.clamp(math.min(max.X - min.X, max.Z - min.Z) * 0.18, 4, 16)

	for index = 1, 6 do
		local angle = math.rad(index * 60)
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local pad = Instance.new("SpawnLocation")
		pad.Name = `LobbySpawn{index}`
		pad.Size = Vector3.new(5, 0.6, 5)
		pad.CFrame = CFrame.new(x, groundedY(lobby, x, z, max.Y + 20), z)
		pad.Color = HOT_PINK
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.45
		pad.Anchored = true
		pad.CanCollide = true
		pad.Neutral = true
		pad.Duration = 0
		pad.Parent = lobby
	end
	warn("[PinkPanic] Lobby had no spawn pads — planted 6 in the middle. Drag them where you want players to appear.")
end

-- The fixed lobby camera: if no CameraAnchor exists, place one back from the
-- town at a flattering height, aimed at its center. Titus drags it to taste;
-- MaxYawDeg / MaxPitchDeg attributes clamp how far it pivots.
local function ensureCameraAnchor(lobby: Instance)
	if lobby:FindFirstChild("CameraAnchor", true) then
		return
	end
	local bounds = { lobbyBounds(lobby) }
	local min, max = bounds[1], bounds[2]
	if not min or not max then
		return
	end
	local center = (min + max) / 2
	local span = max - min
	-- Stand off along +Z by the town's own depth, raised a little.
	local eye = Vector3.new(center.X, min.Y + math.max(span.Y * 0.55, 10), max.Z + math.max(span.Z * 0.75, 40))
	local look = Vector3.new(center.X, min.Y + math.max(span.Y * 0.3, 4), center.Z)

	local anchor = Instance.new("Part")
	anchor.Name = "CameraAnchor"
	anchor.Size = Vector3.new(2, 2, 2)
	anchor.CFrame = CFrame.lookAt(eye, look)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 0.5
	anchor.Color = Color3.fromRGB(120, 200, 255)
	anchor:SetAttribute("MaxYawDeg", 20)
	anchor:SetAttribute("MaxPitchDeg", 10)
	anchor.Parent = lobby
	warn("[PinkPanic] Lobby had no CameraAnchor — placed one facing the town. Drag/rotate it to frame your shot.")
end

function LobbyService.init()
	-- The retired generated plaza is dead content: destroy it wherever it
	-- was saved, every boot, whether or not a hand-built lobby exists.
	local legacy = workspace:FindFirstChild(LEGACY_LOBBY_NAME)
	if legacy then
		legacy:Destroy()
		warn("[PinkPanic] Deleted leftover generated plaza (PinkPanicLobby).")
	end

	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[PinkPanic] No workspace.Lobby found — build your town inside a folder named exactly 'Lobby'.")
		return
	end

	for _, pad in lobby:GetDescendants() do
		if pad:IsA("BasePart") and pad:GetAttribute("PadAction") then
			local name = pad:GetAttribute("PadName")
			if type(name) == "string" and not pad:FindFirstChild("SignAnchor", true) then
				sign(name, pad.Position + Vector3.new(0, 7, 0), pad)
			end
		end
	end

	ensureLobbySpawns(lobby)
	ensureCameraAnchor(lobby)
	LobbyService.setArenaActive(false)
	Remotes.event("LobbyShot").OnServerEvent:Connect(onLobbyShot)
end

return LobbyService
