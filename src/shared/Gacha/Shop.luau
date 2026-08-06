--!strict
--[[
	The reroll shop.

	OWNER'S DESIGN, and it replaces paid rolling outright:

	    "reroll shouldnt cost money just to get the unit should cost money, you can
	     infinite reroll and each reroll you get 3 units you can buy if you have the
	     money for it"

	So the machine offers three units, rerolling is free and unlimited, and gold
	buys an offer rather than a pull.

	WHAT THIS CHANGES ABOUT THE GAME. Under paid rolling, rarity was the gate: you
	paid, and the odds decided whether you got anything good. Here the odds only
	decide HOW OFTEN a band is offered — the gate is PRICE. A patient player will
	see a God offer eventually; they still cannot afford it for a very long time.

	That makes the price ladder the real progression curve, so it is steep on
	purpose (x4 a band), and it makes the Luck upgrade mean "less rerolling to see
	what you want" rather than "better chance of a freebie".

	PITY HAD TO MOVE. Its whole job was protecting a player from bad luck on money
	they had already spent. Rerolling costs nothing now, so pity counted against
	rerolls would fire every couple of minutes of idle clicking and guarantee
	Secrets to anyone willing to hold the button. It therefore ticks on PURCHASES
	instead — see `GameService.handleBuy`. This module never ticks it; it only
	honours a tier that is already due.
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Units = require(script.Parent.Parent.Config.Units)
local Roll = require(script.Parent.Roll)

type RarityId = Rarities.RarityId
type MutationId = Mutations.MutationId

-- [C] Owner: "each reroll you get 3 units".
local OFFER_COUNT = 3

-- [C] Owner: "reroll shouldnt cost money".
local REROLL_COST = 0

export type Offer = {
	unitId: string,
	rarity: RarityId,
	mutation: MutationId,
	price: number,
}

--[[
	[OURS] Base price of a clean, Lv1 unit of each band.

	Tuned against the real income curve rather than picked for looking tidy. With
	the wave economy as it stands (wave 1 pays 36 gold, wave 60 about 230), these
	land roughly at:

	    Common      immediately        Legendary   wave ~60
	    Rare        wave ~10           Mythic      wave ~95
	    Epic        wave ~25           Secret      wave ~125
	                                   God         wave ~160

	x4 a band, which is steeper than the x2.4 power step between bands. That is
	deliberate: buying up a band should be a real decision against buying two of
	the band below, not a formality.

	Limited has no price here because it is not sold by this machine — it comes
	from the Shop or an event, and `Units.rollPool` never offers it.
]]
local BasePrice: { [RarityId]: number } = {
	Common = 100,
	Rare = 400,
	Epic = 1600,
	Legendary = 7000,
	Mythic = 30000,
	Secret = 150000,
	God = 1000000,
}

--[[
	What an offer costs.

	A mutation multiplies the price by exactly what it multiplies the unit's attack
	by, so a Diamond costs 2.25x a clean one because it hits 2.25x as hard. Pricing
	a mutation at anything else would make some mutations strictly better value
	than others for reasons a player could never see.
]]
local function priceFor(rarity: RarityId, mutation: MutationId): number
	local base = BasePrice[rarity]
	if not base then
		-- A band with no price cannot be sold. Better to be unbuyable than free.
		return math.huge
	end
	return math.floor(base * Mutations.Mutations[mutation].damageMultiplier)
end

--[[
	Build one offer at a given band.

	Returns nil when the band has no rollable units, which is a data bug rather than
	a player action — the caller decides whether that is fatal.
]]
local function offerAt(rarity: RarityId, minuteOfHour: number, rng: () -> number): Offer?
	local pool = Units.rollPool(rarity)
	if #pool == 0 then
		return nil
	end
	local unit = pool[math.floor(rng() * #pool) + 1]
	local mutation = Roll.pickMutation(minuteOfHour, rng)
	return {
		unitId = unit.id,
		rarity = rarity,
		mutation = mutation,
		price = priceFor(rarity, mutation),
	}
end

--[[
	Roll a fresh set of offers.

	PURE, and it does NOT touch pity — `pity` is read to decide whether a tier is
	owed, never written. Rerolling is free and unlimited, so a reroll must not be
	able to advance any counter; otherwise holding the button becomes a strategy.

	When a tier IS due, it is forced into the first slot. The other two are always
	natural rolls, so a pity hit still feels like a windfall rather than replacing
	the whole shop.
]]
local function reroll(
	luck: number,
	pity: { [string]: number },
	minuteOfHour: number,
	rng: () -> number
): { Offer }
	local offers: { Offer } = {}

	local due = Roll.pityDue(pity)
	if due then
		local forced = offerAt(due, minuteOfHour, rng)
		if forced then
			table.insert(offers, forced)
		end
	end

	while #offers < OFFER_COUNT do
		local rarity = Roll.rollRarityNatural(luck, rng)
		local offer = offerAt(rarity, minuteOfHour, rng)
		if offer then
			table.insert(offers, offer)
		else
			-- Every band is meant to have a rollable unit; `unit-invariants` asserts
			-- it. Falling back to Common keeps a data bug from emptying the shop.
			local fallback = offerAt("Common", minuteOfHour, rng)
			if not fallback then
				break
			end
			table.insert(offers, fallback)
		end
	end

	return offers
end

--[[
	Can this offer be bought right now?

	Returns false and a REASON, because "nothing happened" is the worst possible
	answer to a click. The caller is the server; the client never decides this.
]]
local function canBuy(gold: number, offers: { Offer }, index: number): (boolean, string?)
	if type(index) ~= "number" or index ~= math.floor(index) then
		return false, "bad offer index"
	end
	local offer = offers[index]
	if not offer then
		return false, "that offer is gone — reroll for more"
	end
	if gold < offer.price then
		return false, string.format("costs %d gold", offer.price)
	end
	return true, nil
end

return {
	OFFER_COUNT = OFFER_COUNT,
	REROLL_COST = REROLL_COST,
	BasePrice = BasePrice,
	priceFor = priceFor,
	offerAt = offerAt,
	reroll = reroll,
	canBuy = canBuy,
}
