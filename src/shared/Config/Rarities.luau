--!strict
--[[
	Unit rarity ladder and the roll odds.

	Ground truth: docs/ground-truth/source-game-teardown.md §3, §8

	[C] Seven tiers. Confirmed by the complete Essence item set in the source
	    game's inventory — there is exactly one Essence per rarity — and by the
	    rarity labels on rolled units.

	[C] There is NO "Uncommon" tier. Several public wikis claim one; the essence
	    set and the in-game index tabs both disprove it.

	[C] ORDER — RESOLVED. Two independent signals now agree:
	      pity counters   Legendary ~50  <  Mythic ~100  <  Secret ~250
	      Robux essence   Legendary R$49 <  Mythic R$129 <  Secret R$249 < God R$499
	    So the ladder is Common < Rare < Epic < Legendary < Mythic < Secret < God.
	    God carries NO pity counter — only three are shown on the Roll Machine, and
	    they belong to Legendary, Mythic and Secret.

	[C] EIGHT BANDS — corrected. The in-game Index lists units in the order
	    Common, Rare, Epic, Legendary, Mythic, Secret, God, LIMITED. `Limited` is a
	    band printed on the card exactly the way `God` is, not a flag on some other
	    rarity, and it sits above God.

	    It is still never in the roll pool — see `UnitSource` at the bottom of this
	    file. A Limited unit comes from the Shop or an event and nowhere else, so the
	    band has no base chance, no luck exponent and no pity counter.
]]

export type RarityId =
	"Common"
	| "Rare"
	| "Epic"
	| "Legendary"
	| "Mythic"
	| "Secret"
	| "God"
	| "Limited"

export type Rarity = {
	id: RarityId,
	displayName: string,
	-- Sort position, ascending. Higher = rarer.
	order: number,
	-- UI tint. Placeholder values; replace once we have art direction.
	color: Color3,
	-- Matching Essence item consumed by the Clone Machine. [C]
	-- nil for Limited, which has no Essence because it cannot be cloned.
	essenceItem: string?,
}

local Rarities: { [RarityId]: Rarity } = {
	Common = {
		id = "Common",
		displayName = "Common",
		order = 1,
		color = Color3.fromRGB(180, 180, 180),
		essenceItem = "CommonEssence",
	},
	Rare = {
		id = "Rare",
		displayName = "Rare",
		order = 2,
		color = Color3.fromRGB(70, 140, 255),
		essenceItem = "RareEssence",
	},
	Epic = {
		id = "Epic",
		displayName = "Epic",
		order = 3,
		color = Color3.fromRGB(170, 80, 255),
		essenceItem = "EpicEssence",
	},
	Legendary = {
		id = "Legendary",
		displayName = "Legendary",
		order = 4,
		color = Color3.fromRGB(255, 190, 40),
		essenceItem = "LegendaryEssence",
	},
	Mythic = {
		id = "Mythic",
		displayName = "Mythic",
		order = 5,
		color = Color3.fromRGB(255, 90, 170),
		essenceItem = "MythicEssence",
	},
	Secret = {
		id = "Secret",
		displayName = "Secret",
		order = 6,
		color = Color3.fromRGB(30, 30, 30),
		essenceItem = "SecretEssence",
	},
	God = {
		id = "God",
		displayName = "God",
		order = 7,
		color = Color3.fromRGB(255, 60, 60),
		essenceItem = "GodEssence",
	},
	--[[
		[C] Limited. Above God in the Index, and NEVER rollable.

		It has no Essence. Every other band has exactly one Essence item, which is
		what the Clone Machine consumes — and a band you cannot roll is a band you
		must not be able to duplicate either, or the shop-only promise is void the
		first time someone clones an event unit.
	]]
	Limited = {
		id = "Limited",
		displayName = "Limited",
		order = 8,
		color = Color3.fromRGB(0, 230, 200),
		essenceItem = nil,
	},
}

--[[
	ROLL ODDS — OUR OWN DESIGN, not a clone of theirs.

	The source game does not publish drop rates and they cannot be recovered from
	public data, so the project owner's call was "you pick the odds". These are
	shaped to satisfy the three hard constraints we DO have:

	  1. [C] The pity counters imply the natural rates. A tier's pity cap has to sit
	         a little ABOVE its natural 1-in-N, so pity acts as a safety net rather
	         than the normal way to get the unit.
	  2. [C] "God tier is really rare even with luck multiplier." God must stay
	         extreme at max luck (x13), not merely uncommon.
	  3. [C] God has no pity counter at all — there is no floor under a dry streak.

	Base chances below are per roll at luck x1.
]]
local BaseChance: { [RarityId]: number } = {
	Common = 0.0, -- computed as the remainder; see rollChances()
	Rare = 0.2500, -- 1 in 4
	Epic = 0.0800, -- 1 in 12.5
	Legendary = 0.0286, -- 1 in 35      (pity 50)
	Mythic = 0.0143, -- 1 in 70      (pity 100)
	Secret = 0.0056, -- 1 in 180     (pity 250)
	God = 0.000025, -- 1 in 40,000  (no pity)
}

--[[
	Luck does NOT scale every tier equally. If it did, x13 luck would drag God from
	1-in-40,000 to roughly 1-in-3,000, which flatly contradicts the owner's "really
	rare even with luck multiplier".

	Instead each tier scales as `chance * luck^exponent`, with the exponent falling
	as the tier gets rarer. Luck is then strongly felt in the Rare..Mythic band —
	which is where players actually notice it — while barely moving God.

	At max luck (x13) this yields roughly:
	    Rare  37%  ·  Epic 15%  ·  Legendary 10%  ·  Mythic 4.5%
	    Secret 1.6%  ·  God 1 in ~18,700   <- still genuinely rare
]]
local LuckExponent: { [RarityId]: number } = {
	Rare = 0.15,
	Epic = 0.25,
	Legendary = 0.50,
	Mythic = 0.45,
	Secret = 0.40,
	God = 0.30,
}

--[[
	Per-roll chance of each rarity at a given luck multiplier.

	Common absorbs whatever probability mass is left over, so the table always sums
	to exactly 1. At extreme luck the rare tiers can crowd Common out entirely;
	`MIN_COMMON_CHANCE` keeps a floor so the distribution stays well-formed.

	THE LADDER IS STRUCTURALLY ENFORCED. The luck exponents above deliberately RISE
	from Rare to Legendary, because luck should be felt where players notice it
	rather than just handing out more Rares. Left unchecked that inverts the ladder
	at high luck — Legendary would overtake Epic — and luck genuinely does stack
	here (x13 upgrade * the x10 LUCK server event * Luck Potions), so those levels
	are reachable in play, not just in theory.

	So after applying luck, every tier is clamped to at most `MAX_TIER_RATIO` of the
	tier below it. The clamp only ever reduces a chance, so the ordering
	Rare > Epic > Legendary > Mythic > Secret > God holds at ANY luck value.
]]
local MIN_COMMON_CHANCE = 0.01
local MAX_TIER_RATIO = 0.6

--[[
	Rarest last, Common excluded — it is the remainder tier.

	Limited is excluded too, and for a different reason: it is not a rung on this
	ladder at all. This list IS the roll pool, so leaving Limited out of it is what
	makes "limited units can never be summoned" true by construction rather than by
	a check somewhere that could be forgotten.
]]
local ASCENDING: { RarityId } = { "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }

-- Can this band come out of the Roll Machine at all?
local function isRollable(id: RarityId): boolean
	return id ~= "Limited"
end

local function rollChances(luckMultiplier: number): { [RarityId]: number }
	local luck = math.max(1, luckMultiplier)
	local chances: { [RarityId]: number } = {}

	for _, id in ASCENDING do
		chances[id] = BaseChance[id] * luck ^ LuckExponent[id]
	end

	-- Walk up the ladder, holding each tier strictly below the one beneath it.
	for i = 2, #ASCENDING do
		local below, current = ASCENDING[i - 1], ASCENDING[i]
		chances[current] = math.min(chances[current], chances[below] * MAX_TIER_RATIO)
	end

	local allocated = 0
	for _, id in ASCENDING do
		allocated += chances[id]
	end

	-- Scale the non-Common tiers back if they would leave Common no room. Uniform
	-- scaling preserves the ordering established above.
	local available = 1 - MIN_COMMON_CHANCE
	if allocated > available then
		local scale = available / allocated
		allocated = 0
		for _, id in ASCENDING do
			chances[id] *= scale
			allocated += chances[id]
		end
	end

	chances.Common = 1 - allocated
	return chances
end

--[[
	[C] Three pity counters are shown on the Roll Machine, for Legendary, Mythic
	    and Secret. Observed values across sessions peaked at 43 / 86 / 236, so the
	    caps sit just above those.

	    God is deliberately absent. It has no pity, which is what makes it the one
	    tier you cannot grind deterministically.
]]
local PityCaps: { [RarityId]: number } = {
	Legendary = 50,
	Mythic = 100,
	Secret = 250,
}

--[[
	[C] LIMITED UNITS ARE NOT IN THE ROLL POOL. Per the project owner: limited units
	    cannot be summoned at all — they come only from the Shop or from events, and
	    are marked "Limited — Unobtainable" once their window closes (observed on the
	    Overlord Gacha: Aldedo, Als, Entomancer, Bloodtear).

	    So a unit's rarity does NOT imply it is rollable. When the unit table is
	    built, every unit needs an explicit source, and the roll pool must filter on
	    it rather than on rarity alone.
]]
export type UnitSource = "roll" | "shop" | "event"

return {
	Rarities = Rarities,
	BaseChance = BaseChance,
	LuckExponent = LuckExponent,
	rollChances = rollChances,
	PityCaps = PityCaps,
	MIN_COMMON_CHANCE = MIN_COMMON_CHANCE,
	MAX_TIER_RATIO = MAX_TIER_RATIO,
	ASCENDING = ASCENDING,
	isRollable = isRollable,
}
