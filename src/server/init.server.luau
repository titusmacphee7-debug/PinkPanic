--!strict
-- Server bootstrap. Order matters: remotes must exist before any service
-- (or any client) tries to use them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local PlayerDataService = require(script.Services.PlayerDataService)

Remotes.init()
PlayerDataService.init()

Players.PlayerRemoving:Connect(function(player)
	Guard.clearPlayer(player)
end)

print("[PinkPanic] Server booted 🎀")
