--!strict
--[[
	The 3D arena — the board the player actually looks at.

	Design: docs/planning/gdd.md §3 · docs/ground-truth/source-game-teardown.md

	[C] The board is two facing banks of tiles: the player fields units on BLUE tiles
	    (4 to start, 12 at max Slot upgrade) and enemies occupy 16 RED tiles opposite.
	    Owner, describing the source game: "you start with 4 slots to put anime on
	    them and you can get more in upgrades till 12 and the enemies are on the 16
	    slots against you in the red slots".

	BUILT ON THE CLIENT, ON PURPOSE. Every player has their own wave counter, their
	own grid and their own squad — nobody else's board is relevant to them. Building
	it here means no replication traffic, no per-player base allocation in Workspace,
	and no way for one player's render to affect another's. The server still owns
	every number; this module only draws what it is told.

	That also means NOTHING here may decide anything. It reads the replicated profile
	and the wave tick and turns them into parts. If a value is not in one of those, it
	does not belong in this file.

	NOT VERIFIABLE HEADLESSLY. It touches Workspace, Camera and Instance — the test
	harness runs under plain Luau with no Roblox runtime. What it renders comes from
	Shared modules that ARE tested; the drawing itself needs eyes on it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Units = require(Shared.Config.Units)
local Upgrades = require(Shared.Config.Upgrades)

local Arena = {}

-- ── Layout ──────────────────────────────────────────────────────────────────
-- Studs. The two banks face each other down +Z, with the camera behind the player
-- side looking across, so "forward" is the direction enemies come from.
local TILE = 8
local GAP = 1.5
local PITCH = TILE + GAP

-- [C] 12 player slots at max, 16 enemy slots.
local PLAYER_COLUMNS = 6
local PLAYER_ROWS = 2
local ENEMY_COLUMNS = 4
local ENEMY_ROWS = 4

local LANE_DEPTH = 26 -- empty ground between the two banks
local FLOOR_Y = 0
local TILE_HEIGHT = 1

local ARENA_ORIGIN = Vector3.new(0, FLOOR_Y, 0)

local COLOUR_PLAYER_TILE = Color3.fromRGB(40, 90, 190)
local COLOUR_PLAYER_TILE_LOCKED = Color3.fromRGB(55, 58, 66)
local COLOUR_ENEMY_TILE = Color3.fromRGB(170, 40, 45)
local COLOUR_FLOOR = Color3.fromRGB(28, 30, 38)
local COLOUR_SELECTED = Color3.fromRGB(255, 210, 70)

local folder: Folder
local playerTiles: { BasePart } = {}
local enemyTiles: { BasePart } = {}
local unitModels: { [number]: Model } = {} -- keyed by tile index
local enemyModels: { Model } = {}

-- uid -> tile index, rebuilt on every renderProfile. The wave tick identifies squad
-- members by uid; the board indexes them by tile. This is the join between the two.
local tileForUid: { [string]: number } = {}

-- Per-tile liveness from the last tick, and each unit's colour before it died, so a
-- revived or replaced unit is restored rather than left grey.
local deadTiles: { [number]: boolean } = {}
local originalColour: { [number]: Color3 } = {}

local selectedTile: number? = nil
local onTileClicked: ((tileIndex: number) -> ())? = nil

-- ── Small builders ──────────────────────────────────────────────────────────

local function make(class: string, props: { [string]: any }): any
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		(instance :: any)[key] = value
	end
	return instance
end

--[[
	Where a tile sits in the world.

	Tile 1 is the tile the player reads FIRST: screen-left, on the rank facing the
	enemy. Indices then run left-to-right, front rank before back rank. `Grid` hands
	out indices 1..slots and the inventory panel lists them in that order, so the
	board has to agree with the panel or the two views describe different games.

	THE X AXIS IS NEGATED, and that is not arbitrary. The camera sits at -Z looking
	toward +Z, and under that view +X falls on the LEFT of the screen. Computing x
	the obvious way mirrored the whole rank: the first playtest put tile 1 on the
	right, so the panel read Legendary, Epic, Epic, Secret while the board showed
	Secret, Epic, Epic, Legendary. Negating x puts increasing index on increasing
	screen-x, which is what every other part of the UI assumes.
]]
local function playerTilePosition(index: number): Vector3
	local zeroBased = index - 1
	local row = math.floor(zeroBased / PLAYER_COLUMNS)
	local column = zeroBased % PLAYER_COLUMNS

	local x = -(column - (PLAYER_COLUMNS - 1) / 2) * PITCH
	-- Row 0 is the rank nearest the lane — the front line, facing the enemy.
	local z = -(LANE_DEPTH / 2) - row * PITCH
	return ARENA_ORIGIN + Vector3.new(x, TILE_HEIGHT / 2, z)
end

local function enemyTilePosition(index: number): Vector3
	local zeroBased = index - 1
	local row = math.floor(zeroBased / ENEMY_COLUMNS)
	local column = zeroBased % ENEMY_COLUMNS

	-- Same negation, same reason: enemy 1 is the one the player sees on the left.
	local x = -(column - (ENEMY_COLUMNS - 1) / 2) * PITCH
	local z = (LANE_DEPTH / 2) + row * PITCH
	return ARENA_ORIGIN + Vector3.new(x, TILE_HEIGHT / 2, z)
end

local function billboard(parent: Instance, offsetY: number, width: number): BillboardGui
	return make("BillboardGui", {
		Parent = parent,
		Adornee = parent,
		-- 52px fits three stacked 16px rows: mutation, name, level.
		Size = UDim2.new(0, width, 0, 52),
		StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = true,
		MaxDistance = 260,
	})
end

--[[
	A health bar, attached above whatever it is given.

	Extracted because units need one too. Before this, only enemies had a bar, which
	meant the player could watch the enemy line melt but had no idea their own squad
	was being ground down — the first sign of trouble was the wave simply ending.
]]
local function healthBar(parent: BasePart, offsetY: number, colour: Color3): Frame
	local holder = make("BillboardGui", {
		Parent = parent,
		Adornee = parent,
		Name = "HealthBar",
		Size = UDim2.new(0, 84, 0, 9),
		StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = true,
		MaxDistance = 260,
	})
	local track = make("Frame", {
		Parent = holder,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BorderSizePixel = 0,
	})
	make("UICorner", { Parent = track, CornerRadius = UDim.new(0, 3) })
	local fill = make("Frame", {
		Name = "Fill",
		Parent = track,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
	})
	make("UICorner", { Parent = fill, CornerRadius = UDim.new(0, 3) })
	return fill
end

--[[
	Set a bar to a fraction, and colour it by how bad things are. A bar that only
	shrinks reads as "some number went down"; one that turns red reads as "this unit
	is about to die", which is the thing the player is actually meant to act on.
]]
local function setBar(fill: Frame?, fraction: number)
	if not fill then
		return
	end
	local f = math.clamp(fraction, 0, 1)
	fill.Size = UDim2.new(f, 0, 1, 0)
	fill.BackgroundColor3 = if f > 0.5
		then Color3.fromRGB(90, 220, 110)
		elseif f > 0.25 then Color3.fromRGB(240, 200, 70)
		else Color3.fromRGB(235, 70, 70)
end

--[[
	A unit's figure.

	Deliberately primitive parts, not meshes. Art can be swapped in later by
	replacing this one function; until then a readable silhouette that is coloured by
	RARITY and outlined by MUTATION tells the player everything the game asks them to
	act on. A pretty model that does not encode rarity would be worse.
]]
local function buildUnitModel(unit: any): Model
	local rarity = Rarities.Rarities[unit.rarity]
	local mutation = Mutations.Mutations[unit.mutation]
	local rosterUnit = Units.get(unit.unitId)

	local model = make("Model", { Name = unit.uid or "Unit" })

	local body = make("Part", {
		Name = "Body",
		Parent = model,
		Size = Vector3.new(3, 5, 3),
		Shape = Enum.PartType.Cylinder,
		Color = rarity.color,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		-- Cylinders are built along X, so stand it up.
		CFrame = CFrame.Angles(0, 0, math.rad(90)),
	})
	model.PrimaryPart = body

	make("Part", {
		Name = "Head",
		Parent = model,
		Size = Vector3.new(2.2, 2.2, 2.2),
		Shape = Enum.PartType.Ball,
		Color = rarity.color:Lerp(Color3.new(1, 1, 1), 0.35),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
	})

	-- The mutation reads as an outline, so it is legible at a glance and never
	-- competes with the rarity colour underneath.
	if unit.mutation ~= "Normal" then
		make("SelectionBox", {
			Parent = model,
			Adornee = body,
			Color3 = mutation.color,
			LineThickness = 0.12,
			SurfaceTransparency = 0.85,
			SurfaceColor3 = mutation.color,
		})
	end

	--[[
		The plate is NARROWER THAN THE TILE PITCH on purpose.

		At 190px it was wider than the gap between units, so neighbouring plates
		overlapped and the names read as one smear sitting off to the side of the
		figures. A plate must not be able to reach its neighbour's tile, so name and
		level are stacked rather than set side by side, and a long name is truncated
		instead of being allowed to grow.
	]]
	local plate = billboard(body, 5.0, 104)
	local name = make("TextLabel", {
		Parent = plate,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = rarity.color,
		TextStrokeTransparency = 0.2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = if rosterUnit then rosterUnit.displayName else unit.unitId,
	})

	--[[
		The mutation goes on its OWN line above the name, matching the source game's
		unit card, where the mutation is printed above the unit rather than prefixed
		to it. Prefixing made "Diamond Rengundam" too long for any sane plate width.
	]]
	if unit.mutation ~= "Normal" then
		name.Position = UDim2.new(0, 0, 0, 16)
		make("TextLabel", {
			Parent = plate,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = mutation.color,
			TextStrokeTransparency = 0.2,
			Text = mutation.displayName,
		})
	end

	make("TextLabel", {
		Parent = plate,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		TextStrokeTransparency = 0.4,
		Text = string.format("Lv. %d", unit.level or 1),
	})

	healthBar(body, 3.2, Color3.fromRGB(90, 220, 110))

	return model
end

local function positionUnitModel(model: Model, base: Vector3)
	local body = model:FindFirstChild("Body") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	body.CFrame = CFrame.new(base + Vector3.new(0, 3.0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	head.CFrame = CFrame.new(base + Vector3.new(0, 6.6, 0))
end

local function buildEnemyModel(index: number): Model
	local model = make("Model", { Name = "Enemy" .. index })

	local body = make("Part", {
		Name = "Body",
		Parent = model,
		Size = Vector3.new(3.2, 4.6, 3.2),
		Color = Color3.fromRGB(190, 55, 55),
		Material = Enum.Material.Slate,
		Anchored = true,
		CanCollide = false,
	})
	model.PrimaryPart = body

	healthBar(body, 3.4, Color3.fromRGB(235, 70, 70))

	return model
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function buildFloor()
	local width = math.max(PLAYER_COLUMNS, ENEMY_COLUMNS) * PITCH + 24
	local depth = LANE_DEPTH + (PLAYER_ROWS + ENEMY_ROWS) * PITCH + 24

	make("Part", {
		Name = "Floor",
		Parent = folder,
		Anchored = true,
		Size = Vector3.new(width, 1, depth),
		Position = ARENA_ORIGIN - Vector3.new(0, 0.5, 0),
		Color = COLOUR_FLOOR,
		Material = Enum.Material.Concrete,
		TopSurface = Enum.SurfaceType.Smooth,
	})

	-- A seam down the middle of the lane, so the two halves read as two sides.
	make("Part", {
		Name = "Centreline",
		Parent = folder,
		Anchored = true,
		CanCollide = false,
		Size = Vector3.new(width, 0.1, 0.6),
		Position = ARENA_ORIGIN + Vector3.new(0, 0.06, 0),
		Color = Color3.fromRGB(90, 95, 110),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
end

local function buildTiles()
	for index = 1, PLAYER_COLUMNS * PLAYER_ROWS do
		local tile = make("Part", {
			Name = "PlayerTile" .. index,
			Parent = folder,
			Anchored = true,
			Size = Vector3.new(TILE, TILE_HEIGHT, TILE),
			Position = playerTilePosition(index),
			Color = COLOUR_PLAYER_TILE,
			Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
		})
		make("SelectionBox", {
			Parent = tile,
			Adornee = tile,
			Color3 = Color3.fromRGB(120, 170, 255),
			LineThickness = 0.06,
			Transparency = 0.5,
		})

		--[[
			Clicking a tile places the selected unit there. This is the same action
			the inventory panel performs, routed through the same callback and so the
			same server remote — the 3D board is a second way to reach one action,
			never a second implementation of it.
		]]
		local detector = make("ClickDetector", { Parent = tile, MaxActivationDistance = 512 })
		detector.MouseClick:Connect(function()
			if onTileClicked then
				onTileClicked(index)
			end
		end)

		playerTiles[index] = tile
	end

	for index = 1, ENEMY_COLUMNS * ENEMY_ROWS do
		enemyTiles[index] = make("Part", {
			Name = "EnemyTile" .. index,
			Parent = folder,
			Anchored = true,
			Size = Vector3.new(TILE, TILE_HEIGHT, TILE),
			Position = enemyTilePosition(index),
			Color = COLOUR_ENEMY_TILE,
			Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
			Transparency = 0.15,
		})
	end
end

--[[
	Park the camera behind the player's bank, looking down the lane.

	Scriptable rather than following a character: there is no character to follow in
	an idle auto-battler, and a free camera would let the player lose the board.
]]
local function frameCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local backRow = -(LANE_DEPTH / 2) - (PLAYER_ROWS - 1) * PITCH
	local eye = ARENA_ORIGIN + Vector3.new(0, 46, backRow - 46)
	local look = ARENA_ORIGIN + Vector3.new(0, 0, LANE_DEPTH / 4)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, look)
	camera.FieldOfView = 62
end

function Arena.build()
	if folder then
		return
	end

	folder = make("Folder", { Name = "Arena", Parent = workspace })
	buildFloor()
	buildTiles()

	-- Lighting that makes the tile colours readable rather than washed out. The
	-- default sun puts the player bank in its own shadow at this camera angle.
	local lighting = game:GetService("Lighting")
	lighting.Ambient = Color3.fromRGB(80, 80, 95)
	lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 85)
	lighting.Brightness = 2
	lighting.ClockTime = 15

	frameCamera()

	--[[
		The camera is re-framed on respawn. Roblox resets CameraType to Custom when a
		character loads, which silently drops the player back into a free camera
		looking at nothing — this game has no character to look at.
	]]
	local localPlayer = Players.LocalPlayer
	localPlayer.CharacterAdded:Connect(function()
		task.defer(frameCamera)
	end)
	-- And once more a frame later, for the character that already exists at join.
	task.defer(frameCamera)
end

-- ── Render ──────────────────────────────────────────────────────────────────

function Arena.setTileClickHandler(handler: (tileIndex: number) -> ())
	onTileClicked = handler
end

--[[
	Highlight the tile whose unit is selected in the inventory panel, so the 2D and
	3D views agree about what is selected.
]]
function Arena.setSelectedTile(tileIndex: number?)
	selectedTile = tileIndex
end

--[[
	Redraw the player's half from the replicated profile.

	Tiles beyond the current Slot upgrade are drawn LOCKED rather than hidden, so the
	player can see what the upgrade buys before they buy it.
]]
function Arena.renderProfile(profile: any)
	if not folder or not profile then
		return
	end

	local slots = Upgrades.Upgrades.Slot.valueAtLevel(profile.upgrades.Slot)

	for index, tile in playerTiles do
		local unlocked = index <= slots
		if selectedTile == index then
			tile.Color = COLOUR_SELECTED
		else
			tile.Color = if unlocked then COLOUR_PLAYER_TILE else COLOUR_PLAYER_TILE_LOCKED
		end
		tile.Transparency = if unlocked then 0 else 0.55
	end

	-- Rebuild the figures. A placement can move, swap or remove a unit, and
	-- rebuilding is both simpler and cheap at 12 models.
	for _, model in pairs(unitModels) do
		model:Destroy()
	end
	table.clear(unitModels)

	table.clear(tileForUid)
	table.clear(originalColour)
	table.clear(deadTiles)
	for index = 1, #playerTiles do
		local uid = profile.grid[tostring(index)]
		local unit = uid and profile.inventory[uid]
		if unit then
			local model = buildUnitModel(unit)
			model.Parent = folder
			positionUnitModel(model, playerTilePosition(index))
			unitModels[index] = model
			tileForUid[uid] = index
			-- Kept so a unit that died last wave is restored to its rarity colour
			-- rather than staying the corpse grey it was tinted.
			local body = model:FindFirstChild("Body") :: BasePart?
			if body then
				originalColour[index] = body.Color
			end
		end
	end
end

--[[
	Draw the enemy line for a wave tick.

	The tick carries counts and totals, not per-enemy health — the server sends what
	the HUD needs, and inflating that payload to drive a nicer animation would put
	bandwidth into cosmetics. So the line shows how many are alive, and the bar on
	the front-most enemy shows the wave's remaining share.
]]
--[[
	Draw the squad's side of the fight: bars, and the dead falling over.

	The tick identifies units by uid rather than by tile, because a unit's tile is a
	player decision and its health is a server one — coupling them would mean a
	placement made mid-wave could silently reassign someone else's health.
]]
local function renderSquad(squad: { any }?)
	if not squad then
		return
	end

	local living: { [number]: boolean } = {}
	for _, entry in squad do
		local tile = tileForUid[entry.uid]
		local model = tile and unitModels[tile]
		if model then
			local body = model:FindFirstChild("Body") :: BasePart?
			local head = model:FindFirstChild("Head") :: BasePart?
			local bar = model:FindFirstChild("Fill", true) :: Frame?

			local fraction = if entry.maxHp > 0 then entry.hp / entry.maxHp else 0
			setBar(bar, fraction)

			local alive = entry.hp > 0
			living[tile] = alive

			if body then
				--[[
					A dead unit FALLS OVER and greys out. Simply hiding it would read
					as a rendering glitch; leaving it upright — which is what the last
					build did — reads as "combat is not happening", which is exactly
					the report that prompted this.
				]]
				if alive then
					body.Transparency = 0
					body.Color = originalColour[tile] or body.Color
				else
					body.Transparency = 0.55
					body.Color = Color3.fromRGB(70, 70, 78)
					local base = playerTilePosition(tile)
					body.CFrame = CFrame.new(base + Vector3.new(0, 1.2, 0))
						* CFrame.Angles(math.rad(90), 0, math.rad(90))
				end
			end
			if head then
				head.Transparency = if alive then 0 else 0.55
				if not alive then
					head.Position = playerTilePosition(tile) + Vector3.new(0, 1.2, 2.2)
				end
			end
		end
	end
	deadTiles = living
end

--[[
	A tracer between the front-most living unit and the front-most living enemy.

	This is the only thing on the board that MOVES during a fight, and it is what
	turns "the numbers are changing" into "they are shooting at each other". It is
	drawn from the same front-most rule the simulation uses (Wave.luau), so what the
	player sees firing is genuinely what is dealing the damage.
]]
local function renderTracer(fromTile: number?, toIndex: number?)
	local beam = folder:FindFirstChild("Tracer") :: BasePart?
	if not fromTile or not toIndex then
		if beam then
			beam.Transparency = 1
		end
		return
	end

	if not beam then
		beam = make("Part", {
			Name = "Tracer",
			Parent = folder,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 235, 140),
			Size = Vector3.new(0.35, 0.35, 1),
		})
	end

	local a = playerTilePosition(fromTile) + Vector3.new(0, 4, 0)
	local b = enemyTilePosition(toIndex) + Vector3.new(0, 3, 0)
	local beamPart = beam :: BasePart
	beamPart.Size = Vector3.new(0.35, 0.35, (b - a).Magnitude)
	beamPart.CFrame = CFrame.lookAt((a + b) / 2, b)
	-- Flickers rather than sitting solid, so it reads as repeated shots.
	beamPart.Transparency = 0.25 + 0.5 * math.abs(math.sin(os.clock() * 14))
end

function Arena.renderWave(tick: any)
	if not folder then
		return
	end

	renderSquad(tick.squad)

	local total = math.min(tick.enemyTotal or 0, #enemyTiles)
	local alive = math.min(tick.enemiesLeft or 0, total)

	for index = #enemyModels, total + 1, -1 do
		enemyModels[index]:Destroy()
		enemyModels[index] = nil
	end

	for index = 1, total do
		local model = enemyModels[index]
		if not model then
			model = buildEnemyModel(index)
			model.Parent = folder
			enemyModels[index] = model
		end

		local body = model.PrimaryPart :: BasePart
		body.CFrame = CFrame.new(enemyTilePosition(index) + Vector3.new(0, 2.8, 0))

		--[[
			WHICH enemies are dead: the ones at the FRONT.

			Both sides focus-fire the front-most living target (Wave.luau), so after
			k kills it is indices 1..k that are gone and k+1..total that are untouched.
			This read `index <= alive`, which greys out the back of the line and leaves
			the corpses at the front standing — the exact opposite of what happened.
		]]
		local dead = total - alive
		local isAlive = index > dead

		body.Transparency = if isAlive then 0 else 0.85
		body.Color = if isAlive then Color3.fromRGB(190, 55, 55) else Color3.fromRGB(70, 70, 78)

		--[[
			Per-enemy health now comes from the tick, so every enemy gets a true bar
			rather than only the front one. The previous build could not do this — the
			payload carried counts, and a count is not a health.
		]]
		local entry = tick.enemies and tick.enemies[index]
		local bar = model:FindFirstChild("Fill", true) :: Frame?
		local holder = body:FindFirstChild("HealthBar") :: BillboardGui?
		if holder then
			holder.Enabled = isAlive
		end
		if entry and entry.maxHp > 0 then
			setBar(bar, entry.hp / entry.maxHp)
		end
	end

	-- Fire from the first living unit at the first living enemy.
	local firstLivingTile: number? = nil
	for tile = 1, #playerTiles do
		if unitModels[tile] and deadTiles[tile] ~= false then
			firstLivingTile = tile
			break
		end
	end
	renderTracer(
		if tick.outcome == "running" then firstLivingTile else nil,
		if tick.outcome == "running" and alive > 0 then total - alive + 1 else nil
	)
end

--[[
	Clear the enemy line when no wave is running, so the board does not sit there
	showing the corpses of the last one.
]]
function Arena.clearWave()
	for _, model in enemyModels do
		model:Destroy()
	end
	table.clear(enemyModels)

	local beam = folder and folder:FindFirstChild("Tracer") :: BasePart?
	if beam then
		beam.Transparency = 1
	end

	--[[
		Stand the squad back up. Units are healed between waves — nothing in the
		profile carries damage across a wave, and Wave.begin rebuilds the squad at
		full health — so leaving corpses on the board would show a state the game
		does not actually have.
	]]
	table.clear(deadTiles)
	for tile, model in pairs(unitModels) do
		local body = model:FindFirstChild("Body") :: BasePart?
		local head = model:FindFirstChild("Head") :: BasePart?
		if body then
			body.Transparency = 0
			body.Color = originalColour[tile] or body.Color
			positionUnitModel(model, playerTilePosition(tile))
		end
		if head then
			head.Transparency = 0
		end
		setBar(model:FindFirstChild("Fill", true) :: Frame?, 1)
	end
end

--[[
	A short pulse on the arena when a wave is cleared. Purely feedback: an idle game
	where the numbers change but nothing moves reads as broken.
]]
function Arena.flashCleared()
	if not folder then
		return
	end
	local line = folder:FindFirstChild("Centreline") :: BasePart?
	if not line then
		return
	end
	line.Color = Color3.fromRGB(90, 255, 140)
	TweenService:Create(line, TweenInfo.new(0.9), { Color = Color3.fromRGB(90, 95, 110) }):Play()
end

-- Idle bob, so the board is never completely static.
local bobStart = os.clock()
RunService.RenderStepped:Connect(function()
	if not folder then
		return
	end
	local t = os.clock() - bobStart
	for index, model in pairs(unitModels) do
		-- A dead unit does not bob. Without this the loop keeps lifting the head back
		-- to standing height every frame, so a fallen unit's head hovers over its own
		-- body and the death reads as a glitch rather than a death.
		if deadTiles[index] == false then
			continue
		end
		local head = model:FindFirstChild("Head") :: BasePart?
		if head then
			local base = playerTilePosition(index)
			head.Position = base + Vector3.new(0, 6.6 + math.sin(t * 2 + index) * 0.18, 0)
		end
	end
end)

return Arena
