--!strict
-- Guard — remote validation helpers (NOD-9, hardened further in NOD-46).
-- Server-side handlers use these to reject bad arguments and spammy clients
-- before any game logic runs. The client is never trusted.

local Guard = {}

-- ---------------------------------------------------------------------------
-- Type / range checks. Each returns true only for well-formed values, so
-- handlers can bail early: `if not Guard.isFiniteNumber(x) then return end`
-- ---------------------------------------------------------------------------

function Guard.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Guard.isNumberInRange(value: any, min: number, max: number): boolean
	return Guard.isFiniteNumber(value) and value >= min and value <= max
end

function Guard.isString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value <= (maxLength or 100)
end

function Guard.isVector3(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return Guard.isFiniteNumber(v.X) and Guard.isFiniteNumber(v.Y) and Guard.isFiniteNumber(v.Z)
end

-- A direction supplied by the client must be a sane unit-ish vector.
function Guard.isUnitVector(value: any): boolean
	return Guard.isVector3(value) and math.abs((value :: Vector3).Magnitude - 1) < 0.01
end

-- ---------------------------------------------------------------------------
-- Per-player rate limiting. Each (player, key) bucket allows `maxCalls` per
-- `windowSeconds`; anything beyond is rejected. Buckets are cleaned up when
-- the player leaves via Guard.clearPlayer.
-- ---------------------------------------------------------------------------

type Bucket = { windowStart: number, count: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

function Guard.checkRate(player: Player, key: string, maxCalls: number, windowSeconds: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local now = os.clock()
	local bucket = playerBuckets[key]
	if not bucket or now - bucket.windowStart >= windowSeconds then
		playerBuckets[key] = { windowStart = now, count = 1 }
		return true
	end

	if bucket.count >= maxCalls then
		return false
	end
	bucket.count += 1
	return true
end

function Guard.clearPlayer(player: Player)
	buckets[player] = nil
end

return Guard
