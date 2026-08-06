--!nocheck
--[[
	Ground-truth regression tests for the shared config tables.

	These assert that our DERIVED formulas still reproduce the values actually
	observed in the source game, and that our OWN designed odds still satisfy the
	constraints the real game imposes on them.
	See docs/ground-truth/source-game-teardown.md.

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

local function expect(label, condition, detail)
	if condition then
		pass += 1
		print(string.format("  ok   %s%s", label, detail and (" — " .. detail) or ""))
	else
		fail += 1
		print(string.format("  FAIL %s%s", label, detail and (" — " .. detail) or ""))
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

print("\nCost curves pass through the one real price point we captured — EXACTLY")
--[[
	This used to accept anything within 0.4x to 2.5x, because the curves were
	hand-picked bases that merely landed near the anchor. They are now built by
	`anchoredCost`, which solves for the base so the curve goes THROUGH the observed
	price by construction. A single photographed price is still a single data point,
	but there is no longer any excuse for the curve to miss it.

	Rounding is the only slack: costAtLevel floors, so it can be up to 1 gold under.
]]
for _, u in pairs(U) do
	local observed = u.observedCost
	local modelled = u.costAtLevel(observed.level)
	expect(
		string.format("%-10s Lv%-2d", u.id, observed.level),
		math.abs(modelled - observed.cost) <= 1,
		string.format("modelled %d vs observed %d", modelled, observed.cost)
	)
end

print("\nThe FIRST purchase of every upgrade is an early-game purchase")
--[[
	The load-bearing test for this whole area. The 5th unit slot used to cost
	100,000 gold, which on the real income curve arrives around wave 121 — so a new
	player spent their entire first session with four units and nothing to spend
	gold on. An upgrade nobody can reach is not an upgrade.

	The bound is expressed in WAVES OF INCOME, not in gold, because gold alone says
	nothing about whether a price is reachable.
]]
for _, u in pairs(U) do
	local firstCost = u.costAtLevel(1)
	-- Income around wave 20, early but past the opening.
	local earlyIncome = Waves.goldPerWave(20)
	local wavesToAfford = firstCost / earlyIncome
	expect(
		string.format("%-10s first purchase", u.id),
		wavesToAfford < 400,
		string.format("%d gold = %.0f waves of wave-20 income", firstCost, wavesToAfford)
	)
end

-- And the last purchase must still be an endgame goal, or the ladder is pointless.
expect(
	"the final slot is still a serious investment",
	U.Slot.costAtLevel(U.Slot.maxLevel - 1) > 1000000,
	string.format("%d gold for the 12th slot", U.Slot.costAtLevel(U.Slot.maxLevel - 1))
)

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
-- [C] Eight bands: Common..God plus Limited, which the Index lists above God.
-- Still NO Uncommon — several public wikis claim one and the Index disproves it.
check("rarity bands (Common..God + Limited, NO Uncommon)", nRar, 8)
check("mutations (7 from Index tabs + Slayer)", nMut, 8)
check("traits (17 from the full dev FAQ)", nTra, 17)
check("mutation event cycle, seconds", Mutations.MUTATION_EVENT_INTERVAL, 900)

print("\nRarity ladder is well-formed")
local seenOrder = {}
for id, r in pairs(Rarities.Rarities) do
	assert(not seenOrder[r.order], "duplicate rarity order on " .. id)
	seenOrder[r.order] = true
	if Rarities.isRollable(id) then
		assert(r.essenceItem and #r.essenceItem > 0, "missing essenceItem on " .. id)
	end
end
ok("8 distinct orders, every rollable band has an essence item")

-- Limited has no Essence ON PURPOSE. Essence is what the Clone Machine consumes, so
-- an Essence for a shop-only band would be a way to duplicate event units — the
-- exact promise the band exists to keep.
expect(
	"Limited has no Essence, so it cannot be cloned",
	Rarities.Rarities.Limited.essenceItem == nil,
	"shop-only means shop-only"
)
expect("and Limited is not rollable", not Rarities.isRollable("Limited"))
expect("while God still is", Rarities.isRollable("God"))

-- [C] Resolved by two agreeing signals: pity counter length and Robux essence price.
local byOrder = {}
for id, r in pairs(Rarities.Rarities) do
	byOrder[r.order] = id
end
check("order 4 is Legendary", byOrder[4], "Legendary")
check("order 5 is Mythic", byOrder[5], "Mythic")
check("order 6 is Secret", byOrder[6], "Secret")
check("order 7 is God", byOrder[7], "God")

print("\nRoll odds: distribution is well-formed at every luck level")
for _, luck in { 1, 2, 5, 10, 13, 50, 500 } do
	local chances = Rarities.rollChances(luck)
	local total = 0
	for _, c in pairs(chances) do
		total += c
	end
	expect(
		string.format("luck x%-3d sums to 1.0", luck),
		math.abs(total - 1) < 1e-9,
		string.format("total %.10f, Common %.4f", total, chances.Common)
	)
	assert(
		chances.Common >= Rarities.MIN_COMMON_CHANCE - 1e-9,
		"Common floor breached at luck " .. luck
	)
end

print("\nRoll odds: rarer is always less likely across the designed tiers")
-- Checked from Rare upward. Common is deliberately excluded: it is the remainder
-- tier, so heavy luck is SUPPOSED to crowd it out — that is what luck is for.
-- Luck stacks in this game (x13 upgrade * x10 LUCK event * potions), so the ladder
-- is checked far beyond the upgrade cap, including absurd values.
for _, luck in { 1, 2, 13, 130, 500, 10000, 1e9 } do
	local chances = Rarities.rollChances(luck)
	for i = 2, 6 do
		local lo, hi = byOrder[i], byOrder[i + 1]
		assert(
			chances[lo] > chances[hi],
			string.format(
				"luck x%g: %s (%.8f) not more likely than %s (%.8f)",
				luck,
				lo,
				chances[lo],
				hi,
				chances[hi]
			)
		)
	end
end
ok("Rare > Epic > Legendary > Mythic > Secret > God, up to luck x1e9")

print("\nRoll odds: Common dominates unlucky play, and luck erodes it")
local commonAt1 = Rarities.rollChances(1).Common
local commonAt13 = Rarities.rollChances(13).Common
expect(
	"Common is the single most likely pull at luck x1",
	commonAt1 > 0.5,
	string.format("%.1f%%", commonAt1 * 100)
)
expect(
	"max luck roughly halves it",
	commonAt13 < commonAt1 * 0.6,
	string.format("%.1f%% -> %.1f%%", commonAt1 * 100, commonAt13 * 100)
)

print("\nRoll odds: God stays genuinely rare even at max luck")
-- [C] Owner: "god tier is really rare even with luck multiplier".
-- Max luck is x13 (Luck Upgrade Lv25).
local atMaxLuck = Rarities.rollChances(U.Luck.valueAtLevel(U.Luck.maxLevel))
local godOneIn = 1 / atMaxLuck.God
expect(
	"God at max luck is rarer than 1 in 10,000",
	godOneIn > 10000,
	string.format("1 in %d", math.floor(godOneIn))
)
local atBase = Rarities.rollChances(1)
expect(
	"max luck improves God by less than 3x",
	atMaxLuck.God / atBase.God < 3,
	string.format(
		"%.2fx (1 in %d -> 1 in %d)",
		atMaxLuck.God / atBase.God,
		math.floor(1 / atBase.God),
		math.floor(godOneIn)
	)
)
expect(
	"but luck is strongly felt in the mid tiers",
	atMaxLuck.Legendary / atBase.Legendary > 3,
	string.format("Legendary %.2fx", atMaxLuck.Legendary / atBase.Legendary)
)

print("\nPity: three counters only, and each cap sits above its natural rate")
-- [C] The Roll Machine shows exactly three. God deliberately has none.
local nPity = 0
for _ in pairs(Rarities.PityCaps) do
	nPity += 1
end
check("pity counters shown in-game", nPity, 3)
expect(
	"God has NO pity counter",
	Rarities.PityCaps.God == nil,
	"cannot be ground out deterministically"
)
for _, tier in { "Legendary", "Mythic", "Secret" } do
	local naturalOneIn = 1 / Rarities.BaseChance[tier]
	local cap = Rarities.PityCaps[tier]
	expect(
		string.format("%-10s pity is a safety net", tier),
		cap > naturalOneIn,
		string.format("natural 1 in %.0f, pity at %d", naturalOneIn, cap)
	)
end

print("\nMutation events follow the dev FAQ clock exactly")
-- [C] Slayer xx:00, Demon xx:15, Destroyer xx:30, Hollow xx:45
check("xx:00 -> Slayer", Mutations.activeEventMutation(0), "Slayer")
check("xx:15 -> Demon", Mutations.activeEventMutation(15), "Demon")
check("xx:30 -> Destroyer", Mutations.activeEventMutation(30), "Destroyer")
check("xx:45 -> Hollow", Mutations.activeEventMutation(45), "Hollow")
check("xx:07 still inside the xx:00 window", Mutations.activeEventMutation(7), "Slayer")
check("xx:59 still inside the xx:45 window", Mutations.activeEventMutation(59), "Hollow")

print("\nEvery minute of the hour lands in exactly one event window")
for minute = 0, 59 do
	assert(Mutations.activeEventMutation(minute), "no active mutation at minute " .. minute)
end
ok("all 60 minutes covered, no dead slots")

print("\nAstronaut is admin-only and never enters the roll pool")
check("Astronaut availability", Mutations.Mutations.Astronaut.availability, "admin")
for minute = 0, 59 do
	for _, id in Mutations.rollableAt(minute) do
		assert(id ~= "Astronaut", "Astronaut rollable at minute " .. minute)
	end
end
ok("checked all 60 minutes")

print("\nRoll pool is the 3 always-on mutations plus exactly one event mutation")
for _, minute in { 0, 15, 30, 45, 7, 22, 38, 51 } do
	local pool = Mutations.rollableAt(minute)
	assert(#pool == 4, string.format("minute %d gave %d mutations, want 4", minute, #pool))
end
ok("4 mutations rollable at any moment")

print("\nMutation power ladder rises with rarity WITHIN an availability class")
--[[
	This used to assert one global ladder: rarer mutation => stronger mutation, across
	the whole table. The measurements broke it, and the break is the point.

	Hollow is event-gated (rollable 15 minutes an hour) yet measures around x1.25 —
	WEAKER than Gold, which is available all day at x1.5. So scarcity in this game
	does not buy power. Event mutations are chased for scarcity, VFX and trade value.

	The invariant that survives is the one that was actually doing the work: inside a
	single availability class, rarer must still mean stronger. Otherwise there would
	be a strictly dominated mutation nobody would ever want.
]]
local byClass: { [string]: { any } } = { always = {}, event = {}, admin = {} }
for _, m in pairs(Mutations.Mutations) do
	table.insert(byClass[m.availability], m)
end

for class, group in pairs(byClass) do
	table.sort(group, function(a, b)
		return a.weight > b.weight
	end)
	for i = 1, #group - 1 do
		assert(
			group[i].damageMultiplier <= group[i + 1].damageMultiplier,
			string.format(
				"%s mutation %s is rarer than %s but weaker",
				class,
				group[i + 1].id,
				group[i].id
			)
		)
	end
end
expect("no dominated mutation inside always / event / admin", true, "3 always, 4 event, 1 admin")

check("Normal is the 1.0x baseline", Mutations.Mutations.Normal.damageMultiplier, 1.0)

-- The one genuinely global claim left: nothing outranks the admin-only mutation.
local strongest = Mutations.Mutations.Normal
for _, m in pairs(Mutations.Mutations) do
	if m.damageMultiplier > strongest.damageMultiplier then
		strongest = m
	end
end
expect("Astronaut tops the whole table", strongest.id == "Astronaut", "admin-only, never farmable")

-- And the correction itself, asserted so it cannot silently regress: an event
-- mutation is NOT automatically stronger than an always-available one.
expect(
	"Gold (always) beats Hollow (event) — scarcity does not buy power",
	Mutations.Mutations.Gold.damageMultiplier > Mutations.Mutations.Hollow.damageMultiplier,
	string.format(
		"x%.2f vs x%.2f",
		Mutations.Mutations.Gold.damageMultiplier,
		Mutations.Mutations.Hollow.damageMultiplier
	)
)

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
ok("all 17 traits sit on Rare/Epic/Legendary/Mythic/God, none on Common or Secret")

print("\nTrait lines match the dev FAQ verbatim")
local cursed = Traits.Traits.Cursed
check("Cursed damage        (+400%)", cursed.effect.damage, 4.00)
check("Cursed health        (+200%)", cursed.effect.health, 2.00)
check("Cursed crit damage   (+100%)", cursed.effect.critDamage, 1.00)
check("Cursed odds          (0.02%)", cursed.chance, 0.0002)
local viking = Traits.Traits.Viking
check("Viking health        (+750%)", viking.effect.health, 7.50)
check("Viking crit damage   (+150%)", viking.effect.critDamage, 1.50)
check("Ghost damage         (+100%)", Traits.Traits.Ghost.effect.damage, 1.00)
check("Ghost resurrects at 80% stats", Traits.Traits.Ghost.effect.resurrectAtFraction, 0.80)
check("Cloner summons 2 units instead of 1", Traits.Traits.Cloner.effect.summonCount, 2)

print("\nSPD sign convention is applied consistently")
-- [C] Resolved: the UI's "-25% SPD" is cooldown, i.e. FASTER. The FAQ's
-- "25% Faster Attacks" is the same effect. Juggernaut is the only real downside.
check("Viking attacks FASTER, not slower", viking.effect.attackSpeed, 0.25)
check("Cursed attacks faster", cursed.effect.attackSpeed, 0.25)
check(
	"Juggernaut is the ONE trait with a downside",
	Traits.Traits.Juggernaut.effect.attackSpeed,
	-0.10
)
local negatives = 0
for _, t in pairs(Traits.Traits) do
	if t.effect.attackSpeed and t.effect.attackSpeed < 0 then
		negatives += 1
	end
end
check("exactly one trait slows the unit down", negatives, 1)

print("\nBoth God traits are present and are the strongest in the table")
local godTraits = {}
for id, t in pairs(Traits.Traits) do
	if t.tier == "God" then
		table.insert(godTraits, id)
	end
end
check("God traits", #godTraits, 2)
for _, t in pairs(Traits.Traits) do
	if t.tier ~= "God" then
		assert(
			(t.effect.damage or 0) <= math.max(cursed.effect.damage, viking.effect.damage),
			"non-God trait " .. t.id .. " out-damages both God traits"
		)
	end
end
ok("Cursed + Viking, and no lesser trait beats them on damage")

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
