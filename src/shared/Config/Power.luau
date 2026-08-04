--!strict
--[[
	The power model — how a unit's effective strength is composed.

	Design: docs/planning/gdd.md §4

	    power = rarityMult * mutationMult * levelMult * (1 + traitBonus)

	Four INDEPENDENT axes. That independence is the whole game: it is what lets a
	mutated Common beat a clean Epic, which is the design pillar.

	[?] No unit stat magnitude appears in any screenshot or FAQ answer, so every
	    number here is [OURS]. They are chosen to satisfy one hard constraint:

	      A MUTATION MUST BE ABLE TO BUY AT LEAST ONE RARITY TIER.

	    If mutation multipliers are too small, rarity dominates and the two-axis
	    pull collapses into an ordinary rarity ladder. The tests assert this
	    property directly, so a future rebalance cannot quietly break the pillar.
]]

local Rarities = require(script.Parent.Rarities)
local Mutations = require(script.Parent.Mutations)

type RarityId = Rarities.RarityId
type MutationId = Mutations.MutationId

-- [OURS] Power multiplier by rarity, Common = 1.0.
local RarityPower: { [RarityId]: number } = {
	Common = 1.0,
	Rare = 2.2,
	Epic = 5.0,
	Legendary = 12.0,
	Mythic = 28.0,
	Secret = 65.0,
	God = 150.0,
}

--[[
	[OURS] Merge level multiplier.

	[C] A merge needs two units of the same identity, mutation AND level, so a
	Lv-n unit costs 2^(n-1) base copies.

	1.8 is deliberately BELOW that 2x copy cost. Merging therefore trades board
	width for depth at a slight loss, which keeps it a real decision. At >= 2.0
	merging would be strictly correct and the choice would evaporate.
]]
local LEVEL_MULTIPLIER = 1.8

local function levelMultiplier(level: number): number
	return LEVEL_MULTIPLIER ^ (level - 1)
end

--[[
	Effective power of a unit.
	`traitBonus` is the summed fractional damage bonus from its trait, e.g. 0.35.
]]
local function power(
	rarity: RarityId,
	mutation: MutationId,
	level: number,
	traitBonus: number?
): number
	return RarityPower[rarity]
		* Mutations.Mutations[mutation].damageMultiplier
		* levelMultiplier(level)
		* (1 + (traitBonus or 0))
end

--[[
	How many rarity tiers a mutation is worth on a given base rarity — the pillar,
	made measurable. Returns the number of clean tiers the mutated unit out-powers.

	Used by the tests to prove mutations stay meaningful, and useful for tuning.
]]
local function tiersGainedByMutation(rarity: RarityId, mutation: MutationId): number
	local mutated = power(rarity, mutation, 1)
	local baseOrder = Rarities.Rarities[rarity].order
	local gained = 0
	for _, r in pairs(Rarities.Rarities) do
		if r.order > baseOrder and RarityPower[r.id] <= mutated then
			gained += 1
		end
	end
	return gained
end

--[[
	[OURS] Damage resolution. Deliberately simple — this is an idle auto-battler,
	and every extra term is a number the player cannot see on screen.

	Defense uses the standard 100/(100+D) curve: diminishing returns, and immunity
	is unreachable no matter how high Defense goes.
]]
local DEFENSE_CONSTANT = 100

local function damageAfterDefense(rawDamage: number, defense: number): number
	return rawDamage * (DEFENSE_CONSTANT / (DEFENSE_CONSTANT + defense))
end

-- Attack period in seconds. Positive attackSpeed bonuses shorten it. See Traits.
local function attackPeriod(basePeriod: number, attackSpeedBonus: number): number
	return basePeriod / (1 + attackSpeedBonus)
end

--[[
	[OURS] The absolute scale. Everything above is relative — these two numbers are
	what turn a power multiplier into damage per second, and therefore into a
	time-to-clear that can actually be tuned against the wave curve.

	A Common / Normal / Lv1 unit deals BASE_ATTACK every BASE_ATTACK_PERIOD seconds.
]]
local BASE_ATTACK = 10
local BASE_ATTACK_PERIOD = 1.0

local function dps(
	rarity: RarityId,
	mutation: MutationId,
	level: number,
	traitBonus: number?,
	attackSpeedBonus: number?
): number
	local hit = BASE_ATTACK * power(rarity, mutation, level, traitBonus)
	return hit / attackPeriod(BASE_ATTACK_PERIOD, attackSpeedBonus or 0)
end

-- Seconds for `squadDps` to chew through `totalHP`. The core tuning number.
local function timeToClear(totalHP: number, squadDps: number): number
	return totalHP / squadDps
end

return {
	RarityPower = RarityPower,
	LEVEL_MULTIPLIER = LEVEL_MULTIPLIER,
	DEFENSE_CONSTANT = DEFENSE_CONSTANT,
	BASE_ATTACK = BASE_ATTACK,
	BASE_ATTACK_PERIOD = BASE_ATTACK_PERIOD,

	levelMultiplier = levelMultiplier,
	power = power,
	tiersGainedByMutation = tiersGainedByMutation,
	damageAfterDefense = damageAfterDefense,
	attackPeriod = attackPeriod,
	dps = dps,
	timeToClear = timeToClear,
}
