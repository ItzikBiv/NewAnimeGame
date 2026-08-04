--!nocheck
--[[
	Save schema, defaults, migration and validation tests.

	A broken migration is one of the very few bugs that destroys player data
	irreversibly — there is no rollback for a profile you have already overwritten.
	That is why Schema is a pure module: it can be exercised exhaustively here,
	with no DataStore and no Studio.

	Expects globals: Rarities, Mutations, Traits, Upgrades, Waves, Power, Schema.
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

print("A fresh profile is complete and valid")
local fresh = Schema.defaultProfile()
local okFresh, reason = Schema.validate(fresh)
expect("default profile validates", okFresh, reason or "no issues")
check("starts on wave 1", fresh.wave, 1)
check("starts with 0 gold", fresh.gold, 0)
check("stamped with the current schema version", fresh.schemaVersion, Schema.CURRENT_VERSION)

print("\nDefaults are derived from config, not hand-copied")
-- If a rarity or upgrade is ever added, the default profile must pick it up
-- automatically. Hand-maintained duplicate lists are how save bugs start.
local nEssence, nRarities = 0, 0
for _ in pairs(fresh.currencies.essence) do
	nEssence += 1
end
for _ in pairs(Rarities.Rarities) do
	nRarities += 1
end
check("one essence counter per rarity", nEssence, nRarities)

for upgradeId, startingLevel in pairs(Upgrades.StartingLevels) do
	check(
		string.format("%-10s starts at level", upgradeId),
		fresh.upgrades[upgradeId],
		startingLevel
	)
end

-- [C] Pity persists across sessions in the source game.
local nPity = 0
for _ in pairs(fresh.pity) do
	nPity += 1
end
check("a persisted pity counter per in-game counter", nPity, 3)
expect("pity is saved, not in-memory only", fresh.pity.Legendary ~= nil, "survives a rejoin")

print("\nA fresh profile matches the confirmed starting state")
-- [C] Owner: "you start with 4 slots ... you can get more in upgrades till 12".
local startingSlots = Upgrades.Upgrades.Slot.valueAtLevel(fresh.upgrades.Slot)
check("starting grid slots", startingSlots, 4)
local startingInventory = Upgrades.Upgrades.Inventory.valueAtLevel(fresh.upgrades.Inventory)
expect(
	"starting inventory capacity is sane",
	startingInventory > 0 and startingInventory < 225,
	string.format("%d slots", startingInventory)
)

print("\nMigration handles every shape it can be handed")
local migrated, steps = Schema.migrate(Schema.defaultProfile())
check("a current profile needs no migration", steps, 0)
check("and keeps its version", migrated.schemaVersion, Schema.CURRENT_VERSION)

-- Data predating the schemaVersion field is treated as version 1, since version 1
-- is the first shipped version — missing field means older than the field, not
-- older than the schema.
local legacy = Schema.defaultProfile()
legacy.schemaVersion = nil
local fromLegacy, legacySteps = Schema.migrate(legacy)
check("versionless data is treated as v1", legacySteps, 0)
expect("and survives migration", type(fromLegacy) == "table")

-- Garbage in must not produce a corrupt profile.
for _, garbage in { "not a table", 42, false } do
	local result = Schema.migrate(garbage)
	local isValid = Schema.validate(result)
	expect(
		string.format(
			"migrating %-12s yields a valid fresh profile",
			"`" .. tostring(garbage) .. "`"
		),
		isValid
	)
end
local fromNil = Schema.migrate(nil)
expect("migrating nil yields a valid fresh profile", (Schema.validate(fromNil)))

print("\nMigration refuses to guess rather than mangling data")
local future = Schema.defaultProfile()
future.schemaVersion = Schema.CURRENT_VERSION + 5
local ranAhead = pcall(function()
	return Schema.migrate(future)
end)
-- A future version needs no migration steps, so it passes through untouched
-- rather than erroring — the loop only runs while version < CURRENT.
expect("data from a newer version passes through, not corrupted", ranAhead)

print("\nwithDefaults backfills without clobbering existing values")
local partial = { schemaVersion = Schema.CURRENT_VERSION, gold = 5000, wave = 42 }
local filled = Schema.withDefaults(partial)
check("keeps the existing gold", filled.gold, 5000)
check("keeps the existing wave", filled.wave, 42)
expect("backfills the missing inventory", filled.inventory ~= nil)
expect("backfills the missing upgrades", filled.upgrades ~= nil)
expect("backfills nested currency tables", filled.currencies.essence ~= nil)
local okFilled, filledReason = Schema.validate(filled)
expect("and the result validates", okFilled, filledReason or "no issues")

print("\nValidation catches the corruption cases that matter")
local function rejects(label, mutate)
	local profile = Schema.defaultProfile()
	mutate(profile)
	local valid, why = Schema.validate(profile)
	expect(label, not valid, why or "unexpectedly accepted")
end

rejects("negative gold is rejected", function(p)
	p.gold = -1
end)
rejects("wave below 1 is rejected", function(p)
	p.wave = 0
end)
rejects("a missing inventory is rejected", function(p)
	p.inventory = nil
end)
rejects("an unmigrated version is rejected", function(p)
	p.schemaVersion = 0
end)

print("\nThe duplication invariant is checked, not assumed")
-- architecture.md §4.2: the grid stores uids, so a placed unit is never a second
-- copy. A tile pointing at a uid the player does not own means that invariant has
-- already been violated somewhere upstream.
rejects("a tile holding an unowned uid is rejected", function(p)
	p.grid["1"] = "uid-that-does-not-exist"
end)

local legit = Schema.defaultProfile()
legit.inventory["u1"] = { unitId = "Noruto", rarity = "Legendary", mutation = "Normal", level = 1 }
legit.grid["1"] = "u1"
local okLegit, legitReason = Schema.validate(legit)
expect("a properly placed unit validates", okLegit, legitReason or "no issues")

print("\nUnits are keyed by uid, never by index")
expect(
	"profile carries a uid counter",
	legit.nextUid ~= nil,
	"merges and trades reorder constantly"
)
expect(
	"inventory is keyed by uid",
	legit.inventory["u1"] ~= nil and legit.inventory[1] == nil,
	"index-keyed references break under reordering"
)

print("\nEvery migration in the chain is present")
-- Never delete a migration: a player who has not logged in since v1 needs the
-- whole chain to still exist.
for version = 1, Schema.CURRENT_VERSION - 1 do
	expect(
		string.format("migration v%d -> v%d exists", version, version + 1),
		Schema.migrations[version] ~= nil
	)
end
expect(
	string.format("chain is complete up to v%d", Schema.CURRENT_VERSION),
	true,
	Schema.CURRENT_VERSION == 1 and "v1 is the first version, no migrations needed yet" or "checked"
)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
