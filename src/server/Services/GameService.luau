--!strict
--[[
	The server's game logic: rolling, merging, placing, upgrading, waves.

	Design: docs/planning/architecture.md §1, §6

	NOT VERIFIABLE OUTSIDE STUDIO — it touches Players, remotes and task
	scheduling. Everything it decides, though, comes from the pure modules under
	Shared, which ARE tested. This layer owns ownership checks, replication and
	timing; it owns no rules.

	Every handler here assumes the payload is already rate-limited and
	well-formed — Guard did that. What it must still check is OWNERSHIP, because
	Guard is pure and has no profile to check against.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Upgrades = require(Shared.Config.Upgrades)
local Mutations = require(Shared.Config.Mutations)
local Roll = require(Shared.Gacha.Roll)
local Shop = require(Shared.Gacha.Shop)
local Inventory = require(Shared.Inventory.Inventory)
local Merge = require(Shared.Inventory.Merge)
local Grid = require(Shared.Grid.Grid)
local Wave = require(Shared.Combat.Wave)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local GameService = {}

local TICK_RATE = 0.2

-- Live wave state per player. Not persisted: an interrupted wave is simply lost,
-- which is the honest behaviour — crediting a partial wave would let a player
-- farm gold by disconnecting mid-fight.
local activeWaves: { [Player]: any } = {}

--[[
	Server-side RNG. Never seeded from anything a client can influence, and never
	exposed — architecture.md §1.
]]
local rng = Random.new()
local function nextRandom(): number
	return rng:NextNumber()
end

local function fire(player: Player, remoteName: string, payload: any)
	local remote = Remotes.folder():FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, payload)
	end
end

local function replicate(player: Player)
	local profile = DataService.get(player)
	if profile then
		fire(player, Remotes.TO_CLIENT.ProfileReplicated, profile)
	end
end

-- Current server minute-of-hour, in UTC. architecture.md §5: never client time.
local function serverMinute(): number
	return tonumber(os.date("!*t").min) or 0
end

--[[
	Reroll the shop. FREE, and deliberately so — owner's design.

	It takes no gold, grants nothing, and advances no counter. That last part is the
	one that matters: rerolling is unlimited, so anything this function incremented
	could be farmed by holding the button. Pity therefore lives on `handleBuy`.
]]
function GameService.handleReroll(player: Player): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end

	local luck = Upgrades.Upgrades.Luck.valueAtLevel(profile.upgrades.Luck)
	profile.offers = Shop.reroll(luck, profile.pity, serverMinute(), nextRandom)
	profile.rollCount += 1

	replicate(player)
	return true
end

--[[
	Buy one of the offers on the table.

	The client sends a SLOT, never a unit or a price. Everything about what that
	slot holds and what it costs is read here, from this player's own profile — a
	client that could name the unit or the price would be choosing both.

	ORDER MATTERS: refuse before charging, charge before granting, and refund if the
	grant fails. A full inventory that has already taken the gold is the single most
	infuriating bug this game could ship.
]]
function GameService.handleBuy(player: Player, payload: any): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end

	local index = payload.offerIndex
	local ok, reason = Shop.canBuy(profile.gold, profile.offers, index)
	if not ok then
		return false, reason
	end
	if Inventory.isFull(profile) then
		return false, "inventory full"
	end

	local offer = profile.offers[index]
	profile.gold -= offer.price

	local granted, uidOrError = Inventory.grant(profile, {
		unitId = offer.unitId,
		rarity = offer.rarity,
		mutation = offer.mutation,
		level = 1,
	})
	if not granted then
		profile.gold += offer.price
		return false, uidOrError
	end

	--[[
		PITY TICKS ON PURCHASE, not on reroll.

		Its job is to protect a player from bad luck on gold they actually spent.
		Rerolling is free, so counting rerolls would guarantee Secrets to anyone
		willing to hold the button for a minute. Counting purchases keeps the
		promise pity was always making.
	]]
	local ticked: { [string]: number } = table.clone(profile.pity)
	for tier, remaining in pairs(ticked) do
		ticked[tier] = remaining - 1
	end
	profile.pity = Roll.resetPityUpTo(ticked, offer.rarity)

	profile.stats.totalRolls += 1

	-- The slot is spent. It stays empty until the next reroll, so buying one offer
	-- never silently re-rolls the other two.
	table.remove(profile.offers, index)

	fire(player, Remotes.TO_CLIENT.RollResult, {
		uid = uidOrError,
		unitId = offer.unitId,
		rarity = offer.rarity,
		mutation = offer.mutation,
		price = offer.price,
		pity = profile.pity,
	})
	replicate(player)
	return true
end

function GameService.handleMerge(player: Player, payload: any): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end

	-- Ownership: Guard validated the SHAPE of these uids, not that they are this
	-- player's. Merge.canMerge resolves them against this profile only.
	local ok, reason = Merge.merge(profile, payload.baseUid, payload.consumedUid)
	if not ok then
		return false, reason
	end

	replicate(player)
	return true
end

function GameService.handlePlace(player: Player, payload: any): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end

	local ok, reason = Grid.place(profile, payload.uid, payload.tileIndex)
	if not ok then
		return false, reason
	end

	replicate(player)
	return true
end

function GameService.handleUpgrade(player: Player, payload: any): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end

	local upgrade = Upgrades.Upgrades[payload.upgradeId]
	local level = profile.upgrades[payload.upgradeId]
	if level >= upgrade.maxLevel then
		return false, "already at max level"
	end

	local cost = upgrade.costAtLevel(level)
	if profile.gold < cost then
		return false, string.format("costs %d gold", cost)
	end

	profile.gold -= cost
	profile.upgrades[payload.upgradeId] = level + 1

	-- A shrinking slot count cannot happen here, but pruning is cheap and keeps
	-- the grid invariant true by construction rather than by argument.
	Grid.pruneOutOfBounds(profile)
	replicate(player)
	return true
end

local function beginWave(player: Player, profile: any): (boolean, string?)
	if activeWaves[player] then
		return false, "a wave is already running"
	end
	if Grid.placedCount(profile) == 0 then
		return false, "place at least one unit first"
	end
	activeWaves[player] = Wave.begin(profile, profile.wave)
	return true, nil
end

function GameService.handleWaveStart(player: Player): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end
	return beginWave(player, profile)
end

--[[
	Stop a running wave. The wave is abandoned, not banked — Wave.commit refuses
	anything but a clear, so nothing is paid out. That is deliberate: crediting a
	partial wave would let a player farm gold by starting and stopping.
]]
function GameService.handleWaveStop(player: Player): (boolean?, string?)
	if not activeWaves[player] then
		return false, "no wave is running"
	end
	activeWaves[player] = nil
	replicate(player)
	return true
end

--[[
	[C] The source game has an "Auto" toggle on the wave HUD, and its developers
	recommend AFK farming — so auto-advance lives on the SERVER and keeps running
	whether or not the player is looking at it.
]]
function GameService.handleAutoToggle(player: Player): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end
	profile.autoWave = not profile.autoWave
	replicate(player)
	return true
end

-- Wave 1, or the furthest checkpoint banked. The player's call.
function GameService.handleRestartModeToggle(player: Player): (boolean?, string?)
	local profile = DataService.get(player)
	if not profile then
		return false, "profile not loaded"
	end
	profile.restartAtCheckpoint = not profile.restartAtCheckpoint
	replicate(player)
	return true
end

local function tickWaves(dt: number)
	for player, state in activeWaves do
		local profile = DataService.get(player)
		if not profile then
			activeWaves[player] = nil
			continue
		end

		Wave.tick(state, dt)

		--[[
			The front enemy's health goes on the wire because the client cannot infer
			it. `enemiesLeft` is a count, not a health, so a bar driven from it would
			sit at full until the enemy vanished — which is exactly what the first
			playtest showed. Two numbers is the whole cost, and it is what makes the
			boss bar honest.

			[C] The source game shows this same pair as raw numbers, e.g.
			"Jigi 6604153.7/8030480.2 HP".
		]]
		local front = Wave.frontLiving(state.enemies)

		--[[
			THE WHOLE BATTLE GOES ON THE WIRE, not just the totals.

			Counts are enough to write "4/6 enemies" in a label, and that is all the
			client could draw before: units stood still at full health and never fell
			over, so a wave looked like a number changing rather than a fight. You
			could lose four units and see nothing.

			The cost is bounded and small — at most 12 units and 10 enemies, three
			numbers each, five times a second. That is cheaper than almost any visual
			effect it pays for, and it is the difference between an idle game you
			watch and an idle game you ignore.
		]]
		local squadState = table.create(#state.squad)
		for _, c in state.squad do
			table.insert(squadState, { uid = c.id, hp = c.hp, maxHp = c.maxHp })
		end
		local enemyState = table.create(#state.enemies)
		for _, c in state.enemies do
			table.insert(enemyState, { hp = c.hp, maxHp = c.maxHp })
		end

		fire(player, Remotes.TO_CLIENT.WaveTick, {
			wave = state.wave,
			outcome = state.outcome,
			elapsed = state.elapsed,
			goldEarned = state.goldEarned,
			enemiesLeft = Wave.livingCount(state.enemies),
			enemyTotal = #state.enemies,
			unitsLeft = Wave.livingCount(state.squad),
			frontHp = front and front.hp or 0,
			frontMaxHp = front and front.maxHp or 0,
			squad = squadState,
			enemies = enemyState,
		})

		if state.outcome ~= "running" then
			local cleared = state.outcome == "cleared"
			if cleared then
				Wave.commit(profile, state)
			else
				-- Losing sends the player back to their restart point. Gold, units
				-- and upgrades all survive; only position is lost.
				Wave.commitLoss(profile, state)
			end
			activeWaves[player] = nil
			replicate(player)

			-- Auto only chains on a CLEAR. A failed wave stops, so a player who has
			-- outrun their squad is told rather than silently looped forever.
			if cleared and profile.autoWave then
				beginWave(player, profile)
			end
		end
	end
end

-- Announce the mutation rotation when the window changes, so clients can show
-- what is currently rollable without polling.
local function watchEventClock()
	local last: string? = nil
	while true do
		local active = Mutations.activeEventMutation(serverMinute())
		if active ~= last then
			last = active
			for _, player in Players:GetPlayers() do
				fire(player, Remotes.TO_CLIENT.EventClockChanged, {
					activeMutation = active,
					minute = serverMinute(),
				})
			end
		end
		task.wait(5)
	end
end

local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)
	if not profile then
		-- Refusing beats overwriting. The player can rejoin; a clobbered save
		-- cannot be recovered.
		player:Kick("Could not load your save. Please rejoin in a moment.")
		return
	end
	replicate(player)
end

function GameService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	--[[
		PlayerAdded only fires for players who join AFTER the connection exists.
		In Studio Play Solo the local player is already in the game before the
		server finishes booting, so without this sweep their profile is never
		loaded and the client waits forever on a replication that never comes.

		This is not Studio-only paranoia: on a live server the same race can lose
		the first player to join a fresh server instance.
	]]
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		activeWaves[player] = nil
	end)

	task.spawn(function()
		while true do
			tickWaves(TICK_RATE)
			task.wait(TICK_RATE)
		end
	end)

	task.spawn(watchEventClock)
end

GameService.rarityOrder = Rarities.ASCENDING

return GameService
