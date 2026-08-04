--!nocheck
--[[
	Ground-truth regression tests for the shared config tables.

	These assert that our DERIVED formulas still reproduce the values actually
	observed in the source game (docs/ground-truth/source-game-teardown.md §6).
	If someone "tidies" a formula and breaks parity with the real game, this fails.

	Run with:  ./scripts/run-tests.sh
	The runner inlines the config modules and executes them under the plain Luau
	CLI, so this needs no Roblox runtime and no Studio.

	Expects globals: Rarities, Mutations, Traits, Upgrades (supplied by the runner).
]]

local pass, fail = 0, 0

local function check(label, got, want)
	if type(got) == "number" and type(want) == "number" and math.abs(got - want) < 1e-9 then
		pass += 1
		print(string.format("  ok   %-52s = %s", label, tostring(got)))
	elseif got == want then
		pass += 1
		print(string.format("  ok   %-52s = %s", label, tostring(got)))
	else
		fail += 1
		print(string.format("  FAIL %-52s = %s (want %s)", label, tostring(got), tostring(want)))
	end
end

local function ok(label)
	pass += 1
	print(string.format("  ok   %s", label))
end

print("Upgrades: derived formulas vs values observed in the source game")
local U = Upgrades.Upgrades
check("Gold      Lv18 -> x2.7  [C observed]", U.Gold.valueAtLevel(18), 2.7)
check("Gold      Lv25 -> x3.4  [C MAX]", U.Gold.valueAtLevel(25), 3.4)
check("Luck      Lv20 -> x10.5 [C observed]", U.Luck.valueAtLevel(20), 10.5)
check("Luck      Lv25 -> x13   [C MAX]", U.Luck.valueAtLevel(25), 13)
check("Slot      Lv1  -> 4     [C start]", U.Slot.valueAtLevel(1), 4)
check("Slot      Lv9  -> 12    [C MAX]", U.Slot.valueAtLevel(9), 12)
check("Inventory Lv3  -> 125   [C observed]", U.Inventory.valueAtLevel(3), 125)
check("Inventory Lv7  -> 225   [C MAX]", U.Inventory.valueAtLevel(7), 225)
check("Enemy slots -> 16       [C observed]", Upgrades.ENEMY_SLOTS, 16)

print("\nmaxLevel matches the level at which MAX was observed in-game")
check("Gold.maxLevel", U.Gold.maxLevel, 25)
check("Luck.maxLevel", U.Luck.maxLevel, 25)
check("Slot.maxLevel", U.Slot.maxLevel, 9)
check("Inventory.maxLevel", U.Inventory.maxLevel, 7)

print("\nCost curves pass through the one real price point we captured")
for _, u in pairs(U) do
	local observed = u.observedCost
	local modelled = u.costAtLevel(observed.level)
	-- Loose bound: we only have a single point per upgrade, so this guards against
	-- an order-of-magnitude mistake, not against a wrong curve shape. [?]
	local ratio = modelled / observed.cost
	if ratio > 0.4 and ratio < 2.5 then
		pass += 1
		print(
			string.format(
				"  ok   %-14s Lv%-2d modelled %d vs observed %d (%.2fx)",
				u.id,
				observed.level,
				modelled,
				observed.cost,
				ratio
			)
		)
	else
		fail += 1
		print(
			string.format(
				"  FAIL %-14s Lv%-2d modelled %d vs observed %d (%.2fx)",
				u.id,
				observed.level,
				modelled,
				observed.cost,
				ratio
			)
		)
	end
end

print("\nTable integrity")
local nRar, nMut, nTra = 0, 0, 0
for _ in pairs(Rarities.Rarities) do
	nRar += 1
end
for _ in pairs(Mutations.Mutations) do
	nMut += 1
end
for _ in pairs(Traits.Traits) do
	nTra += 1
end
check("rarity tiers (Common..God, NO Uncommon)", nRar, 7)
check("mutations confirmed from Index tabs", nMut, 7)
check("traits (15 from dev FAQ + Viking)", nTra, 16)
check("mutation event interval, seconds", Mutations.MUTATION_EVENT_INTERVAL, 900)

print("\nRarity table is well-formed")
local seenOrder = {}
for id, r in pairs(Rarities.Rarities) do
	assert(not seenOrder[r.order], "duplicate rarity order on " .. id)
	seenOrder[r.order] = true
	assert(r.essenceItem and #r.essenceItem > 0, "missing essenceItem on " .. id)
	assert(Rarities.BaseWeights[id], "missing base roll weight for " .. id)
end
ok("7 distinct orders, all essence items and roll weights present")

print("\nRoll weights decrease monotonically as rarity increases")
local byOrder = {}
for id, r in pairs(Rarities.Rarities) do
	byOrder[r.order] = id
end
for i = 1, 6 do
	local lo, hi = byOrder[i], byOrder[i + 1]
	assert(
		Rarities.BaseWeights[lo] > Rarities.BaseWeights[hi],
		string.format(
			"weight not decreasing: %s (%s) <= %s (%s)",
			lo,
			tostring(Rarities.BaseWeights[lo]),
			hi,
			tostring(Rarities.BaseWeights[hi])
		)
	)
end
ok("Common > Rare > Epic > Legendary > Mythic > Secret > God")

print("\nPity caps exist for the three counters shown on the Roll Machine")
for _, tier in { "Legendary", "Mythic", "God" } do
	assert(Rarities.PityCaps[tier], "missing pity cap: " .. tier)
end
ok("Legendary / Mythic / God")

print("\nTrait tiers are the trait ladder, NOT the unit rarity ladder")
local validTiers = { Rare = true, Epic = true, Legendary = true, Mythic = true, God = true }
for id, t in pairs(Traits.Traits) do
	assert(validTiers[t.tier], string.format("trait %s has invalid tier %s", id, tostring(t.tier)))
	assert(Traits.TierWeights[t.tier], "missing tier weight for " .. t.tier)
end
-- The trait ladder deliberately omits Common and Secret.
assert(
	not validTiers.Common and not validTiers.Secret,
	"trait ladder must not include Common/Secret"
)
ok("all 16 traits sit on Rare/Epic/Legendary/God/Mythic, none on Common or Secret")

print("\nSpot-check the strongest trait lines against the dev FAQ verbatim")
local cursed = Traits.Traits.Cursed
check("Cursed damage    (+400%)", cursed.effect.damage, 4.00)
check("Cursed health    (+200%)", cursed.effect.health, 2.00)
check("Cursed crit dmg  (+100%)", cursed.effect.critDamage, 1.00)
check("Cursed odds      (0.02%)", cursed.chance, 0.0002)
check(
	"Juggernaut is the one trait with a downside",
	Traits.Traits.Juggernaut.effect.attackSpeed,
	-0.10
)
check("Cloner summons 2 units instead of 1", Traits.Traits.Cloner.effect.summonCount, 2)

print("\nMutation ladder rises with rarity of the mutation")
local muts = {}
for _, m in pairs(Mutations.Mutations) do
	table.insert(muts, m)
end
table.sort(muts, function(a, b)
	return a.weight > b.weight
end)
for i = 1, #muts - 1 do
	assert(
		muts[i].damageMultiplier <= muts[i + 1].damageMultiplier,
		string.format("mutation %s is rarer than %s but weaker", muts[i + 1].id, muts[i].id)
	)
end
check("Normal is the 1.0x baseline", Mutations.Mutations.Normal.damageMultiplier, 1.0)
ok("rarer mutations are never weaker than commoner ones")

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
