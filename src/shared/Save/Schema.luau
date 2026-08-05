--!strict
--[[
	Player save schema, defaults, and migrations.

	Design: docs/planning/architecture.md §4

	PURE MODULE. No DataStore, no services, no yields — the same discipline as
	Shared/Config. That is what lets migrations be tested headlessly, with no
	Roblox runtime and no Studio, which matters because a broken migration is one
	of the few bugs that destroys player data irreversibly.

	Versioned from day one. The one capability that cannot be retrofitted is the
	ability to know what shape old data is in.
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)

local CURRENT_VERSION = 1

--[[
	[OURS] Gold a brand-new profile starts with.

	Without this the game is unplayable from a cold start: a roll costs gold,
	gold comes from clearing a wave, and a wave needs at least one placed unit —
	so a new player has no way to earn their first coin. The source game must
	grant something equivalent; we cannot see what, so this is our call.

	500 buys five rolls, which is enough to fill the four starting slots and
	still have one pull spare. Adjust freely — it is a single number.
]]
local STARTING_GOLD = 500

export type StoredUnit = {
	unitId: string,
	rarity: string,
	mutation: string,
	level: number,
	trait: string?,
}

export type Profile = {
	schemaVersion: number,
	wave: number,
	gold: number,
	rollCount: number,
	nextUid: number,
	autoWave: boolean,
	checkpointWave: number,
	restartAtCheckpoint: boolean,
	currencies: { traitShards: number, essence: { [string]: number } },
	upgrades: { [string]: number },
	pity: { [string]: number },
	inventory: { [string]: StoredUnit },
	grid: { [string]: string },
	stats: { highestWave: number, highestGold: number, totalRolls: number },
}

local function defaultProfile(): Profile
	local essence: { [string]: number } = {}
	for rarityId in pairs(Rarities.Rarities) do
		essence[rarityId] = 0
	end

	-- A shallow copy, so a new upgrade added to config lands in new profiles for
	-- free and the clone can be mutated without touching the config table.
	local upgrades: { [string]: number } = table.clone(Upgrades.StartingLevels)

	-- [C] Pity persists across sessions. The source game's counters survive a
	-- rejoin; losing them on disconnect would be a player-hostile bug in the most
	-- emotionally loaded system in the game.
	local pity: { [string]: number } = {}
	for tier in pairs(Rarities.PityCaps) do
		pity[tier] = 0
	end

	return {
		schemaVersion = CURRENT_VERSION,
		wave = 1,
		gold = STARTING_GOLD,
		rollCount = 0,
		-- [C] The source game has a persistent "Auto" toggle on the wave HUD, and
		-- the devs recommend AFK farming — so this is a saved preference, not a
		-- per-session one.
		-- Owner's call: auto should be the default, not opt-in. The devs of the
		-- source game recommend AFK farming, so idle is the expected mode of play.
		autoWave = true,
		--[[
			[C] CHECKPOINTS — previously open question 8, now answered by the owner:
			losing sends you back to wave 1 or to the furthest checkpoint you reached,
			and which one is a setting.

			This is what makes an endless run survivable. Without it a loss at wave 40
			throws away the whole session, which no idle game does.
		]]
		checkpointWave = 1,
		restartAtCheckpoint = true,
		-- Server-issued unit ids. Units are keyed by uid, never by index — merges
		-- and trades reorder the collection constantly, and index-keyed references
		-- break under exactly that.
		nextUid = 1,
		currencies = { traitShards = 0, essence = essence },
		upgrades = upgrades,
		pity = pity,
		inventory = {},
		-- Maps tile index (as a string key, for DataStore JSON safety) to a unit
		-- uid. Storing uids rather than unit copies is the invariant that prevents
		-- duplication through the grid: one unit, one record.
		grid = {},
		stats = { highestWave = 1, highestGold = 0, totalRolls = 0 },
	}
end

--[[
	Migrations, applied in sequence on load.

	Each entry migrates version N to N+1 and MUST be pure — take a table, return a
	table, touch nothing else. Never delete a migration: a player who has not
	logged in since version 1 still needs the whole chain.
]]
local migrations: { [number]: (any) -> any } = {
	-- [1] = function(data) ... returns version 2 ... end,
}

--[[
	Bring a stored profile up to CURRENT_VERSION.

	Returns the migrated profile and how many steps were applied. Data with no
	`schemaVersion` is treated as version 1 — that is the first shipped version, so
	anything lacking the field predates the field, not the schema.
]]
local function migrate(data: any): (any, number)
	if type(data) ~= "table" then
		return defaultProfile(), 0
	end

	local version = tonumber(data.schemaVersion) or 1
	local steps = 0

	while version < CURRENT_VERSION do
		local step = migrations[version]
		if not step then
			-- No path forward. Refusing to guess is the correct behaviour: a
			-- caller must decide whether to reset or to fail the load, and
			-- silently mangling a profile is worse than either.
			error(
				string.format(
					"no migration from schema version %d (current is %d)",
					version,
					CURRENT_VERSION
				)
			)
		end
		data = step(data)
		version += 1
		data.schemaVersion = version
		steps += 1
	end

	return data, steps
end

--[[
	Fill in anything a profile is missing, without clobbering what it has.

	Guards the case a migration cannot: a profile saved before a field existed, or
	one partially written by an interrupted save. Runs after `migrate` on load.
]]
local function withDefaults(profile: any): Profile
	local defaults = defaultProfile()

	local function fill(target: any, source: any)
		for key, value in pairs(source) do
			if target[key] == nil then
				target[key] = value
			elseif type(value) == "table" and type(target[key]) == "table" then
				fill(target[key], value)
			end
		end
	end

	fill(profile, defaults)
	return profile
end

-- Cheap structural check. Returns false plus a reason rather than throwing, so a
-- caller can decide between resetting and failing the load.
local function validate(profile: any): (boolean, string?)
	if type(profile) ~= "table" then
		return false, "profile is not a table"
	end
	for _, field in { "schemaVersion", "wave", "gold", "inventory", "grid", "upgrades", "pity" } do
		if profile[field] == nil then
			return false, "missing field: " .. field
		end
	end
	if profile.schemaVersion ~= CURRENT_VERSION then
		return false, string.format("unmigrated: version %s", tostring(profile.schemaVersion))
	end
	if profile.wave < 1 then
		return false, "wave below 1"
	end
	if profile.gold < 0 then
		return false, "negative gold"
	end
	-- Every placed uid must correspond to an owned unit. This is the duplication
	-- invariant from architecture.md §4.2, checked rather than assumed.
	for tile, uid in pairs(profile.grid) do
		if profile.inventory[uid] == nil then
			return false,
				string.format("tile %s holds unowned uid %s", tostring(tile), tostring(uid))
		end
	end
	return true, nil
end

return {
	CURRENT_VERSION = CURRENT_VERSION,
	STARTING_GOLD = STARTING_GOLD,
	defaultProfile = defaultProfile,
	migrations = migrations,
	migrate = migrate,
	withDefaults = withDefaults,
	validate = validate,
}
