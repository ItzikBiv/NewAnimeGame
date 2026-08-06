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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	NO AVATAR. This is an idle auto-battler played from a fixed camera looking at
	your own board — there is nothing to walk to and nothing to walk on. Workspace
	ships with no baseplate, and the arena is built on the client, so a character
	that spawned here would drop straight through the world into the void.

	Turning the character off is therefore not a cosmetic choice, it removes a
	guaranteed bug. If we later want the source game's walk-around base, this line
	comes out AND the floor has to move to the server first — in that order.
]]
Players.CharacterAutoLoads = false

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
Guard.connect(Remotes.TO_SERVER.RequestReroll, function(player)
	return GameService.handleReroll(player)
end)
Guard.connect(Remotes.TO_SERVER.RequestBuy, function(player, payload)
	return GameService.handleBuy(player, payload)
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
