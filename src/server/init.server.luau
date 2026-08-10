--!strict
-- Server bootstrap. Order matters: remotes must exist before any service
-- (or any client) tries to use them.
--
-- BUILD_TAG is bumped whenever behavior changes in a way that's easy to
-- mistake for "my fix didn't work". It prints at boot: if the Output window
-- doesn't show this exact tag, Studio is running stale scripts (Rojo not
-- connected at Play time, or a duplicate script tree in the place file).
-- If it prints TWICE, there are two copies of the server running.

local BUILD_TAG = "2026-08-10-C · START-GAME-button · lobby-holds-solo · ads-jitter-fixed"

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

-- Duplicate-script detector: a second copy of this bootstrap (a stale Rojo
-- sync target, or scripts pasted into the place) would run everything twice
-- and re-create content the live copy just deleted.
local ServerScriptService = game:GetService("ServerScriptService")
local bootMarker = ServerScriptService:FindFirstChild("PinkPanicBootMarker")
if bootMarker then
	warn(
		"[PinkPanic] ⚠️ DUPLICATE SERVER SCRIPT DETECTED — two copies of the bootstrap are running. "
			.. "Delete the stale script tree in ServerScriptService (keep only the Rojo-synced one)."
	)
else
	local marker = Instance.new("BoolValue")
	marker.Name = "PinkPanicBootMarker"
	marker.Value = true
	marker.Parent = ServerScriptService
end

print(`[PinkPanic] Server booted 🎀  build: {BUILD_TAG}`)
