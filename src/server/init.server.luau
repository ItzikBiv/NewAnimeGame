--!strict
--[[
	Server bootstrap.

	Order matters: remotes must exist before anything connects to them, and the
	coverage assertion runs before any player can call in — a remote missing a
	rate limit or a validator should stop the server at boot, not leak in
	production.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local RateLimit = require(Shared.Net.RateLimit)
local Validate = require(Shared.Net.Validate)

local Guard = require(script.Middleware.Guard)
local DataService = require(script.Services.DataService)
local GameService = require(script.Services.GameService)

Remotes.build()
Remotes.assertCoverage(RateLimit.LIMITS, Validate.validators)

DataService.start()
GameService.start()

-- Every client->server remote goes through Guard. There is no other path.
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

print("[RollAnimeToFight] server ready")
