--!strict
--[[
	Unit rarity ladder.

	Ground truth: docs/ground-truth/source-game-teardown.md §3

	[C] Seven tiers. Confirmed by the complete Essence item set in the source
	    game's inventory — there is exactly one Essence per rarity — and by the
	    rarity labels on rolled units.

	[C] There is NO "Uncommon" tier. Several public wikis claim one; the essence
	    set and the in-game index tabs both disprove it.

	[?] The ORDER of Secret vs Mythic is unresolved. Two contradicting signals:
	      - Robux essence-pack pricing implies  Legendary < Mythic < Secret < God
	      - Inventory display order + wikis imply Legendary < Secret < Mythic < God
	    `order` below follows the pricing signal, which is the harder evidence
	    (real money is rarely mispriced against rarity). Revisit once a Secret and
	    a Mythic have been rolled side by side.
]]

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret" | "God"

export type Rarity = {
	id: RarityId,
	displayName: string,
	-- Sort position, ascending. Higher = rarer.
	order: number,
	-- UI tint. Placeholder values; replace once we have art direction.
	color: Color3,
	-- Matching Essence item consumed by the Clone Machine. [C]
	essenceItem: string,
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
}

--[[
	[?] BASE ROLL ODDS ARE UNKNOWN — this is the single biggest hole in our data.

	The source game does not publish drop rates, no wiki has them, and they are not
	visible in any screenshot. The weights below are OUR OWN starting curve, not a
	clone of theirs. They are shaped to be consistent with the one hard constraint
	we do have: the observed pity caps (Legendary ~40-50 rolls, Mythic ~100, and a
	third counter at ~250 that is probably God or Secret).

	Treat these as tuning knobs, not ground truth. They must survive a simulated
	roll session before they ship.
]]
local BaseWeights: { [RarityId]: number } = {
	Common = 1000,
	Rare = 400,
	Epic = 120,
	Legendary = 25,
	Mythic = 8,
	Secret = 2,
	God = 0.4,
}

--[[
	[C] Three pity counters are displayed on the Roll Machine simultaneously.
	[I] They are countdowns that reset when the tier is hit. Caps below are read
	    off the highest observed values across sessions.
]]
local PityCaps: { [RarityId]: number } = {
	Legendary = 50,
	Mythic = 100,
	God = 250,
}

return {
	Rarities = Rarities,
	BaseWeights = BaseWeights,
	PityCaps = PityCaps,
}
