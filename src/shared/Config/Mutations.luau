--!strict
--[[
	Mutations — the second power axis, independent of rarity.

	Ground truth: docs/ground-truth/source-game-teardown.md §4

	[C] A mutation renders as a label ABOVE the rarity on a unit card
	    (e.g. "Diamond" / "Legendary" / "Sakuna") with a distinct battle VFX.

	[C] Mutations are NOT all available at once. The dev FAQ gives an exact
	    server-clock schedule — each event mutation is rollable only during its
	    slot in the quarter-hour cycle:

	        Slayer     xx:00
	        Demon      xx:15
	        Destroyer  xx:30
	        Hollow     xx:45
	        Astronaut  Admin Abuse events only — never on the clock

	    This matches the in-game hint "[HINT] Mutation Events start every 15
	    minutes!" and explains it: the hint is the cycle, not a single event.

	[I] Normal, Gold and Diamond carry no event slot, so they are treated as
	    always-available baseline mutations.

	THE LOAD-BEARING DESIGN RULE: a mutated low-rarity unit can beat a clean
	high-rarity one. Rarity alone is NOT the power axis. If this interaction is
	flattened, the clone reproduces the shell and loses the game. Multipliers here
	must stay large enough that chasing mutations outranks chasing rarity.

	[C] GOLD AND DIAMOND ARE MEASURED. The owner captured the same unit
	    (Ulquiopta, Secret, Lv. 1) under all three always-available mutations, which
	    is a controlled experiment: only the mutation varies.

	        Normal    7500 atk   7500 hp   2.5 spd
	        Gold     11250 atk   9375 hp   2.5 spd    -> x1.50 dmg, x1.25 hp
	        Diamond  16875 atk  11250 hp   2.5 spd    -> x2.25 dmg, x1.50 hp

	    [C] MUTATIONS DO NOT TOUCH SPEED. All three rows read 2.5.
	    [D] Diamond's damage multiplier is exactly Gold's squared.

	[I] HOLLOW IS SMALL TOO, and that was a surprise. Two independent cross-unit
	    comparisons agree:

	        Mika (Rare, Hollow) 198 atk / 1395 hp   vs  Goke (Rare, Normal) 157.5 / 1200
	          -> x1.26 dmg, x1.16 hp
	        Goji (Legendary, Hollow) 1125 atk       vs  the Legendary attack baseline
	          -> x1.25 dmg

	    Dividing Mika's block by x1.25/x1.15 lands on 158 atk / 1213 hp, within 1% of
	    Goke's 157.5 / 1200. Two separate stats agreeing that closely is not a
	    coincidence, so the estimate is good even though it is cross-unit.

	    THE CONSEQUENCE IS A DESIGN CORRECTION. Our ladder previously ran to x6.5,
	    on the theory that a mutation should buy a rarity band outright. The measured
	    numbers do not support that: at x2.25, a Diamond Common (65 -> 146 atk) still
	    loses to a clean Rare (157.5). In the source game, rarity dominates and a
	    mutation is worth roughly HALF A BAND.

	    So event mutations are not a power ladder. They are scarcity, VFX and trade
	    value — you chase Hollow because it is only rollable for 15 minutes an hour,
	    not because it doubles your damage. That is the better design anyway: a
	    15-minute window should not gate raw power for players who are asleep.

	[OURS] Everything above Diamond is still ours. The two measured points anchor the
	    bottom of the ladder; Slayer, Demon, Destroyer and Astronaut extend it on the
	    same modest scale rather than the old steep one.
]]

export type MutationId =
	"Normal"
	| "Gold"
	| "Diamond"
	| "Demon"
	| "Slayer"
	| "Hollow"
	| "Destroyer"
	| "Astronaut"

-- How a mutation becomes obtainable. [C]
export type Availability =
	-- Rollable at any time.
	"always"
	-- Rollable only during its slot in the quarter-hour cycle.
	| "event"
	-- Only from an Admin Abuse event; never on a timer.
	| "admin"

export type Mutation = {
	id: MutationId,
	displayName: string,
	-- Multiplicative on the unit's base damage. [?]
	damageMultiplier: number,
	-- Multiplicative on the unit's base health. [?]
	healthMultiplier: number,
	-- Relative roll weight against the Normal baseline, WITHIN its window. [?]
	weight: number,
	availability: Availability,
	-- Minute past the hour this mutation's window opens. Only for `event`. [C]
	eventMinute: number?,
	color: Color3,
}

local Mutations: { [MutationId]: Mutation } = {
	Normal = {
		id = "Normal",
		displayName = "Normal",
		damageMultiplier = 1.0,
		healthMultiplier = 1.0,
		weight = 1000,
		availability = "always",
		color = Color3.fromRGB(200, 200, 200),
	},
	Gold = {
		id = "Gold",
		displayName = "Gold",
		damageMultiplier = 1.5,
		healthMultiplier = 1.25,
		weight = 120,
		availability = "always",
		color = Color3.fromRGB(255, 200, 50),
	},
	Diamond = {
		id = "Diamond",
		displayName = "Diamond",
		damageMultiplier = 2.25,
		healthMultiplier = 1.5,
		weight = 45,
		availability = "always",
		color = Color3.fromRGB(120, 230, 255),
	},

	-- ── Event mutations, on the quarter-hour cycle ─────────────────────────────
	Demon = {
		id = "Demon",
		displayName = "Demon",
		damageMultiplier = 1.75,
		healthMultiplier = 1.35,
		weight = 30,
		availability = "event",
		eventMinute = 15,
		color = Color3.fromRGB(200, 40, 40),
	},
	Slayer = {
		id = "Slayer",
		displayName = "Slayer",
		damageMultiplier = 1.35,
		healthMultiplier = 1.2,
		weight = 45,
		availability = "event",
		eventMinute = 0,
		color = Color3.fromRGB(60, 200, 130),
	},
	Hollow = {
		id = "Hollow",
		displayName = "Hollow",
		damageMultiplier = 1.25,
		healthMultiplier = 1.15,
		weight = 60,
		availability = "event",
		eventMinute = 45,
		color = Color3.fromRGB(240, 240, 240),
	},
	Destroyer = {
		id = "Destroyer",
		displayName = "Destroyer",
		damageMultiplier = 2.0,
		healthMultiplier = 1.4,
		weight = 18,
		availability = "event",
		eventMinute = 30,
		color = Color3.fromRGB(255, 90, 0),
	},

	-- ── Admin-only ────────────────────────────────────────────────────────────
	-- [C] "Astronaut mutation" is listed among Admin Abuse event rewards, and its
	-- schedule entry reads "Every Admin Abuse" rather than a clock time. It is the
	-- rarest mutation precisely because it cannot be farmed on a timer.
	Astronaut = {
		id = "Astronaut",
		displayName = "Astronaut",
		damageMultiplier = 3.0,
		healthMultiplier = 2.0,
		weight = 1,
		availability = "admin",
		color = Color3.fromRGB(90, 120, 255),
	},
}

-- [C] The mutation event cycle repeats every 15 minutes.
local MUTATION_EVENT_INTERVAL = 15 * 60

--[[
	Which event mutation's window is open at a given server time, if any.
	`minuteOfHour` is 0-59. Returns nil outside an event window.
]]
local function activeEventMutation(minuteOfHour: number): MutationId?
	local slot = minuteOfHour - (minuteOfHour % 15)
	for id, mutation in pairs(Mutations) do
		if mutation.availability == "event" and mutation.eventMinute == slot then
			return id
		end
	end
	return nil
end

--[[
	The mutations a roll can produce right now: the always-available ones, plus
	whichever event mutation currently holds the floor. Admin mutations never
	appear here — they are granted by the event, not rolled.
]]
local function rollableAt(minuteOfHour: number): { MutationId }
	local pool: { MutationId } = {}
	for id, mutation in pairs(Mutations) do
		if mutation.availability == "always" then
			table.insert(pool, id)
		end
	end
	local active = activeEventMutation(minuteOfHour)
	if active then
		table.insert(pool, active)
	end
	return pool
end

return {
	Mutations = Mutations,
	MUTATION_EVENT_INTERVAL = MUTATION_EVENT_INTERVAL,
	activeEventMutation = activeEventMutation,
	rollableAt = rollableAt,
}
