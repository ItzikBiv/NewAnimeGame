--!strict
--[[
	Server bootstrap.

	Placeholder entry point so `rojo build` succeeds against default.project.json.
	Gameplay systems land here in Epic 1 (the vertical slice):
	roll -> merge -> place -> wave -> gold -> save.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Upgrades = require(Config:WaitForChild("Upgrades"))

print(
	string.format(
		"[RollAnimeToFight] server booted — %d enemy slots, players start with %d unit slots",
		Upgrades.ENEMY_SLOTS,
		Upgrades.Upgrades.Slot.valueAtLevel(Upgrades.StartingLevels.Slot)
	)
)
