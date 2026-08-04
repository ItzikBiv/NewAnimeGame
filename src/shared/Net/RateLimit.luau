--!strict
--[[
	Per-player, per-remote token buckets. Story 1.7.

	Design: docs/planning/architecture.md §3.3

	PURE MODULE. Time is an ARGUMENT, never `os.clock()` — which is what makes rate
	limiting testable without waiting in real time. A rate limiter you cannot test
	is a rate limiter you find out about in production.

	Why this is not optional: a client loop calling RequestRoll thousands of times
	a second is both an economy exploit and a server-performance incident. On
	Roblox the client can fire any RemoteEvent at any rate, so the server has to
	assume it will.

	Token bucket rather than a fixed window, because players legitimately burst —
	opening the roll machine and clicking five times is normal — while a sustained
	flood is not. A bucket allows the burst and throttles the flood.
]]

export type Bucket = {
	tokens: number,
	lastRefill: number,
}

export type Limit = {
	-- Sustained rate, tokens per second.
	refillPerSecond: number,
	-- Maximum burst.
	capacity: number,
}

--[[
	Limits per remote. Deliberately generous for human play and hostile to scripts:
	a player physically cannot roll 10 times a second, but a script trivially can.
]]
local LIMITS: { [string]: Limit } = {
	RequestRoll = { refillPerSecond = 5, capacity = 10 },
	RequestMerge = { refillPerSecond = 10, capacity = 20 },
	RequestPlace = { refillPerSecond = 10, capacity = 20 },
	RequestUpgrade = { refillPerSecond = 2, capacity = 5 },
	RequestWaveStart = { refillPerSecond = 1, capacity = 3 },
}

-- Anything not listed above gets this, so a new remote is throttled by default
-- rather than unthrottled by omission. Failing closed matters more than
-- convenience here.
local DEFAULT_LIMIT: Limit = { refillPerSecond = 2, capacity = 5 }

local function limitFor(remoteName: string): Limit
	return LIMITS[remoteName] or DEFAULT_LIMIT
end

local function newBucket(remoteName: string, now: number): Bucket
	return {
		tokens = limitFor(remoteName).capacity,
		lastRefill = now,
	}
end

--[[
	Try to spend one token.

	Returns whether the call is allowed, the updated bucket, and — when refused —
	how long until a token is available, so the caller can tell the client to back
	off rather than leaving it to retry blindly.
]]
local function consume(bucket: Bucket, remoteName: string, now: number): (boolean, Bucket, number?)
	local limit = limitFor(remoteName)

	local elapsed = math.max(0, now - bucket.lastRefill)
	local refilled = math.min(limit.capacity, bucket.tokens + elapsed * limit.refillPerSecond)

	if refilled >= 1 then
		return true, { tokens = refilled - 1, lastRefill = now }, nil
	end

	local waitFor = (1 - refilled) / limit.refillPerSecond
	return false, { tokens = refilled, lastRefill = now }, waitFor
end

--[[
	A whole player's buckets, keyed by remote name.

	Held in memory only — losing them on server restart is fine, because the
	persistent cooldowns that MUST survive a reconnect live in the profile instead
	(architecture.md §7). This is flood protection, not game state.
]]
export type PlayerBuckets = { [string]: Bucket }

local function check(buckets: PlayerBuckets, remoteName: string, now: number): (boolean, number?)
	local bucket = buckets[remoteName] or newBucket(remoteName, now)
	local allowed, updated, waitFor = consume(bucket, remoteName, now)
	buckets[remoteName] = updated
	return allowed, waitFor
end

return {
	LIMITS = LIMITS,
	DEFAULT_LIMIT = DEFAULT_LIMIT,
	limitFor = limitFor,
	newBucket = newBucket,
	consume = consume,
	check = check,
}
