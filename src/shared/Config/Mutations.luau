--!strict
--[[
	Mutations — the second power axis, independent of rarity.

	Ground truth: docs/ground-truth/source-game-teardown.md §4

	[C] A mutation renders as a label ABOVE the rarity on a unit card
	    (e.g. "Diamond" / "Legendary" / "Sakuna") with a distinct battle VFX.

	[C] "[HINT] Mutation Events start every 15 minutes!" — mutation availability is
	    gated on a server-wide 15-minute cycle.

	THE LOAD-BEARING DESIGN RULE: a mutated low-rarity unit can beat a clean
	high-rarity one. Rarity alone is NOT the power axis. If this interaction is
	flattened, the clone reproduces the shell and loses the game. Multipliers here
	must stay large enough that chasing mutations outranks chasing rarity.

	[C] These seven are confirmed from the in-game Index tabs.
	[I] More exist off-screen. Public sources additionally name Titan, Nen, Quincy,
	    Admin, Dragonborn, Beast and Arrancar — unverified, so NOT encoded here.

	[?] MULTIPLIERS ARE UNKNOWN. Not one mutation multiplier is visible in any
	    screenshot. The values below are OUR OWN ladder, not a clone of theirs.
	    Public (unverified) claims put the top mutations around 5x-6.5x damage,
	    which is the ceiling this ladder is shaped toward.
]]

export type MutationId =
	"Normal" | "Gold" | "Diamond" | "Demon" | "Destroyer" | "Hollow" | "Astronaut"

export type Mutation = {
	id: MutationId,
	displayName: string,
	-- Multiplicative on the unit's base damage. [?]
	damageMultiplier: number,
	-- Multiplicative on the unit's base health. [?]
	healthMultiplier: number,
	-- Relative roll weight against the Normal baseline. [?]
	weight: number,
	color: Color3,
}

local Mutations: { [MutationId]: Mutation } = {
	Normal = {
		id = "Normal",
		displayName = "Normal",
		damageMultiplier = 1.0,
		healthMultiplier = 1.0,
		weight = 1000,
		color = Color3.fromRGB(200, 200, 200),
	},
	Gold = {
		id = "Gold",
		displayName = "Gold",
		damageMultiplier = 1.75,
		healthMultiplier = 1.5,
		weight = 120,
		color = Color3.fromRGB(255, 200, 50),
	},
	Diamond = {
		id = "Diamond",
		displayName = "Diamond",
		damageMultiplier = 2.5,
		healthMultiplier = 2.0,
		weight = 45,
		color = Color3.fromRGB(120, 230, 255),
	},
	Demon = {
		id = "Demon",
		displayName = "Demon",
		damageMultiplier = 3.25,
		healthMultiplier = 2.5,
		weight = 18,
		color = Color3.fromRGB(200, 40, 40),
	},
	Hollow = {
		id = "Hollow",
		displayName = "Hollow",
		damageMultiplier = 4.0,
		healthMultiplier = 3.0,
		weight = 8,
		color = Color3.fromRGB(240, 240, 240),
	},
	Astronaut = {
		id = "Astronaut",
		displayName = "Astronaut",
		damageMultiplier = 5.0,
		healthMultiplier = 3.5,
		weight = 3,
		color = Color3.fromRGB(90, 120, 255),
	},
	Destroyer = {
		id = "Destroyer",
		displayName = "Destroyer",
		damageMultiplier = 6.5,
		healthMultiplier = 4.0,
		weight = 1,
		color = Color3.fromRGB(255, 90, 0),
	},
}

-- [C] Server-wide mutation event cycle, in seconds.
local MUTATION_EVENT_INTERVAL = 15 * 60

return {
	Mutations = Mutations,
	MUTATION_EVENT_INTERVAL = MUTATION_EVENT_INTERVAL,
}
