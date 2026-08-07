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

local EffectsController = require(script.Controllers.EffectsController)
local ViewmodelController = require(script.Controllers.ViewmodelController)
local WeaponController = require(script.Controllers.WeaponController)
local HitFeedbackController = require(script.Controllers.HitFeedbackController)
local RoundController = require(script.Controllers.RoundController)
local EconomyController = require(script.Controllers.EconomyController)

EffectsController.init()
ViewmodelController.init()
WeaponController.init()
HitFeedbackController.init()
RoundController.init()
EconomyController.init()

print("[PinkPanic] Client booted 🎀")
