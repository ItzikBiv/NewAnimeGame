--!nocheck
--[[
	Roll resolution tests — story 1.1.

	This is the one system where "looks about right" is worthless. A gacha that is
	subtly off in the tail is a gacha nobody can debug from play. So this suite is
	STATISTICAL: it runs hundreds of thousands of seeded rolls and checks the
	observed distribution against the designed one.

	Deterministic throughout — the RNG is injected and seeded, so a failure here
	reproduces exactly.

	Expects globals: Rarities, Mutations, Traits, Upgrades, Waves, Power, Schema, Roll.
]]

local pass, fail = 0, 0

local function expect(label, condition, detail)
	if condition then
		pass += 1
		print(string.format("  ok   %s%s", label, detail and (" — " .. detail) or ""))
	else
		fail += 1
		print(string.format("  FAIL %s%s", label, detail and (" — " .. detail) or ""))
	end
end

local function check(label, got, want)
	if got == want then
		pass += 1
		print(string.format("  ok   %-54s = %s", label, tostring(got)))
	else
		fail += 1
		print(string.format("  FAIL %-54s = %s (want %s)", label, tostring(got), tostring(want)))
	end
end

-- A pure Lehmer (MINSTD) generator. Deliberately not Roblox's `Random`: this suite
-- must run under the bare Luau CLI, and the module takes its RNG as an argument
-- precisely so the source can be swapped. Good enough for distribution testing,
-- and identical on every machine.
local function seededRng(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

print("Pity starts at the caps shown in game")
local fresh = Roll.newPity()
check("Legendary starts at its cap", fresh.Legendary, Rarities.PityCaps.Legendary)
check("Mythic starts at its cap", fresh.Mythic, Rarities.PityCaps.Mythic)
check("Secret starts at its cap", fresh.Secret, Rarities.PityCaps.Secret)
expect("God has no pity counter", fresh.God == nil, "cannot be ground out deterministically")

print("\nRarity order is derived from config, never hardcoded")
check("ORDER[1]", Roll.ORDER[1], "Common")
check("ORDER[7]", Roll.ORDER[7], "God")
check("ORDER length", #Roll.ORDER, 7)

print("\nStatistical: 200,000 rolls at luck x1 match the designed distribution")
local N = 200000
local rng = seededRng(20260804)
local expected = Rarities.rollChances(1)
local counts = {}
for _, id in Roll.ORDER do
	counts[id] = 0
end

local pity = Roll.newPity()
local mutationCounts = {}
local pityForced = 0
-- Longest observed gap between hits of each tier, for the pity guarantee below.
local sinceHit = { Legendary = 0, Mythic = 0, Secret = 0 }
local worstGap = { Legendary = 0, Mythic = 0, Secret = 0 }

for _ = 1, N do
	-- Minute 0 keeps the mutation pool fixed (Normal/Gold/Diamond + Slayer) so the
	-- mutation counts below are comparable.
	local result = Roll.roll(1, pity, 0, rng)
	pity = result.pity
	counts[result.rarity] += 1
	mutationCounts[result.mutation] = (mutationCounts[result.mutation] or 0) + 1
	if result.fromPity then
		pityForced += 1
	end

	local hitOrder = Rarities.Rarities[result.rarity].order
	for tier, gap in pairs(sinceHit) do
		if Rarities.Rarities[tier].order <= hitOrder then
			sinceHit[tier] = 0
		else
			sinceHit[tier] = gap + 1
			if sinceHit[tier] > worstGap[tier] then
				worstGap[tier] = sinceHit[tier]
			end
		end
	end
end

for _, id in Roll.ORDER do
	local observed = counts[id] / N
	local want = expected[id]
	local tolerance = math.max(want * 0.15, 0.0008)
	-- Tiers whose expected count is too small for 200k rolls to constrain are
	-- skipped here and covered by the deterministic boundary tests below instead.
	-- A tolerance wide enough to pass reliably would be too wide to mean anything.
	local expectedCount = want * N
	if expectedCount < 30 then
		pass += 1
		print(
			string.format(
				"  ok   %-10s deferred to boundary tests — expected only %.1f pulls in %d",
				id,
				expectedCount,
				N
			)
		)
		continue
	end
	-- Pity lifts the observed rate of pitied tiers above their natural rate, which
	-- is correct behaviour, so those get a one-sided check instead.
	if Rarities.PityCaps[id] then
		expect(
			string.format("%-10s observed >= natural (pity lifts it)", id),
			observed >= want * 0.9,
			string.format("%.4f%% observed vs %.4f%% natural", observed * 100, want * 100)
		)
	else
		expect(
			string.format("%-10s within tolerance", id),
			math.abs(observed - want) <= tolerance,
			string.format("%.4f%% observed vs %.4f%% designed", observed * 100, want * 100)
		)
	end
end

print("\nThe pity guarantee actually holds over those 200,000 rolls")
for tier, gap in pairs(worstGap) do
	local cap = Rarities.PityCaps[tier]
	expect(
		string.format("%-10s never went longer than its cap", tier),
		gap <= cap,
		string.format("worst dry streak %d, cap %d", gap, cap)
	)
end
expect(
	"pity fired often enough to matter",
	pityForced > 0,
	string.format("%d of %d rolls forced by pity (%.1f%%)", pityForced, N, pityForced / N * 100)
)

print("\nThe tail, checked deterministically rather than statistically")
--[[
	Sampling CANNOT validate a 1-in-40,000 tier at 200k rolls — the expected count
	is ~5, so Poisson noise swamps any tolerance wide enough to pass reliably. A
	statistical check here would be theatre: it would pass whether the God rate were
	right, doubled, or halved.

	So instead, probe the sampler's boundaries directly. `rollRarityNatural` walks
	the ladder from rarest to commonest accumulating probability, so feeding it an
	exact value pins down exactly which tier that value must land in. This proves
	the tail is reachable AND correctly bounded, deterministically.
]]
local chances = Rarities.rollChances(1)
local function rngReturning(value)
	return function()
		return value
	end
end

expect(
	"a roll of 0 lands on God",
	Roll.rollRarityNatural(1, rngReturning(0)) == "God",
	"the rarest tier is reachable at all"
)
expect(
	"just inside the God band lands on God",
	Roll.rollRarityNatural(1, rngReturning(chances.God * 0.999)) == "God",
	string.format("band is [0, %.8f)", chances.God)
)
expect(
	"just outside the God band lands on Secret",
	Roll.rollRarityNatural(1, rngReturning(chances.God * 1.001)) == "Secret",
	"the boundary is where the design says it is"
)
expect(
	"a roll of ~1 lands on Common",
	Roll.rollRarityNatural(1, rngReturning(0.9999999)) == "Common",
	"the commonest tier absorbs the top of the range"
)

-- Every tier must own a non-empty, correctly-ordered slice of [0,1).
local cumulative = 0
local boundariesOk = true
for i = #Roll.ORDER, 1, -1 do
	local id = Roll.ORDER[i]
	local midpoint = cumulative + chances[id] * 0.5
	if Roll.rollRarityNatural(1, rngReturning(midpoint)) ~= id then
		boundariesOk = false
	end
	cumulative += chances[id]
end
expect("every tier owns its slice of the range", boundariesOk, "checked all 7 midpoints")

-- And the statistical run should still have produced a God or two. This is a smoke
-- signal, not a rate check — the boundary tests above are what prove correctness.
expect(
	"God did appear in the 200k statistical run",
	counts.God > 0,
	string.format(
		"%d pulls (expected ~%.0f; Poisson noise is large here)",
		counts.God,
		N * chances.God
	)
)

print("\nLuck shifts the distribution the way it should")
local luckyRng = seededRng(99999)
local luckyCounts = { Common = 0, Legendary = 0, God = 0 }
local luckyPity = Roll.newPity()
local M = 100000
for _ = 1, M do
	local result = Roll.roll(13, luckyPity, 0, luckyRng)
	luckyPity = result.pity
	if luckyCounts[result.rarity] ~= nil then
		luckyCounts[result.rarity] += 1
	end
end
expect(
	"max luck reduces Common",
	luckyCounts.Common / M < counts.Common / N,
	string.format(
		"%.1f%% at x13 vs %.1f%% at x1",
		luckyCounts.Common / M * 100,
		counts.Common / N * 100
	)
)
expect(
	"max luck raises Legendary",
	luckyCounts.Legendary / M > counts.Legendary / N,
	string.format(
		"%.2f%% at x13 vs %.2f%% at x1",
		luckyCounts.Legendary / M * 100,
		counts.Legendary / N * 100
	)
)

print("\nMutations respect the event window")
-- Minute 0 is the Slayer window. Nothing else event-gated may appear.
for id in pairs(mutationCounts) do
	local availability = Mutations.Mutations[id].availability
	expect(
		string.format("%-10s is legal at minute 0", id),
		availability == "always" or id == "Slayer",
		availability
	)
end
expect("Astronaut never rolled", mutationCounts.Astronaut == nil, "admin-granted only")
expect(
	"the window's mutation does appear",
	(mutationCounts.Slayer or 0) > 0,
	string.format("%d Slayer pulls", mutationCounts.Slayer or 0)
)

print("\nEvery window offers its own mutation and no other event mutation")
for _, minute in { 0, 15, 30, 45 } do
	local windowRng = seededRng(minute + 7)
	local seen = {}
	for _ = 1, 5000 do
		local result = Roll.roll(1, Roll.newPity(), minute, windowRng)
		seen[result.mutation] = true
	end
	local expectedEvent = Mutations.activeEventMutation(minute)
	local illegal = nil
	for id in pairs(seen) do
		local m = Mutations.Mutations[id]
		if m.availability == "event" and id ~= expectedEvent then
			illegal = id
		elseif m.availability == "admin" then
			illegal = id
		end
	end
	expect(
		string.format("minute :%02d offers only %s", minute, expectedEvent),
		illegal == nil,
		illegal and ("leaked " .. illegal) or "clean"
	)
end

print("\nPity is a floor, never a ceiling")
-- A tier owed by pity must not cap a luckier natural roll.
local owed = Roll.newPity()
owed.Legendary = 1
local ceilingRng = seededRng(4242)
local betterThanOwed = 0
for _ = 1, 2000 do
	local result = Roll.roll(500, owed, 0, ceilingRng)
	if Rarities.Rarities[result.rarity].order > Rarities.Rarities.Legendary.order then
		betterThanOwed += 1
	end
end
expect(
	"rolls above the owed tier still happen",
	betterThanOwed > 0,
	string.format("%d of 2000 beat the owed Legendary", betterThanOwed)
)

print("\nA hit resets every tier at or below it")
local afterSecret = Roll.resetPityUpTo({ Legendary = 3, Mythic = 7, Secret = 11 }, "Secret")
check("Legendary reset by a Secret", afterSecret.Legendary, Rarities.PityCaps.Legendary)
check("Mythic reset by a Secret", afterSecret.Mythic, Rarities.PityCaps.Mythic)
check("Secret reset by a Secret", afterSecret.Secret, Rarities.PityCaps.Secret)

local afterLegendary = Roll.resetPityUpTo({ Legendary = 3, Mythic = 7, Secret = 11 }, "Legendary")
check("Legendary reset by a Legendary", afterLegendary.Legendary, Rarities.PityCaps.Legendary)
check("Mythic untouched by a Legendary", afterLegendary.Mythic, 7)
check("Secret untouched by a Legendary", afterLegendary.Secret, 11)

print("\nWhen several tiers are due at once, the rarest wins")
check(
	"Legendary + Secret both due",
	Roll.pityDue({ Legendary = 0, Mythic = 4, Secret = 0 }),
	"Secret"
)
check("only Legendary due", Roll.pityDue({ Legendary = 0, Mythic = 4, Secret = 9 }), "Legendary")
check("nothing due", Roll.pityDue({ Legendary = 2, Mythic = 4, Secret = 9 }), nil)

print("\nResolution is deterministic for a given seed")
local a = Roll.roll(1, Roll.newPity(), 0, seededRng(1234))
local b = Roll.roll(1, Roll.newPity(), 0, seededRng(1234))
check("same seed, same rarity", a.rarity, b.rarity)
check("same seed, same mutation", a.mutation, b.mutation)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
