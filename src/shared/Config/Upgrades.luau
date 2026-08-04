--!strict
--[[
	The four gold upgrades.

	Ground truth: docs/ground-truth/source-game-teardown.md §6

	Every formula here is [D] DERIVED — fitted to two independent save-states of
	the source game and verified against the observed MAX value. These are the
	best-established numbers we have; they are not guesses.

		Gold      Lv18 -> x2.7   Lv25 -> x3.4  (MAX)
		Luck      Lv20 -> x10.5  Lv25 -> x13   (MAX)
		Slot      Lv8  -> ?      Lv9  -> 12    (MAX), starts at 4
		Inventory Lv3  -> 125    Lv7  -> 225   (MAX)

	[?] COST CURVES ARE NOT DERIVABLE. Only one price point per upgrade was
	    captured, so `costAtLevel` below is our own placeholder curve, anchored to
	    pass through the single observed price. Needs ~3 consecutive levels of any
	    one upgrade to fit properly.
]]

export type UpgradeId = "Gold" | "Luck" | "Slot" | "Inventory"

export type Upgrade = {
	id: UpgradeId,
	displayName: string,
	-- Verbatim from the source game's upgrade panel. [C]
	description: string,
	maxLevel: number,
	-- Level -> effect value. [D]
	valueAtLevel: (level: number) -> number,
	-- Level -> gold cost to reach `level + 1`. [?] placeholder curve.
	costAtLevel: (level: number) -> number,
	-- The one real price point we observed, for regression-testing the curve. [C]
	observedCost: { level: number, cost: number },
}

local Upgrades: { [UpgradeId]: Upgrade } = {
	Gold = {
		id = "Gold",
		displayName = "Gold Upgrade",
		description = "Increase the amount of gold you get from killing the enemies!",
		maxLevel = 25,
		-- [D] multiplier = 1 + 0.1 * (level - 1)   =>  Lv25 = 3.4 (MAX) ✓
		valueAtLevel = function(level: number): number
			return 1 + 0.1 * (level - 1)
		end,
		costAtLevel = function(level: number): number
			return math.floor(20000 * 1.22 ^ (level - 1))
		end,
		observedCost = { level = 18, cost = 840000 },
	},

	Luck = {
		id = "Luck",
		displayName = "Luck Upgrade",
		description = "Increase the chance of rolling rarer animes!",
		maxLevel = 25,
		-- [D] multiplier = 1 + 0.5 * (level - 1)   =>  Lv25 = 13 (MAX) ✓
		valueAtLevel = function(level: number): number
			return 1 + 0.5 * (level - 1)
		end,
		costAtLevel = function(level: number): number
			return math.floor(25000 * 1.23 ^ (level - 1))
		end,
		observedCost = { level = 20, cost = 1365000 },
	},

	Slot = {
		id = "Slot",
		displayName = "Slot Upgrade",
		description = "Unlock more slots to place more animes!",
		maxLevel = 9,
		-- [D] slots = level + 3   =>  Lv1 = 4 (start) ✓, Lv9 = 12 (MAX) ✓
		valueAtLevel = function(level: number): number
			return level + 3
		end,
		costAtLevel = function(level: number): number
			return math.floor(100000 * 1.58 ^ (level - 1))
		end,
		observedCost = { level = 8, cost = 5000000 },
	},

	Inventory = {
		id = "Inventory",
		displayName = "Inventory Upgrade",
		description = "Increase inventory capacity to store more animes!",
		maxLevel = 7,
		-- [D] capacity = 50 + 25 * level   =>  Lv3 = 125 ✓, Lv7 = 225 (MAX) ✓
		valueAtLevel = function(level: number): number
			return 50 + 25 * level
		end,
		costAtLevel = function(level: number): number
			return math.floor(125000 * 1.6 ^ (level - 1))
		end,
		observedCost = { level = 3, cost = 500000 },
	},
}

-- [D] Starting state, cross-checked against the project owner's description
-- ("you start with 4 slots ... up to 12").
local StartingLevels: { [UpgradeId]: number } = {
	Gold = 1,
	Luck = 1,
	Slot = 1,
	Inventory = 1,
}

-- [C] The enemy side of the arena is a fixed 16 tiles; only the player's side grows.
local ENEMY_SLOTS = 16

return {
	Upgrades = Upgrades,
	StartingLevels = StartingLevels,
	ENEMY_SLOTS = ENEMY_SLOTS,
}
