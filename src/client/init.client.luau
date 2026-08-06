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
local Units = require(Shared.Config.Units)
local Merge = require(Shared.Inventory.Merge)
local Shop = require(Shared.Gacha.Shop)
local Remotes = require(Shared.Net.Remotes)

--[[
	The 3D board.

	`script.Arena`, NOT `script.Parent.Arena`. This directory has an
	init.client.luau, so Rojo turns the DIRECTORY into the LocalScript and every
	sibling file becomes a CHILD of it. `script.Parent` is PlayerScripts, where no
	Arena exists.

	Loaded defensively, because of what the wrong path did: the require threw on this
	line, the client script died before building anything, and the player got an
	empty grey void with no HUD, no camera and no error visible in-game. The arena is
	pure rendering — every action can still be taken from the 2D panels — so a
	failure here must cost the board, never the whole client.
]]
local Arena
do
	local ok, loaded = pcall(function()
		return require(script:FindFirstChild("Arena") :: any)
	end)
	if ok then
		Arena = loaded
	else
		warn("[RollAnimeToFight] arena unavailable, running 2D only — " .. tostring(loaded))
		-- Every Arena.* call becomes a no-op rather than a second crash.
		local noop = function() end
		Arena = setmetatable({}, {
			__index = function()
				return noop
			end,
		})
	end
end

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

--[[
	REROLL IS FREE. Owner's design: rerolling costs nothing and can be spammed;
	gold buys an offer, not a pull.

	The label says so explicitly. A red button next to a gold counter reads as
	"this costs something" no matter what the rules are, and a player who thinks
	rerolling is expensive will hoard instead of using the machine as intended.
]]
local rollButton = button(
	"REROLL — free",
	UDim2.new(0, 12, 0, 152),
	Color3.fromRGB(200, 45, 60),
	function()
		Remotes.get(Remotes.TO_SERVER.RequestReroll):FireServer()
	end
)

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

--=============================================================================
-- The shop
--=============================================================================

--[[
	Three offers, and a BUY button under each.

	Owner's design: rerolling is free and unlimited, and gold buys a unit rather
	than a pull. So the interesting decision moved — it used to be "can I afford to
	roll", and it is now "is this offer worth my gold, or do I reroll for a better
	one". The card therefore has to show everything that decision needs: the unit,
	its band, its mutation, and the price, all at once.
]]
local offerFrame = make("Frame", {
	Parent = gui,
	Size = UDim2.new(0, 310, 0, 128),
	-- Third column. The grid and upgrades already own the second one.
	Position = UDim2.new(0, 656, 0, 210),
	BackgroundColor3 = Color3.fromRGB(20, 20, 28),
	BackgroundTransparency = 0.2,
})
make("UICorner", { Parent = offerFrame, CornerRadius = UDim.new(0, 10) })
make("UIListLayout", {
	Parent = offerFrame,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
make("UIPadding", {
	Parent = offerFrame,
	PaddingTop = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
})

local offerTitle =
	label(gui, "SHOP — reroll is free", UDim2.new(0, 310, 0, 20), UDim2.new(0, 656, 0, 188))
offerTitle.TextColor3 = Color3.fromRGB(255, 210, 90)
offerTitle.TextSize = 15
offerTitle.TextScaled = false

local offerRows: { TextButton } = {}
for index = 1, Shop.OFFER_COUNT do
	local row = make("TextButton", {
		Parent = offerFrame,
		LayoutOrder = index,
		Size = UDim2.new(1, -12, 0, 36),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		Text = "",
		AutoButtonColor = true,
	})
	make("UICorner", { Parent = row, CornerRadius = UDim.new(0, 6) })

	local name = label(row, "", UDim2.new(1, -80, 0, 18), UDim2.new(0, 8, 0, 2))
	name.Name = "Name"
	local sub = label(row, "", UDim2.new(1, -80, 0, 14), UDim2.new(0, 8, 0, 20))
	sub.Name = "Sub"
	sub.TextSize = 12
	local price = label(row, "", UDim2.new(0, 74, 0, 32), UDim2.new(1, -78, 0, 2))
	price.Name = "Price"
	price.TextXAlignment = Enum.TextXAlignment.Right

	--[[
		The card sends its SLOT and nothing else. It does not send the unit, and it
		does not send the price — the server reads both from the offers it generated.
		A client that named either would be choosing what it buys and what it pays.
	]]
	row.Activated:Connect(function()
		Remotes.get(Remotes.TO_SERVER.RequestBuy):FireServer({ offerIndex = index })
	end)

	offerRows[index] = row
end

local function redrawOffers()
	if not profile then
		return
	end
	local offers = profile.offers or {}

	for index, row in offerRows do
		local offer = offers[index]
		local name = row:FindFirstChild("Name") :: TextLabel
		local sub = row:FindFirstChild("Sub") :: TextLabel
		local price = row:FindFirstChild("Price") :: TextLabel

		if not offer then
			-- An empty slot is either a fresh save or a slot the player just bought
			-- out. Saying so beats an unexplained blank row.
			name.Text = if #offers == 0 then "Reroll to see offers" else "— bought —"
			name.TextColor3 = Color3.fromRGB(120, 120, 132)
			sub.Text = ""
			price.Text = ""
			row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
			continue
		end

		local rarity = Rarities.Rarities[offer.rarity]
		local unit = Units.get(offer.unitId)
		name.Text = unit and unit.displayName or offer.unitId
		name.TextColor3 = rarity.color

		if offer.mutation ~= "Normal" then
			sub.Text = string.format(
				"%s  %s",
				Mutations.Mutations[offer.mutation].displayName,
				offer.rarity
			)
			sub.TextColor3 = Mutations.Mutations[offer.mutation].color
		else
			sub.Text = offer.rarity
			sub.TextColor3 = Color3.fromRGB(180, 180, 195)
		end

		local affordable = profile.gold >= offer.price
		price.Text = string.format("%d", offer.price)
		price.TextColor3 = affordable and Color3.fromRGB(150, 230, 150)
			or Color3.fromRGB(200, 130, 130)
		row.BackgroundColor3 = affordable and Color3.fromRGB(42, 62, 48)
			or Color3.fromRGB(38, 38, 50)
	end
end

--=============================================================================
-- Upgrades
--=============================================================================

--[[
	The four upgrades, and until now the client had no way to buy any of them.

	The server has handled RequestUpgrade since story 1.2, but nothing on screen
	ever fired it — so gold had exactly one sink (rolling), the Slot upgrade was
	unreachable, and a player was capped at four units permanently no matter how
	long they played. That is not a missing screen, it is three quarters of the
	progression being inert.

	Each row shows what the upgrade does NOW and what the next level buys, because
	"Gold Upgrade Lv7" on its own tells a player nothing about whether to spend.
]]
local upgradeFrame = make("Frame", {
	Parent = gui,
	Size = UDim2.new(0, 310, 0, 208),
	Position = UDim2.new(0, 334, 0, 346),
	BackgroundColor3 = Color3.fromRGB(20, 28, 40),
	BackgroundTransparency = 0.2,
})
make("UICorner", { Parent = upgradeFrame, CornerRadius = UDim.new(0, 10) })
make("UIListLayout", {
	Parent = upgradeFrame,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
make("UIPadding", {
	Parent = upgradeFrame,
	PaddingTop = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
})

-- Fixed order. Iterating the config table would reorder the rows between sessions,
-- which makes a panel of four similar buttons genuinely hard to use.
local UPGRADE_ORDER = { "Slot", "Luck", "Gold", "Inventory" }

-- How each upgrade's value reads to a player. A raw number is not self-explanatory:
-- Slot Lv5 means 8 slots, Gold Lv5 means x1.4 gold.
local UPGRADE_UNIT: { [string]: (number) -> string } = {
	Slot = function(v)
		return string.format("%d slots", v)
	end,
	Inventory = function(v)
		return string.format("%d storage", v)
	end,
	Gold = function(v)
		return string.format("x%.1f gold", v)
	end,
	Luck = function(v)
		return string.format("x%.1f luck", v)
	end,
}

local upgradeRows: { [string]: TextButton } = {}
for order, id in UPGRADE_ORDER do
	local row = make("TextButton", {
		Parent = upgradeFrame,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 44),
		BackgroundColor3 = Color3.fromRGB(45, 60, 90),
		Text = "",
		AutoButtonColor = true,
	})
	make("UICorner", { Parent = row, CornerRadius = UDim.new(0, 6) })

	local title = label(row, "", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 3))
	title.Name = "Title"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold

	local detail = label(row, "", UDim2.new(1, -12, 0, 18), UDim2.new(0, 8, 0, 22))
	detail.Name = "Detail"
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextSize = 13

	row.Activated:Connect(function()
		Remotes.get(Remotes.TO_SERVER.RequestUpgrade):FireServer({ upgradeId = id })
	end)

	upgradeRows[id] = row
end

--[[
	Repaint the upgrade rows from the profile.

	The affordability colour is a HINT, not a gate: the button still fires and the
	server still refuses, and its refusal lands in the status line. Disabling the
	button client-side would mean a player who mis-reads the colour gets silence
	instead of "costs 2703 gold" — and the server is the only thing that actually
	knows whether a purchase is legal.
]]
local function redrawUpgrades()
	if not profile then
		return
	end

	for _, id in UPGRADE_ORDER do
		local upgrade = Upgrades.Upgrades[id]
		local level = profile.upgrades[id]
		local row = upgradeRows[id]
		local title = row:FindFirstChild("Title") :: TextLabel
		local detail = row:FindFirstChild("Detail") :: TextLabel

		local unit = UPGRADE_UNIT[id]
		title.Text = string.format(
			"%s  Lv%d  —  %s",
			upgrade.displayName:gsub(" Upgrade", ""),
			level,
			unit(upgrade.valueAtLevel(level))
		)

		if level >= upgrade.maxLevel then
			detail.Text = "MAX"
			detail.TextColor3 = Color3.fromRGB(255, 210, 90)
			row.BackgroundColor3 = Color3.fromRGB(60, 55, 35)
		else
			local cost = upgrade.costAtLevel(level)
			local affordable = profile.gold >= cost
			detail.Text =
				string.format("next: %s  —  %d gold", unit(upgrade.valueAtLevel(level + 1)), cost)
			detail.TextColor3 = affordable and Color3.fromRGB(150, 230, 150)
				or Color3.fromRGB(190, 140, 140)
			row.BackgroundColor3 = affordable and Color3.fromRGB(45, 80, 60)
				or Color3.fromRGB(38, 45, 62)
		end
	end
end

-- Which tile a uid sits on, or nil if it is on the bench. Used to highlight the
-- selected unit's tile in the arena.
local function tileHolding(uid: string): number?
	if not profile then
		return nil
	end
	for tile, occupant in pairs(profile.grid) do
		if occupant == uid then
			return tonumber(tile)
		end
	end
	return nil
end

local function unitCaption(unit: any): string
	local prefix = unit.mutation ~= "Normal" and (unit.mutation .. " ") or ""
	return string.format("%s%s  Lv%d", prefix, unit.rarity, unit.level)
end

local function redraw()
	if not profile then
		return
	end

	--[[
		The 3D board is redrawn from the same call and the same profile as the 2D
		panels. Giving it its own refresh path is how the two views drift apart.
	]]
	Arena.setSelectedTile(if selectedUid then tileHolding(selectedUid) else nil)
	Arena.renderProfile(profile)
	redrawUpgrades()
	redrawOffers()

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
	Arena.renderWave(tick)
	if tick.outcome ~= "running" then
		Arena.clearWave()
		if tick.outcome == "cleared" then
			Arena.flashCleared()
		end
	end
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

--=============================================================================
-- The 3D board
--=============================================================================

Arena.build()

--[[
	Clicking a tile in the world does exactly what clicking its row in the 2D grid
	does — same branches, same remote. The two are separate INPUTS to one action, not
	two implementations of it, which is why the rules live here and not in Arena.
]]
Arena.setTileClickHandler(function(tileIndex)
	if not profile then
		return
	end

	local slots = Upgrades.Upgrades.Slot.valueAtLevel(profile.upgrades.Slot)
	if tileIndex > slots then
		say(string.format("Slot %d is locked — buy the Slot upgrade to unlock it.", tileIndex))
		return
	end

	local occupant = profile.grid[tostring(tileIndex)]
	if not selectedUid then
		if occupant then
			selectedUid = occupant
			say("Holding " .. unitCaption(profile.inventory[occupant]) .. " — tap a slot.", true)
			redraw()
		else
			say("Select a unit from your inventory first.")
		end
		return
	end

	Remotes.get(Remotes.TO_SERVER.RequestPlace)
		:FireServer({ uid = selectedUid, tileIndex = tileIndex })
	selectedUid = nil
	redraw()
end)

-- Loading state until the first replication lands.
goldLabel.Text = "Loading your save…"
rollButton.Text = "ROLL"

print("[RollAnimeToFight] client ready")
