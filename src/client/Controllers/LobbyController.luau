--!strict
-- LobbyController — plaza life: detects which building zone you're standing
-- in (banner + camera framing + auto-opening the right UI), and runs the
-- cosmetic click-to-shoot (your character turns and fires at whatever you
-- click; balloons at the Heartbreaker Range pop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ClientData = require(script.Parent.Parent.ClientData)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local ShopController = require(script.Parent.ShopController)
local SettingsController = require(script.Parent.SettingsController)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)

local SHOT_COOLDOWN = 0.25

local LobbyController = {}

local currentZone: BasePart? = nil
local banner: TextLabel? = nil
local startButton: TextButton? = nil
local bannerToken = 0
local lastShotAt = 0

-- Forward declaration: buildBanner's button callback closes over this.
local showBanner: (text: string) -> ()

local function lobbyFolder(): Folder?
	return workspace:FindFirstChild("PinkPanicLobby") :: Folder?
end

-- Titus's hand-built lobby: pads are attribute-tagged parts (PadAction /
-- PadName / optional PadRadius) anywhere under workspace.Lobby.
local cachedPads: { BasePart }? = nil
local function customPads(custom: Instance): { BasePart }
	local cached = cachedPads
	if cached then
		return cached
	end
	local list: { BasePart } = {}
	for _, descendant in custom:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("PadAction") then
			table.insert(list, descendant)
		end
	end
	cachedPads = list
	return list
end

local function buildBanner()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "LobbyUI"
	screen.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 64)
	label.Size = UDim2.new(0, 500, 0, 44)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 34
	label.TextColor3 = HOT_PINK
	label.TextStrokeColor3 = PINK_WHITE
	label.TextStrokeTransparency = 0.2
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = screen
	banner = label

	-- START GAME: the deliberate way into a round. Always available in the
	-- lobby, so testing never depends on a pad existing.
	local button = Instance.new("TextButton")
	button.Name = "StartGame"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -38)
	button.Size = UDim2.fromOffset(300, 62)
	button.BackgroundColor3 = HOT_PINK
	button.BorderSizePixel = 0
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 26
	button.TextColor3 = PINK_WHITE
	button.Text = "START GAME 💗"
	button.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = PINK_WHITE
	stroke.Thickness = 3
	stroke.Transparency = 0.25
	stroke.Parent = button
	button.Activated:Connect(function()
		Remotes.event("EnterPortal"):FireServer()
		showBanner("Starting the round... 💗")
	end)
	button.Parent = screen
	startButton = button

	screen.Parent = playerGui
end

-- The button lives and dies with lobby state.
local function updateStartButton()
	local button = startButton
	if not button then
		return
	end
	button.Visible = ClientData.inLobby()
		and not ClientData.menuOpen()
		and not ClientData.armoryBusy
	button.Text = if ClientData.roundState == "Intermission"
		then "STARTING... 💗"
		else "START GAME 💗"
end

function showBanner(text: string)
	local label = banner
	if not label then
		return
	end
	bannerToken += 1
	local token = bannerToken
	label.Text = text
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.2
	task.delay(2, function()
		if bannerToken == token then
			TweenService:Create(label, TweenInfo.new(0.5), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
end

local function insideZone(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

local function applyZone(zone: BasePart?)
	if zone == currentZone then
		return
	end
	local previous = currentZone
	local previousAction = previous
		and (previous:GetAttribute("ZoneAction") or previous:GetAttribute("PadAction"))
	currentZone = zone
	-- Hand-built lobby uses the fixed-pivot camera; no per-zone framing.
	CameraController.setZone(if workspace:FindFirstChild("Lobby") then nil else zone)

	-- Leaving a building closes its UI.
	if previousAction == "shop" then
		ShopController.setOpen(false)
	elseif previousAction == "loadout" then
		SettingsController.setOpen(false)
	end

	if zone then
		local name = zone:GetAttribute("ZoneName") or zone:GetAttribute("PadName")
		if type(name) == "string" then
			showBanner(name)
		end
		local action = zone:GetAttribute("ZoneAction") or zone:GetAttribute("PadAction")
		if action == "shop" then
			ShopController.setOpen(true)
		elseif action == "loadout" then
			SettingsController.setOpen(true)
		elseif action == "portal" then
			-- The Panic Portal: asks the server to start the round (Studio
			-- solo starts on demand; live lobbies run the normal timer).
			showBanner("Entering the arena... 💗")
			Remotes.event("EnterPortal"):FireServer()
		end
	end
end

local function updateZones()
	updateStartButton()
	if not ClientData.inLobby() then
		applyZone(nil)
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		applyZone(nil)
		return
	end

	-- Hand-built lobby: proximity to tagged pads.
	local custom = workspace:FindFirstChild("Lobby")
	if custom then
		for _, pad in customPads(custom) do
			local radius = (pad:GetAttribute("PadRadius") :: number?) or 8
			if (pad.Position - root.Position).Magnitude <= radius then
				applyZone(pad)
				return
			end
		end
		applyZone(nil)
		return
	end

	local lobby = lobbyFolder()
	if not lobby then
		applyZone(nil)
		return
	end
	for _, child in lobby:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ZoneAction") and insideZone(child, root.Position) then
			applyZone(child)
			return
		end
	end
	applyZone(nil)
end

local function lobbyShoot()
	if ClientData.armoryBusy then
		return
	end
	local now = os.clock()
	if now - lastShotAt < SHOT_COOLDOWN then
		return
	end
	lastShotAt = now

	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not character or not root or not root:IsA("BasePart") then
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local hitPosition = if result then result.Position else ray.Origin + ray.Direction * 150

	-- Turn the character toward the click.
	local flat = Vector3.new(hitPosition.X - root.Position.X, 0, hitPosition.Z - root.Position.Z)
	if flat.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAlong(root.Position, flat.Unit)
	end

	-- Immediate local effects from the held gun; the server rebroadcasts to
	-- everyone else and validates target pops.
	local gun = character:FindFirstChild("WorldGun")
	local origin = if gun and gun:IsA("Model") and gun.PrimaryPart
		then gun.PrimaryPart.Position
		else root.Position + Vector3.new(0, 1, 0)
	EffectsController.drawTracer(origin, hitPosition)
	EffectsController.playShotSound(0.5)

	Remotes.event("LobbyShot"):FireServer(hitPosition, result and result.Instance)
end

local function onTargetPopped(position: any, color: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local burst = Instance.new("Part")
	burst.Shape = Enum.PartType.Ball
	burst.Size = Vector3.new(1, 1, 1)
	burst.Position = position
	burst.Color = if typeof(color) == "Color3" then color else HOT_PINK
	burst.Material = Enum.Material.Neon
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.Parent = workspace
	TweenService:Create(burst, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(7, 7, 7),
		Transparency = 1,
	}):Play()
	EffectsController.playHitSound()
	task.delay(0.45, function()
		burst:Destroy()
	end)
end

function LobbyController.init()
	buildBanner()

	RunService.Heartbeat:Connect(updateZones)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and ClientData.inLobby() then
			lobbyShoot()
		end
	end)

	Remotes.event("TargetPopped").OnClientEvent:Connect(onTargetPopped)
end

return LobbyController
