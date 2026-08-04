--!strict
--[[
	Grid placement. Story 1.4.

	[C] The player's side grows from 4 tiles to 12 via the Slot Upgrade; the enemy
	side is a fixed 16. Tiles are keyed by their index as a STRING, because
	DataStore serialisation does not preserve integer keys in a sparse table.

	The invariants this module exists to hold:
	  - a tile never holds a uid the player does not own
	  - a uid never occupies two tiles at once
	  - no tile beyond the current slot count is usable

	`Schema.validate` re-checks the first of those on load, so a bug here surfaces
	as a refused session rather than as silent duplication.
]]

local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Inventory = require(script.Parent.Parent.Inventory.Inventory)

-- How many tiles this profile can use, from its Slot Upgrade level. [D]
local function slotCount(profile: any): number
	return Upgrades.Upgrades.Slot.valueAtLevel(profile.upgrades.Slot)
end

local function key(tileIndex: number): string
	return tostring(tileIndex)
end

local function unitAt(profile: any, tileIndex: number): string?
	return profile.grid[key(tileIndex)]
end

-- Which tile holds this uid, if any.
local function tileOf(profile: any, uid: string): number?
	for tile, placed in pairs(profile.grid) do
		if placed == uid then
			return tonumber(tile)
		end
	end
	return nil
end

local function placedCount(profile: any): number
	local n = 0
	for _ in pairs(profile.grid) do
		n += 1
	end
	return n
end

--[[
	Place a unit on a tile.

	Placing a unit that is already on another tile MOVES it rather than duplicating
	it — that is the natural reading of the player's intent, and the alternative
	(two tiles holding one uid) is exactly the corruption we are guarding against.
]]
local function place(profile: any, uid: string, tileIndex: number): (boolean, string?)
	if not Inventory.owns(profile, uid) then
		return false, "not owned: " .. uid
	end

	local slots = slotCount(profile)
	if tileIndex < 1 or tileIndex > slots then
		return false, string.format("tile %d outside 1..%d", tileIndex, slots)
	end
	if tileIndex ~= math.floor(tileIndex) then
		return false, "tile index must be a whole number"
	end

	local occupant = unitAt(profile, tileIndex)
	if occupant and occupant ~= uid then
		return false, string.format("tile %d already holds %s", tileIndex, occupant)
	end

	local existing = tileOf(profile, uid)
	if existing then
		profile.grid[key(existing)] = nil
	end

	profile.grid[key(tileIndex)] = uid
	return true, nil
end

local function clear(profile: any, tileIndex: number): (boolean, string?)
	if not unitAt(profile, tileIndex) then
		return false, string.format("tile %d is empty", tileIndex)
	end
	profile.grid[key(tileIndex)] = nil
	return true, nil
end

--[[
	Drop any placement that a shrinking slot count has left out of bounds.

	Slots only grow through upgrades today, so this cannot fire in normal play — but
	an admin rollback or a data fix could shrink them, and a tile beyond the limit
	would then be invisible to the player yet still fielded in combat.
]]
local function pruneOutOfBounds(profile: any): number
	local slots = slotCount(profile)
	local pruned = 0
	for tile in pairs(profile.grid) do
		local index = tonumber(tile)
		if not index or index < 1 or index > slots then
			profile.grid[tile] = nil
			pruned += 1
		end
	end
	return pruned
end

-- The uids currently fielded, for combat.
local function fieldedUids(profile: any): { string }
	local uids = {}
	for _, uid in pairs(profile.grid) do
		table.insert(uids, uid)
	end
	table.sort(uids)
	return uids
end

return {
	slotCount = slotCount,
	unitAt = unitAt,
	tileOf = tileOf,
	placedCount = placedCount,
	place = place,
	clear = clear,
	pruneOutOfBounds = pruneOutOfBounds,
	fieldedUids = fieldedUids,
}
