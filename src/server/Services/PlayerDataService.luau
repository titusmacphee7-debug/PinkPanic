--!strict
-- PlayerDataService — the persistence layer (NOD-8).
-- Loads a profile on join with session locking (so two servers can never hold
-- the same profile and dupe items), autosaves on an interval, and saves on
-- leave / server shutdown. All other systems read and mutate profiles through
-- this service; nothing else touches DataStores.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataSchema = require(ReplicatedStorage.Shared.Data.PlayerDataSchema)
type PlayerData = PlayerDataSchema.PlayerData

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 60
local LOCK_TIMEOUT = 90 -- a lock older than this is presumed dead and stolen
local LOAD_RETRIES = 3
local SAVE_RETRIES = 3

type Record = {
	data: PlayerData,
	lock: { id: string, timestamp: number }?,
}

type Profile = {
	data: PlayerData,
	lockId: string,
	loaded: boolean,
	-- Studio fallback profile: playable but never written to the DataStore,
	-- so it can't clobber real data or fight another session's lock.
	ephemeral: boolean?,
}

local PlayerDataService = {}

-- Acquired in init() behind a pcall: GetDataStore throws in Studio when API
-- access is disabled, and that must degrade to no-persistence mode, not kill
-- the server boot.
local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function withRetries<T...>(retries: number, fn: () -> T...): (boolean, T...)
	local delaySeconds = 1
	for attempt = 1, retries do
		local results = table.pack(pcall(fn))
		if results[1] then
			return true, table.unpack(results, 2, results.n)
		end
		warn(`[PlayerDataService] attempt {attempt}/{retries} failed: {results[2]}`)
		if attempt < retries then
			task.wait(delaySeconds)
			delaySeconds *= 2
		end
	end
	return false
end

-- Attempts to acquire the session lock and load the profile in one UpdateAsync.
-- Returns nil if another live server holds the lock or the DataStore is down.
local function loadProfile(player: Player): Profile?
	local dataStore = store
	if not dataStore then
		-- No-persistence mode (Studio without API access): fresh default profile.
		return { data = PlayerDataSchema.default(), lockId = "local", loaded = true }
	end

	local lockId = HttpService:GenerateGUID(false)
	local acquired = false
	local loadedData: PlayerData? = nil

	local ok = withRetries(LOAD_RETRIES, function()
		dataStore:UpdateAsync(keyFor(player), function(record: Record?)
			local now = os.time()
			if record and record.lock and now - record.lock.timestamp < LOCK_TIMEOUT then
				-- Someone else (a live server) owns this profile; do not touch it.
				acquired = false
				return nil
			end

			acquired = true
			loadedData = PlayerDataSchema.migrate(record and record.data)
			return {
				data = loadedData,
				lock = { id = lockId, timestamp = now },
			}
		end)
	end)

	if not ok or not acquired or not loadedData then
		return nil
	end
	return { data = loadedData :: PlayerData, lockId = lockId, loaded = true }
end

-- Writes the profile back, refreshing the lock (or releasing it on final save).
-- Only writes if we still hold the lock — never clobbers another server's session.
local function saveProfile(player: Player, profile: Profile, releaseLock: boolean): boolean
	if profile.ephemeral then
		return true
	end
	local dataStore = store
	if not dataStore then
		return true
	end

	local ok = withRetries(SAVE_RETRIES, function()
		dataStore:UpdateAsync(keyFor(player), function(record: Record?)
			if record and record.lock and record.lock.id ~= profile.lockId then
				return nil -- lock was stolen (we must have hung); keep their data
			end
			return {
				data = profile.data,
				lock = if releaseLock then nil else { id = profile.lockId, timestamp = os.time() },
			}
		end)
	end)
	return ok
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns the player's loaded profile data, or nil if it isn't available
-- (still loading or load failed). Callers must handle nil and treat the
-- player as read-only until data exists.
function PlayerDataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile and profile.loaded then profile.data else nil
end

-- Runs `mutator` against the player's data if it's loaded. Returns true on success.
-- All writes to player data go through here so there is one choke point.
function PlayerDataService.update(player: Player, mutator: (PlayerData) -> ()): boolean
	local data = PlayerDataService.get(player)
	if not data then
		return false
	end
	mutator(data)
	return true
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)

	if player.Parent ~= Players then
		-- Player left while we were loading; release the lock immediately.
		if profile then
			saveProfile(player, profile, true)
		end
		return
	end

	if profile then
		profiles[player] = profile
	elseif RunService:IsStudio() then
		-- Studio testing: stale locks from abrupt stops are common and a kick
		-- just disrupts iteration. Play on a throwaway profile that never saves.
		warn(`[PlayerDataService] {player.Name}: profile unavailable — using ephemeral Studio profile (no saving)`)
		profiles[player] = {
			data = PlayerDataSchema.default(),
			lockId = "",
			loaded = true,
			ephemeral = true,
		}
	else
		-- Session locked elsewhere or DataStore outage. Kick rather than risk
		-- playing on a profile that can't save (dupes, lost purchases).
		player:Kick("Your data couldn't be loaded safely. Please rejoin in a minute.")
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		saveProfile(player, profile, true)
	end
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerDataService] DataStores unavailable — running without persistence. " .. tostring(result))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(onPlayerRemoving, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave loop: refreshes locks so they never look abandoned mid-session.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(saveProfile, player, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(2) -- give Studio saves a moment; full waits hang Studio stop
			return
		end
		local saving = 0
		for player, profile in profiles do
			saving += 1
			task.spawn(function()
				saveProfile(player, profile, true)
				saving -= 1
			end)
		end
		while saving > 0 do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
