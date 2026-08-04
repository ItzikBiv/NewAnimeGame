--!strict
--[[
	Roll resolution — the heart of the game.

	Design: docs/planning/gdd.md §4, docs/planning/epics.md story 1.1
	Ground truth: docs/ground-truth/source-game-teardown.md §8

	PURE MODULE. Takes state and an RNG, returns a result and new state. It touches
	no services, holds no state of its own, and yields nowhere — so it can be run
	200,000 times in a test to check that the distribution is actually what we
	designed, rather than what we hoped.

	The RNG is an ARGUMENT, not a global. That is what makes the statistical tests
	deterministic and reproducible.

	SERVER ONLY at runtime. architecture.md §1: the client never sees a seed, a
	weight, or a pending result. This module must never be required from
	src/client.
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)
local Mutations = require(script.Parent.Parent.Config.Mutations)

type RarityId = Rarities.RarityId
type MutationId = Mutations.MutationId

-- Rolls remaining until each tier is guaranteed. [C] The source game shows
-- exactly three such counters, for Legendary, Mythic and Secret.
export type PityState = { [string]: number }

export type RollResult = {
	rarity: RarityId,
	mutation: MutationId,
	-- True when the pity floor forced this tier rather than luck producing it.
	fromPity: boolean,
	pity: PityState,
}

-- A function returning a float in [0, 1). Injected so tests are deterministic.
export type Rng = () -> number

--[[
	Fresh pity state: every counter at its cap.

	[C] The counters shown in game are "N rolls until X", so they count DOWN and
	reset on a hit.
]]
local function newPity(): PityState
	-- A shallow copy of the caps: every counter starts full. Cloning rather than
	-- aliasing matters, since callers mutate the returned table.
	return table.clone(Rarities.PityCaps)
end

-- Ascending rarity order (Common first), computed once from the config's `order`
-- field so this never drifts from Rarities.luau.
local ORDER: { RarityId } = {}
do
	for id in pairs(Rarities.Rarities) do
		table.insert(ORDER, id)
	end
	table.sort(ORDER, function(a, b)
		return Rarities.Rarities[a].order < Rarities.Rarities[b].order
	end)
end

local function orderOf(rarity: RarityId): number
	return Rarities.Rarities[rarity].order
end

--[[
	Pick a rarity from the luck-adjusted distribution, ignoring pity.
	Walks the ladder from rarest to commonest so the tiny tail is never skipped by
	floating-point accumulation at the front.
]]
local function rollRarityNatural(luck: number, rng: Rng): RarityId
	local chances = Rarities.rollChances(luck)
	local roll = rng()
	local cumulative = 0

	for i = #ORDER, 1, -1 do
		local id = ORDER[i]
		cumulative += chances[id]
		if roll < cumulative then
			return id
		end
	end

	-- Only reachable through float drift at the very top of the range.
	return ORDER[1]
end

--[[
	Which tier, if any, pity is currently forcing. When several are due at once the
	RAREST wins — a player owed both a Legendary and a Secret should get the Secret.
]]
local function pityDue(pity: PityState): RarityId?
	local due: RarityId? = nil
	for tier, remaining in pairs(pity) do
		if remaining <= 0 then
			if not due or orderOf(tier :: RarityId) > orderOf(due) then
				due = tier :: RarityId
			end
		end
	end
	return due
end

--[[
	Apply a hit at `rarity`: reset the counter for that tier and every tier below
	it, since landing a Secret has also satisfied any Legendary the player was owed.
]]
local function resetPityUpTo(pity: PityState, rarity: RarityId): PityState
	local next_: PityState = table.clone(pity)
	local hitOrder = orderOf(rarity)
	for tier, _ in pairs(next_) do
		if orderOf(tier :: RarityId) <= hitOrder then
			next_[tier] = Rarities.PityCaps[tier]
		end
	end
	return next_
end

--[[
	Pick a mutation from the pool currently open.

	[C] The pool is the three always-on mutations plus whichever event mutation
	holds the quarter-hour slot. Astronaut is admin-granted and never appears here —
	`Mutations.rollableAt` already excludes it.
]]
local function pickMutation(minuteOfHour: number, rng: Rng): MutationId
	local pool = Mutations.rollableAt(minuteOfHour)

	local total = 0
	for _, id in pool do
		total += Mutations.Mutations[id].weight
	end

	local roll_ = rng() * total
	local cumulative = 0
	for _, id in pool do
		cumulative += Mutations.Mutations[id].weight
		if roll_ < cumulative then
			return id
		end
	end

	return "Normal"
end

--[[
	Resolve one roll.

	`minuteOfHour` selects the open mutation window — pass the SERVER's clock.
	architecture.md §5: a client that can lie about the time can farm the rarest
	rollable mutation on demand.
]]
local function roll(luck: number, pity: PityState, minuteOfHour: number, rng: Rng): RollResult
	-- Tick every counter down first, so a counter reaching zero on THIS roll is
	-- honoured on this roll rather than the next one.
	local ticked: PityState = table.clone(pity)
	for tier, remaining in pairs(ticked) do
		ticked[tier] = remaining - 1
	end

	local natural = rollRarityNatural(luck, rng)
	local due = pityDue(ticked)

	local rarity = natural
	local fromPity = false
	-- Pity is a FLOOR, never a ceiling: a lucky natural roll above the owed tier
	-- stands as-is.
	if due and orderOf(due) > orderOf(natural) then
		rarity = due
		fromPity = true
	end

	return {
		rarity = rarity,
		mutation = pickMutation(minuteOfHour, rng),
		fromPity = fromPity,
		pity = resetPityUpTo(ticked, rarity),
	}
end

return {
	newPity = newPity,
	roll = roll,
	rollRarityNatural = rollRarityNatural,
	pickMutation = pickMutation,
	pityDue = pityDue,
	resetPityUpTo = resetPityUpTo,
	ORDER = ORDER,
}
