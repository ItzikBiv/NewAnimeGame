--!nocheck
--[[
	The reroll shop.

	The rules that matter here are ECONOMIC, and they are the ones an exploit would
	go after. Rerolling is free and unlimited, so anything a reroll advances can be
	farmed by holding a button — that single fact drives most of this file.

	Expects globals: Rarities, Mutations, Units, Upgrades, Waves, Roll, Shop, Schema.
]]

local pass, fail = 0, 0

local function check(label, got, want)
	if got == want then
		pass += 1
		print(string.format("  ok   %-54s = %s", label, tostring(got)))
	else
		fail += 1
		print(string.format("  FAIL %-54s = %s (want %s)", label, tostring(got), tostring(want)))
	end
end

local function expect(label, condition, detail)
	if condition then
		pass += 1
		print(string.format("  ok   %s%s", label, detail and (" — " .. detail) or ""))
	else
		fail += 1
		print(string.format("  FAIL %s%s", label, detail and (" — " .. detail) or ""))
	end
end

local function seededRng(seed)
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

print("A reroll offers exactly three buyable units")
local rng = seededRng(4242)
local pity = Roll.newPity()
local offers = Shop.reroll(1, pity, 0, rng)
check("offer count", #offers, Shop.OFFER_COUNT)
check("and that is three", Shop.OFFER_COUNT, 3)
for _, offer in offers do
	assert(Units.get(offer.unitId), "offer names a unit that does not exist: " .. offer.unitId)
	assert(Rarities.Rarities[offer.rarity], "offer has an unknown band")
	assert(Mutations.Mutations[offer.mutation], "offer has an unknown mutation")
	assert(offer.price > 0 and offer.price < math.huge, "offer has no usable price")
end
expect("every offer is a real, priced unit", true)

print("\nRerolling is FREE, and advances nothing")
-- The load-bearing property. Rerolling costs nothing and cannot be rate-limited by
-- gold, so if a reroll moved any counter, holding the button would farm it.
check("reroll cost", Shop.REROLL_COST, 0)

local before = Roll.newPity()
local snapshot = {}
for tier, value in pairs(before) do
	snapshot[tier] = value
end
for _ = 1, 500 do
	Shop.reroll(1, before, 0, rng)
end
local unchanged = true
for tier, value in pairs(before) do
	if value ~= snapshot[tier] then
		unchanged = false
	end
end
expect(
	"500 rerolls leave pity untouched",
	unchanged,
	"otherwise holding the button farms guaranteed Secrets"
)

print("\nA due pity tier is honoured, but does not take over the shop")
local due = Roll.newPity()
due.Legendary = 0
local forced = Shop.reroll(1, due, 0, rng)
check("a Legendary is offered", forced[1].rarity, "Legendary")
expect(
	"the other two slots are still natural rolls",
	#forced == Shop.OFFER_COUNT,
	"a pity hit is a windfall, not a whole new shop"
)

print("\nPrice rises with band, and every band is priced")
local ladder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
local previous = 0
for _, band in ladder do
	local price = Shop.priceFor(band, "Normal")
	assert(price > previous, string.format("%s is not dearer than the band below", band))
	previous = price
end
expect("Common < Rare < Epic < Legendary < Mythic < Secret < God", true)

-- Limited is not sold by this machine, so it has no price. Returning infinity keeps
-- it unbuyable rather than free, which is what a missing entry would otherwise mean.
expect(
	"Limited cannot be bought here",
	Shop.priceFor("Limited", "Normal") == math.huge,
	"shop and events only"
)

print("\nA mutation costs exactly what it is worth")
--[[
	Price scales by the mutation's DAMAGE multiplier. If it scaled by anything else,
	some mutations would be strictly better value than others for a reason no player
	could see on screen.
]]
for mutationId, mutation in pairs(Mutations.Mutations) do
	local clean = Shop.priceFor("Epic", "Normal")
	local mutated = Shop.priceFor("Epic", mutationId)
	local ratio = mutated / clean
	assert(
		math.abs(ratio - mutation.damageMultiplier) < 0.01,
		string.format(
			"%s costs x%.2f but hits for x%.2f",
			mutationId,
			ratio,
			mutation.damageMultiplier
		)
	)
end
expect("price multiplier equals damage multiplier, for all 8 mutations", true)

print("\nBuying is refused for a reason, never in silence")
local table3 = Shop.reroll(1, Roll.newPity(), 0, rng)
local ok, why = Shop.canBuy(0, table3, 1)
expect("no gold is refused", not ok, why)
expect("and the refusal names the price", why and why:find("gold") ~= nil, why)

ok, why = Shop.canBuy(1e12, table3, 99)
expect("an empty slot is refused", not ok, why)

ok, why = Shop.canBuy(1e12, table3, 1.5)
expect("a fractional index is refused", not ok, why)

ok, why = Shop.canBuy(1e12, table3, "1")
expect("a string index is refused", not ok, why)

ok = Shop.canBuy(1e12, table3, 1)
expect("and a real purchase is allowed", ok)

print("\nExactly enough gold buys the offer")
-- Off-by-one on an affordability check is the kind of bug a player reports as
-- "it says I can afford it and nothing happens".
local exact = table3[1]
expect("price to the gold is enough", (Shop.canBuy(exact.price, table3, 1)))
expect("one gold short is not", not (Shop.canBuy(exact.price - 1, table3, 1)))

print("\nThe shop can never offer something unrollable")
-- Limited units are shop-and-event only. If a Limited ever reached the reroll
-- machine, the band's entire promise would be void.
local seen = {}
local wideRng = seededRng(90210)
for _ = 1, 3000 do
	for _, offer in Shop.reroll(13, Roll.newPity(), 0, wideRng) do
		seen[offer.rarity] = (seen[offer.rarity] or 0) + 1
		local unit = Units.get(offer.unitId)
		assert(unit.source == "roll", offer.unitId .. " is not rollable but was offered")
		assert(unit.rarity ~= "Limited", "a Limited unit reached the shop")
	end
end
expect("9,000 offers at max luck, no Limited", seen.Limited == nil)
expect(
	"and Common still dominates",
	seen.Common > (seen.Epic or 0),
	string.format("Common %d vs Epic %d", seen.Common, seen.Epic or 0)
)

print("\nPrices are reachable on the real income curve")
--[[
	A price nobody can pay is not a price. Measured in cumulative wave income at
	Gold Lv1 — the pessimistic case, since the Gold upgrade only ever helps.
]]
local cumulative, reachedAt = Schema.STARTING_GOLD or 500, {}
for w = 1, 400 do
	cumulative += Waves.goldPerWave(w)
	for _, band in ladder do
		if not reachedAt[band] and cumulative >= Shop.priceFor(band, "Normal") then
			reachedAt[band] = w
		end
	end
end
for _, band in ladder do
	expect(
		string.format("%-10s affordable by wave %s", band, tostring(reachedAt[band] or ">400")),
		reachedAt[band] ~= nil,
		string.format("%d gold", Shop.priceFor(band, "Normal"))
	)
end
expect(
	"and the ladder is spread out, not all at once",
	reachedAt.God > reachedAt.Common + 100,
	string.format("Common at wave %d, God at wave %d", reachedAt.Common, reachedAt.God)
)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
