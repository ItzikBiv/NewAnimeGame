--!strict
--[[
	Inventory — uid issuing, capacity, ownership. Story 1.2.

	Design: docs/planning/epics.md story 1.2, architecture.md §4.2

	PURE MODULE in the sense that matters: no services, no yields, no globals. It
	DOES mutate the profile table it is handed, deliberately — a maxed inventory is
	225 units and deep-copying it on every grant would be waste for no safety gain,
	since the server owns the only copy.

	Every function returns `(ok, errorOrValue)` rather than throwing. A rolled unit
	that cannot be stored is a real situation the caller must handle, not an
	exception.
]]

local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Schema = require(script.Parent.Parent.Save.Schema)

type StoredUnit = Schema.StoredUnit

-- How many units this profile can hold, from its Inventory Upgrade level. [D]
local function capacity(profile: any): number
	return Upgrades.Upgrades.Inventory.valueAtLevel(profile.upgrades.Inventory)
end

local function count(profile: any): number
	local n = 0
	for _ in pairs(profile.inventory) do
		n += 1
	end
	return n
end

local function isFull(profile: any): boolean
	return count(profile) >= capacity(profile)
end

local function owns(profile: any, uid: string): boolean
	return profile.inventory[uid] ~= nil
end

local function get(profile: any, uid: string): StoredUnit?
	return profile.inventory[uid]
end

--[[
	Store a unit and return its new uid.

	Uids are issued from a monotonic counter and NEVER reused, even after a unit is
	consumed by a merge. Reuse would let a stale client reference — a queued merge,
	an in-flight trade — silently resolve against a different unit than the one the
	player meant.
]]
local function grant(profile: any, unit: StoredUnit): (boolean, string)
	if isFull(profile) then
		-- [C] The source game caps inventory and sells the upgrade, so hitting this
		-- is expected play, not an error state. The caller must surface it — silently
		-- dropping a rolled unit is the worst possible outcome in a gacha.
		return false, "inventory full"
	end

	local uid = "u" .. tostring(profile.nextUid)
	profile.nextUid += 1
	profile.inventory[uid] = unit
	return true, uid
end

--[[
	Remove a unit. Also clears it from the grid, so the two can never disagree —
	`Schema.validate` treats a tile holding an unowned uid as corruption, and the
	only way to guarantee that never happens is to keep removal in one place.
]]
local function remove(profile: any, uid: string): (boolean, string?)
	if not owns(profile, uid) then
		return false, "not owned: " .. uid
	end

	profile.inventory[uid] = nil
	for tile, placed in pairs(profile.grid) do
		if placed == uid then
			profile.grid[tile] = nil
		end
	end
	return true, nil
end

return {
	capacity = capacity,
	count = count,
	isFull = isFull,
	owns = owns,
	get = get,
	grant = grant,
	remove = remove,
}
