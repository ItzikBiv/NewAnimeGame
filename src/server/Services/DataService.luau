--!strict
--[[
	Profile persistence. Story 1.6.

	Design: docs/planning/architecture.md §4

	NOT VERIFIABLE OUTSIDE STUDIO. This module touches DataStoreService, which
	does not exist in the headless test environment. The pure parts it depends on —
	Schema.migrate, withDefaults, validate — are exhaustively tested in
	tests/save-invariants.luau; this is the thin, untested glue around them.

	SESSION LOCKING. Roblox DataStores have no cross-server lock, so two servers
	holding the same player duplicates items — unrecoverable in a game with
	trading. The lock below is a minimal own implementation:

	  A profile carries a lock { jobId, heartbeat }. A server may claim it if the
	  lock is absent, already ours, or stale (no heartbeat within LOCK_TIMEOUT).
	  We refresh the heartbeat on every autosave.

	This is deliberately simpler than ProfileStore, which remains the recommended
	upgrade (architecture.md §4.1) — it handles retries, backoff and edge cases
	this does not. It is NOT added as a Wally dependency yet because this
	environment cannot install or exercise it, and shipping an unverified
	dependency is worse than shipping a documented simpler one.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Schema = require(Shared.Save.Schema)

local STORE_NAME = "RollAnimeToFight_v1"
local LOCK_TIMEOUT = 120
local AUTOSAVE_INTERVAL = 60

local store = DataStoreService:GetDataStore(STORE_NAME)

local DataService = {}

local profiles: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}

local function key(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function lockIsOurs(lock: any): boolean
	return lock ~= nil and lock.jobId == game.JobId
end

local function lockIsStale(lock: any): boolean
	if lock == nil then
		return true
	end
	return (os.time() - (tonumber(lock.heartbeat) or 0)) > LOCK_TIMEOUT
end

--[[
	Load, migrate and validate a player's profile, claiming the session lock.

	Returns nil when the profile is held by a live session elsewhere, or when it
	fails validation. In BOTH cases the caller must refuse the session rather than
	start a fresh profile — overwriting a real save is the one unrecoverable
	mistake this system can make.
]]
--[[
	Is persistence actually available?

	DataStores require a PUBLISHED place with "Enable Studio Access to API
	Services" turned on. In a fresh local place neither is true, so every call
	throws — and since a failed load correctly refuses the session, a playtester
	would be kicked the instant they join with no idea why.

	So in Studio, when DataStores are unreachable, fall back to an in-memory
	profile. That makes a local playtest possible without publishing anything.
	It is Studio-only and never applies in a live game: `RunService:IsStudio()`
	is false on a real server, so production always uses the real store or
	refuses the session.
]]
local dataStoresAvailable: boolean? = nil

local function persistenceAvailable(): boolean
	if dataStoresAvailable ~= nil then
		return dataStoresAvailable
	end
	local ok = pcall(function()
		store:GetAsync("__probe")
	end)
	dataStoresAvailable = ok
	if not ok then
		warn(
			"[DataService] DataStores unavailable — running with IN-MEMORY profiles. "
				.. "Progress will NOT be saved. Publish the place and enable Studio "
				.. "access to API services for real persistence."
		)
	end
	return ok
end

function DataService.load(player: Player): any?
	if loading[player] then
		return nil
	end

	if not persistenceAvailable() then
		if not RunService:IsStudio() then
			-- Live, and the store is unreachable. Refuse rather than hand out a
			-- blank profile that will later overwrite a real save.
			return nil
		end
		local profile = Schema.withDefaults(Schema.migrate(nil))
		profiles[player] = profile
		return profile
	end

	loading[player] = true

	local ok, result = pcall(function()
		return store:UpdateAsync(key(player), function(stored)
			if stored ~= nil and not lockIsOurs(stored.lock) and not lockIsStale(stored.lock) then
				-- Held elsewhere. Returning nil aborts the update.
				return nil
			end

			local data = stored and stored.profile or nil
			local migrated = Schema.migrate(data)
			migrated = Schema.withDefaults(migrated)

			return {
				profile = migrated,
				lock = { jobId = game.JobId, heartbeat = os.time() },
			}
		end)
	end)

	loading[player] = nil

	if not ok then
		warn(string.format("[DataService] load failed for %s: %s", player.Name, tostring(result)))
		return nil
	end
	if result == nil then
		warn(string.format("[DataService] %s is locked by another server", player.Name))
		return nil
	end

	local profile = result.profile
	local valid, why = Schema.validate(profile)
	if not valid then
		-- Refuse rather than reset. A corrupt profile the player can complain about
		-- is recoverable; one we have already overwritten is not.
		warn(string.format("[DataService] %s failed validation: %s", player.Name, tostring(why)))
		return nil
	end

	profiles[player] = profile
	return profile
end

function DataService.get(player: Player): any?
	return profiles[player]
end

-- Persist and refresh the lock heartbeat. `release` clears the lock on leave.
function DataService.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not persistenceAvailable() then
		return false -- in-memory Studio session; nothing to write
	end

	local valid, why = Schema.validate(profile)
	if not valid then
		warn(string.format("[DataService] refusing to save invalid profile: %s", tostring(why)))
		return false
	end

	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function(stored)
			if stored and not lockIsOurs(stored.lock) and not lockIsStale(stored.lock) then
				return nil -- lost the lock; do not clobber
			end
			return {
				profile = profile,
				lock = release and nil or { jobId = game.JobId, heartbeat = os.time() },
			}
		end)
	end)

	if not ok then
		warn(string.format("[DataService] save failed for %s: %s", player.Name, tostring(err)))
		return false
	end
	return true
end

function DataService.release(player: Player)
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerRemoving:Connect(function(player)
		DataService.release(player)
	end)

	-- BindToClose is the last chance to flush before a shutdown, and Roblox gives
	-- it a bounded window — save everyone in parallel, not in sequence.
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.release(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				DataService.save(player)
			end
		end
	end)
end

return DataService
