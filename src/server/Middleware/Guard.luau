--!strict
--[[
	The single gate every client->server call passes through.

	Design: docs/planning/architecture.md §3.3, §7

	Order matters and is deliberate:

	  1. RATE LIMIT first — it is the cheapest check, and the whole point is to
	     shed load before doing any work. Validating a flood is still doing work
	     for a flood.
	  2. VALIDATE second — reject anything malformed before a service sees it.
	  3. OWNERSHIP last, in the service — it needs the profile, which this layer
	     deliberately does not hold.

	Rejections are reported back to the client so a legitimate player sees why
	rather than a dead button. That is a UX requirement, not a courtesy: a silent
	no-op is indistinguishable from a bug.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RateLimit = require(Shared.Net.RateLimit)
local Validate = require(Shared.Net.Validate)
local Remotes = require(Shared.Net.Remotes)

local Guard = {}

-- Per-player buckets, in memory only. Persistent cooldowns live in the profile.
local buckets: { [Player]: RateLimit.PlayerBuckets } = {}

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

local function reject(player: Player, remoteName: string, reason: string, retryAfter: number?)
	local remote = Remotes.folder():FindFirstChild(Remotes.TO_CLIENT.ActionRejected)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, {
			remote = remoteName,
			reason = reason,
			retryAfter = retryAfter,
		})
	end
end

--[[
	Wrap a handler so it only ever sees rate-limited, validated calls.

	`handler(player, payload)` may return `(false, reason)` to reject; anything
	else is treated as success.
]]
function Guard.wrap(remoteName: string, handler: (Player, any) -> (boolean?, string?))
	return function(player: Player, payload: any)
		local playerBuckets = buckets[player]
		if not playerBuckets then
			playerBuckets = {}
			buckets[player] = playerBuckets
		end

		local allowed, retryAfter = RateLimit.check(playerBuckets, remoteName, os.clock())
		if not allowed then
			reject(player, remoteName, "too many requests", retryAfter)
			return
		end

		local valid, why = Validate.validate(remoteName, payload)
		if not valid then
			reject(player, remoteName, why or "invalid request")
			return
		end

		local ok, reason = handler(player, payload)
		if ok == false then
			reject(player, remoteName, reason or "rejected")
		end
	end
end

-- Connect a guarded handler to its remote.
function Guard.connect(remoteName: string, handler: (Player, any) -> (boolean?, string?))
	local remote = Remotes.folder():WaitForChild(remoteName) :: RemoteEvent
	remote.OnServerEvent:Connect(Guard.wrap(remoteName, handler))
end

return Guard
