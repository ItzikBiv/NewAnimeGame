--!nocheck
--[[
	Inventory, merge and grid — stories 1.2, 1.3, 1.4.

	Together these three modules complete `roll -> merge -> place`. They share one
	suite because they share one invariant: a unit exists exactly once, and the
	grid only ever references units the player owns. Testing them apart would miss
	the interactions that break that.

	Expects globals: Rarities, Mutations, Traits, Upgrades, Waves, Power, Schema,
	Roll, Inventory, Merge, Grid.
]]

local pass, fail = 0, 0

local function check(label, got, want)
	if got == want then
		pass += 1
		print(string.format("  ok   %-54s = %s", label, tostring(got)))
	else
		fail += 1
		print(string.format("  FAIL %-54s = %s (want %s)", label, tostring(got), tostring(want)))
	end
end

local function expect(label, condition, detail)
	if condition then
		pass += 1
		print(string.format("  ok   %s%s", label, detail and (" — " .. detail) or ""))
	else
		fail += 1
		print(string.format("  FAIL %s%s", label, detail and (" — " .. detail) or ""))
	end
end

local function unit(unitId, mutation, level, trait)
	return {
		unitId = unitId,
		rarity = "Common",
		mutation = mutation or "Normal",
		level = level or 1,
		trait = trait,
	}
end

local function freshProfile()
	return Schema.defaultProfile()
end

print("Story 1.2 — inventory capacity comes from the upgrade")
local p = freshProfile()
check("a fresh profile is empty", Inventory.count(p), 0)
check("capacity at Inventory Lv1", Inventory.capacity(p), 75)
p.upgrades.Inventory = 7
check("capacity at max Lv7", Inventory.capacity(p), 225)
p.upgrades.Inventory = 1

print("\nUids are issued monotonically and never reused")
local okA, uidA = Inventory.grant(p, unit("Noruto"))
local okB, uidB = Inventory.grant(p, unit("Luppi"))
expect("first grant succeeded", okA, uidA)
expect("second grant succeeded", okB, uidB)
expect("uids differ", uidA ~= uidB, uidA .. " vs " .. uidB)
check("count after two grants", Inventory.count(p), 2)

Inventory.remove(p, uidA)
local _, uidC = Inventory.grant(p, unit("Sakuna"))
expect(
	"a uid freed by removal is NOT reused",
	uidC ~= uidA,
	string.format("removed %s, next issued %s", uidA, uidC)
)

print("\nA full inventory refuses the grant rather than dropping the unit")
local full = freshProfile()
local capacityOf = Inventory.capacity(full)
for i = 1, capacityOf do
	local granted = Inventory.grant(full, unit("Filler" .. i))
	if not granted then
		fail += 1
		print("  FAIL could not fill to capacity")
		break
	end
end
check("filled to capacity", Inventory.count(full), capacityOf)
expect("inventory reports full", Inventory.isFull(full))
local overflowed, overflowReason = Inventory.grant(full, unit("OneTooMany"))
expect("the grant is refused", not overflowed, overflowReason)
check("count did not change", Inventory.count(full), capacityOf)

print("\nRemoving a unit also clears it from the grid")
local g = freshProfile()
local _, gUid = Inventory.grant(g, unit("Goji"))
Grid.place(g, gUid, 1)
check("placed on tile 1", Grid.unitAt(g, 1), gUid)
Inventory.remove(g, gUid)
expect("tile 1 is now empty", Grid.unitAt(g, 1) == nil, "grid and inventory cannot disagree")
expect("and the profile still validates", (Schema.validate(g)))

print("\nStory 1.3 — merging requires ALL THREE of identity, mutation and level")
local m = freshProfile()
local _, base = Inventory.grant(m, unit("Noruto", "Normal", 1, "Sharp"))
local _, sameEverything = Inventory.grant(m, unit("Noruto", "Normal", 1))
local _, otherUnit = Inventory.grant(m, unit("Luppi", "Normal", 1))
local _, otherMutation = Inventory.grant(m, unit("Noruto", "Gold", 1))
local _, otherLevel = Inventory.grant(m, unit("Noruto", "Normal", 2))

local canSame = Merge.canMerge(m, base, sameEverything)
expect("identical units can merge", canSame)

local _, whyUnit = Merge.canMerge(m, base, otherUnit)
expect("a different unit is refused", whyUnit ~= nil, whyUnit)
local _, whyMutation = Merge.canMerge(m, base, otherMutation)
expect("a different mutation is refused", whyMutation ~= nil, whyMutation)
local _, whyLevel = Merge.canMerge(m, base, otherLevel)
expect("a different level is refused", whyLevel ~= nil, whyLevel)
local _, whySelf = Merge.canMerge(m, base, base)
expect("merging into itself is refused", whySelf ~= nil, whySelf)

print("\nThe refusal says WHICH condition failed")
-- The UI has to tell the player why. "Merge failed" destroys trust in a system
-- where the wrong move permanently destroys a trait.
expect(
	"mutation mismatch names both mutations",
	string.find(whyMutation, "Gold") ~= nil,
	whyMutation
)
expect("level mismatch names both levels", string.find(whyLevel, "2") ~= nil, whyLevel)

print("\nThe base keeps its trait; the fodder is consumed")
local merged, mergeError = Merge.merge(m, base, sameEverything)
expect("merge succeeded", merged, mergeError or "")
check("base is now level 2", Inventory.get(m, base).level, 2)
check("base kept its trait", Inventory.get(m, base).trait, "Sharp")
expect("fodder is gone", not Inventory.owns(m, sameEverything), "consumed")
check("base kept its uid", Inventory.owns(m, base), true)

print("\nA traited fodder loses its trait — the FAQ's warning, made real")
local t = freshProfile()
local _, keepTrait = Inventory.grant(t, unit("Sakuna", "Normal", 1, "Reaper"))
local _, loseTrait = Inventory.grant(t, unit("Sakuna", "Normal", 1, "Cursed"))
Merge.merge(t, keepTrait, loseTrait)
check("the BASE trait survives", Inventory.get(t, keepTrait).trait, "Reaper")
expect(
	"the fodder's Cursed trait is destroyed",
	not Inventory.owns(t, loseTrait),
	"merge order is a losable decision"
)

print("\nA placed unit stays placed through a merge")
local pm = freshProfile()
local _, pBase = Inventory.grant(pm, unit("Bills", "Normal", 1))
local _, pFodder = Inventory.grant(pm, unit("Bills", "Normal", 1))
Grid.place(pm, pBase, 2)
Merge.merge(pm, pBase, pFodder)
check("still on tile 2", Grid.unitAt(pm, 2), pBase)
check("and levelled up", Inventory.get(pm, pBase).level, 2)
expect("profile still validates", (Schema.validate(pm)))

print("\neligibleFodder finds every valid match and nothing else")
local e = freshProfile()
local _, eBase = Inventory.grant(e, unit("Yutta", "Normal", 1))
local _, match1 = Inventory.grant(e, unit("Yutta", "Normal", 1))
local _, match2 = Inventory.grant(e, unit("Yutta", "Normal", 1))
Inventory.grant(e, unit("Yutta", "Gold", 1))
Inventory.grant(e, unit("Yutta", "Normal", 2))
Inventory.grant(e, unit("Megumo", "Normal", 1))
local eligible = Merge.eligibleFodder(e, eBase)
check("found exactly the two valid matches", #eligible, 2)
expect(
	"and they are the right ones",
	(eligible[1] == match1 or eligible[1] == match2)
		and (eligible[2] == match1 or eligible[2] == match2),
	table.concat(eligible, ", ")
)

print("\nStory 1.4 — grid respects the slot count")
local gr = freshProfile()
check("a fresh profile has 4 slots", Grid.slotCount(gr), 4)
local _, u1 = Inventory.grant(gr, unit("A"))
local placedOk = Grid.place(gr, u1, 4)
expect("tile 4 is placeable at Lv1", placedOk)
local tooFar, tooFarReason = Grid.place(gr, u1, 5)
expect("tile 5 is refused at Lv1", not tooFar, tooFarReason)
local zero, zeroReason = Grid.place(gr, u1, 0)
expect("tile 0 is refused", not zero, zeroReason)

gr.upgrades.Slot = 9
check("slots at max Lv9", Grid.slotCount(gr), 12)
expect("tile 12 is placeable at max", (Grid.place(gr, u1, 12)))
local past, pastReason = Grid.place(gr, u1, 13)
expect("tile 13 is refused even at max", not past, pastReason)

print("\nA uid can never occupy two tiles")
local two = freshProfile()
local _, tUid = Inventory.grant(two, unit("Fryren"))
Grid.place(two, tUid, 1)
Grid.place(two, tUid, 3)
check("only one tile is occupied", Grid.placedCount(two), 1)
check("and it is the newest", Grid.unitAt(two, 3), tUid)
expect("the old tile was vacated", Grid.unitAt(two, 1) == nil, "placing moves, never duplicates")

print("\nAn occupied tile refuses a different unit")
local occ = freshProfile()
local _, o1 = Inventory.grant(occ, unit("X"))
local _, o2 = Inventory.grant(occ, unit("Y"))
Grid.place(occ, o1, 1)
local blocked, blockedReason = Grid.place(occ, o2, 1)
expect("the tile is defended", not blocked, blockedReason)
check("the original occupant stays", Grid.unitAt(occ, 1), o1)
expect("re-placing the SAME unit on its own tile is fine", (Grid.place(occ, o1, 1)))

print("\nUnowned uids can never reach the grid")
local un = freshProfile()
local ghost, ghostReason = Grid.place(un, "u999", 1)
expect("an unowned uid is refused", not ghost, ghostReason)
check("the grid stayed empty", Grid.placedCount(un), 0)

print("\nShrinking the slot count prunes orphaned placements")
local sh = freshProfile()
sh.upgrades.Slot = 9
for i = 1, 12 do
	local _, uid = Inventory.grant(sh, unit("U" .. i))
	Grid.place(sh, uid, i)
end
check("12 units fielded", Grid.placedCount(sh), 12)
sh.upgrades.Slot = 1
local pruned = Grid.pruneOutOfBounds(sh)
check("pruned the out-of-bounds tiles", pruned, 8)
check("4 remain", Grid.placedCount(sh), 4)
expect("profile still validates", (Schema.validate(sh)))

print("\nEnd to end: roll -> grant -> merge -> place -> still valid")
local e2e = freshProfile()
local rng = (function()
	local state = 4242
	return function()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end)()

local granted = 0
local pity = Roll.newPity()
for _ = 1, 40 do
	local result = Roll.roll(1, pity, 0, rng)
	pity = result.pity
	local ok = Inventory.grant(e2e, {
		unitId = "Unit_" .. result.rarity,
		rarity = result.rarity,
		mutation = result.mutation,
		level = 1,
	})
	if ok then
		granted += 1
	end
end
expect("40 rolls all stored", granted == 40, string.format("%d units", granted))

-- Merge whatever the rolls happened to produce a pair of.
local mergesDone = 0
for uid in pairs(e2e.inventory) do
	local fodder = Merge.eligibleFodder(e2e, uid)
	if #fodder > 0 then
		local ok = Merge.merge(e2e, uid, fodder[1])
		if ok then
			mergesDone += 1
		end
	end
end
expect("merges happened naturally", mergesDone > 0, string.format("%d merges", mergesDone))

local fielded = 0
for uid in pairs(e2e.inventory) do
	if fielded >= Grid.slotCount(e2e) then
		break
	end
	if Grid.place(e2e, uid, fielded + 1) then
		fielded += 1
	end
end
check("filled all 4 starting slots", fielded, 4)

local finalOk, finalReason = Schema.validate(e2e)
expect("the profile survives the whole loop", finalOk, finalReason or "valid")
check("fielded uids match placements", #Grid.fieldedUids(e2e), 4)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
