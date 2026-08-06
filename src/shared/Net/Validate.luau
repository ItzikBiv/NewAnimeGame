--!strict
--[[
	Remote argument validation. Story 1.7.

	Design: docs/planning/architecture.md §3.1, §7

	PURE MODULE. Every C->S remote's payload passes through here before a service
	sees it.

	The threat this exists for: on Roblox a client can fire any RemoteEvent with
	ANY arguments — nil, NaN, a table where a number belongs, a uid belonging to
	another player, a tile index of 1e308. Luau will happily carry all of that into
	game logic and produce nonsense rather than an error.

	So every validator here is a DENYLIST-free allowlist: it states exactly what
	shape is acceptable and rejects everything else, rather than trying to enumerate
	what an attacker might send.

	Ownership is checked in the services, not here — this module is pure and has no
	profile. Validation answers "is this well-formed?"; the service answers "is this
	yours?".
]]

-- NaN is the one value that fails every comparison including equality with
-- itself, so it slips past naive range checks. Catch it explicitly.
local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false -- NaN
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 1 and value == math.floor(value)
end

-- Uids are server-issued and always "u" followed by digits. Anything else is
-- forged, and bounding the length stops a megabyte string being used to make the
-- server do pattern-matching work.
-- Generous upper bound on an offer slot. The shop offers 3; this only has to be
-- small enough that a hostile index cannot be used to probe, and large enough that
-- growing the shop does not silently start rejecting valid clicks.
local MAX_OFFER_INDEX = 16

local MAX_UID_LENGTH = 32

local function isUid(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	if #value < 2 or #value > MAX_UID_LENGTH then
		return false
	end
	return string.match(value, "^u%d+$") ~= nil
end

export type Validator = (payload: any) -> (boolean, string?)

local validators: { [string]: Validator } = {
	--[[
		[C] RequestReroll takes NO arguments — architecture.md §3.1. There is no field
		to tamper with; the server reads gold and luck from its own state. Anything
		sent is either a bug or a probe, and both deserve rejection.
	]]
	RequestReroll = function(payload: any): (boolean, string?)
		if payload ~= nil then
			return false, "RequestReroll takes no arguments"
		end
		return true, nil
	end,

	--[[
		RequestBuy names an OFFER SLOT, never a unit and never a price.

		Same rule as everywhere else here: the payload carries intent, and the server
		looks up what that slot actually holds. A client able to send a unit id or a
		price would be choosing what it buys and what it pays.

		The bound below is a SHAPE check, not the real rule. This module stays free of
		game imports on purpose — it must be able to reject a malformed payload
		without knowing anything about shops — so it only rejects indices that could
		never be a slot. Whether slot 3 currently holds anything is `Shop.canBuy`'s
		call, on the server, against that player's actual offers.
	]]
	RequestBuy = function(payload: any): (boolean, string?)
		if type(payload) ~= "table" then
			return false, "expected a table"
		end
		if not isPositiveInteger(payload.offerIndex) then
			return false, "invalid offerIndex"
		end
		if payload.offerIndex > MAX_OFFER_INDEX then
			return false, "offerIndex out of range"
		end
		return true, nil
	end,

	RequestMerge = function(payload: any): (boolean, string?)
		if type(payload) ~= "table" then
			return false, "expected a table"
		end
		if not isUid(payload.baseUid) then
			return false, "invalid baseUid"
		end
		if not isUid(payload.consumedUid) then
			return false, "invalid consumedUid"
		end
		if payload.baseUid == payload.consumedUid then
			return false, "baseUid and consumedUid are the same"
		end
		return true, nil
	end,

	RequestPlace = function(payload: any): (boolean, string?)
		if type(payload) ~= "table" then
			return false, "expected a table"
		end
		if not isUid(payload.uid) then
			return false, "invalid uid"
		end
		-- The real bound is the player's Slot Upgrade, checked by Grid.place. Here
		-- we only reject values that are not plausibly a tile at all, so a hostile
		-- 1e308 never reaches game logic.
		if not isPositiveInteger(payload.tileIndex) or payload.tileIndex > 64 then
			return false, "invalid tileIndex"
		end
		return true, nil
	end,

	RequestUpgrade = function(payload: any): (boolean, string?)
		if type(payload) ~= "table" then
			return false, "expected a table"
		end
		local id = payload.upgradeId
		if type(id) ~= "string" then
			return false, "invalid upgradeId"
		end
		if id ~= "Gold" and id ~= "Luck" and id ~= "Slot" and id ~= "Inventory" then
			return false, "unknown upgradeId: " .. id
		end
		return true, nil
	end,

	RequestWaveStart = function(payload: any): (boolean, string?)
		if payload ~= nil then
			return false, "RequestWaveStart takes no arguments"
		end
		return true, nil
	end,

	RequestWaveStop = function(payload: any): (boolean, string?)
		if payload ~= nil then
			return false, "RequestWaveStop takes no arguments"
		end
		return true, nil
	end,

	-- Toggle, not set: the client cannot assert which state it wants, only that
	-- it wants the other one. Nothing to forge.
	RequestAutoToggle = function(payload: any): (boolean, string?)
		if payload ~= nil then
			return false, "RequestAutoToggle takes no arguments"
		end
		return true, nil
	end,

	RequestRestartModeToggle = function(payload: any): (boolean, string?)
		if payload ~= nil then
			return false, "RequestRestartModeToggle takes no arguments"
		end
		return true, nil
	end,
}

--[[
	Validate a payload for a named remote.

	An UNKNOWN remote name is rejected. Failing closed is the point: a remote added
	without a validator should stop working loudly rather than accept anything
	quietly.
]]
local function validate(remoteName: string, payload: any): (boolean, string?)
	local validator = validators[remoteName]
	if not validator then
		return false, "no validator for remote: " .. tostring(remoteName)
	end
	return validator(payload)
end

return {
	validate = validate,
	validators = validators,
	isUid = isUid,
	isFiniteNumber = isFiniteNumber,
	isPositiveInteger = isPositiveInteger,
	MAX_UID_LENGTH = MAX_UID_LENGTH,
}
