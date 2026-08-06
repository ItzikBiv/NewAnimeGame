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
local Units = require(script.Parent.Units)

type RarityId = Rarities.RarityId
type MutationId = Mutations.MutationId

--[[
	[OURS] Power multiplier by rarity, Common = 1.0.

	THIS IS NO LONGER HOW A REAL UNIT IS STATTED — see `unitStats` below and
	`Units.luau`. Real units carry authored Attack/Defense/Health/Speed. This ladder
	survives for two narrower jobs: it is the yardstick `tiersGainedByMutation` uses
	to ask "how much is a mutation worth in band terms", and it stats a unit that has
	no roster entry at all (synthetic units in balance tests).

	Limited tracks God: it is a band you buy, not a band you out-roll, so it must not
	be the strongest thing in the game by construction.
]]
local RarityPower: { [RarityId]: number } = {
	Common = 1.0,
	Rare = 2.2,
	Epic = 5.0,
	Legendary = 12.0,
	Mythic = 28.0,
	Secret = 65.0,
	God = 150.0,
	Limited = 150.0,
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
-- [OURS] A Common / Normal / Lv1 unit's health pool.
local BASE_HEALTH = 100

--[[
	A unit's health. Mutations carry their own health multiplier, separate from
	their damage one — that is what makes a mutated tank meaningfully different
	from a mutated damage dealer rather than just "bigger".
]]
local function health(
	rarity: RarityId,
	mutation: MutationId,
	level: number,
	traitHealthBonus: number?
): number
	return BASE_HEALTH
		* RarityPower[rarity]
		* Mutations.Mutations[mutation].healthMultiplier
		* levelMultiplier(level)
		* (1 + (traitHealthBonus or 0))
end

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

--[[
	A ROSTER unit's live stats: its authored block, under a mutation, at a level.

	This is the real path. `power`/`health` above are the fallback for units that
	have no roster entry.

	    attack  = base.attack  * mutation.damage * level
	    health  = base.health  * mutation.health * level
	    speed   = base.speed                                  <- mutation-independent
	    defense = base.defense                                <- near-flat, see below

	[C] SPEED IS UNTOUCHED BY MUTATION. The three Ulquiopta captures all read 2.5.

	[I] DEFENSE IS LEFT ALONE TOO. Across those same three captures it moved 1.25 ->
	    1.28 -> 1.29 — real but tiny, and two points cannot distinguish a x1.02/x1.035
	    scaling from a flat +0.03/+0.04. Modelling it as flat is the honest choice
	    until there is a third point; the alternative is inventing a curve and then
	    balancing against it as though it were known.
]]
local function unitStats(
	unitId: string,
	mutation: MutationId,
	level: number,
	traitBonus: number?,
	traitHealthBonus: number?
): Units.Stats?
	local unit = Units.get(unitId)
	if not unit then
		return nil
	end

	local base = Units.baseStats(unit)
	local m = Mutations.Mutations[mutation]
	local lvl = levelMultiplier(level)

	return {
		attack = base.attack * m.damageMultiplier * lvl * (1 + (traitBonus or 0)),
		defense = base.defense,
		health = base.health * m.healthMultiplier * lvl * (1 + (traitHealthBonus or 0)),
		speed = base.speed,
	}
end

return {
	RarityPower = RarityPower,
	unitStats = unitStats,
	LEVEL_MULTIPLIER = LEVEL_MULTIPLIER,
	DEFENSE_CONSTANT = DEFENSE_CONSTANT,
	BASE_ATTACK = BASE_ATTACK,
	BASE_ATTACK_PERIOD = BASE_ATTACK_PERIOD,
	BASE_HEALTH = BASE_HEALTH,

	levelMultiplier = levelMultiplier,
	power = power,
	health = health,
	tiersGainedByMutation = tiersGainedByMutation,
	damageAfterDefense = damageAfterDefense,
	attackPeriod = attackPeriod,
	dps = dps,
	timeToClear = timeToClear,
}
