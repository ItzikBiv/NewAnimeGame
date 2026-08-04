--!nocheck
--[[
	Wave simulation — story 1.5.

	Closes the loop: this is the half that pays for the next roll. The checks that
	matter most are the ones about MONEY, because a wave that can pay out twice, or
	pay out without being cleared, is an economy bug that only shows up after it has
	already ruined the leaderboard.

	Expects globals: Rarities, Mutations, Traits, Upgrades, Waves, Power, Schema,
	Roll, Inventory, Merge, Grid, Wave.
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

-- A profile with `n` units of the given rarity fielded on the grid.
local function squadOf(n, rarity, mutation, level)
	local profile = Schema.defaultProfile()
	profile.upgrades.Slot = 9 -- 12 slots, so tests are not bounded by placement
	for i = 1, n do
		local _, uid = Inventory.grant(profile, {
			unitId = "Test" .. i,
			rarity = rarity or "Common",
			mutation = mutation or "Normal",
			level = level or 1,
		})
		Grid.place(profile, uid, i)
	end
	return profile
end

print("The squad is built from the GRID, not the inventory")
local benched = Schema.defaultProfile()
local _, benchedUid = Inventory.grant(benched, {
	unitId = "Benched",
	rarity = "God",
	mutation = "Destroyer",
	level = 5,
})
check("a unit in the bag contributes nothing", #Wave.buildSquad(benched), 0)
Grid.place(benched, benchedUid, 1)
check("until it is placed", #Wave.buildSquad(benched), 1)
expect("placement has to matter", true, "an unplaced God is worth zero")

print("\nEnemies come from the wave config")
local enemies = Wave.buildEnemies(9)
check("count matches Waves", #enemies, Waves.enemyCount(9))
expect(
	"HP matches Waves",
	math.abs(enemies[1].maxHp - Waves.enemyHP(9)) < 1e-9,
	string.format("%.1f HP", enemies[1].maxHp)
)
local boss = Wave.buildEnemies(10)
check("a boss wave is a single enemy", #boss, 1)
expect(
	"with 8x the health",
	math.abs(boss[1].maxHp - Waves.baseEnemyHP(10) * Waves.BOSS_HP_MULTIPLIER) < 1e-9,
	string.format("%.0f HP", boss[1].maxHp)
)

print("\nA starting squad clears the early waves")
for _, w in { 1, 5, 9 } do
	local state = Wave.simulate(squadOf(4, "Common"), w)
	expect(
		string.format("wave %-2d cleared", w),
		state.outcome == "cleared",
		string.format("%s in %.1fs, %d gold", state.outcome, state.elapsed, state.goldEarned)
	)
end

print("\nAnd is overwhelmed deep in the run")
local deep = Wave.simulate(squadOf(4, "Common"), 60, 0.1, 300)
expect(
	"wave 60 is not cleared by four Commons",
	deep.outcome ~= "cleared",
	string.format("%s after %.0fs", deep.outcome, deep.elapsed)
)

print("\nProgression answers that wall")
local strong = Wave.simulate(squadOf(4, "Legendary", "Destroyer", 3), 60, 0.1, 300)
expect(
	"a mutated, merged Legendary squad clears wave 60",
	strong.outcome == "cleared",
	string.format("%s in %.1fs", strong.outcome, strong.elapsed)
)

print("\nAn empty grid fails rather than hanging or winning")
local empty = Wave.simulate(Schema.defaultProfile(), 1)
check("outcome", empty.outcome, "failed")
check("no gold from a wave you did not fight", empty.goldEarned, 0)

print("\nGold is paid once per kill, never twice")
local goldProfile = squadOf(4, "Legendary")
local cleared = Wave.simulate(goldProfile, 5)
check("wave 5 cleared", cleared.outcome, "cleared")
local expectedGold = math.floor(Waves.goldPerKill(5) * cleared.goldMultiplier) * Waves.enemyCount(5)
check("gold equals per-kill x enemy count", cleared.goldEarned, expectedGold)

-- Ticking a finished wave must not keep paying.
local before = cleared.goldEarned
for _ = 1, 50 do
	Wave.tick(cleared, 0.1)
end
check("ticking a cleared wave pays nothing more", cleared.goldEarned, before)
check("and the outcome is unchanged", cleared.outcome, "cleared")

print("\nThe Gold Upgrade multiplier is captured at wave start")
local upgraded = squadOf(4, "Legendary")
upgraded.upgrades.Gold = 25
local richState = Wave.begin(upgraded, 5)
expect(
	"multiplier read from the profile",
	math.abs(richState.goldMultiplier - 3.4) < 1e-9,
	string.format("x%.1f at Lv25", richState.goldMultiplier)
)
-- Changing the upgrade mid-wave must not retroactively repay earlier kills.
local capturedMultiplier = richState.goldMultiplier
upgraded.upgrades.Gold = 1
expect(
	"mid-wave change does not alter it",
	richState.goldMultiplier == capturedMultiplier,
	string.format("still x%.1f", richState.goldMultiplier)
)

print("\nA cleared wave banks gold and advances the counter")
local commitProfile = squadOf(4, "Legendary")
local goldBefore = commitProfile.gold
local waveBefore = commitProfile.wave
local run = Wave.simulate(commitProfile, waveBefore)
local committed, commitError = Wave.commit(commitProfile, run)
expect("commit succeeded", committed, commitError or "")
check("wave advanced by one", commitProfile.wave, waveBefore + 1)
check("gold banked", commitProfile.gold, goldBefore + run.goldEarned)
expect(
	"highest-wave stat updated",
	commitProfile.stats.highestWave == commitProfile.wave,
	string.format("wave %d", commitProfile.stats.highestWave)
)
expect("profile still validates", (Schema.validate(commitProfile)))

print("\nA FAILED wave pays nothing and advances nothing")
local lost = squadOf(1, "Common")
local goldAtLoss = lost.gold
local waveAtLoss = lost.wave
local lostRun = Wave.simulate(lost, 80, 0.1, 120)
expect("the wave was not cleared", lostRun.outcome ~= "cleared", lostRun.outcome)
local paidOut, payError = Wave.commit(lost, lostRun)
expect("commit is refused", not paidOut, payError)
check("gold unchanged", lost.gold, goldAtLoss)
check("wave unchanged", lost.wave, waveAtLoss)

print("\nNeither side gets a free hit from resolution order")
-- Both sides deal damage from the state at the start of the step. A squad and an
-- enemy that would kill each other in the same tick must BOTH die.
local mutual = Schema.defaultProfile()
local _, mUid =
	Inventory.grant(mutual, { unitId = "M", rarity = "Common", mutation = "Normal", level = 1 })
Grid.place(mutual, mUid, 1)
local state = Wave.begin(mutual, 1)
state.squad[1].hp = 1
state.enemies[1].hp = 1
Wave.tick(state, 1.0)
expect(
	"both combatants died in the same tick",
	state.squad[1].hp == 0 and state.enemies[1].hp == 0,
	"simultaneous resolution, not sequential"
)

print("\nCombat is deterministic")
local a = Wave.simulate(squadOf(4, "Epic"), 12)
local b = Wave.simulate(squadOf(4, "Epic"), 12)
check("same outcome", a.outcome, b.outcome)
check("same gold", a.goldEarned, b.goldEarned)
expect("same duration", math.abs(a.elapsed - b.elapsed) < 1e-9, string.format("%.2fs", a.elapsed))

print("\nHP never goes negative in the reported state")
local clean = Wave.simulate(squadOf(4, "Legendary"), 20)
local negatives = 0
for _, c in clean.enemies do
	if c.hp < 0 then
		negatives += 1
	end
end
for _, c in clean.squad do
	if c.hp < 0 then
		negatives += 1
	end
end
check("no negative HP anywhere", negatives, 0)

print("\nThe simulation always terminates")
-- A squad that cannot out-damage the wave must hit the bound and stop, not spin.
local stuck = Wave.simulate(squadOf(1, "Common"), 200, 0.5, 30)
expect(
	"a hopeless wave stops at the limit",
	stuck.elapsed <= 30 + 0.5,
	string.format("%s after %.1fs", stuck.outcome, stuck.elapsed)
)

print("\nEnd to end: roll -> place -> fight -> bank -> afford the next roll")
local loop = Schema.defaultProfile()
local rng = (function()
	local s = 777
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end)()

local pity = Roll.newPity()
for i = 1, 4 do
	local result = Roll.roll(1, pity, 0, rng)
	pity = result.pity
	local _, uid = Inventory.grant(loop, {
		unitId = "U" .. i,
		rarity = result.rarity,
		mutation = result.mutation,
		level = 1,
	})
	Grid.place(loop, uid, i)
end
check("four units fielded", #Wave.buildSquad(loop), 4)

local wavesCleared = 0
for _ = 1, 10 do
	local run2 = Wave.simulate(loop, loop.wave)
	if run2.outcome ~= "cleared" then
		break
	end
	Wave.commit(loop, run2)
	wavesCleared += 1
end
expect("cleared several waves in a row", wavesCleared >= 5, string.format("%d waves", wavesCleared))
expect("and banked gold doing it", loop.gold > 0, string.format("%d gold", loop.gold))
expect("profile survives the full loop", (Schema.validate(loop)))

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
