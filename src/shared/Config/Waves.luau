--!strict
--[[
	Wave scaling — enemy HP, count and gold reward as functions of wave number.

	Design: docs/planning/gdd.md §5
	Ground truth: docs/ground-truth/source-game-teardown.md

	[C] The ONLY hard anchor is a single screenshot: wave 174, enemy HP 481,324.

	[D] Solving `base * growth^(wave-1)` against that anchor:

	        growth 1.04  -> base 544
	        growth 1.045 -> base 237
	        growth 1.05  -> base 103.9   <- essentially a round 100
	        growth 1.055 -> base 46
	        growth 1.06  -> base 20

	    A 5% growth rate implies a wave-1 HP of 103.9. One data point landing that
	    close to a round number, 173 waves out, is strong evidence 5% is the real
	    curve — so that is what we use. It reproduces the anchor to within 3.8%,
	    which is as much precision as a single point can honestly support.

	[OURS] Everything else here is designed, not observed.
]]

-- [OURS] Fitted to the [C] anchor. See header.
local BASE_ENEMY_HP = 100
local HP_GROWTH_PER_WAVE = 1.05

-- [C] Observed enemy counts across 9 screenshots, wave 9 through wave 174:
--     w9->4  w13->3  w16->5  w25->6  w26->7  w29->9  w33->7  w34->7  w174->8
-- Count does NOT scale with wave — it sits in a 3-9 band the whole way. Difficulty
-- comes from HP, not swarm size, which fits an arena capped at 16 enemy tiles.
local MIN_ENEMIES = 3
local MAX_ENEMIES = 10
local WAVES_PER_EXTRA_ENEMY = 20

-- [OURS] Gold is proportional to enemy HP so the economy self-balances against the
-- difficulty curve instead of needing a second independently-tuned exponent.
local GOLD_PER_HP = 0.02

--[[
	[OURS] Boss waves are our addition, NOT observed in the source game's wave
	rotation. The Admin Abuse event has a "boss spawn", so bosses exist as a concept
	there, but nothing confirms them on the normal ramp.

	Rationale: an endless 5%-per-wave climb with no rhythm is monotonous. Every 10th
	wave becomes a single high-HP, high-reward enemy to break the cadence.

	Flagged for the owner in gdd.md §8. Easy to disable — set BOSS_WAVE_INTERVAL to 0.
]]
local BOSS_WAVE_INTERVAL = 10
local BOSS_HP_MULTIPLIER = 8
local BOSS_GOLD_MULTIPLIER = 5

--[[
	[C] Checkpoints are permanent milestones — clearing one means a later loss
	sends you back here rather than to wave 1. [OURS] every 10th wave, aligning
	them with boss waves so the boss reads as "the thing that banks your progress".
]]
local CHECKPOINT_INTERVAL = 10

local function isCheckpointWave(wave: number): boolean
	return wave % CHECKPOINT_INTERVAL == 0
end

-- The highest checkpoint at or below `wave`. Wave 1 is always a valid restart.
local function checkpointFor(wave: number): number
	if wave < CHECKPOINT_INTERVAL then
		return 1
	end
	return wave - (wave % CHECKPOINT_INTERVAL)
end

local function isBossWave(wave: number): boolean
	return BOSS_WAVE_INTERVAL > 0 and wave % BOSS_WAVE_INTERVAL == 0
end

-- Base HP of a single enemy on this wave, before the boss multiplier.
local function baseEnemyHP(wave: number): number
	return BASE_ENEMY_HP * HP_GROWTH_PER_WAVE ^ (wave - 1)
end

-- Actual HP of each enemy on this wave.
local function enemyHP(wave: number): number
	local hp = baseEnemyHP(wave)
	if isBossWave(wave) then
		hp *= BOSS_HP_MULTIPLIER
	end
	return hp
end

-- How many enemies spawn on this wave. Boss waves are a single enemy.
local function enemyCount(wave: number): number
	if isBossWave(wave) then
		return 1
	end
	local count = MIN_ENEMIES + math.floor(wave / WAVES_PER_EXTRA_ENEMY)
	return math.clamp(count, MIN_ENEMIES, MAX_ENEMIES)
end

--[[
	Gold awarded per enemy killed, before the player's Gold Upgrade multiplier.
	Callers apply that separately so the upgrade stays a single source of truth.
]]
local function goldPerKill(wave: number): number
	local gold = math.ceil(baseEnemyHP(wave) * GOLD_PER_HP)
	if isBossWave(wave) then
		gold *= BOSS_GOLD_MULTIPLIER
	end
	return gold
end

-- Total gold from clearing the wave, before the Gold Upgrade multiplier.
local function goldPerWave(wave: number): number
	return goldPerKill(wave) * enemyCount(wave)
end

-- Total effective HP the squad must chew through to clear the wave.
local function waveTotalHP(wave: number): number
	return enemyHP(wave) * enemyCount(wave)
end

--[[
	[OURS] Damage per second dealt by a single enemy.

	Nothing in the screenshots or the FAQ gives enemy damage, but it cannot be zero:
	units visibly have health bars, and the Ghost trait revives a unit "on death",
	so units demonstrably die. Without incoming damage the Defense stat and every
	tank unit would be decoration.

	Tied to enemy HP by the same ratio as gold, so one curve drives difficulty,
	reward and threat together rather than three independently-tuned exponents.
]]
local ENEMY_DAMAGE_PER_HP = 0.02

local function enemyDamage(wave: number): number
	return baseEnemyHP(wave) * ENEMY_DAMAGE_PER_HP
end

return {
	BASE_ENEMY_HP = BASE_ENEMY_HP,
	HP_GROWTH_PER_WAVE = HP_GROWTH_PER_WAVE,
	MIN_ENEMIES = MIN_ENEMIES,
	MAX_ENEMIES = MAX_ENEMIES,
	GOLD_PER_HP = GOLD_PER_HP,
	ENEMY_DAMAGE_PER_HP = ENEMY_DAMAGE_PER_HP,
	BOSS_WAVE_INTERVAL = BOSS_WAVE_INTERVAL,
	BOSS_HP_MULTIPLIER = BOSS_HP_MULTIPLIER,

	CHECKPOINT_INTERVAL = CHECKPOINT_INTERVAL,
	isCheckpointWave = isCheckpointWave,
	checkpointFor = checkpointFor,
	isBossWave = isBossWave,
	baseEnemyHP = baseEnemyHP,
	enemyHP = enemyHP,
	enemyDamage = enemyDamage,
	enemyCount = enemyCount,
	goldPerKill = goldPerKill,
	goldPerWave = goldPerWave,
	waveTotalHP = waveTotalHP,
}
