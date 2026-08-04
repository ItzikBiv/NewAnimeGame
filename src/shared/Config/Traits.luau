--!strict
--[[
	Traits — rolled at the Trait Machine with Trait Shards, applied to one unit.

	Ground truth: docs/ground-truth/source-game-teardown.md §7

	[C] The whole table below is quoted VERBATIM from the source game developers'
	    own Discord FAQ. This is the most reliable data we have on the game — it
	    came from the devs, not from a wiki.

	[C] Trait tiers are Rare -> Epic -> Legendary -> Mythic -> God.
	    NOTE this ladder omits Common and Secret. It is NOT the same ladder as unit
	    rarity (Rarities.luau) — deliberately kept as a separate enum. Do not merge.

	[C] "Obtain trait shards by killing enemies!"
	[C] God-tier trait odds are 0.02%, displayed in-game.
]]

export type TraitTier = "Rare" | "Epic" | "Legendary" | "Mythic" | "God"

--[[
	All modifiers are fractional bonuses: 0.10 means +10%.

	`attackSpeed` is POSITIVE FOR FASTER attacks.

	[?] UNRESOLVED SIGN CONVENTION — see teardown §7. The dev FAQ describes Cursed
	    as "25% Faster Attacks", while the in-game Trait Machine renders what looks
	    like the same trait as "-25% SPD". Either SPD means attack COOLDOWN (lower
	    is faster, and the two agree), or one of the two surfaces is wrong.

	    This inverts the effect of the strongest trait in the game. It MUST be
	    resolved before attack-speed code is written. Until then this file follows
	    the dev FAQ, because it is the more authoritative source.
]]
export type TraitEffect = {
	damage: number?,
	health: number?,
	critChance: number?,
	critDamage: number?,
	attackSpeed: number?,
	cash: number?,
	-- Cloner only: number of units summoned per placement. [C]
	summonCount: number?,
}

export type Trait = {
	id: string,
	displayName: string,
	tier: TraitTier,
	effect: TraitEffect,
	-- Roll chance where known, as a fraction (0.0002 = 0.02%). [C] where present.
	chance: number?,
}

local Traits: { [string]: Trait } = {
	-- ── Rare ──────────────────────────────────────────────────────────────────
	Sharp = {
		id = "Sharp",
		displayName = "Sharp",
		tier = "Rare",
		effect = { critChance = 0.10, critDamage = 0.25 },
	},
	Swift = {
		id = "Swift",
		displayName = "Swift",
		tier = "Rare",
		effect = { attackSpeed = 0.10 },
	},
	Strong = {
		id = "Strong",
		displayName = "Strong",
		tier = "Rare",
		effect = { damage = 0.10 },
	},

	-- ── Epic ──────────────────────────────────────────────────────────────────
	Deadly = {
		id = "Deadly",
		displayName = "Deadly",
		tier = "Epic",
		effect = { critChance = 0.15, critDamage = 0.30 },
	},
	Rush = {
		id = "Rush",
		displayName = "Rush",
		tier = "Epic",
		effect = { attackSpeed = 0.15 },
	},
	Powerful = {
		id = "Powerful",
		displayName = "Powerful",
		tier = "Epic",
		effect = { damage = 0.20, health = 0.10 },
	},

	-- ── Legendary ─────────────────────────────────────────────────────────────
	Deadeye = {
		id = "Deadeye",
		displayName = "Deadeye",
		tier = "Legendary",
		effect = { critChance = 0.35, critDamage = 0.45 },
	},
	Juggernaut = {
		id = "Juggernaut",
		displayName = "Juggernaut",
		tier = "Legendary",
		-- The only trait with an explicit DOWNSIDE: 10% Slower Attacks. [C]
		effect = { damage = 0.50, health = 0.35, attackSpeed = -0.10 },
	},
	Lethal = {
		id = "Lethal",
		displayName = "Lethal",
		tier = "Legendary",
		effect = { damage = 0.35, critChance = 0.30, critDamage = 0.40 },
	},
	Royal = {
		id = "Royal",
		displayName = "Royal",
		tier = "Legendary",
		effect = { damage = 0.25, health = 0.15, cash = 0.25 },
	},

	-- ── Mythic ────────────────────────────────────────────────────────────────
	Entrepreneur = {
		id = "Entrepreneur",
		displayName = "Entrepreneur",
		tier = "Mythic",
		effect = { damage = 0.45, health = 0.25, attackSpeed = 0.10, cash = 0.65 },
	},
	Reaper = {
		id = "Reaper",
		displayName = "Reaper",
		tier = "Mythic",
		effect = {
			damage = 0.90,
			health = 0.35,
			attackSpeed = 0.16,
			critChance = 0.35,
			critDamage = 0.45,
		},
	},
	Cloner = {
		id = "Cloner",
		displayName = "Cloner",
		tier = "Mythic",
		-- Unique mechanic, not a stat line: summons 2 units instead of 1. [C]
		effect = { damage = 0.40, health = 0.60, summonCount = 2 },
	},
	Superior = {
		id = "Superior",
		displayName = "Superior",
		tier = "Mythic",
		effect = {
			damage = 2.00,
			health = 1.00,
			attackSpeed = 0.20,
			critChance = 0.40,
			critDamage = 0.65,
		},
	},

	-- ── God ───────────────────────────────────────────────────────────────────
	Cursed = {
		id = "Cursed",
		displayName = "Cursed",
		tier = "God",
		effect = {
			damage = 4.00,
			health = 2.00,
			attackSpeed = 0.25,
			cash = 0.65,
			critChance = 0.50,
			critDamage = 1.00,
		},
		chance = 0.0002,
	},
	--[[
		Viking appears in the Trait Machine but NOT in the dev FAQ list — it is
		newer content added after that FAQ post. Its stat line is read directly off
		the machine, including the "-25% SPD" that triggers the open question above.
	]]
	Viking = {
		id = "Viking",
		displayName = "Viking",
		tier = "God",
		effect = {
			damage = 2.00,
			health = 7.50,
			attackSpeed = -0.25,
			critChance = 0.50,
			critDamage = 1.50,
		},
		chance = 0.0002,
	},
}

--[[
	[?] Per-tier roll weights are unknown apart from the 0.02% God figure shown
	    in-game. These are our own starting values, shaped so the God tier lands
	    near the confirmed 0.02%.
]]
local TierWeights: { [TraitTier]: number } = {
	Rare = 600,
	Epic = 300,
	Legendary = 90,
	Mythic = 10,
	God = 0.2,
}

return {
	Traits = Traits,
	TierWeights = TierWeights,
}
