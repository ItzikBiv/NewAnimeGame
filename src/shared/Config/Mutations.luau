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

	[?] MULTIPLIERS ARE UNKNOWN. Not one mutation multiplier is visible in any
	    screenshot or FAQ answer. The values below are OUR OWN ladder, not a clone
	    of theirs. Public (unverified) claims put the top mutations around 5x-6.5x
	    damage, which is the ceiling this ladder is shaped toward.
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
		damageMultiplier = 1.75,
		healthMultiplier = 1.5,
		weight = 120,
		availability = "always",
		color = Color3.fromRGB(255, 200, 50),
	},
	Diamond = {
		id = "Diamond",
		displayName = "Diamond",
		damageMultiplier = 2.5,
		healthMultiplier = 2.0,
		weight = 45,
		availability = "always",
		color = Color3.fromRGB(120, 230, 255),
	},

	-- ── Event mutations, on the quarter-hour cycle ─────────────────────────────
	Demon = {
		id = "Demon",
		displayName = "Demon",
		damageMultiplier = 3.25,
		healthMultiplier = 2.5,
		weight = 20,
		availability = "event",
		eventMinute = 15,
		color = Color3.fromRGB(200, 40, 40),
	},
	Slayer = {
		id = "Slayer",
		displayName = "Slayer",
		damageMultiplier = 4.0,
		healthMultiplier = 3.0,
		weight = 14,
		availability = "event",
		eventMinute = 0,
		color = Color3.fromRGB(60, 200, 130),
	},
	Hollow = {
		id = "Hollow",
		displayName = "Hollow",
		damageMultiplier = 4.75,
		healthMultiplier = 3.5,
		weight = 9,
		availability = "event",
		eventMinute = 45,
		color = Color3.fromRGB(240, 240, 240),
	},
	Destroyer = {
		id = "Destroyer",
		displayName = "Destroyer",
		damageMultiplier = 5.5,
		healthMultiplier = 4.0,
		weight = 5,
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
		damageMultiplier = 6.5,
		healthMultiplier = 4.5,
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
