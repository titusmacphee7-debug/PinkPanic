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

-- Mirrors Theme.color primary / primaryDeep / surfaceRaised. Theme lives in
-- src/client and the server can't require it, so these are kept in step by
-- hand (see docs/design/DESIGN_SYSTEM.md).
local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)

local LobbyService = {}

local poppedTargets: { [BasePart]: boolean } = {}

-- Pad signs are FIXED, not billboards.
--
-- A BillboardGui always turns to face the live camera, so every sign swivelled
-- as the lobby camera panned. These are SurfaceGuis on a part aimed once at
-- the CameraAnchor: they read straight-on from the lobby shot and never
-- rotate. The part is pushed toward the anchor so the text floats in FRONT of
-- the pad instead of sitting on top of it.
--
-- Per-pad tuning without touching code (the usual attribute convention):
--   PadSignForward — studs toward the camera  (default SIGN_FORWARD)
--   PadSignHeight  — studs above the pad      (default SIGN_HEIGHT)
--   PadSignScale   — multiplies the plate size    (default 1)
local SIGN_FORWARD = 6
local SIGN_HEIGHT = 8
local SIGN_SIZE = Vector3.new(19, 5.4, 0.2)
local SIGN_MAX_DISTANCE = 500

local function sign(text: string, pad: BasePart, lookAt: Vector3?)
	local forward = pad:GetAttribute("PadSignForward")
	local height = pad:GetAttribute("PadSignHeight")
	local push = if type(forward) == "number" then forward else SIGN_FORWARD
	local rise = if type(height) == "number" then height else SIGN_HEIGHT

	local base = pad.Position + Vector3.new(0, rise, 0)
	local cframe = CFrame.new(base)
	if lookAt then
		-- Flatten the aim to the horizontal plane so signs stay upright rather
		-- than tipping back toward a camera anchor mounted above them.
		local flat = Vector3.new(lookAt.X - base.X, 0, lookAt.Z - base.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		local position = base + direction * push
		cframe = CFrame.lookAt(position, position + direction)
	end

	local scaleAttr = pad:GetAttribute("PadSignScale")
	local scale = if type(scaleAttr) == "number" and scaleAttr > 0 then scaleAttr else 1

	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(SIGN_SIZE.X * scale, SIGN_SIZE.Y * scale, SIGN_SIZE.Z)
	anchor.CFrame = cframe
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1

	-- Front is -Z, which is exactly where CFrame.lookAt points, so the text
	-- faces the anchor. Two-sided would show a mirrored copy from behind.
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 64
	surface.AlwaysOnTop = false
	surface.MaxDistance = SIGN_MAX_DISTANCE
	surface.LightInfluence = 0

	-- Hot pink text floating over a pink town is nearly unreadable — the
	-- contrast problem, not the size, is what made these hard to make out.
	-- A near-white plate with deep-pink text reads cleanly against any
	-- storefront behind it.
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = PINK_WHITE
	plate.BackgroundTransparency = 0.08
	plate.BorderSizePixel = 0
	plate.Parent = surface

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = plate

	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 6
	stroke.Transparency = 0.15
	stroke.Parent = plate

	-- Keep vertical padding tight. TextScaled fits the SMALLER constraint, so
	-- on a wide plate the text is height-limited — generous top/bottom padding
	-- just shrinks the letters and leaves the plate looking empty.
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.04, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	-- Do NOT set TextWrapped alongside TextScaled. TextScaled manages wrapping
	-- itself, and forcing it off collapses the layout to blank plates.
	label.TextScaled = true
	label.TextColor3 = DEEP_PINK
	label.Text = text
	label.Parent = plate

	surface.Parent = anchor

	anchor.Parent = pad
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
-- Returns (min, max), or (nil, nil) when the lobby has no parts. Note the
-- return type is a pair of optionals: Luau has no way to mark a whole type
-- pack optional, and writing `(Vector3, Vector3)?` is a syntax error that
-- takes the entire server bootstrap down with it.
local function lobbyBounds(lobby: Instance): (Vector3?, Vector3?)
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
		return nil, nil
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

	-- These two must run whether or not a lobby exists. They used to sit below
	-- the guard, so a missing workspace.Lobby left arena spawns Enabled at boot
	-- (players spawning straight into the arena outside a round) and left
	-- LobbyShot with no server listener at all.
	LobbyService.setArenaActive(false)
	Remotes.event("LobbyShot").OnServerEvent:Connect(onLobbyShot)

	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[PinkPanic] No workspace.Lobby found — build your town inside a folder named exactly 'Lobby'.")
		return
	end

	ensureLobbySpawns(lobby)
	ensureCameraAnchor(lobby)

	-- Signs are aimed at the CameraAnchor, so they're built AFTER the anchor is
	-- guaranteed to exist — otherwise the first boot of a fresh lobby would
	-- place every sign unaimed.
	local cameraAnchor = lobby:FindFirstChild("CameraAnchor", true)
	local lookAt = if cameraAnchor and cameraAnchor:IsA("BasePart") then cameraAnchor.Position else nil
	for _, pad in lobby:GetDescendants() do
		if pad:IsA("BasePart") and pad:GetAttribute("PadAction") then
			local name = pad:GetAttribute("PadName")
			if type(name) == "string" and not pad:FindFirstChild("SignAnchor", true) then
				sign(name, pad, lookAt)
			end
		end
	end
end

return LobbyService
