--!strict
--[[
	The unit roster.

	Ground truth: docs/ground-truth/unit-roster.md

	[C] A unit has FOUR stats, not one power number. Every unit card in the source
	    game shows exactly: Attack · Defense · Health · Speed. Our earlier model
	    collapsed a unit to a single `power` scalar derived from its rarity; that is
	    wrong, and this module is the correction.

	[C] Units also have a ROLE. The Index has a filter row reading
	    `ALL · DAMAGE · TANK · SUPPORT`, and the stat blocks back it up — within
	    Secret alone, Ulquiopta is 7500 atk / 7500 hp while Gyomain is 4000 atk /
	    25000 hp. Those are two different jobs, not a strong unit and a weak one.

	[C] BASE STATS ARE HAND-AUTHORED PER UNIT, NOT DERIVED FROM RARITY. Observed
	    Mythics span 360 to 7000 Attack. There is no formula hiding in that spread —
	    there is a designer. So this file is data, and it is meant to be edited.

	HOW A BLANK ENTRY WORKS. A unit may leave any stat `nil`, in which case it takes
	its band's baseline shaped by its role. That is not a second stat model competing
	with the first: the baseline is simply the default value of a field, and an
	explicit number always wins. Units we MEASURED carry explicit numbers; units we
	only know the name of take the default. Which is which is marked per entry.

	Speed is attacks per second. [C] Mutations never change it — the three Ulquiopta
	captures all read 2.5 — so it belongs to the unit alone.
]]

local Rarities = require(script.Parent.Rarities)

type RarityId = Rarities.RarityId

export type Role = "Damage" | "Tank" | "Support"

--[[
	[C] How a unit is obtained. Rarity does NOT imply this: a Limited unit is never
	rollable, and the Shop sells units from bands that are otherwise rollable too.
]]
export type UnitSource = "roll" | "shop" | "event"

export type Unit = {
	-- Stable internal key. Never rendered, never changes — save data references it.
	id: string,
	-- The only string shown to a player. Renaming the roster edits this and nothing else.
	displayName: string,
	rarity: RarityId,
	role: Role,
	source: UnitSource,
	-- nil = take the band/role default. An explicit value always wins.
	attack: number?,
	defense: number?,
	health: number?,
	speed: number?,
}

--[[
	[OURS] Band baselines, for units with no measured block.

	These sit near the observed medians rather than on a clean geometric ladder,
	because the observations are not geometric. The Common->Legendary steps are all
	about x2.4; Legendary->Mythic->Secret compresses to about x1.7, which is real —
	at the top of the roster, per-unit variation and role matter more than the band.
]]
local BandBase: { [RarityId]: { attack: number, health: number, defense: number } } = {
	Common = { attack = 65, health = 900, defense = 1.05 },
	Rare = { attack = 156, health = 1200, defense = 1.08 },
	Epic = { attack = 375, health = 2200, defense = 1.12 },
	Legendary = { attack = 900, health = 4100, defense = 1.18 },
	Mythic = { attack = 1500, health = 7000, defense = 1.22 },
	Secret = { attack = 2500, health = 14000, defense = 1.28 },
	God = { attack = 12000, health = 40000, defense = 1.35 },
	Limited = { attack = 12000, health = 40000, defense = 1.35 },
}

--[[
	[OURS] What a role does to the baseline.

	Shaped to reproduce the observed spread: Gyomain (Tank) really is ~1/2 the attack
	and ~2x the health of Ulquiopta (Damage) in the same band.

	THESE MULTIPLIERS ARE CENTRED ON 1.0, deliberately. An earlier version used
	Damage x1.6 attack at Speed 1.4, and the effect was that a band made entirely of
	name-only units out-DPS'd the band above it, whose units were measured and mostly
	slow (the observed Legendaries sit at Speed 0.7-0.8). A default that beats the
	evidence is a default that is wrong. The band baseline is the median unit, so the
	roles have to spread around it rather than sit above it.

	Speed defaults track the observed distribution too: the 15 captured speeds run
	0.6 to 3.5 with a median near 1.0, so a default damage dealer gets 1.2 and not 1.4.
]]
local RoleShape: {
	[Role]: { attack: number, health: number, defense: number, speed: number },
} =
	{
		Damage = { attack = 1.35, health = 0.75, defense = 1.0, speed = 1.2 },
		Tank = { attack = 0.6, health = 1.9, defense = 1.08, speed = 0.8 },
		Support = { attack = 0.85, health = 1.15, defense = 1.03, speed = 0.9 },
	}

--[[
	THE ROSTER.

	[C] = the stat block was read directly off a unit card.
	[D] = read off a card that carried a mutation, then divided by that mutation's
	      measured multiplier to recover the base. Only ever done with Gold (x1.5 dmg
	      / x1.25 hp) and Diamond (x2.25 / x1.5), which are measured, or Hollow
	      (x1.25 / x1.15) and Demon, which are not — those are marked.
	[N] = the name is confirmed from the Index, but no stat block was captured. Takes
	      the band/role default.
	[OURS] = our own unit, filling an Index slot the owner has not collected.
]]
local Roster: { Unit } = {
	-- ── Common ────────────────────────────────────────────────────────────────
	-- [C] card: 65 / 1.21 / 1705 / 1. The high health for a Common is why it reads
	-- as the game's starter tank rather than as a weak damage dealer.
	{
		id = "Itadoro",
		displayName = "Itadoro",
		rarity = "Common",
		role = "Damage",
		source = "roll",
		attack = 65,
		defense = 1.21,
		health = 1705,
		speed = 1.0,
	},
	{ id = "Usoff", displayName = "Usoff", rarity = "Common", role = "Support", source = "roll" }, -- [N]
	{ id = "Luppi", displayName = "Luppi", rarity = "Common", role = "Damage", source = "roll" }, -- [N]
	{
		id = "Keririn",
		displayName = "Keririn",
		rarity = "Common",
		role = "Support",
		source = "roll",
	}, -- [N]
	{ id = "Zero", displayName = "Zero", rarity = "Common", role = "Tank", source = "roll" }, -- [N]

	-- ── Rare ──────────────────────────────────────────────────────────────────
	-- [C] card: 157.5 / 1.06 / 1200 / 1.1
	{
		id = "Goke",
		displayName = "Goke",
		rarity = "Rare",
		role = "Damage",
		source = "roll",
		attack = 157.5,
		defense = 1.06,
		health = 1200,
		speed = 1.1,
	},
	-- [D] card read 198 / 1.17 / 1395 under Hollow. Divided by Hollow's x1.25/x1.15
	-- this lands on 158 / 1215 — within 1% of Goke's 157.5 / 1200. That agreement
	-- across two independent stats is what gave us the Hollow multiplier.
	{
		id = "Mika",
		displayName = "Mika",
		rarity = "Rare",
		role = "Damage",
		source = "roll",
		attack = 158,
		defense = 1.17,
		health = 1215,
		speed = 1.0,
	},
	{ id = "Sukora", displayName = "Sukora", rarity = "Rare", role = "Tank", source = "roll" }, -- [N]
	{ id = "Chapa", displayName = "Chapa", rarity = "Rare", role = "Damage", source = "roll" }, -- [OURS]
	{ id = "Kirita", displayName = "Kirita", rarity = "Rare", role = "Tank", source = "roll" }, -- [OURS]

	-- ── Epic ──────────────────────────────────────────────────────────────────
	{ id = "Manji", displayName = "Manji", rarity = "Epic", role = "Damage", source = "roll" }, -- [N]
	{ id = "Rukio", displayName = "Rukio", rarity = "Epic", role = "Support", source = "roll" }, -- [OURS]
	{ id = "Zenetsu", displayName = "Zenetsu", rarity = "Epic", role = "Damage", source = "roll" }, -- [OURS]
	{ id = "Bakugu", displayName = "Bakugu", rarity = "Epic", role = "Damage", source = "roll" }, -- [OURS]
	{ id = "Tenge", displayName = "Tenge", rarity = "Epic", role = "Tank", source = "roll" }, -- [OURS]

	-- ── Legendary ─────────────────────────────────────────────────────────────
	-- [D] Both Goji and Sakuna were captured under Hollow reading an IDENTICAL
	-- 1125 / 1.33 / 4725, differing only in Speed. Either they share a base block or
	-- Hollow overwrites — unresolved, see unit-roster.md §6. Recorded as a shared base.
	{
		id = "Goji",
		displayName = "Goji",
		rarity = "Legendary",
		role = "Damage",
		source = "roll",
		attack = 900,
		defense = 1.33,
		health = 4110,
		speed = 0.8,
	},
	{
		id = "Sakuna",
		displayName = "Sakuna",
		rarity = "Legendary",
		role = "Damage",
		source = "roll",
		attack = 900,
		defense = 1.33,
		health = 4110,
		speed = 0.75,
	},
	-- [D] card read 2137.5 / 1.50 / 15000 under Diamond (x2.25 / x1.5, measured).
	{
		id = "Nonomi",
		displayName = "Nonomi",
		rarity = "Legendary",
		role = "Tank",
		source = "roll",
		attack = 950,
		defense = 1.50,
		health = 10000,
		speed = 0.7,
	},
	{ id = "Truck", displayName = "Truck", rarity = "Legendary", role = "Tank", source = "roll" }, -- [N]
	{
		id = "Noruto",
		displayName = "Noruto",
		rarity = "Legendary",
		role = "Damage",
		source = "roll",
	}, -- [N]
	{
		id = "Saitomo",
		displayName = "Saitomo",
		rarity = "Legendary",
		role = "Damage",
		source = "roll",
	}, -- [N]

	-- ── Mythic ────────────────────────────────────────────────────────────────
	-- [C] Six Mythic cards were captured clean (no mutation), and they are the best
	-- evidence in the whole set that base stats are authored per unit: 360 to 7000
	-- Attack inside one band.
	{
		id = "Acer",
		displayName = "Acer",
		rarity = "Mythic",
		role = "Support",
		source = "roll",
		attack = 360,
		defense = 1.20,
		health = 3500,
		speed = 0.6,
	},
	{
		id = "Hoshira",
		displayName = "Hoshira",
		rarity = "Mythic",
		role = "Support",
		source = "roll",
		attack = 430,
		defense = 1.20,
		health = 4165,
		speed = 0.6,
	},
	{
		id = "Brocolli",
		displayName = "Brocolli",
		rarity = "Mythic",
		role = "Damage",
		source = "roll",
		attack = 600,
		defense = 1.22,
		health = 6400,
		speed = 1.0,
	},
	-- [D] captured at Lv. 2 (612.5 / 1.38 / 6440). Level scaling is unmeasured, so
	-- the Lv. 1 block is taken as Brocolli's — the two are near-identical at Lv. 2,
	-- which is the only reason that substitution is defensible. Revisit when we
	-- have a same-unit Lv.1/Lv.2 pair.
	{
		id = "Orihemi",
		displayName = "Orihemi",
		rarity = "Mythic",
		role = "Damage",
		source = "roll",
		attack = 600,
		defense = 1.38,
		health = 6400,
		speed = 1.0,
	},
	{
		id = "Kokushiro",
		displayName = "Kokushiro",
		rarity = "Mythic",
		role = "Tank",
		source = "roll",
		attack = 700,
		defense = 1.15,
		health = 5780,
		speed = 1.0,
	},
	{
		id = "Yoriki",
		displayName = "Yoriki",
		rarity = "Mythic",
		role = "Damage",
		source = "roll",
		attack = 1250,
		defense = 1.15,
		health = 5780,
		speed = 1.0,
	},
	{
		id = "Joti",
		displayName = "Joti",
		rarity = "Mythic",
		role = "Tank",
		source = "roll",
		attack = 1750,
		defense = 1.50,
		health = 10000,
		speed = 1.0,
	},
	-- [D] card read 2025 / 1.29 / 11250 under Diamond.
	{
		id = "Rengundam",
		displayName = "Rengundam",
		rarity = "Mythic",
		role = "Damage",
		source = "roll",
		attack = 900,
		defense = 1.29,
		health = 7500,
		speed = 1.2,
	},
	-- [D] card read 5250 / 1.28 / 15625 under Gold.
	{
		id = "Kashimi",
		displayName = "Kashimi",
		rarity = "Mythic",
		role = "Tank",
		source = "roll",
		attack = 3500,
		defense = 1.28,
		health = 12500,
		speed = 0.8,
	},
	-- [C] 7000 attack at Speed 3 on 3145 health. The clearest glass cannon in the
	-- data, and the reason DPS = Attack x Speed had to become a first-class idea.
	{
		id = "ShimoHaya",
		displayName = "Shimo Haya",
		rarity = "Mythic",
		role = "Damage",
		source = "roll",
		attack = 7000,
		defense = 1.20,
		health = 3145,
		speed = 3.0,
	},
	{
		id = "Kiwusuke",
		displayName = "Kiwusuke",
		rarity = "Mythic",
		role = "Support",
		source = "roll",
	}, -- [N]

	-- ── Secret ────────────────────────────────────────────────────────────────
	{
		id = "Deyo",
		displayName = "Deyo",
		rarity = "Secret",
		role = "Tank",
		source = "roll",
		attack = 420,
		defense = 1.28,
		health = 14000,
		speed = 1.0,
	},
	{
		id = "Jerin",
		displayName = "Jerin",
		rarity = "Secret",
		role = "Tank",
		source = "roll",
		attack = 625,
		defense = 1.25,
		health = 18975,
		speed = 1.0,
	},
	{
		id = "Fryren",
		displayName = "Fryren",
		rarity = "Secret",
		role = "Damage",
		source = "roll",
		attack = 2000,
		defense = 1.25,
		health = 5800,
		speed = 3.5,
	},
	{
		id = "Yuwah",
		displayName = "Yuwah",
		rarity = "Secret",
		role = "Damage",
		source = "roll",
		attack = 3000,
		defense = 1.12,
		health = 8500,
		speed = 1.0,
	},
	{
		id = "Gyomain",
		displayName = "Gyomain",
		rarity = "Secret",
		role = "Tank",
		source = "roll",
		attack = 4000,
		defense = 1.32,
		health = 25000,
		speed = 2.0,
	},
	-- [D] card read 4725 / 1.37 / 27000 under Diamond.
	{
		id = "Kenie",
		displayName = "Kenie",
		rarity = "Secret",
		role = "Tank",
		source = "roll",
		attack = 2100,
		defense = 1.37,
		health = 18000,
		speed = 1.8,
	},
	-- [C] The control unit. Captured Normal, Gold and Diamond — every mutation
	-- multiplier we trust comes from these three cards.
	{
		id = "Ulquiopta",
		displayName = "Ulquiopta",
		rarity = "Secret",
		role = "Damage",
		source = "roll",
		attack = 7500,
		defense = 1.25,
		health = 7500,
		speed = 2.5,
	},
	-- [D] card read 15000 / 1.31 / 17500 under Demon. Demon's multiplier is OURS, not
	-- measured, so this base is the softest number in the file — it moves if Demon does.
	{
		id = "Megumo",
		displayName = "Megumo",
		rarity = "Secret",
		role = "Damage",
		source = "roll",
		attack = 8570,
		defense = 1.31,
		health = 12960,
		speed = 1.0,
	},
	{ id = "Yutta", displayName = "Yutta", rarity = "Secret", role = "Damage", source = "roll" }, -- [N]
	{
		id = "Brakura",
		displayName = "Brakura",
		rarity = "Secret",
		role = "Damage",
		source = "roll",
	}, -- [N]

	-- ── God ───────────────────────────────────────────────────────────────────
	-- [C] "Goji (Shinjuku)" is a God-band variant of the Legendary Goji. The roster
	-- deliberately reuses a character across bands with a parenthesised name, which
	-- is why unit ids key on the full name and not on the character.
	{
		id = "GojiShinjuku",
		displayName = "Goji (Shinjuku)",
		rarity = "God",
		role = "Damage",
		source = "roll",
	}, -- [N]
	{ id = "Michael", displayName = "Michael", rarity = "God", role = "Support", source = "roll" }, -- [N]
	{ id = "Wise", displayName = "Wise", rarity = "God", role = "Support", source = "roll" }, -- [N]
	{ id = "Bills", displayName = "Bills", rarity = "God", role = "Damage", source = "roll" }, -- [N]
	{ id = "Remura", displayName = "Remura", rarity = "God", role = "Tank", source = "roll" }, -- [N]

	-- ── Limited ───────────────────────────────────────────────────────────────
	-- Every Limited slot in the owner's Index is uncollected, so we have no names and
	-- no stats. These two are OURS, and they exist so the Shop has something to sell
	-- and the band is not empty. `source` is what keeps them out of the roll pool.
	{ id = "Aldedo", displayName = "Aldedo", rarity = "Limited", role = "Tank", source = "shop" }, -- [OURS]
	{
		id = "Bloodtear",
		displayName = "Bloodtear",
		rarity = "Limited",
		role = "Damage",
		source = "event",
	}, -- [OURS]
}

-- Indexed by id, built once.
local byId: { [string]: Unit } = {}
for _, unit in Roster do
	assert(byId[unit.id] == nil, "duplicate unit id: " .. unit.id)
	byId[unit.id] = unit
end

--[[
	The roll pool for a band: the units a Roll Machine pull can actually produce.

	Filtering on `source` rather than on rarity is what makes "limited units can
	never be summoned" hold even if someone later adds a Limited unit to a rollable
	band by mistake.
]]
local rollPools: { [RarityId]: { Unit } } = {}
for _, unit in Roster do
	if unit.source == "roll" then
		local pool = rollPools[unit.rarity]
		if not pool then
			pool = {}
			rollPools[unit.rarity] = pool
		end
		table.insert(pool, unit)
	end
end

local function get(unitId: string): Unit?
	return byId[unitId]
end

local function rollPool(rarity: RarityId): { Unit }
	return rollPools[rarity] or {}
end

export type Stats = {
	attack: number,
	defense: number,
	health: number,
	speed: number,
}

--[[
	A unit's own stats, before mutation and level.

	Any stat the unit did not declare falls back to its band baseline shaped by its
	role. Roles do not shape an EXPLICIT value — a measured block is used exactly as
	measured, never re-shaped.
]]
local function baseStats(unit: Unit): Stats
	local band = BandBase[unit.rarity]
	local shape = RoleShape[unit.role]
	return {
		attack = unit.attack or (band.attack * shape.attack),
		defense = unit.defense or (band.defense * shape.defense),
		health = unit.health or (band.health * shape.health),
		speed = unit.speed or shape.speed,
	}
end

--[[
	Damage per second. [D] The single number that orders the roster sensibly.

	Attack alone does not: Kenie has less Attack than Ulquiopta but 2.4x the health,
	and reading them as "weaker" and "stronger" gets the game wrong. This is also
	what the source game's `EQUIP BEST` button must be sorting on.
]]
local function dps(stats: Stats): number
	return stats.attack * stats.speed
end

return {
	Roster = Roster,
	BandBase = BandBase,
	RoleShape = RoleShape,
	byId = byId,
	get = get,
	rollPool = rollPool,
	baseStats = baseStats,
	dps = dps,
}
