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

-- Safety net: a lobby with no spawn pads drops players at the world origin.
-- If none exist, plant one under the CameraAnchor (or the lobby's center).
local function ensureLobbySpawn(lobby: Instance)
	for _, child in lobby:GetDescendants() do
		if child:IsA("SpawnLocation") then
			return
		end
	end

	local position: Vector3? = nil
	local anchor = lobby:FindFirstChild("CameraAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		-- In front of the camera anchor, on the ground below it.
		position = anchor.Position + anchor.CFrame.LookVector * 28 - Vector3.new(0, anchor.Position.Y - 3, 0)
	elseif lobby:IsA("Model") then
		position = lobby:GetPivot().Position + Vector3.new(0, 3, 0)
	else
		for _, child in lobby:GetDescendants() do
			if child:IsA("BasePart") then
				position = child.Position + Vector3.new(0, 5, 0)
				break
			end
		end
	end
	if not position then
		return
	end

	local pad = Instance.new("SpawnLocation")
	pad.Name = "LobbySpawn_Fallback"
	pad.Size = Vector3.new(6, 0.6, 6)
	pad.CFrame = CFrame.new(position)
	pad.Color = HOT_PINK
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.4
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0
	pad.Parent = lobby
	warn("[PinkPanic] Lobby had no SpawnLocations — planted a fallback pad. Add your own inside workspace.Lobby.")
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

	ensureLobbySpawn(lobby)
	LobbyService.setArenaActive(false)
	Remotes.event("LobbyShot").OnServerEvent:Connect(onLobbyShot)
end

return LobbyService
