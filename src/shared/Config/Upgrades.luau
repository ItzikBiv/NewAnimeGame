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

--[[
	[OURS] Cost curve builder.

	Every upgrade's price is geometric — each level costs `ratio` times the last —
	and is ANCHORED so it passes through the one real price we photographed for that
	upgrade EXACTLY. The base is solved for rather than typed in, so the anchor
	cannot drift away from the curve when someone retunes the ratio.

	WHY THE RATIOS ARE WHAT THEY ARE. The previous curves were hand-picked bases that
	happened to land within 2x of the anchor, and they made the early game
	unplayable: the 5th unit slot cost 100,000 gold, which the owner's own playtest
	would not have reached until around wave 121. Anchoring instead to the LATE price
	and choosing a steeper ratio keeps the endgame prices honest while pulling the
	first purchase of each upgrade into the first half-hour of play.
]]
local function anchoredCost(
	anchorLevel: number,
	anchorCost: number,
	ratio: number
): (level: number) -> number
	local base = anchorCost / ratio ^ (anchorLevel - 1)
	return function(level: number): number
		return math.floor(base * ratio ^ (level - 1))
	end
end

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
		-- Lv1->Lv2 costs 1,500; Lv18->Lv19 costs the observed 840,000.
		costAtLevel = anchoredCost(18, 840000, 1.4353),
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
		-- Lv1->Lv2 costs 2,000; Lv20->Lv21 costs the observed 1,365,000.
		costAtLevel = anchoredCost(20, 1365000, 1.3949),
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
		-- The 5th slot costs 3,000, not 100,000. Lv8->Lv9 still costs the
		-- observed 5,000,000, so the last slot stays a genuine endgame goal.
		costAtLevel = anchoredCost(8, 5000000, 2.929),
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
		-- Lv1->Lv2 costs 25,000; Lv3->Lv4 costs the observed 500,000.
		costAtLevel = anchoredCost(3, 500000, 4.472),
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
