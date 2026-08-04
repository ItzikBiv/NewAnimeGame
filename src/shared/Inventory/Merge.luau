--!strict
--[[
	Merge resolution — the strict three-way match. Story 1.3.

	Ground truth: docs/ground-truth/source-game-teardown.md §5, quoted from the
	developers' own Discord FAQ:

	  "First, you need 2 of the same unit with the same mutation and level. Place
	   your 1st unit and then hold/equip your 2nd unit. When equipped, place your
	   2nd unit on your 1st unit — must be the same unit"

	And on trait retention, from a separate FAQ answer:

	  "Firstly place the unit you wanted to keep the trait, and then put the other
	   unit you don't want the trait or doesn't have a trait above it when fusing"

	So: the BASE unit (placed first) keeps its trait. The unit dropped ON TOP is
	consumed and its trait is destroyed. This is irreversible, and players get it
	wrong often enough that the devs put it in the FAQ — which is why `canMerge`
	returns a specific reason rather than a bare boolean. The UI needs to say which
	condition failed.
]]

local Inventory = require(script.Parent.Inventory)

--[[
	Can these two merge? Returns false plus the specific failing condition.

	All three must match: identity, mutation, AND level. This is much stricter than
	the "combine duplicates" that several public wikis describe.
]]
local function canMerge(profile: any, baseUid: string, fodderUid: string): (boolean, string?)
	if baseUid == fodderUid then
		return false, "a unit cannot merge into itself"
	end

	local base = Inventory.get(profile, baseUid)
	local fodder = Inventory.get(profile, fodderUid)

	if not base then
		return false, "base not owned: " .. baseUid
	end
	if not fodder then
		return false, "fodder not owned: " .. fodderUid
	end

	if base.unitId ~= fodder.unitId then
		return false, string.format("different units: %s vs %s", base.unitId, fodder.unitId)
	end
	if base.mutation ~= fodder.mutation then
		return false, string.format("different mutations: %s vs %s", base.mutation, fodder.mutation)
	end
	if base.level ~= fodder.level then
		return false, string.format("different levels: %d vs %d", base.level, fodder.level)
	end

	return true, nil
end

--[[
	Merge `fodderUid` into `baseUid`.

	The base keeps its uid, so a unit already placed on the grid stays placed and
	the grid needs no fixing up. That is the whole reason the grid stores uids.
]]
local function merge(profile: any, baseUid: string, fodderUid: string): (boolean, string?)
	local ok, reason = canMerge(profile, baseUid, fodderUid)
	if not ok then
		return false, reason
	end

	local base = profile.inventory[baseUid]
	base.level += 1
	-- base.trait is untouched: the base keeps its trait, per the FAQ.

	local removed, removeError = Inventory.remove(profile, fodderUid)
	if not removed then
		return false, removeError
	end

	return true, nil
end

--[[
	Every uid in the inventory that could merge into `baseUid`.

	The UI needs this to highlight valid fodder — with three conditions to satisfy,
	making the player hunt for matches by eye is how traits get destroyed.
]]
local function eligibleFodder(profile: any, baseUid: string): { string }
	local matches = {}
	for uid in pairs(profile.inventory) do
		if canMerge(profile, baseUid, uid) then
			table.insert(matches, uid)
		end
	end
	table.sort(matches)
	return matches
end

return {
	canMerge = canMerge,
	merge = merge,
	eligibleFodder = eligibleFodder,
}
