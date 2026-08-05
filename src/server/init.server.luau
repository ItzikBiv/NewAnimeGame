--!strict
--[[
	Server bootstrap.

	ORDER IS LOAD-BEARING. Remotes are built FIRST, before any service is even
	required, because the client blocks on `WaitForChild("Remotes")`. If a service
	throws while loading and remotes do not exist yet, every client hangs forever
	on that wait with nothing in the output to explain it — which is exactly what
	happened when DataService threw at module scope in Studio.

	So: create the remotes, then start services, and let a service failure be loud
	and contained rather than silent and total.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local RateLimit = require(Shared.Net.RateLimit)
local Validate = require(Shared.Net.Validate)

-- 1. Remotes exist before anything can fail.
Remotes.build()
Remotes.assertCoverage(RateLimit.LIMITS, Validate.validators)

-- 2. Services. Required only now, so a throw here cannot strand a client.
local Guard = require(script.Middleware.Guard)
local DataService = require(script.Services.DataService)
local GameService = require(script.Services.GameService)

DataService.start()
GameService.start()

-- 3. Every client->server remote goes through Guard. There is no other path.
Guard.connect(Remotes.TO_SERVER.RequestRoll, function(player)
	return GameService.handleRoll(player)
end)
Guard.connect(Remotes.TO_SERVER.RequestMerge, function(player, payload)
	return GameService.handleMerge(player, payload)
end)
Guard.connect(Remotes.TO_SERVER.RequestPlace, function(player, payload)
	return GameService.handlePlace(player, payload)
end)
Guard.connect(Remotes.TO_SERVER.RequestUpgrade, function(player, payload)
	return GameService.handleUpgrade(player, payload)
end)
Guard.connect(Remotes.TO_SERVER.RequestWaveStart, function(player)
	return GameService.handleWaveStart(player)
end)
Guard.connect(Remotes.TO_SERVER.RequestWaveStop, function(player)
	return GameService.handleWaveStop(player)
end)
Guard.connect(Remotes.TO_SERVER.RequestAutoToggle, function(player)
	return GameService.handleAutoToggle(player)
end)
Guard.connect(Remotes.TO_SERVER.RequestRestartModeToggle, function(player)
	return GameService.handleRestartModeToggle(player)
end)

print("[RollAnimeToFight] server ready")
