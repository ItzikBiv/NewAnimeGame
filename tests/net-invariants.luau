--!nocheck
--[[
	Rate limiting and remote validation — story 1.7, the pure half.

	This suite is adversarial by design. Every other suite asks "does the happy
	path work?"; this one asks "what happens when the client is hostile?" — which
	on Roblox is the realistic assumption, since a client can fire any RemoteEvent
	with any arguments at any rate.

	Expects globals: ... RateLimit, Validate.
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

print("A burst is allowed, a flood is not")
local buckets = {}
local allowedInBurst = 0
for _ = 1, 10 do
	if RateLimit.check(buckets, "RequestRoll", 0) then
		allowedInBurst += 1
	end
end
check("the full burst capacity gets through", allowedInBurst, RateLimit.LIMITS.RequestRoll.capacity)

local blocked, waitFor = RateLimit.check(buckets, "RequestRoll", 0)
expect("the next call is refused", not blocked, string.format("retry in %.2fs", waitFor))
expect(
	"and it says how long to wait",
	waitFor and waitFor > 0,
	"clients can back off instead of hammering"
)

print("\nTokens refill over time")
local refilled = RateLimit.check(buckets, "RequestRoll", 0.25)
expect(
	"a quarter second buys one token back",
	refilled,
	string.format("at %d/sec", RateLimit.LIMITS.RequestRoll.refillPerSecond)
)

local full = {}
RateLimit.check(full, "RequestRoll", 0)
local afterLongIdle = 0
for _ = 1, 20 do
	if RateLimit.check(full, "RequestRoll", 1000) then
		afterLongIdle += 1
	end
end
check(
	"a long idle refills to capacity, no further",
	afterLongIdle,
	RateLimit.LIMITS.RequestRoll.capacity
)

print("\nA sustained flood is throttled to the configured rate")
-- One second of a script calling as fast as it can.
local flood = {}
local got = 0
for i = 1, 1000 do
	if RateLimit.check(flood, "RequestRoll", i / 1000) then
		got += 1
	end
end
local limit = RateLimit.LIMITS.RequestRoll
expect(
	"1000 calls in one second yield only capacity + one second of refill",
	got <= limit.capacity + limit.refillPerSecond + 1,
	string.format("%d of 1000 allowed", got)
)

print("\nEach remote has its own bucket")
local shared = {}
for _ = 1, RateLimit.LIMITS.RequestRoll.capacity do
	RateLimit.check(shared, "RequestRoll", 0)
end
expect("exhausting rolls does not block merges", (RateLimit.check(shared, "RequestMerge", 0)))
expect("but rolls stay blocked", not (RateLimit.check(shared, "RequestRoll", 0)))

print("\nAn unknown remote is throttled by default, not left open")
local unknownLimit = RateLimit.limitFor("SomeRemoteNobodyConfigured")
check("falls back to the default capacity", unknownLimit.capacity, RateLimit.DEFAULT_LIMIT.capacity)
expect(
	"failing closed beats failing convenient",
	unknownLimit.capacity < RateLimit.LIMITS.RequestMerge.capacity,
	"a new remote is limited by omission, not unlimited"
)

print("\nTime going backwards cannot mint tokens")
-- Clocks are not guaranteed monotonic across a server's life.
local backwards = {}
for _ = 1, RateLimit.LIMITS.RequestRoll.capacity do
	RateLimit.check(backwards, "RequestRoll", 100)
end
expect(
	"a rewound clock does not refill the bucket",
	not (RateLimit.check(backwards, "RequestRoll", 0)),
	"elapsed time is clamped at zero"
)

print("\nRequestRoll accepts no arguments at all")
-- [C] architecture.md §3.1 — there is no field to tamper with.
expect("nil is accepted", (Validate.validate("RequestRoll", nil)))
for _, hostile in { {}, { luck = 999 }, 42, "gimme", true } do
	local ok = Validate.validate("RequestRoll", hostile)
	expect(string.format("payload %-12s is rejected", "`" .. tostring(hostile) .. "`"), not ok)
end

print("\nUid validation rejects everything that is not a server-issued uid")
expect("a real uid passes", Validate.isUid("u1"))
expect("a long real uid passes", Validate.isUid("u123456"))
for _, forged in
	{
		"",
		"u",
		"x1",
		"u1x",
		"1",
		"u-1",
		"u 1",
		"u1; DROP",
		"../../etc/passwd",
		42,
		true,
		{},
	}
do
	expect(
		string.format("%-18s is rejected", "`" .. tostring(forged) .. "`"),
		not Validate.isUid(forged)
	)
end
expect(
	"an absurdly long string is rejected on length",
	not Validate.isUid("u" .. string.rep("9", 100)),
	"bounded before pattern matching"
)

print("\nNaN and infinity cannot slip through numeric checks")
-- NaN fails every comparison including equality with itself, so naive range checks
-- let it through and it then poisons every arithmetic result downstream.
expect("NaN is not a finite number", not Validate.isFiniteNumber(0 / 0))
expect("infinity is not finite", not Validate.isFiniteNumber(math.huge))
expect("negative infinity is not finite", not Validate.isFiniteNumber(-math.huge))
expect("NaN is not a positive integer", not Validate.isPositiveInteger(0 / 0))
expect("a real integer is", Validate.isPositiveInteger(3))
expect("a fraction is not", not Validate.isPositiveInteger(1.5))
expect("zero is not", not Validate.isPositiveInteger(0))
expect("negative is not", not Validate.isPositiveInteger(-1))

print("\nRequestPlace rejects hostile tile indices")
expect(
	"a valid placement passes",
	(Validate.validate("RequestPlace", { uid = "u1", tileIndex = 3 }))
)
for _, tile in { 0, -1, 1.5, 1e308, 0 / 0, math.huge, "3", {} } do
	local ok = Validate.validate("RequestPlace", { uid = "u1", tileIndex = tile })
	expect(string.format("tileIndex %-8s rejected", tostring(tile)), not ok)
end
-- Tested separately: a trailing nil in a Lua array literal is not iterated, so
-- putting it in the list above would have silently skipped the single most likely
-- malformed payload of all — a missing field.
expect(
	"a missing tileIndex is rejected",
	not (Validate.validate("RequestPlace", { uid = "u1" })),
	"the most likely malformed payload"
)
expect(
	"a missing uid is rejected",
	not (Validate.validate("RequestPlace", { tileIndex = 1 })),
	"and its counterpart"
)
expect("an entirely empty payload is rejected", not (Validate.validate("RequestPlace", {})))

print("\nRequestMerge rejects malformed and self-referential merges")
expect(
	"a valid merge passes",
	(Validate.validate("RequestMerge", { baseUid = "u1", consumedUid = "u2" }))
)
local sameOk, sameWhy = Validate.validate("RequestMerge", { baseUid = "u1", consumedUid = "u1" })
expect("merging a unit into itself is rejected", not sameOk, sameWhy)
expect("a missing field is rejected", not (Validate.validate("RequestMerge", { baseUid = "u1" })))
expect("a non-table is rejected", not (Validate.validate("RequestMerge", "u1,u2")))

print("\nRequestUpgrade only accepts the four real upgrades")
for _, id in { "Gold", "Luck", "Slot", "Inventory" } do
	expect(
		string.format("%-10s accepted", id),
		(Validate.validate("RequestUpgrade", { upgradeId = id }))
	)
end
for _, id in { "gold", "Godmode", "", "Gold ", 42 } do
	expect(
		string.format("%-10s rejected", "`" .. tostring(id) .. "`"),
		not (Validate.validate("RequestUpgrade", { upgradeId = id }))
	)
end

print("\nAn unregistered remote is rejected outright")
local unknownOk, unknownWhy = Validate.validate("RequestFreeGold", {})
expect("no validator means no entry", not unknownOk, unknownWhy)
expect(
	"a remote added without a validator fails loudly",
	not (Validate.validate("SomeNewRemote", nil)),
	"rather than accepting anything quietly"
)

print("\nEvery configured remote has both a limit and a validator")
-- The two must not drift apart: a remote with a validator but no limit is
-- floodable, and one with a limit but no validator accepts garbage.
for remoteName in pairs(RateLimit.LIMITS) do
	expect(
		string.format("%-18s has a validator", remoteName),
		Validate.validators[remoteName] ~= nil
	)
end
for remoteName in pairs(Validate.validators) do
	expect(string.format("%-18s has a rate limit", remoteName), RateLimit.LIMITS[remoteName] ~= nil)
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
	error(string.format("%d check(s) failed", fail))
end
