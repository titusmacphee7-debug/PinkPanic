--!strict
-- Remotes — the central RemoteEvent/RemoteFunction registry (NOD-129).
--
-- Every remote in the game is declared here, once. The server creates them at
-- boot; both sides look them up by name. Never Instance.new a remote anywhere.
--
-- The rule this module enforces: **a declared remote with nobody on the other
-- end is a boot failure, not a mystery.** A client that fires into a remote with
-- no server handler gets no error, no response, and no explanation — the button
-- simply does nothing. That failure mode is the whole reason this rebuild
-- exists, so it is now caught at boot on both sides:
--
--   assertHandlers()   server: every ClientToServer remote has a handler
--   assertListeners()  client: every ServerToClient remote has a listener
--
-- Which means every remote carries its DIRECTION. Direction is not decoration:
-- it is what makes "who is missing" answerable at all, and it makes firing a
-- remote the wrong way down the wire an immediate error instead of a silent
-- no-op.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

local FOLDER_NAME = "Remotes"
local SYSTEM = "Remotes"

export type RemoteKind = "Event" | "Function"
export type Direction = "ClientToServer" | "ServerToClient"

export type RemoteDef = {
	kind: RemoteKind,
	dir: Direction,
	note: string,
}

-- The full remote surface of the game. Add entries here as systems come online,
-- and add the handler in the SAME commit — an entry with no handler now fails
-- the boot manifest by name, which is the point.
--
-- Combat, round-loop and movement remotes were REMOVED with the rewrite rather
-- than left declared-but-unhandled. The new systems re-declare exactly what
-- they use.
-- Deleted: FireWeapon, ReloadWeapon, SelectWeapon, AmmoChanged, DamageDealt,
-- Killfeed, RoundStateChanged, ScoreUpdated, EnterPortal, MovementState.
local Definitions: { [string]: RemoteDef } = {
	-- Combat. FireWeapon carries INTENT only — where the muzzle is and where
	-- it points. No target, no hit, no damage: everything the server would
	-- have to take the client's word for is absent by design, which is why
	-- there is nothing here for a modified client to lie about.
	FireWeapon = { kind = "Event", dir = "ClientToServer", note = "fire intent: origin + unit direction" },

	-- Lobby
	LobbyShot = { kind = "Event", dir = "ClientToServer", note = "cosmetic lobby shot (target pops)" },
	TargetPopped = { kind = "Event", dir = "ServerToClient", note = "a lobby target burst" },
	-- ShotFired SURVIVED the combat wipe: it is how the lobby's own balloon
	-- shooting draws tracers for other players, so it belongs to the lobby as
	-- much as to combat.
	ShotFired = { kind = "Event", dir = "ServerToClient", note = "a shot happened (tracers/sound)" },

	-- Economy
	PurchaseItem = { kind = "Function", dir = "ClientToServer", note = "buy from catalog" },
	EquipItem = { kind = "Function", dir = "ClientToServer", note = "equip owned cosmetic" },
	UpdateSettings = { kind = "Function", dir = "ClientToServer", note = "persist sensitivity/volume/starting weapon" },

	-- Gun roster economy
	BuyGun = { kind = "Function", dir = "ClientToServer", note = "buy a roster gun" },
	BuyGunSkin = { kind = "Function", dir = "ClientToServer", note = "buy a colour skin for an owned gun" },
	BuyCamo = { kind = "Function", dir = "ClientToServer", note = "buy a universal camo" },
	EquipLoadout = { kind = "Function", dir = "ClientToServer", note = "set primary/secondary (lobby only)" },
	EquipGunCosmetics = { kind = "Function", dir = "ClientToServer", note = "set a gun's skin/camo" },
	TryGun = { kind = "Function", dir = "ClientToServer", note = "60s lobby trial (never persisted)" },
	DataChanged = { kind = "Event", dir = "ServerToClient", note = "profile replication (coins, xp, owned)" },
}

local Remotes = {}

-- Names that have had a handler (server) or listener (client) attached.
local wired: { [string]: boolean } = {}

local function def(name: string): RemoteDef
	local d = Definitions[name]
	assert(d ~= nil, `Remote "{name}" is not declared in Remotes.Definitions`)
	return d
end

-- ---------------------------------------------------------------------------
-- Lookup
-- ---------------------------------------------------------------------------

local function getRemote(name: string): Instance
	def(name)

	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		assert(folder, "Remotes.init has not run yet")
		return assert(folder:FindFirstChild(name), `Remote "{name}" missing — was init called?`)
	end

	-- These used to be untimed. If the server errored before Remotes.init()
	-- ran, the client parked here forever, printed nothing at all, and looked
	-- "fine, just idle" — the same silent death that hid a server parse error
	-- for days. Warn loudly, then keep waiting so a late server still works.
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)
	if not folder then
		warn(
			`[PinkPanic] ⚠️ ReplicatedStorage.{FOLDER_NAME} never appeared after 10s — `
				.. `the SERVER failed to boot. Scroll up in Output for the server error.`
		)
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	local remote = (folder :: Instance):WaitForChild(name, 10)
	if not remote then
		warn(`[PinkPanic] ⚠️ Remote "{name}" never appeared — is it declared in Remotes.Definitions?`)
		remote = (folder :: Instance):WaitForChild(name)
	end
	return remote :: Instance
end

function Remotes.event(name: string): RemoteEvent
	assert(def(name).kind == "Event", `Remote "{name}" is not an Event`)
	return getRemote(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(def(name).kind == "Function", `Remote "{name}" is not a Function`)
	return getRemote(name) :: RemoteFunction
end

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

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

	local count = 0
	for name, d in Definitions do
		count += 1
		if not folder:FindFirstChild(name) then
			local className = if d.kind == "Function" then "RemoteFunction" else "RemoteEvent"
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end

	Diagnostics.ok(SYSTEM, `{count} declared`)
end

function Remotes.handleEvent(name: string, handler: (player: Player, ...any) -> ())
	local d = def(name)
	assert(RunService:IsServer(), `Remotes.handleEvent("{name}") may only be called on the server`)
	assert(d.kind == "Event", `Remote "{name}" is a Function — use handleFunction`)
	assert(
		d.dir == "ClientToServer",
		`Remote "{name}" is ServerToClient — the server fires it, it does not handle it`
	)

	;(getRemote(name) :: RemoteEvent).OnServerEvent:Connect(handler)
	wired[name] = true
end

function Remotes.handleFunction(name: string, handler: (player: Player, ...any) -> any)
	local d = def(name)
	assert(RunService:IsServer(), `Remotes.handleFunction("{name}") may only be called on the server`)
	assert(d.kind == "Function", `Remote "{name}" is an Event — use handleEvent`)
	assert(d.dir == "ClientToServer", `Remote "{name}" is ServerToClient — functions are always client-to-server`)

	;(getRemote(name) :: RemoteFunction).OnServerInvoke = handler
	wired[name] = true
end

function Remotes.fireClient(name: string, player: Player, ...: any)
	local d = def(name)
	assert(RunService:IsServer(), `Remotes.fireClient("{name}") may only be called on the server`)
	assert(d.dir == "ServerToClient", `Remote "{name}" is ClientToServer — the server does not fire it`)

	;(getRemote(name) :: RemoteEvent):FireClient(player, ...)
end

function Remotes.fireAllClients(name: string, ...: any)
	local d = def(name)
	assert(RunService:IsServer(), `Remotes.fireAllClients("{name}") may only be called on the server`)
	assert(d.dir == "ServerToClient", `Remote "{name}" is ClientToServer — the server does not fire it`)

	;(getRemote(name) :: RemoteEvent):FireAllClients(...)
end

-- ---------------------------------------------------------------------------
-- Client
-- ---------------------------------------------------------------------------

-- Blocks until the remote surface exists. Use as the client's boot barrier so
-- everything after it can assume remotes are there.
function Remotes.awaitReady()
	assert(RunService:IsClient(), "Remotes.awaitReady is client-only")
	getRemote("DataChanged")
end

function Remotes.listen(name: string, handler: (...any) -> ())
	local d = def(name)
	assert(RunService:IsClient(), `Remotes.listen("{name}") may only be called on the client`)
	assert(d.kind == "Event", `Remote "{name}" is a Function — the client invokes it, it does not listen`)
	assert(d.dir == "ServerToClient", `Remote "{name}" is ClientToServer — the client fires it, it does not listen`)

	;(getRemote(name) :: RemoteEvent).OnClientEvent:Connect(handler)
	wired[name] = true
end

function Remotes.fireServer(name: string, ...: any)
	local d = def(name)
	assert(RunService:IsClient(), `Remotes.fireServer("{name}") may only be called on the client`)
	assert(d.kind == "Event", `Remote "{name}" is a Function — use invoke`)
	assert(d.dir == "ClientToServer", `Remote "{name}" is ServerToClient — the client does not fire it`)

	;(getRemote(name) :: RemoteEvent):FireServer(...)
end

function Remotes.invoke(name: string, ...: any): any
	local d = def(name)
	assert(RunService:IsClient(), `Remotes.invoke("{name}") may only be called on the client`)
	assert(d.kind == "Function", `Remote "{name}" is an Event — use fireServer`)
	assert(d.dir == "ClientToServer", `Remote "{name}" is ServerToClient`)

	return (getRemote(name) :: RemoteFunction):InvokeServer(...)
end

-- ---------------------------------------------------------------------------
-- Boot assertions — the reason this module exists
-- ---------------------------------------------------------------------------

local function assertWired(wantedDir: Direction, role: string)
	local expected, missing = 0, {}

	for name, d in Definitions do
		if d.dir == wantedDir then
			expected += 1
			if not wired[name] then
				table.insert(missing, name)
			end
		end
	end

	if #missing > 0 then
		table.sort(missing)
		Diagnostics.dead(
			SYSTEM,
			`{#missing}/{expected} {wantedDir} remote(s) have NO {role}: {table.concat(missing, ", ")} `
				.. `— firing these does nothing and reports no error`
		)
		return
	end

	Diagnostics.ok(SYSTEM, `{expected} declared, {expected} {role}s attached`)
end

-- Call at the very end of server boot, after every service has init'd.
function Remotes.assertHandlers()
	assertWired("ClientToServer", "handler")
end

-- Call at the very end of client boot, after every controller has init'd.
function Remotes.assertListeners()
	assertWired("ServerToClient", "listener")
end

return Remotes
