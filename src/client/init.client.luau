--!strict
-- Client bootstrap. Controllers (input, viewmodel, HUD) will be required from
-- here as they come online in M1+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- Mirrors BUILD_TAG in src/server/init.server.luau. If the two don't match in
-- Output, one side is stale.
local CLIENT_BUILD_TAG = "2026-08-11-I · rig-type-guard"

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
local LoadoutController = require(script.Controllers.LoadoutController)
local CameraController = require(script.Controllers.CameraController)
local LobbyController = require(script.Controllers.LobbyController)

local MovementController = require(script.Controllers.MovementController)
local MovementAnimator = require(script.Controllers.MovementAnimator)

local ArmoryController = require(script.Controllers.ArmoryController)

-- Each init() is isolated. Previously these ran bare and in order, so a throw
-- in any one of them silently skipped EVERY controller after it — a failure in
-- SettingsController took out the loadout screen, the camera, the pads and the
-- START GAME button, which is indistinguishable from "the whole game is
-- broken" and points debugging at entirely the wrong place.
local function boot(name: string, init: () -> ())
	local ok, err = pcall(init)
	if not ok then
		warn(`[PinkPanic] ⚠️ {name}.init() FAILED — that system is dead, the rest still ran. {err}`)
	end
end

boot("ClientData", ClientData.init)
boot("EffectsController", EffectsController.init)
boot("MovementController", MovementController.init)
boot("MovementAnimator", MovementAnimator.init)
boot("ViewmodelController", ViewmodelController.init)
boot("WeaponController", WeaponController.init)
boot("HitFeedbackController", HitFeedbackController.init)
boot("RoundController", RoundController.init)
boot("EconomyController", EconomyController.init)
boot("ShopController", ShopController.init)
boot("HudController", HudController.init)
boot("SettingsController", SettingsController.init)
boot("LoadoutController", LoadoutController.init)
boot("CameraController", CameraController.init)
boot("LobbyController", LobbyController.init)
boot("ArmoryController", ArmoryController.init)

-- The client half of the BUILD_TAG check. The server has always printed its
-- tag; the client printed nothing versioned, so "is the client stale?" had no
-- answer. Keep this in step with BUILD_TAG in src/server/init.server.luau.
print(`[PinkPanic] Client booted 🎀  build: {CLIENT_BUILD_TAG}`)
