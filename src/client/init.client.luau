--!strict
-- Client bootstrap. Controllers (input, viewmodel, HUD) will be required from
-- here as they come online in M1+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- Touching any remote here blocks until the server has finished Remotes.init,
-- so everything after this line can assume the remote surface exists.
Remotes.event("RoundStateChanged")

local EffectsController = require(script.Controllers.EffectsController)
local WeaponController = require(script.Controllers.WeaponController)
local HitFeedbackController = require(script.Controllers.HitFeedbackController)

EffectsController.init()
WeaponController.init()
HitFeedbackController.init()

print("[PinkPanic] Client booted 🎀")
