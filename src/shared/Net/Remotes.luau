--!strict
--[[
	Remote definitions — the single place client and server agree on names.

	Design: docs/planning/architecture.md §3.1

	Names live here so `RateLimit.LIMITS`, `Validate.validators` and the actual
	RemoteEvents cannot drift apart. The test suite already asserts the first two
	agree; `assertCoverage` below lets the server assert all three at boot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Client -> Server. Intent only, never outcome.
local TO_SERVER = {
	RequestRoll = "RequestRoll",
	RequestMerge = "RequestMerge",
	RequestPlace = "RequestPlace",
	RequestUpgrade = "RequestUpgrade",
	RequestWaveStart = "RequestWaveStart",
	RequestWaveStop = "RequestWaveStop",
	RequestAutoToggle = "RequestAutoToggle",
	RequestRestartModeToggle = "RequestRestartModeToggle",
}

-- Server -> Client.
local TO_CLIENT = {
	ProfileReplicated = "ProfileReplicated",
	ProfileDelta = "ProfileDelta",
	RollResult = "RollResult",
	WaveTick = "WaveTick",
	EventClockChanged = "EventClockChanged",
	ActionRejected = "ActionRejected",
}

local FOLDER_NAME = "Remotes"

--[[
	Server-side: create the folder and every RemoteEvent under it.
	Idempotent, so a hot reload does not duplicate anything.
]]
local function build(): Folder
	assert(RunService:IsServer(), "Remotes.build must run on the server")

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, name in TO_SERVER do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in TO_CLIENT do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	return folder :: Folder
end

-- Client-side: wait for the folder the server built.
local function folder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function get(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

--[[
	Assert every client->server remote has both a rate limit and a validator.

	Called at server boot. A remote that reaches a service without passing both is
	either floodable or accepts garbage, and finding that out at boot beats finding
	it out from a player.
]]
local function assertCoverage(limits: { [string]: any }, validators: { [string]: any })
	for _, name in TO_SERVER do
		assert(limits[name], "remote has no rate limit: " .. name)
		assert(validators[name], "remote has no validator: " .. name)
	end
end

return {
	TO_SERVER = TO_SERVER,
	TO_CLIENT = TO_CLIENT,
	FOLDER_NAME = FOLDER_NAME,
	build = build,
	folder = folder,
	get = get,
	assertCoverage = assertCoverage,
}
