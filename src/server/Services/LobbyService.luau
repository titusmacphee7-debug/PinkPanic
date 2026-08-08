--!strict
-- LobbyService — the plaza hub (NOD-41, NOD-42): a walkable diorama lobby
-- where the buildings ARE the menu. Zones carry attributes the client reads
-- (ZoneName / ZoneAction) to drive camera framing, name banners, and UI.
-- Also owns which spawn set is live (lobby vs arena) and validates the
-- cosmetic click-to-shoot target pops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)

local LOBBY_NAME = "PinkPanicLobby"
local ARENA_NAME = "PinkPanicMap"
local CENTER = Vector3.new(0, 0, -320) -- well clear of the arena (z ±75)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local BUBBLEGUM = Color3.fromRGB(255, 130, 190)
local BLUSH = Color3.fromRGB(255, 227, 240)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)
local PLUM_DARK = Color3.fromRGB(92, 72, 88)
local GOLD = Color3.fromRGB(255, 196, 88)

local LobbyService = {}

local folder: Folder? = nil
local targetsFolder: Folder? = nil
local poppedTargets: { [BasePart]: boolean } = {}

local function mkPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.Parent = folder
	return part
end

local function column(name: string, diameter: number, height: number, position: Vector3, color: Color3): Part
	local part = mkPart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function sign(text: string, position: Vector3)
	local anchor = mkPart("SignAnchor", Vector3.new(0.5, 0.5, 0.5), CFrame.new(position), PINK_WHITE)
	anchor.Transparency = 1
	anchor.CanCollide = false
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
end

local function zone(name: string, action: string, size: Vector3, cframe: CFrame)
	local part = mkPart("Zone_" .. action, size, cframe, HOT_PINK)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part:SetAttribute("ZoneName", name)
	part:SetAttribute("ZoneAction", action)
end

-- A cute storefront: body, roof, awning, dark doorway, name sign, entry zone.
local function building(name: string, action: string, offset: Vector3, bodyColor: Color3)
	local position = CENTER + offset
	-- Orientation: -Z of the body faces the plaza.
	local look = CFrame.lookAt(Vector3.new(position.X, 7, position.Z), Vector3.new(CENTER.X, 7, CENTER.Z))

	local body = mkPart("Body", Vector3.new(26, 14, 16), look, bodyColor)
	mkPart("Roof", Vector3.new(28, 1.6, 18), look * CFrame.new(0, 7.8, 0), HOT_PINK)
	mkPart("Awning", Vector3.new(20, 1, 4), look * CFrame.new(0, 3.4, -9.5), BUBBLEGUM)
	local door = mkPart("Doorway", Vector3.new(7, 9, 0.4), look * CFrame.new(0, -2.5, -8.2), PLUM_DARK)
	door.CanCollide = false
	mkPart("DoorTrim", Vector3.new(8, 10, 0.3), look * CFrame.new(0, -2, -8.05), PINK_WHITE).CanCollide = false

	sign(name, look:PointToWorldSpace(Vector3.new(0, 10.5, -8)))
	zone(name, action, Vector3.new(26, 12, 18), look * CFrame.new(0, -1, -16))
	return look
end

local function buildPlaza()
	mkPart("Floor", Vector3.new(150, 1, 150), CFrame.new(CENTER), PINK_WHITE)
	column("Plaza", 52, 0.2, CENTER + Vector3.new(0, 0.6, 0), BLUSH)

	-- Fountain centerpiece with the glowing heart.
	column("FountainBase", 16, 2, CENTER + Vector3.new(0, 1.5, 0), PINK_WHITE)
	column("FountainWater", 13.5, 0.6, CENTER + Vector3.new(0, 2.6, 0), BLUSH)
	column("FountainMid", 8, 3, CENTER + Vector3.new(0, 4, 0), BUBBLEGUM)
	column("FountainTop", 4.5, 3.5, CENTER + Vector3.new(0, 7.2, 0), PINK_WHITE)
	local heart = mkPart("FountainHeart", Vector3.new(2.6, 2.6, 2.6), CFrame.new(CENTER + Vector3.new(0, 10.4, 0)), HOT_PINK)
	heart.Shape = Enum.PartType.Ball
	heart.Material = Enum.Material.Neon

	-- Lamp posts + topiaries + gifts.
	for _, corner in { Vector3.new(-30, 0, -30), Vector3.new(30, 0, -30), Vector3.new(-30, 0, 30), Vector3.new(30, 0, 30) } do
		local base = CENTER + corner
		column("LampPole", 0.6, 9, base + Vector3.new(0, 5, 0), PLUM_DARK)
		local bulb = mkPart("LampBulb", Vector3.new(1.6, 1.6, 1.6), CFrame.new(base + Vector3.new(0, 10, 0)), GOLD)
		bulb.Shape = Enum.PartType.Ball
		bulb.Material = Enum.Material.Neon
	end
	for _, offset in { Vector3.new(-14, 0, 12), Vector3.new(14, 0, 12), Vector3.new(0, 0, -16) } do
		local base = CENTER + offset
		mkPart("GiftBox", Vector3.new(3, 3, 3), CFrame.new(base + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.rad(math.random(0, 80)), 0), if math.random() > 0.5 then BUBBLEGUM else PINK_WHITE)
	end
end

local function buildRange(look: CFrame)
	-- Balloon targets on poles inside the range storefront's forecourt.
	local targets = Instance.new("Folder")
	targets.Name = "Targets"
	targets.Parent = folder
	targetsFolder = targets

	for index, lateral in { -8, 0, 8 } do
		local base = look:PointToWorldSpace(Vector3.new(lateral, -7, -12))
		column("TargetPole", 0.4, 5, base + Vector3.new(0, 2.5, 0), PLUM_DARK)
		local balloon = Instance.new("Part")
		balloon.Name = `Balloon{index}`
		balloon.Shape = Enum.PartType.Ball
		balloon.Size = Vector3.new(3, 3, 3)
		balloon.Position = base + Vector3.new(0, 6.5, 0)
		balloon.Color = if index == 2 then GOLD else HOT_PINK
		balloon.Material = Enum.Material.Neon
		balloon.Anchored = true
		balloon.CanCollide = false
		balloon:SetAttribute("LobbyTarget", true)
		balloon.Parent = targets
	end
end

local function buildPortal()
	-- The queue gate: an arch facing the arena direction (+Z side).
	local base = CENTER + Vector3.new(0, 0, 52)
	for _, x in { -8, 8 } do
		column("PortalPillar", 3, 16, base + Vector3.new(x, 8, 0), PINK_WHITE)
	end
	mkPart("PortalLintel", Vector3.new(20, 3, 3), CFrame.new(base + Vector3.new(0, 17, 0)), HOT_PINK)
	local heart = mkPart("PortalHeart", Vector3.new(2, 2, 2), CFrame.new(base + Vector3.new(0, 20, 0)), HOT_PINK)
	heart.Shape = Enum.PartType.Ball
	heart.Material = Enum.Material.Neon
	sign("The Panic Portal 💗", base + Vector3.new(0, 23, 0))
	zone("The Panic Portal 💗", "portal", Vector3.new(24, 14, 16), CFrame.new(base + Vector3.new(0, 7, 0)))
end

local function buildSpawns()
	for index = 1, 6 do
		local angle = math.rad(index * 60)
		local position = CENTER + Vector3.new(math.cos(angle) * 20, 1.3, math.sin(angle) * 20)
		local pad = Instance.new("SpawnLocation")
		pad.Name = `LobbySpawn{index}`
		pad.Size = Vector3.new(5, 0.6, 5)
		pad.CFrame = CFrame.new(position)
		pad.Color = BUBBLEGUM
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.5
		pad.Anchored = true
		pad.Neutral = true
		pad.Duration = 0
		pad.Enabled = true
		pad.Parent = folder
	end
end

-- Round flow: arena spawns live only while a round is Active.
function LobbyService.setArenaActive(active: boolean)
	local arena = workspace:FindFirstChild(ARENA_NAME)
	if arena then
		for _, child in arena:GetChildren() do
			if child:IsA("SpawnLocation") then
				child.Enabled = active
			end
		end
	end
	local lobby = folder
	if lobby then
		for _, child in lobby:GetChildren() do
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

	-- Balloon pops: validated server-side, hidden briefly, then reinflated.
	local targets = targetsFolder
	if typeof(hitInstance) == "Instance"
		and hitInstance:IsA("BasePart")
		and targets
		and hitInstance:IsDescendantOf(targets)
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

function LobbyService.init()
	if workspace:FindFirstChild(LOBBY_NAME) then
		return
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = LOBBY_NAME
	newFolder:SetAttribute("PlazaCenter", CENTER)
	folder = newFolder

	buildPlaza()
	building("The Bow-tique 🎀", "shop", Vector3.new(-52, 0, 0), BLUSH)
	building("Candy Armory 🍭", "loadout", Vector3.new(52, 0, 0), PINK_WHITE)
	local rangeLook = building("Heartbreaker Range 💘", "range", Vector3.new(0, 0, -52), BUBBLEGUM)
	buildRange(rangeLook)
	buildPortal()
	buildSpawns()

	newFolder.Parent = workspace

	-- The game starts in Waiting: lobby live, arena dormant.
	LobbyService.setArenaActive(false)

	Remotes.event("LobbyShot").OnServerEvent:Connect(onLobbyShot)
end

return LobbyService
