--!strict
--[[
	Wave simulation. Story 1.5.

	Design: docs/planning/gdd.md §3, §5 · docs/planning/epics.md story 1.5

	PURE MODULE. `begin` builds a battle from a profile, `tick` advances it by a
	time step, and neither touches a service or a clock. The server owns timing and
	replication; this owns what happens.

	Being pure is what lets `simulate` run a whole wave in a loop with no waiting,
	so balance can be checked in CI rather than by playing.

	COMBAT MODEL — [C] EVERYONE FIGHTS AT ONCE. Owner: "make every team fight at the
	same time not one by one".

	Every living unit picks its own target and deals damage on the same tick, and so
	does every living enemy. Both sides resolve from the state at the START of the
	step, so neither gets a free hit from being processed first.

	This replaces focus-fire, where the whole squad hammered one enemy and the whole
	enemy line hammered one unit. Focus-fire is easy to reason about but it renders
	as a duel with an audience: eleven of your twelve units had nothing to do, and a
	twelve-unit board looked exactly like a one-unit board.

	TARGETING is round-robin over the living. Attacker `i` hits living defender
	`((i-1) mod n) + 1`. Two properties matter:

	  * damage spreads, so a wide board actually kills faster, and
	  * when a defender dies the list shrinks and its attackers RETARGET on the next
	    tick, so nobody stands idle swinging at a corpse.

	HEALTH PERSISTS between waves — see `Schema.StoredUnit.hp`. A wave is attrition,
	not a fresh squad, and only a LOSS heals the board.
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
	-- Enemy ids already paid out. With everyone attacking at once, several enemies
	-- can die on the same tick and any of them can die on a tick where the code is
	-- not looking at it — so payment is tracked per enemy rather than inferred.
	paid: { [string]: boolean },
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
			local maxHp, dps
			if stats then
				maxHp = stats.health
				dps = stats.attack * stats.speed
			else
				maxHp = Power.health(unit.rarity, unit.mutation, unit.level)
				dps = Power.dps(unit.rarity, unit.mutation, unit.level)
			end

			--[[
				Start from the health this unit ENDED the last wave on, not from full.

				Clamped to maxHp because a merge or an upgrade can raise a unit's
				ceiling between waves; a stored value above the new maximum would show
				a bar past the end of its track.
			]]
			local hp = if unit.hp ~= nil then math.clamp(unit.hp, 0, maxHp) else maxHp
			table.insert(squad, { id = uid, hp = hp, maxHp = maxHp, dps = dps })
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
		paid = {},
	}
end

-- The living members of a side, in board order. Rebuilt each tick so that a death
-- immediately changes who everyone is aiming at.
local function living(side: { Combatant }): { Combatant }
	local out: { Combatant } = {}
	for _, c in side do
		if c.hp > 0 then
			table.insert(out, c)
		end
	end
	return out
end

--[[
	Apply one side's damage, spread across the other side.

	Attacker `i` hits living defender `((i-1) mod n) + 1`. With more attackers than
	defenders the extra attackers wrap around and double up; with fewer, some
	defenders are untouched this tick. Both are the honest outcome of everyone
	swinging at once.

	Damage is ACCUMULATED into a side table rather than applied in place, because
	the caller resolves both sides from the state at the start of the step. Writing
	straight into `defenders` would let a unit killed by this side's damage stop
	dealing its own — a free hit for whichever side happened to be processed first.
]]
local function dealDamage(
	attackers: { Combatant },
	defenders: { Combatant },
	dt: number,
	into: { [Combatant]: number }
)
	local targets = living(defenders)
	if #targets == 0 then
		return
	end
	for index, attacker in living(attackers) do
		local target = targets[((index - 1) % #targets) + 1]
		into[target] = (into[target] or 0) + attacker.dps * dt
	end
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

	-- Settle an already-decided battle before anyone swings.
	if livingCount(state.enemies) == 0 then
		state.outcome = "cleared"
		return state
	end
	if livingCount(state.squad) == 0 then
		state.outcome = "failed"
		return state
	end

	local incoming: { [Combatant]: number } = {}
	dealDamage(state.squad, state.enemies, dt, incoming)
	dealDamage(state.enemies, state.squad, dt, incoming)

	-- Now apply it. Every combatant on both sides took its damage from the same
	-- snapshot, so two combatants that would kill each other this tick both die.
	for combatant, damage in incoming do
		combatant.hp -= damage
		if combatant.hp <= 0 then
			combatant.hp = 0
		end
	end

	-- Gold is paid per enemy that died THIS tick, once. Counting survivors instead
	-- of tracking deaths would pay again on every later tick.
	for _, enemy in state.enemies do
		if enemy.hp <= 0 and not state.paid[enemy.id] then
			state.paid[enemy.id] = true
			state.goldEarned += math.floor(Waves.goldPerKill(state.wave) * state.goldMultiplier)
		end
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

	--[[
		CARRY THE DAMAGE FORWARD. Owner: "dont revive the units each turn".

		A wave you barely survived leaves you weaker for the next one, which is what
		makes a run a run rather than a sequence of independent fights. Only a LOSS
		heals the board — see commitLoss — so there is always a way back, and the
		player chooses when to take it.
	]]
	for _, combatant in state.squad do
		local unit = profile.inventory[combatant.id]
		if unit then
			unit.hp = combatant.hp
		end
	end

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

	--[[
		A loss heals everything. This is the ONLY thing that does.

		Without it, damage carried across waves is a one-way ratchet into a save that
		can never win another fight: your squad is dead, a dead squad loses instantly,
		and losing does not help. Healing here turns "you lost" into a real reset —
		you give up the waves you had climbed and get your squad back.
	]]
	for _, unit in pairs(profile.inventory) do
		unit.hp = nil
	end
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
