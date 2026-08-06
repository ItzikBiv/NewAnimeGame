--!nocheck
--[[
	The unit roster.

	The centrepiece here is §"Measured cards reproduce exactly". Every entry in
	Units.luau that carries an explicit stat block was derived from a photograph of a
	unit card, sometimes by dividing out a mutation multiplier. That derivation is
	reversible — feeding the base stats back through the same mutation must land on
	the number in the photo.

	So this suite pins the roster to the evidence. If someone retunes a mutation
	multiplier, or nudges a base stat, the recomputed card stops matching the
	screenshot and CI says so. Without it the screenshots are a thing we read once;
	with it they are a thing that keeps being true.

	Expects globals: Rarities, Mutations, Units, Power.
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

-- Cards are rendered to a couple of decimals, and two of our bases were recovered by
-- division, so exact equality is the wrong bar. 0.5% is far tighter than any plausible
-- retune and far looser than float noise.
local function near(label, got, want, tolerancePct)
	local tol = (tolerancePct or 0.5) / 100
	local ok = want ~= 0 and math.abs(got - want) / math.abs(want) <= tol
	if ok then
		pass += 1
		print(string.format("  ok   %-40s %10.1f (card %.1f)", label, got, want))
	else
		fail += 1
		print(string.format("  FAIL %-40s %10.1f (card %.1f)", label, got, want))
	end
end

print("Every unit is well-formed")
local seen, count = {}, 0
for _, unit in Units.Roster do
	count += 1
	assert(not seen[unit.id], "duplicate unit id: " .. unit.id)
	seen[unit.id] = true
	assert(Rarities.Rarities[unit.rarity], unit.id .. " has an unknown rarity")
	assert(#unit.displayName > 0, unit.id .. " has no display name")

	local stats = Units.baseStats(unit)
	for _, field in { "attack", "defense", "health", "speed" } do
		local v = stats[field]
		assert(
			type(v) == "number" and v > 0 and v == v and v ~= math.huge,
			string.format("%s has a bad %s: %s", unit.id, field, tostring(v))
		)
	end
end
expect(string.format("%d units, all valid", count), true, "unique ids, known bands, finite stats")

print("\nThe roll pool never contains something a player cannot roll")
for _, unit in Units.Roster do
	if unit.rarity == "Limited" then
		assert(unit.source ~= "roll", unit.id .. " is Limited but marked rollable")
	end
end
for _, band in Rarities.ASCENDING do
	local pool = Units.rollPool(band)
	-- An empty pool on a rollable band is a live crash: the roll picks the band, then
	-- finds nothing to hand out. Cheaper to fail here than in a player's face.
	expect(
		string.format("%-10s has something to roll", band),
		#pool > 0,
		string.format("%d unit(s)", #pool)
	)
	for _, unit in pool do
		assert(unit.rarity == band, unit.id .. " is in the wrong pool")
		assert(unit.source == "roll", unit.id .. " is not rollable but is in a roll pool")
	end
end
check("Common has a pool too", #Units.rollPool("Common") > 0, true)
check("Limited has none", #Units.rollPool("Limited"), 0)

print("\nMeasured cards reproduce exactly")
--[[
	{ unitId, mutation, attack, health, speed } as READ OFF THE SCREENSHOT.
	Feeding our stored base stats back through the mutation must return these.
]]
local cards = {
	-- The control unit: one unit, three mutations, one level. Everything we know
	-- about mutation multipliers comes from these three rows.
	{ "Ulquiopta", "Normal", 7500, 7500, 2.5 },
	{ "Ulquiopta", "Gold", 11250, 9375, 2.5 },
	{ "Ulquiopta", "Diamond", 16875, 11250, 2.5 },

	-- Clean Mythic cards — no mutation, so these test the stored block directly.
	{ "Acer", "Normal", 360, 3500, 0.6 },
	{ "Hoshira", "Normal", 430, 4165, 0.6 },
	{ "Brocolli", "Normal", 600, 6400, 1.0 },
	{ "Kokushiro", "Normal", 700, 5780, 1.0 },
	{ "Yoriki", "Normal", 1250, 5780, 1.0 },
	{ "Joti", "Normal", 1750, 10000, 1.0 },
	{ "ShimoHaya", "Normal", 7000, 3145, 3.0 },

	-- Clean Secret cards.
	{ "Deyo", "Normal", 420, 14000, 1.0 },
	{ "Jerin", "Normal", 625, 18975, 1.0 },
	{ "Fryren", "Normal", 2000, 5800, 3.5 },
	{ "Yuwah", "Normal", 3000, 8500, 1.0 },
	{ "Gyomain", "Normal", 4000, 25000, 2.0 },

	-- Clean low bands.
	{ "Itadoro", "Normal", 65, 1705, 1.0 },
	{ "Goke", "Normal", 157.5, 1200, 1.1 },

	-- Cards captured UNDER a mutation. These are the round trip: base was recovered
	-- by division, and must multiply back to the photographed number.
	{ "Nonomi", "Diamond", 2137.5, 15000, 0.7 },
	{ "Rengundam", "Diamond", 2025, 11250, 1.2 },
	{ "Kenie", "Diamond", 4725, 27000, 1.8 },
	{ "Kashimi", "Gold", 5250, 15625, 0.8 },
	{ "Mika", "Hollow", 198, 1395, 1.0 },
	{ "Goji", "Hollow", 1125, 4725, 0.8 },
	{ "Sakuna", "Hollow", 1125, 4725, 0.75 },
	{ "Megumo", "Demon", 15000, 17500, 1.0 },
}

for _, card in cards do
	local unitId, mutation, attack, health, speed = card[1], card[2], card[3], card[4], card[5]
	local stats = Power.unitStats(unitId, mutation, 1)
	assert(stats, unitId .. " is not in the roster")
	near(string.format("%s %s atk", unitId, mutation), stats.attack, attack)
	near(string.format("%s %s hp", unitId, mutation), stats.health, health)
	check(string.format("%s %s spd", unitId, mutation), stats.speed, speed)
end

print("\nMutations move attack and health, and NOTHING else")
-- [C] The three Ulquiopta captures all read Speed 2.5 and Defense barely moved.
local base = Power.unitStats("Ulquiopta", "Normal", 1)
for mutationId in pairs(Mutations.Mutations) do
	local mutated = Power.unitStats("Ulquiopta", mutationId, 1)
	assert(mutated.speed == base.speed, mutationId .. " changed speed")
	assert(mutated.defense == base.defense, mutationId .. " changed defense")
end
expect("speed and defense survive every mutation", true, "8 mutations checked")

check("Gold is x1.5 attack", Power.unitStats("Ulquiopta", "Gold", 1).attack / base.attack, 1.5)
check("Gold is x1.25 health", Power.unitStats("Ulquiopta", "Gold", 1).health / base.health, 1.25)
check(
	"Diamond is x2.25 attack",
	Power.unitStats("Ulquiopta", "Diamond", 1).attack / base.attack,
	2.25
)
check(
	"Diamond is x1.5 health",
	Power.unitStats("Ulquiopta", "Diamond", 1).health / base.health,
	1.5
)

print("\nRoles mean something")
--[[
	Not "tanks have more health than damage dealers" unit-by-unit — Gyomain is a Tank
	with more ATTACK than several Damage units, and that is fine. The claim is about
	SHAPE: within a band, tanks carry a lower share of their power in attack.
]]
local function bandShape(band, role)
	local totalAtk, totalHp, n = 0, 0, 0
	for _, unit in Units.Roster do
		if unit.rarity == band and unit.role == role then
			local s = Units.baseStats(unit)
			totalAtk += s.attack
			totalHp += s.health
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return (totalAtk / n) / (totalHp / n)
end

for _, band in { "Mythic", "Secret" } do
	local damageRatio = bandShape(band, "Damage")
	local tankRatio = bandShape(band, "Tank")
	expect(
		string.format("%s tanks are health-shaped, damage is attack-shaped", band),
		damageRatio > tankRatio,
		string.format("atk/hp %.3f vs %.3f", damageRatio, tankRatio)
	)
end

print("\nDPS is the ordering that makes sense of the roster")
-- [D] Kenie has LESS attack than Ulquiopta but 2.4x the health. Reading them as
-- weak/strong gets the game wrong; DPS and effective health are two axes.
local kenie = Units.baseStats(Units.get("Kenie"))
local ulqui = Units.baseStats(Units.get("Ulquiopta"))
expect(
	"Kenie has less attack than Ulquiopta",
	kenie.attack < ulqui.attack,
	string.format("%.0f vs %.0f", kenie.attack, ulqui.attack)
)
expect(
	"but far more health",
	kenie.health > ulqui.health * 2,
	string.format("%.0f vs %.0f", kenie.health, ulqui.health)
)
expect(
	"so neither strictly dominates",
	Units.dps(kenie) < Units.dps(ulqui) and kenie.health > ulqui.health,
	"a tank and a damage dealer, not a weak one and a strong one"
)

print("\nBands still climb, on the median")
local function medianDps(band)
	local values = {}
	for _, unit in Units.Roster do
		if unit.rarity == band then
			table.insert(values, Units.dps(Units.baseStats(unit)))
		end
	end
	table.sort(values)
	return values[math.ceil(#values / 2)]
end

local ladder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
for i = 1, #ladder - 1 do
	local lower, upper = medianDps(ladder[i]), medianDps(ladder[i + 1])
	expect(
		string.format("%-10s -> %-10s", ladder[i], ladder[i + 1]),
		upper > lower,
		string.format("%.0f -> %.0f dps", lower, upper)
	)
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
