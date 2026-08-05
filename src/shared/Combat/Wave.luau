--!strict
--[[
	Wave simulation. Story 1.5.

	Design: docs/planning/gdd.md §3, §5 · docs/planning/epics.md story 1.5

	PURE MODULE. `begin` builds a battle from a profile, `tick` advances it by a
	time step, and neither touches a service or a clock. The server owns timing and
	replication; this owns what happens.

	Being pure is what lets `simulate` run a whole wave in a loop with no waiting,
	so balance can be checked in CI rather than by playing.

	COMBAT MODEL — deliberately simple, and [OURS] where the source game is silent.
	Both sides focus-fire the front-most living target. That is the readable
	behaviour for an idle auto-battler: the player watches a line advance and fall.
	Aggregate-DPS-versus-total-HP would be simpler still, but it makes tanks and
	unit death meaningless, and the Ghost trait proves units die.
]]

local Waves = require(script.Parent.Parent.Config.Waves)
local Power = require(script.Parent.Parent.Config.Power)
local Grid = require(script.Parent.Parent.Grid.Grid)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)

export type Combatant = {
	-- Unit uid for the player's side; a generated id for enemies.
	id: string,
	hp: number,
	maxHp: number,
	dps: number,
}

export type Outcome = "running" | "cleared" | "failed"

export type WaveState = {
	wave: number,
	squad: { Combatant },
	enemies: { Combatant },
	goldEarned: number,
	elapsed: number,
	outcome: Outcome,
	-- Gold multiplier from the player's Gold Upgrade, captured at wave start so a
	-- mid-wave upgrade cannot retroactively repay earlier kills.
	goldMultiplier: number,
}

-- The front-most living combatant, or nil when the side is wiped out.
local function frontLiving(side: { Combatant }): Combatant?
	for _, c in side do
		if c.hp > 0 then
			return c
		end
	end
	return nil
end

local function livingCount(side: { Combatant }): number
	local n = 0
	for _, c in side do
		if c.hp > 0 then
			n += 1
		end
	end
	return n
end

--[[
	Build the squad from whatever is actually on the grid.

	Reads placements through `Grid.fieldedUids`, so a unit in the inventory but not
	placed contributes nothing — the placement decision has to matter.
]]
local function buildSquad(profile: any): { Combatant }
	local squad: { Combatant } = {}
	for _, uid in Grid.fieldedUids(profile) do
		local unit = profile.inventory[uid]
		if unit then
			--[[
				A rostered unit fights with its OWN authored stats. Only a unit with
				no roster entry falls back to the rarity ladder — which in practice
				means synthetic units built by balance tests, never anything a player
				can own, because every roll draws from the roster.
			]]
			local stats = Power.unitStats(unit.unitId, unit.mutation, unit.level)
			local hp, dps
			if stats then
				hp = stats.health
				dps = stats.attack * stats.speed
			else
				hp = Power.health(unit.rarity, unit.mutation, unit.level)
				dps = Power.dps(unit.rarity, unit.mutation, unit.level)
			end
			table.insert(squad, { id = uid, hp = hp, maxHp = hp, dps = dps })
		end
	end
	return squad
end

local function buildEnemies(wave: number): { Combatant }
	local enemies: { Combatant } = {}
	local hp = Waves.enemyHP(wave)
	local dps = Waves.enemyDamage(wave)
	for i = 1, Waves.enemyCount(wave) do
		table.insert(enemies, {
			id = string.format("e%d_%d", wave, i),
			hp = hp,
			maxHp = hp,
			dps = dps,
		})
	end
	return enemies
end

local function begin(profile: any, wave: number): WaveState
	local goldLevel = profile.upgrades.Gold
	return {
		wave = wave,
		squad = buildSquad(profile),
		enemies = buildEnemies(wave),
		goldEarned = 0,
		elapsed = 0,
		-- A squad of nobody cannot clear anything.
		outcome = "running",
		goldMultiplier = Upgrades.Upgrades.Gold.valueAtLevel(goldLevel),
	}
end

--[[
	Advance the battle by `dt` seconds.

	Both sides deal damage from the state at the START of the step, so neither gets
	a free hit from being resolved first. Without that, whichever side the code
	happened to process first would win every near-tie.
]]
local function tick(state: WaveState, dt: number): WaveState
	if state.outcome ~= "running" then
		return state
	end

	local squadTarget = frontLiving(state.enemies)
	local enemyTarget = frontLiving(state.squad)

	-- No enemies left: the wave is already won.
	if not squadTarget then
		state.outcome = "cleared"
		return state
	end
	-- No units left: the wave is lost.
	if not enemyTarget then
		state.outcome = "failed"
		return state
	end

	local squadDps = 0
	for _, c in state.squad do
		if c.hp > 0 then
			squadDps += c.dps
		end
	end

	local enemyDps = 0
	for _, c in state.enemies do
		if c.hp > 0 then
			enemyDps += c.dps
		end
	end

	-- Damage is dealt simultaneously, then deaths are resolved.
	squadTarget.hp -= squadDps * dt
	enemyTarget.hp -= enemyDps * dt

	if squadTarget.hp <= 0 then
		squadTarget.hp = 0
		state.goldEarned += math.floor(Waves.goldPerKill(state.wave) * state.goldMultiplier)
	end
	if enemyTarget.hp <= 0 then
		enemyTarget.hp = 0
	end

	state.elapsed += dt

	if livingCount(state.enemies) == 0 then
		state.outcome = "cleared"
	elseif livingCount(state.squad) == 0 then
		state.outcome = "failed"
	end

	return state
end

--[[
	Run a wave to completion. For tests and balance work — the live server ticks
	instead, so it can replicate each step.

	`maxSeconds` bounds the run so a squad too weak to out-damage nothing cannot
	spin forever.
]]
local function simulate(profile: any, wave: number, dt: number?, maxSeconds: number?): WaveState
	local step = dt or 0.1
	local limit = maxSeconds or 600
	local state = begin(profile, wave)

	while state.outcome == "running" and state.elapsed < limit do
		tick(state, step)
	end

	return state
end

--[[
	Apply a cleared wave to the profile: bank the gold, advance the counter, and
	update the lifetime stats behind the leaderboard.

	Refuses anything but a clear, so a failed wave can never pay out.
]]
local function commit(profile: any, state: WaveState): (boolean, string?)
	if state.outcome ~= "cleared" then
		return false, "wave not cleared: " .. state.outcome
	end

	profile.gold += state.goldEarned
	profile.wave = state.wave + 1

	-- Clearing a checkpoint wave banks it permanently.
	if Waves.isCheckpointWave(state.wave) then
		profile.checkpointWave = math.max(profile.checkpointWave or 1, state.wave)
	end

	if profile.wave > profile.stats.highestWave then
		profile.stats.highestWave = profile.wave
	end
	if profile.gold > profile.stats.highestGold then
		profile.stats.highestGold = profile.gold
	end

	return true, nil
end

--[[
	Apply a LOST wave: send the player back to their restart point.

	Which point is the player's setting — wave 1, or the furthest checkpoint they
	banked. Nothing is taken away except position; gold, units and upgrades all
	survive a loss.
]]
local function commitLoss(profile: any, state: WaveState): (boolean, string?)
	if state.outcome ~= "failed" then
		return false, "wave was not lost: " .. state.outcome
	end
	profile.wave = if profile.restartAtCheckpoint
		then math.max(profile.checkpointWave or 1, 1)
		else 1
	return true, nil
end

return {
	begin = begin,
	commitLoss = commitLoss,
	tick = tick,
	simulate = simulate,
	commit = commit,
	buildSquad = buildSquad,
	buildEnemies = buildEnemies,
	frontLiving = frontLiving,
	livingCount = livingCount,
}
