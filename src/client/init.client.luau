--!strict
-- Client bootstrap. Controllers (input, viewmodel, HUD) will be required from
-- here as they come online in M1+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- First-person shooter: the pink crosshair is the cursor.
UserInputService.MouseIconEnabled = false

-- Touching any remote here blocks until the server has finished Remotes.init,
-- so everything after this line can assume the remote surface exists.
Remotes.event("RoundStateChanged")

local ClientData = require(script.ClientData)
local EffectsController = require(script.Controllers.EffectsController)
local ViewmodelController = require(script.Controllers.ViewmodelController)
local WeaponController = require(script.Controllers.WeaponController)
local HitFeedbackController = require(script.Controllers.HitFeedbackController)
local RoundController = require(script.Controllers.RoundController)
local EconomyController = require(script.Controllers.EconomyController)
local ShopController = require(script.Controllers.ShopController)
local HudController = require(script.Controllers.HudController)
local SettingsController = require(script.Controllers.SettingsController)
local CameraController = require(script.Controllers.CameraController)
local LobbyController = require(script.Controllers.LobbyController)

local MovementController = require(script.Controllers.MovementController)
local MovementAnimator = require(script.Controllers.MovementAnimator)

ClientData.init()
EffectsController.init()
MovementController.init()
MovementAnimator.init()
ViewmodelController.init()
WeaponController.init()
HitFeedbackController.init()
RoundController.init()
EconomyController.init()
ShopController.init()
HudController.init()
SettingsController.init()
CameraController.init()
LobbyController.init()

local ArmoryController = require(script.Controllers.ArmoryController)
ArmoryController.init()

print("[PinkPanic] Client booted 🎀")
