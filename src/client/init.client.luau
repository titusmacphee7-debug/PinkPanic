--!strict
-- Client bootstrap. Controllers (input, viewmodel, HUD) will be required from
-- here as they come online in M1+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

-- Mirrors BUILD_TAG in src/server/init.server.luau. If the two don't match in
-- Output, one side is stale.
local CLIENT_BUILD_TAG = "2026-08-12-E · client firing loop + server ammo (NOD-136)"

-- First-person shooter: the pink crosshair is the cursor.
UserInputService.MouseIconEnabled = false

Diagnostics.expect(
	"Remotes",
	"ClientData",
	"EffectsController",
	"EconomyController",
	"ShopController",
	"SettingsController",
	"LoadoutController",
	"CameraController",
	"LobbyController",
	"ArmoryController",
	"Firing",
	"WeaponController"
)

local Remotes: any = Diagnostics.load("Remotes", ReplicatedStorage.Shared.Net.Remotes)

-- Touching any remote here blocks until the server has finished Remotes.init,
-- so everything after this line can assume the remote surface exists. This
-- was RoundStateChanged until the round loop was deleted; DataChanged is the
-- barrier now because the economy is the one system guaranteed to exist.
if Remotes then
	Diagnostics.start("Remotes", Remotes.awaitReady)
end

-- Loaded through Diagnostics so a controller with a syntax error is one DEAD
-- line rather than a client that boots to a black screen. The previous version
-- guarded init() but not require(), which left the worse half unguarded: a
-- module that fails to compile never reaches its init at all.
local controllers: { { name: string, module: any } } = {
	{ name = "ClientData", module = Diagnostics.load("ClientData", script.ClientData) },
	{ name = "EffectsController", module = Diagnostics.load("EffectsController", script.Controllers.EffectsController) },
	{ name = "EconomyController", module = Diagnostics.load("EconomyController", script.Controllers.EconomyController) },
	{ name = "ShopController", module = Diagnostics.load("ShopController", script.Controllers.ShopController) },
	{
		name = "SettingsController",
		module = Diagnostics.load("SettingsController", script.Controllers.SettingsController),
	},
	{ name = "LoadoutController", module = Diagnostics.load("LoadoutController", script.Controllers.LoadoutController) },
	{ name = "CameraController", module = Diagnostics.load("CameraController", script.Controllers.CameraController) },
	{ name = "LobbyController", module = Diagnostics.load("LobbyController", script.Controllers.LobbyController) },
	{ name = "ArmoryController", module = Diagnostics.load("ArmoryController", script.Controllers.ArmoryController) },
	-- Last, and after EffectsController, whose muzzle flash and tracer it
	-- calls the moment a shot is predicted. WeaponController.init also starts
	-- Firing, so the two report separately: "the trigger is bound" and "the
	-- magazine is being predicted" are different things to be wrong about.
	{
		name = "WeaponController",
		module = Diagnostics.load("WeaponController", script.Controllers.WeaponController),
	},
}

-- Each init() is isolated. Previously these ran bare and in order, so a throw
-- in any one of them silently skipped EVERY controller after it — a failure in
-- SettingsController took out the loadout screen, the camera, the pads and the
-- START GAME button, which is indistinguishable from "the whole game is
-- broken" and points debugging at entirely the wrong place.
for _, controller in controllers do
	if controller.module then
		Diagnostics.start(controller.name, controller.module.init)
	end
end

-- The mirror of the server's check: a server-to-client remote nobody listens
-- for means the server is firing into nothing, which looks identical to the
-- server not firing at all.
if Remotes then
	Remotes.assertListeners()
end

Diagnostics.report(CLIENT_BUILD_TAG)
