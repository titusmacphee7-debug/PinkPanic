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
local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
type PlayerData = PlayerDataSchema.PlayerData

local SYSTEM = "PlayerDataService"

local STORE_NAME = "PlayerData_v1"

-- Every autosave refreshes the lock, so the ratio between these two IS the
-- safety margin. It used to be 60 against 90, leaving room for exactly one
-- missed save before another server could decide the session was dead and
-- steal it — while the player was still playing. Retries alone can eat several
-- seconds, so that margin was routinely thinner than it looked.
--
-- 45 against 300 gives six missed autosaves of slack. The cost is that a
-- genuinely crashed server holds a profile for up to five minutes before
-- anyone can rejoin on it, which is a far better failure than two servers
-- writing the same profile and duping items.
local AUTOSAVE_INTERVAL = 45
local LOCK_TIMEOUT = 300

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
	-- Set once the final save has released the lock. An autosave that was
	-- already in flight at that moment must not write the lock back.
	released: boolean?,
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

			-- `record.lock.id ~= lockId` is the whole fix. Without it, this
			-- check could not tell someone else's lock from OUR OWN.
			--
			-- withRetries wraps the UpdateAsync call, not the transform. So if
			-- attempt 1 successfully wrote our lock and then failed on the way
			-- out — a transient DataStore error, a throttle — attempt 2 would
			-- run this transform again, find a fresh lock that we placed, and
			-- conclude another server owned the profile. It then set
			-- acquired = false and the player was kicked off their own data by
			-- their own retry.
			if
				record
				and record.lock
				and record.lock.id ~= lockId
				and now - record.lock.timestamp < LOCK_TIMEOUT
			then
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

	-- An autosave that was already in flight when the player left would
	-- otherwise land AFTER the leave-save and write the lock straight back —
	-- locking the player out of their own profile for the full timeout on the
	-- very next join. Once released, only a release may write again.
	if profile.released and not releaseLock then
		return true
	end
	if releaseLock then
		profile.released = true
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
	end

	-- Getting the handle is NOT proof that saving works. With Studio API access
	-- off, GetDataStore succeeds and every write fails — so a handle-only check
	-- reports a healthy OK while nothing at all is persisting, which is exactly
	-- the "looks like it saved" failure this service is supposed to make
	-- impossible. Probe an actual write, on a throwaway key, and report what
	-- really happened.
	local writable = false
	local probeError: any = result
	if store then
		local dataStore = store :: DataStore
		writable = pcall(function()
			dataStore:UpdateAsync("__writeprobe", function()
				return os.time()
			end)
		end)
		if not writable then
			local _, err = pcall(function()
				dataStore:UpdateAsync("__writeprobe", function()
					return os.time()
				end)
			end)
			probeError = err
		end
	end

	if writable then
		Diagnostics.ok(SYSTEM, `schema v{PlayerDataSchema.VERSION} · autosave {AUTOSAVE_INTERVAL}s · lock {LOCK_TIMEOUT}s`)
	else
		-- Deliberately WARN, not ok. A session with no persistence behaves
		-- exactly like a working one right up until you rejoin and everything
		-- you earned is gone — so it has to be visible in the manifest every
		-- single boot, not in one warning that scrolls away.
		store = nil
		Diagnostics.warn(
			SYSTEM,
			`NOTHING IS SAVING — DataStore writes are failing. `
				.. `In Studio: Game Settings → Security → Enable Studio Access to API Services. `
				.. `({probeError})`
		)
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
