--!strict
-- Server bootstrap. Order matters: remotes must exist before any service
-- (or any client) tries to use them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local PlayerDataService = require(script.Services.PlayerDataService)
local CombatService = require(script.Services.CombatService)
local WeaponService = require(script.Services.WeaponService)
local RoundService = require(script.Services.RoundService)
local EconomyService = require(script.Services.EconomyService)
local ShopService = require(script.Services.ShopService)
local SettingsService = require(script.Services.SettingsService)
local GunShopService = require(script.Services.GunShopService)
local MapService = require(script.Services.MapService)
local LobbyService = require(script.Services.LobbyService)
local MovementStateService = require(script.Services.MovementStateService)

Remotes.init()
MapService.init()
LobbyService.init()
PlayerDataService.init()
CombatService.init()
WeaponService.init()
RoundService.init()
EconomyService.init()
ShopService.init()
SettingsService.init()
GunShopService.init()
MovementStateService.init()

Players.PlayerRemoving:Connect(function(player)
	Guard.clearPlayer(player)
end)

print("[PinkPanic] Server booted 🎀")
