--!strict
-- Remotes — the central RemoteEvent/RemoteFunction registry (NOD-9).
-- Every remote in the game is declared here, once. The server creates them at
-- boot; clients look them up by name. Never Instance.new a remote anywhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

export type RemoteKind = "Event" | "Function"

-- The full remote surface of the game. Add entries here as systems come online.
local Definitions: { [string]: RemoteKind } = {
	-- Combat (M1)
	FireWeapon = "Event", -- client -> server: report a shot for validation
	ReloadWeapon = "Event", -- client -> server: request reload
	SelectWeapon = "Event", -- client -> server: switch carried weapon
	AmmoChanged = "Event", -- server -> client: ammo/reload state for the HUD
	ShotFired = "Event", -- server -> clients: a validated shot happened (tracers/sound)
	DamageDealt = "Event", -- server -> client: hitmarker / damage number feedback
	Killfeed = "Event", -- server -> clients: someone died

	-- Round loop (M2)
	RoundStateChanged = "Event", -- server -> clients: state machine transitions
	ScoreUpdated = "Event", -- server -> clients: live standings

	-- Lobby (M6)
	LobbyShot = "Event", -- client -> server: cosmetic lobby shot (target pops)
	TargetPopped = "Event", -- server -> clients: a lobby target burst

	-- Economy (M4)
	PurchaseItem = "Function", -- client -> server: buy from catalog, returns result
	EquipItem = "Function", -- client -> server: equip owned cosmetic, returns result
	UpdateSettings = "Function", -- client -> server: persist sensitivity/volume/starting weapon

	-- Gun roster economy (docs/GUNS_HANDOFF.md §4.3)
	BuyGun = "Function", -- client -> server: buy a roster gun
	BuyGunSkin = "Function", -- client -> server: buy a color skin for an owned gun
	BuyCamo = "Function", -- client -> server: buy a universal camo
	EquipLoadout = "Function", -- client -> server: set primary/secondary (lobby only)
	EquipGunCosmetics = "Function", -- client -> server: set a gun's skin/camo
	DataChanged = "Event", -- server -> client: profile replication (coins, xp, owned)
}

local Remotes = {}

-- Server-only: creates the folder and every declared remote. Call once at boot.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init may only be called on the server")

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = FOLDER_NAME
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end

	for name, kind in Definitions do
		if not folder:FindFirstChild(name) then
			local className = if kind == "Function" then "RemoteFunction" else "RemoteEvent"
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

local function getRemote(name: string): Instance
	local kind = Definitions[name]
	assert(kind ~= nil, `Remote "{name}" is not declared in Remotes.Definitions`)

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		assert(folder, "Remotes.init has not run yet")
		return assert(folder:FindFirstChild(name), `Remote "{name}" missing — was init called?`)
	end

	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

function Remotes.event(name: string): RemoteEvent
	assert(Definitions[name] == "Event", `Remote "{name}" is not an Event`)
	return getRemote(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(Definitions[name] == "Function", `Remote "{name}" is not a Function`)
	return getRemote(name) :: RemoteFunction
end

return Remotes
