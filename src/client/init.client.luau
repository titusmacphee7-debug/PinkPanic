--!strict
-- Client bootstrap. Controllers (input, viewmodel, HUD) will be required from
-- here as they come online in M1+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

-- Mirrors BUILD_TAG in src/server/init.server.luau. If the two don't match in
-- Output, one side is stale.
local CLIENT_BUILD_TAG = "2026-08-12-P · attachment slots and the no-strict-upgrade rule (NOD-150)"

-- First-person shooter: the pink crosshair is the cursor.
UserInputService.MouseIconEnabled = false

Diagnostics.expect(
	"Remotes",
	"CameraRig",
	"ClientData",
	"EffectsController",
	"EconomyController",
	"ShopController",
	"SettingsController",
	"LoadoutController",
	"CameraController",
	"LobbyController",
	"ArmoryController",
	"CombatHUD",
	"Movement",
	"MovementController",
	"Handling",
	"Recoil",
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
	-- First. It owns every camera render-step binding (NOD-142), and ClientData
	-- claims the mouse-unlock slot the moment a menu opens — a slot claimed
	-- before the rig exists is a camera write nobody is ordering.
	{ name = "CameraRig", module = Diagnostics.load("CameraRig", script.Camera.CameraRig) },
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
	-- Before WeaponController, so the hitmarker exists by the time the trigger
	-- can be pulled. It listens rather than being called, so the order only
	-- matters for that first frame — but that first frame is a real one.
	{ name = "CombatHUD", module = Diagnostics.load("CombatHUD", script.Controllers.CombatHUD) },
	-- MovementController reads the held weapon's weight from Firing, which
	-- WeaponController starts — but only on the frame loop, never at init, so
	-- the order between them does not matter and a missing weapon is weight 1.
	{
		name = "MovementController",
		module = Diagnostics.load("MovementController", script.Controllers.MovementController),
	},
	-- Shared with the server, and reported on both sides on purpose: the drift
	-- check measures the timings against the machine that is actually running,
	-- and "the client thinks the draw is 220ms" is a different fact from "the
	-- server thinks it is 220ms".
	{ name = "Handling", module = Diagnostics.load("Handling", ReplicatedStorage.Shared.Systems.Handling) },
	{ name = "Recoil", module = Diagnostics.load("Recoil", ReplicatedStorage.Shared.Systems.Recoil) },
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
