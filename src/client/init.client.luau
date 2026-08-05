--!strict
--[[
	Client bootstrap and HUD. Story 1.8.

	Design: docs/planning/epics.md story 1.8

	NOT VERIFIABLE OUTSIDE STUDIO. Nothing in CI can judge whether this looks or
	feels right — that is story 1.9, and it is the owner's to run.

	Two rules this file exists to honour:

	  1. The roll animation plays AFTER the server's result arrives. It never
	     predicts. A client that knows the outcome early is a client that can act
	     on it (architecture.md §1), and the spin is theatre over a settled value.

	  2. Rarity and mutation must read as SEPARATE things at a glance. That is the
	     game's pillar rendered on screen: a Gold Common has to feel like a result,
	     not like a Common.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Upgrades = require(Shared.Config.Upgrades)
local Merge = require(Shared.Inventory.Merge)
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "RollAnimeToFight"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local profile: any = nil
local selectedUid: string? = nil

--=============================================================================
-- Small UI helpers
--=============================================================================

local function make(class: string, props: { [string]: any }): any
	local instance = Instance.new(class)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2): TextLabel
	return make("TextLabel", {
		Parent = parent,
		Size = size,
		Position = pos,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

--=============================================================================
-- HUD
--=============================================================================

local hud = make("Frame", {
	Parent = gui,
	Size = UDim2.new(0, 320, 0, 96),
	Position = UDim2.new(0, 12, 0, 12),
	BackgroundColor3 = Color3.fromRGB(20, 20, 28),
	BackgroundTransparency = 0.15,
})
make("UICorner", { Parent = hud, CornerRadius = UDim.new(0, 10) })

local goldLabel = label(hud, "Gold: —", UDim2.new(1, -16, 0, 28), UDim2.new(0, 12, 0, 6))
local waveLabel = label(hud, "Wave: —", UDim2.new(1, -16, 0, 28), UDim2.new(0, 12, 0, 34))
local clockLabel =
	label(hud, "Mutation window: —", UDim2.new(1, -16, 0, 22), UDim2.new(0, 12, 0, 64))
clockLabel.TextColor3 = Color3.fromRGB(170, 200, 255)

-- Status line: the answer to "why did nothing happen?". A silent no-op is
-- indistinguishable from a bug, so every rejection lands here.
local status = label(gui, "", UDim2.new(0, 520, 0, 28), UDim2.new(0, 12, 0, 116))
status.TextColor3 = Color3.fromRGB(255, 140, 140)
status.TextXAlignment = Enum.TextXAlignment.Left

local function say(message: string, good: boolean?)
	status.TextColor3 = good and Color3.fromRGB(150, 230, 150) or Color3.fromRGB(255, 140, 140)
	status.Text = message
	task.delay(4, function()
		if status.Text == message then
			status.Text = ""
		end
	end)
end

--=============================================================================
-- Buttons
--=============================================================================

local function button(text: string, pos: UDim2, colour: Color3, onClick: () -> ()): TextButton
	local b = make("TextButton", {
		Parent = gui,
		Size = UDim2.new(0, 150, 0, 46),
		Position = pos,
		BackgroundColor3 = colour,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = true,
	})
	make("UICorner", { Parent = b, CornerRadius = UDim.new(0, 8) })
	b.Activated:Connect(onClick)
	return b
end

local rollButton = button("ROLL", UDim2.new(0, 12, 0, 152), Color3.fromRGB(200, 45, 60), function()
	Remotes.get(Remotes.TO_SERVER.RequestRoll):FireServer()
end)

--[[
	One button that starts and stops, mirroring the source game's START/STOP.
	`waveRunning` is driven purely by server WaveTick messages — the client never
	decides it is running.
]]
local waveRunning = false

local waveButton
waveButton = button("FIGHT", UDim2.new(0, 172, 0, 152), Color3.fromRGB(40, 160, 80), function()
	if waveRunning then
		Remotes.get(Remotes.TO_SERVER.RequestWaveStop):FireServer()
	else
		Remotes.get(Remotes.TO_SERVER.RequestWaveStart):FireServer()
	end
end)

local autoButton = button(
	"Auto: —",
	UDim2.new(0, 332, 0, 152),
	Color3.fromRGB(55, 90, 150),
	function()
		Remotes.get(Remotes.TO_SERVER.RequestAutoToggle):FireServer()
	end
)

local restartButton = button(
	"Restart: —",
	UDim2.new(0, 492, 0, 152),
	Color3.fromRGB(90, 70, 140),
	function()
		Remotes.get(Remotes.TO_SERVER.RequestRestartModeToggle):FireServer()
	end
)

local function setWaveRunning(running: boolean)
	waveRunning = running
	waveButton.Text = running and "STOP" or "FIGHT"
	waveButton.BackgroundColor3 = running and Color3.fromRGB(190, 60, 60)
		or Color3.fromRGB(40, 160, 80)
end

--=============================================================================
-- The roll reveal
--=============================================================================

local reveal = make("Frame", {
	Parent = gui,
	Size = UDim2.new(0, 320, 0, 120),
	Position = UDim2.new(0.5, -160, 0, 40),
	BackgroundColor3 = Color3.fromRGB(15, 15, 20),
	BackgroundTransparency = 1,
	Visible = false,
})
make("UICorner", { Parent = reveal, CornerRadius = UDim.new(0, 12) })
local revealStroke = make("UIStroke", { Parent = reveal, Thickness = 3 })

local mutationLabel = label(reveal, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 8))
mutationLabel.TextXAlignment = Enum.TextXAlignment.Center
local rarityLabel = label(reveal, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 40))
rarityLabel.TextXAlignment = Enum.TextXAlignment.Center
local pityLabel = label(reveal, "", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 0, 86))
pityLabel.TextXAlignment = Enum.TextXAlignment.Center
pityLabel.TextColor3 = Color3.fromRGB(190, 190, 200)

--[[
	Show a pull. Called ONLY from the server's RollResult — never predicted.

	Mutation renders ABOVE rarity, matching the source game's card layout, and in
	its own colour. That separation is the pillar on screen: the player should be
	able to see "Gold" and "Common" as two independent pieces of news.
]]
local function showRoll(result: any)
	local rarity = Rarities.Rarities[result.rarity]
	local mutation = Mutations.Mutations[result.mutation]

	reveal.Visible = true
	reveal.BackgroundTransparency = 0.1
	revealStroke.Color = rarity.color

	if result.mutation ~= "Normal" then
		mutationLabel.Text = string.upper(mutation.displayName)
		mutationLabel.TextColor3 = mutation.color
	else
		mutationLabel.Text = ""
	end

	rarityLabel.Text = rarity.displayName
	rarityLabel.TextColor3 = rarity.color
	pityLabel.Text = result.fromPity and "guaranteed by pity" or ""

	-- A brief pop, scaled to how big a deal the pull is. Rarer pulls linger.
	local weight = rarity.order + (mutation.damageMultiplier > 1 and 2 or 0)
	reveal.Size = UDim2.new(0, 300, 0, 110)
	TweenService
		:Create(reveal, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 320, 0, 120),
		})
		:Play()

	task.delay(1.0 + weight * 0.15, function()
		if reveal.Visible then
			TweenService:Create(reveal, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			reveal.Visible = false
		end
	end)
end

--=============================================================================
-- Inventory and grid
--=============================================================================

local panel = make("ScrollingFrame", {
	Parent = gui,
	Size = UDim2.new(0, 310, 0, 340),
	Position = UDim2.new(0, 12, 0, 210),
	BackgroundColor3 = Color3.fromRGB(20, 20, 28),
	BackgroundTransparency = 0.2,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
make("UICorner", { Parent = panel, CornerRadius = UDim.new(0, 10) })
make(
	"UIListLayout",
	{ Parent = panel, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }
)

local gridFrame = make("Frame", {
	Parent = gui,
	Size = UDim2.new(0, 310, 0, 120),
	Position = UDim2.new(0, 334, 0, 210),
	BackgroundColor3 = Color3.fromRGB(20, 28, 40),
	BackgroundTransparency = 0.2,
})
make("UICorner", { Parent = gridFrame, CornerRadius = UDim.new(0, 10) })
make("UIGridLayout", {
	Parent = gridFrame,
	CellSize = UDim2.new(0, 70, 0, 34),
	CellPadding = UDim2.new(0, 6, 0, 6),
})

local function unitCaption(unit: any): string
	local prefix = unit.mutation ~= "Normal" and (unit.mutation .. " ") or ""
	return string.format("%s%s  Lv%d", prefix, unit.rarity, unit.level)
end

local function redraw()
	if not profile then
		return
	end

	goldLabel.Text = string.format("Gold: %d", profile.gold)
	if not waveRunning then
		waveLabel.Text = string.format("Wave: %d", profile.wave)
	end
	autoButton.Text = profile.autoWave and "Auto: ON" or "Auto: OFF"
	restartButton.Text = profile.restartAtCheckpoint
			and string.format("Restart: wave %d", profile.checkpointWave or 1)
		or "Restart: wave 1"
	autoButton.BackgroundColor3 = profile.autoWave and Color3.fromRGB(60, 150, 90)
		or Color3.fromRGB(55, 90, 150)

	-- Clear BOTH buttons and labels. Destroying only buttons left the
	-- "No units yet" notice stranded on screen behind the real rows.
	for _, child in panel:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local uids = {}
	for uid in profile.inventory do
		table.insert(uids, uid)
	end
	table.sort(uids)

	if #uids == 0 then
		-- Empty state, not a blank box.
		local empty =
			label(panel, "  No units yet — press ROLL", UDim2.new(1, 0, 0, 30), UDim2.new())
		empty.TextColor3 = Color3.fromRGB(150, 150, 160)
	end

	for index, uid in uids do
		local unit = profile.inventory[uid]
		local rarity = Rarities.Rarities[unit.rarity]
		local isSelected = selectedUid == uid

		local row = make("TextButton", {
			Parent = panel,
			Size = UDim2.new(1, -8, 0, 30),
			LayoutOrder = index,
			BackgroundColor3 = isSelected and Color3.fromRGB(60, 80, 120)
				or Color3.fromRGB(32, 32, 42),
			Text = "  " .. unitCaption(unit),
			TextColor3 = rarity.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			Font = Enum.Font.Gotham,
		})
		make("UICorner", { Parent = row, CornerRadius = UDim.new(0, 6) })

		if isSelected then
			-- The base unit is the one that KEEPS its trait. Making that
			-- unmistakable is a hard requirement — the source game's own FAQ
			-- exists because players get this backwards and lose traits.
			make("UIStroke", { Parent = row, Color = Color3.fromRGB(120, 180, 255), Thickness = 2 })
		end

		row.Activated:Connect(function()
			if selectedUid == nil then
				selectedUid = uid
				say("Base selected — it KEEPS its trait. Now pick the unit to consume.", true)
			elseif selectedUid == uid then
				selectedUid = nil
				say("Selection cleared.", true)
			else
				local canMerge, why = Merge.canMerge(profile, selectedUid, uid)
				if not canMerge then
					say("Cannot merge: " .. tostring(why))
				else
					Remotes.get(Remotes.TO_SERVER.RequestMerge)
						:FireServer({ baseUid = selectedUid, consumedUid = uid })
					selectedUid = nil
				end
			end
			redraw()
		end)
	end

	for _, child in gridFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local slots = Upgrades.Upgrades.Slot.valueAtLevel(profile.upgrades.Slot)
	for tile = 1, slots do
		local occupant = profile.grid[tostring(tile)]
		local unit = occupant and profile.inventory[occupant]
		local tileButton = make("TextButton", {
			Parent = gridFrame,
			LayoutOrder = tile,
			BackgroundColor3 = unit and Color3.fromRGB(40, 70, 110) or Color3.fromRGB(30, 30, 40),
			Text = unit and unitCaption(unit) or ("slot " .. tile),
			TextColor3 = unit and Rarities.Rarities[unit.rarity].color
				or Color3.fromRGB(120, 120, 130),
			TextScaled = true,
			Font = Enum.Font.Gotham,
		})
		make("UICorner", { Parent = tileButton, CornerRadius = UDim.new(0, 6) })

		tileButton.Activated:Connect(function()
			if not selectedUid then
				if occupant then
					-- Tapping a filled tile with nothing held picks that unit up, so
					-- a slot can be emptied and not only swapped.
					selectedUid = occupant
					say("Holding " .. unitCaption(unit) .. " — tap a slot to move it.", true)
					redraw()
				else
					say("Select a unit from your inventory first.")
				end
				return
			end
			Remotes.get(Remotes.TO_SERVER.RequestPlace)
				:FireServer({ uid = selectedUid, tileIndex = tile })
			selectedUid = nil
			redraw()
		end)
	end
end

--=============================================================================
-- Server events
--=============================================================================

Remotes.get(Remotes.TO_CLIENT.ProfileReplicated).OnClientEvent:Connect(function(replicated)
	profile = replicated
	redraw()
end)

Remotes.get(Remotes.TO_CLIENT.RollResult).OnClientEvent:Connect(showRoll)

Remotes.get(Remotes.TO_CLIENT.ActionRejected).OnClientEvent:Connect(function(payload)
	local suffix = payload.retryAfter and string.format(" (retry in %.1fs)", payload.retryAfter)
		or ""
	say(tostring(payload.reason) .. suffix)
end)

Remotes.get(Remotes.TO_CLIENT.WaveTick).OnClientEvent:Connect(function(tick)
	setWaveRunning(tick.outcome == "running")
	if tick.outcome == "running" then
		waveLabel.Text = string.format(
			"Wave %d — %d/%d enemies, %d units",
			tick.wave,
			tick.enemiesLeft,
			tick.enemyTotal,
			tick.unitsLeft
		)
	elseif tick.outcome == "cleared" then
		say(string.format("Wave %d cleared! +%d gold", tick.wave, tick.goldEarned), true)
	else
		say(
			string.format(
				"Wave %d lost — back to wave %d. Merge or roll for more power.",
				tick.wave,
				profile and profile.wave or 1
			)
		)
	end
end)

Remotes.get(Remotes.TO_CLIENT.EventClockChanged).OnClientEvent:Connect(function(payload)
	if payload.activeMutation then
		local mutation = Mutations.Mutations[payload.activeMutation]
		clockLabel.Text = string.format("Now rolling: %s", mutation.displayName)
		clockLabel.TextColor3 = mutation.color
	else
		clockLabel.Text = "Mutation window: none"
	end
end)

-- Loading state until the first replication lands.
goldLabel.Text = "Loading your save…"
rollButton.Text = "ROLL"

print("[RollAnimeToFight] client ready")
