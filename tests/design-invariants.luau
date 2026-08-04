--!nocheck
--[[
	Design-invariant tests for the wave and power models.

	Where config-invariants.luau guards facts about the SOURCE game, this file
	guards the DESIGN PILLARS from docs/planning/gdd.md. These numbers are ours, so
	nothing external pins them — which is exactly why they need tests. A future
	rebalance that quietly kills the two-axis pull should fail CI, not ship.

	Expects globals: Rarities, Mutations, Traits, Upgrades, Waves, Power.
]]

local pass, fail = 0, 0

local function check(label, got, want, tolerance)
	local tol = tolerance or 1e-9
	if type(got) == "number" and type(want) == "number" and math.abs(got - want) <= tol then
		pass += 1
		print(string.format("  ok   %-54s = %s", label, tostring(got)))
	elseif got == want then
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

print("PILLAR 1 — a mutation must be able to buy at least one rarity tier")
-- If this fails, rarity dominates and the two-axis pull has collapsed into an
-- ordinary rarity ladder. This is the single most important test in the project.
expect(
	"Destroyer Common out-powers a clean Epic",
	Power.power("Common", "Destroyer", 1) > Power.RarityPower.Epic,
	string.format("%.2f vs %.2f", Power.power("Common", "Destroyer", 1), Power.RarityPower.Epic)
)
expect(
	"Diamond Rare out-powers a clean Epic",
	Power.power("Rare", "Diamond", 1) > Power.RarityPower.Epic,
	string.format("%.2f vs %.2f", Power.power("Rare", "Diamond", 1), Power.RarityPower.Epic)
)
for _, rarity in { "Common", "Rare", "Epic", "Legendary" } do
	local gained = Power.tiersGainedByMutation(rarity, "Destroyer")
	expect(
		string.format("Destroyer %-10s gains a tier", rarity),
		gained >= 1,
		string.format("%d tier(s)", gained)
	)
end

print("\nPILLAR 1 — but mutations must NOT trivialise the ladder")
-- A mutation buying 3+ tiers would make rarity meaningless in the other direction.
for _, rarity in { "Common", "Rare", "Epic", "Legendary", "Mythic" } do
	for mutationId in pairs(Mutations.Mutations) do
		local gained = Power.tiersGainedByMutation(rarity, mutationId)
		assert(
			gained <= 2,
			string.format(
				"%s %s jumps %d tiers — mutations are too strong",
				mutationId,
				rarity,
				gained
			)
		)
	end
end
expect(
	"no mutation jumps more than 2 tiers on any rarity",
	true,
	"checked 8 mutations x 5 rarities"
)
expect(
	"a clean Legendary still beats a Gold Epic",
	Power.RarityPower.Legendary > Power.power("Epic", "Gold", 1),
	string.format("%.2f vs %.2f", Power.RarityPower.Legendary, Power.power("Epic", "Gold", 1))
)

print("\nMerging trades width for depth — it must not be strictly correct")
-- levelMult must stay BELOW the 2x copy cost, or merging is always right and the
-- decision evaporates.
check("level multiplier per merge", Power.LEVEL_MULTIPLIER, 1.8)
expect(
	"merge gain is below the 2x copy cost",
	Power.LEVEL_MULTIPLIER < 2.0,
	string.format("%.2fx power for 2x copies", Power.LEVEL_MULTIPLIER)
)
check("Lv1 is the 1.0x baseline", Power.levelMultiplier(1), 1.0)
check("Lv4 costs 8 copies, gives", Power.levelMultiplier(4), 1.8 ^ 3, 1e-9)
expect(
	"two Lv1 units out-power one Lv2 of the same unit",
	2 * Power.levelMultiplier(1) > Power.levelMultiplier(2),
	string.format("2.00 vs %.2f", Power.levelMultiplier(2))
)

print("\nRarity power rises monotonically with rarity")
local byOrder = {}
for id, r in pairs(Rarities.Rarities) do
	byOrder[r.order] = id
end
for i = 1, 6 do
	local lo, hi = byOrder[i], byOrder[i + 1]
	assert(
		Power.RarityPower[lo] < Power.RarityPower[hi],
		string.format(
			"%s (%.1f) not weaker than %s (%.1f)",
			lo,
			Power.RarityPower[lo],
			hi,
			Power.RarityPower[hi]
		)
	)
end
check("Common is the 1.0x baseline", Power.RarityPower.Common, 1.0)
expect("Common < Rare < Epic < Legendary < Mythic < Secret < God", true)

print("\nDefense has diminishing returns and can never reach immunity")
check("0 defense is no mitigation", Power.damageAfterDefense(100, 0), 100)
check("defense 100 halves damage", Power.damageAfterDefense(100, 100), 50)
check("defense 300 quarters damage", Power.damageAfterDefense(100, 300), 25)
expect(
	"absurd defense still lets damage through",
	Power.damageAfterDefense(100, 1e9) > 0,
	string.format("%.8f at defense 1e9", Power.damageAfterDefense(100, 1e9))
)
local prev = math.huge
for _, d in { 0, 50, 100, 200, 400, 800 } do
	local dmg = Power.damageAfterDefense(100, d)
	assert(dmg < prev, "defense must always reduce damage")
	prev = dmg
end
expect("damage strictly decreases as defense rises", true)

print("\nAttack speed: positive bonus means faster, per the resolved SPD convention")
check("no bonus leaves the period alone", Power.attackPeriod(1.0, 0), 1.0)
expect(
	"Cursed (+25%) shortens the attack period",
	Power.attackPeriod(1.0, Traits.Traits.Cursed.effect.attackSpeed) < 1.0,
	string.format("%.4fs", Power.attackPeriod(1.0, Traits.Traits.Cursed.effect.attackSpeed))
)
expect(
	"Juggernaut (-10%) lengthens it — the one real downside",
	Power.attackPeriod(1.0, Traits.Traits.Juggernaut.effect.attackSpeed) > 1.0,
	string.format("%.4fs", Power.attackPeriod(1.0, Traits.Traits.Juggernaut.effect.attackSpeed))
)

print("\nWave scaling reproduces the one confirmed anchor")
-- [C] wave 174 -> enemy HP 481,324, read off a screenshot.
local OBSERVED_WAVE, OBSERVED_HP = 174, 481324
local modelled = Waves.baseEnemyHP(OBSERVED_WAVE)
local errorPct = math.abs(modelled / OBSERVED_HP - 1) * 100
expect(
	"wave 174 HP within 5% of observed",
	errorPct < 5,
	string.format("modelled %.0f vs observed %d (%.1f%% off)", modelled, OBSERVED_HP, errorPct)
)
check("wave 1 is a round 100 HP", Waves.baseEnemyHP(1), 100)
check("growth rate", Waves.HP_GROWTH_PER_WAVE, 1.05)

print("\nEnemy HP grows strictly, forever")
local prevHP = 0
for _, w in { 1, 2, 10, 25, 50, 100, 174, 500, 1000 } do
	local hp = Waves.baseEnemyHP(w)
	assert(hp > prevHP, "HP must rise with wave number")
	prevHP = hp
end
expect(
	"HP strictly increasing through wave 1000",
	true,
	string.format("wave 1000 = %.3g HP", Waves.baseEnemyHP(1000))
)

print("\nEnemy count stays in the observed 3-10 band, not scaling with wave")
-- [C] Observed 3-9 from wave 9 to wave 174 — difficulty comes from HP, not swarm size.
for _, w in { 1, 9, 13, 16, 25, 29, 33, 174, 1000 } do
	local n = Waves.enemyCount(w)
	assert(n >= 1 and n <= Waves.MAX_ENEMIES, string.format("wave %d gave %d enemies", w, n))
end
expect(
	"count never exceeds the 16 enemy tiles",
	Waves.MAX_ENEMIES <= Upgrades.ENEMY_SLOTS,
	string.format("max %d vs %d tiles", Waves.MAX_ENEMIES, Upgrades.ENEMY_SLOTS)
)
check("non-boss wave 9 count", Waves.enemyCount(9), 3)
check("non-boss wave 174 count", Waves.enemyCount(174), 10)

print("\nBoss waves break the cadence [OURS — flagged for owner review]")
expect("wave 10 is a boss wave", Waves.isBossWave(10))
expect("wave 174 is not", not Waves.isBossWave(174))
check("a boss wave spawns one enemy", Waves.enemyCount(10), 1)
expect(
	"boss HP is 8x the wave baseline",
	Waves.enemyHP(10) == Waves.baseEnemyHP(10) * Waves.BOSS_HP_MULTIPLIER,
	string.format("%.0f HP", Waves.enemyHP(10))
)
expect(
	"a boss wave is worth more than the wave before it",
	Waves.goldPerWave(10) > Waves.goldPerWave(9),
	string.format("%d vs %d gold", Waves.goldPerWave(10), Waves.goldPerWave(9))
)

print("\nGold tracks difficulty, and the max upgrade matches the observed bank")
for _, w in { 1, 10, 50, 174 } do
	assert(Waves.goldPerKill(w) >= 1, "every kill must pay at least 1 gold")
end
expect("every kill pays at least 1 gold, from wave 1", true)
local maxGoldMult = Upgrades.Upgrades.Gold.valueAtLevel(Upgrades.Upgrades.Gold.maxLevel)
local lateGame = Waves.goldPerKill(174) * maxGoldMult
expect(
	"late-game gold/kill is consistent with the observed 50.8M bank",
	lateGame > 1000 and lateGame < 1e6,
	string.format("%.0f per kill at wave 174 with x%.1f upgrade", lateGame, maxGoldMult)
)
local prevGold = 0
for _, w in { 1, 5, 25, 100, 174 } do
	local g = Waves.goldPerKill(w)
	assert(g > prevGold, "gold per kill must rise with wave")
	prevGold = g
end
expect("gold per kill rises with wave", true)

print("\nTime-to-clear: the starting squad's real experience")
-- The tuning target from the GDD is that a fresh player reaches roughly wave 15 in
-- their first session. Measured in SECONDS, not in a ratio of mismatched units:
-- 4 starting slots, all Common / Normal / Lv1.
local startingSlots = Upgrades.Upgrades.Slot.valueAtLevel(1)
local startingDps = startingSlots * Power.dps("Common", "Normal", 1)
check("a fresh player has 4 slots", startingSlots, 4)
expect(
	"starting squad DPS",
	startingDps > 0,
	string.format("%.0f dps (%d x Common Lv1)", startingDps, startingSlots)
)

for _, w in { 1, 5, 9, 15 } do
	local secs = Power.timeToClear(Waves.waveTotalHP(w), startingDps)
	expect(
		string.format("wave %-2d clears in a sane time unaided", w),
		secs > 1 and secs < 120,
		string.format("%.1fs", secs)
	)
end

-- Past the target the unaided squad should visibly struggle — that is the pressure
-- that makes rolling and merging feel necessary rather than optional. Rather than
-- assert an arbitrary wave, find where the stall ACTUALLY lands and check it sits
-- in a sensible band. This measures the design property instead of a guess.
local STALL_SECONDS = 120
local stallWave
for w = 1, 500 do
	if Power.timeToClear(Waves.waveTotalHP(w), startingDps) > STALL_SECONDS then
		stallWave = w
		break
	end
end
expect(
	"an unaided starting squad stalls somewhere in waves 20-60",
	stallWave and stallWave >= 20 and stallWave <= 60,
	string.format("stalls at wave %d (first wave over %ds)", stallWave or -1, STALL_SECONDS)
)
expect(
	"the stall sits comfortably past the wave-15 first-session target",
	stallWave and stallWave > 15,
	string.format("target 15, stall %d", stallWave or -1)
)

-- Boss waves must be a real spike, not a rounding error.
local bossSecs = Power.timeToClear(Waves.waveTotalHP(10), startingDps)
local beforeSecs = Power.timeToClear(Waves.waveTotalHP(9), startingDps)
expect(
	"a boss wave takes markedly longer than the wave before it",
	bossSecs > beforeSecs * 2,
	string.format("wave 9 %.0fs -> wave 10 boss %.0fs", beforeSecs, bossSecs)
)

-- And progression must actually answer that wall. One Legendary beats four Commons.
local oneLegendary = Power.dps("Legendary", "Normal", 1)
expect(
	"a single Legendary out-damages the whole starting squad",
	oneLegendary > startingDps,
	string.format("%.0f vs %.0f dps", oneLegendary, startingDps)
)
local mutatedCommon = Power.dps("Common", "Destroyer", 1)
expect(
	"a Destroyer Common is a genuine upgrade over a clean Common",
	mutatedCommon > Power.dps("Epic", "Normal", 1),
	string.format("%.0f vs %.0f dps (clean Epic)", mutatedCommon, Power.dps("Epic", "Normal", 1))
)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
