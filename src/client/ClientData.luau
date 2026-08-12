--!strict
-- ClientData — the client's mirror of its profile snapshot (DataChanged) plus
-- small bits of shared UI state. Controllers read from here instead of each
-- subscribing to the remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
-- The rig requires nothing from the client tree, which is the only reason the
-- lowest-level client module can depend on it without a cycle.
local CameraRig = require(script.Parent.Camera.CameraRig)

local changedEvent = Instance.new("BindableEvent")
local stateEvent = Instance.new("BindableEvent")
local unlockBound = false

local ClientData = {}

ClientData.snapshot = nil :: any
ClientData.changed = changedEvent.Event
ClientData.shopOpen = false
ClientData.settingsOpen = false
ClientData.loadoutOpen = false
-- True while the Armory dialog/inspection owns the mouse (blocks lobby shooting).
ClientData.armoryBusy = false

-- Round state mirror. Lobby life happens in every state except Active.
--
-- Nothing writes this right now: the round loop was deleted along with combat
-- for the rebuild, so this stays "Waiting" and inLobby() is permanently true,
-- which is what keeps the lobby camera, cursor and pads alive. The new game
-- loop should call setRoundState and this all works again unchanged.
ClientData.roundState = "Waiting"
ClientData.roundStateChanged = stateEvent.Event

function ClientData.inLobby(): boolean
	return ClientData.roundState ~= "Active"
end

-- ---------------------------------------------------------------------------
-- Standing in the arena, as a stand-in for the round state
--
-- The round loop was deleted in the rebuild and has not landed again, so
-- `inLobby()` is permanently true. Anything gated on it alone can NEVER run —
-- finished, correct, and unreachable, which is indistinguishable from broken.
--
-- So: if your feet are in the arena, you are in a fight. This lived in
-- WeaponController, where it decided whether the trigger works; the camera
-- needs the same answer, and two slightly different answers to "am I in a
-- fight" is how you end up shooting people through a lobby camera.
--
-- Delete the whole section the moment RoundService exists.
-- ---------------------------------------------------------------------------

-- The arena is content and does not move, so this is a scan of a few thousand
-- parts once every ten seconds rather than per frame.
local ARENA_RECHECK_SECONDS = 10

local arenaBox: { min: Vector3, max: Vector3 }? = nil
local arenaCheckedAt = -math.huge

local function arenaBounds(): { min: Vector3, max: Vector3 }?
	local now = os.clock()
	if now - arenaCheckedAt < ARENA_RECHECK_SECONDS then
		return arenaBox
	end
	arenaCheckedAt = now

	-- The arena is a FOLDER, per the attribute conventions in CLAUDE.md, so
	-- there is no GetBoundingBox to call — that was the first version and it
	-- threw, which the caller swallowed as "not in the arena". Something that
	-- never activates and reports nothing is the worst of both.
	local arena = workspace:FindFirstChild("Arena") or workspace:FindFirstChild("PinkPanicMap")
	if not arena then
		arenaBox = nil
		return nil
	end

	local min: Vector3? = nil
	local max: Vector3? = nil
	for _, part in arena:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local half = part.Size / 2
		local lo, hi = part.Position - half, part.Position + half
		min = if min then Vector3.new(math.min(min.X, lo.X), math.min(min.Y, lo.Y), math.min(min.Z, lo.Z)) else lo
		max = if max then Vector3.new(math.max(max.X, hi.X), math.max(max.Y, hi.Y), math.max(max.Z, hi.Z)) else hi
	end
	if not min or not max then
		arenaBox = nil
		return nil
	end

	-- Generous vertically: the box stops at the rooftops, and falling off one
	-- should not disarm you on the way down.
	arenaBox = { min = min - Vector3.new(0, 80, 0), max = max + Vector3.new(0, 80, 0) }
	return arenaBox
end

function ClientData.inArena(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local box = arenaBounds()
	if not box then
		return false
	end
	local p = root.Position
	return p.X >= box.min.X
		and p.X <= box.max.X
		and p.Y >= box.min.Y
		and p.Y <= box.max.Y
		and p.Z >= box.min.Z
		and p.Z <= box.max.Z
end

-- Am I in a fight? The one answer, for the trigger and the camera both.
function ClientData.fighting(): boolean
	return not ClientData.inLobby() or ClientData.inArena()
end

function ClientData.setRoundState(state: string)
	if ClientData.roundState == state then
		return
	end
	ClientData.roundState = state
	ClientData.updateMouseUnlock()
	stateEvent:Fire(state)
end

-- True while any modal menu should block gameplay input.
function ClientData.menuOpen(): boolean
	return ClientData.shopOpen or ClientData.settingsOpen or ClientData.loadoutOpen
end

-- Call after toggling shopOpen/settingsOpen. The first-person camera scripts
-- re-lock the mouse every render step, so while a menu is open we bind AFTER
-- them (RenderPriority.Last) and force the cursor free each frame — the only
-- approach that reliably wins that fight.
function ClientData.updateMouseUnlock()
	local shouldUnlock = ClientData.menuOpen() or not ClientData.fighting()
	if shouldUnlock and not unlockBound then
		unlockBound = true
		-- Through the rig (NOD-142). Not camera work, but it IS in the camera
		-- chain and it has to be last, so it is a slot like everything else.
		CameraRig.claim("MouseUnlock", "ClientData", function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	elseif not shouldUnlock and unlockBound then
		unlockBound = false
		CameraRig.release("MouseUnlock")
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

function ClientData.equippedSkin(): string?
	local snap = ClientData.snapshot
	local skins = snap and snap.equipped and snap.equipped.skins
	return if type(skins) == "table" then skins.Pistol else nil
end

function ClientData.equippedCharm(): string?
	local snap = ClientData.snapshot
	local charms = snap and snap.equipped and snap.equipped.charms
	return if type(charms) == "table" then charms.Pistol else nil
end

-- Gun-roster helpers (schema v2 snapshot fields).
local function inList(list: any, itemId: string): boolean
	return type(list) == "table" and table.find(list, itemId) ~= nil
end

function ClientData.ownsGun(gunId: string): boolean
	local snap = ClientData.snapshot
	return inList(snap and snap.ownedGuns, gunId)
end

function ClientData.ownsGunSkin(skinId: string): boolean
	local snap = ClientData.snapshot
	return inList(snap and snap.ownedGunSkins, skinId)
end

function ClientData.ownsCamo(camoId: string): boolean
	local snap = ClientData.snapshot
	return inList(snap and snap.ownedCamos, camoId)
end

function ClientData.loadout(): (string?, string)
	local snap = ClientData.snapshot
	local loadout = snap and snap.loadout
	local primary = if type(loadout) == "table" then loadout.primary else nil
	local secondary = if type(loadout) == "table" and type(loadout.secondary) == "string"
		then loadout.secondary
		else "Pistol_1"
	return primary, secondary
end

function ClientData.gunCosmeticsFor(gunId: string): (string?, string?)
	local snap = ClientData.snapshot
	local all = snap and snap.gunCosmetics
	local entry = if type(all) == "table" then all[gunId] else nil
	if type(entry) == "table" then
		return entry.skinId, entry.camoId
	end
	return nil, nil
end

function ClientData.owns(kind: string, itemId: string): boolean
	local snap = ClientData.snapshot
	local list = if kind == "skin" then snap and snap.ownedSkins else snap and snap.ownedCharms
	return type(list) == "table" and table.find(list, itemId) ~= nil
end

function ClientData.init()
	Remotes.listen("DataChanged", function(data)
		if type(data) == "table" then
			ClientData.snapshot = data
			changedEvent:Fire(data)
		end
	end)
	-- The game opens in the lobby; free the cursor from the start.
	ClientData.updateMouseUnlock()
end

return ClientData
