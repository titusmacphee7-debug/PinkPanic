--!strict
-- Server bootstrap. Order matters: remotes must exist before any service
-- (or any client) tries to use them.
--
-- BUILD_TAG is bumped whenever behavior changes in a way that's easy to
-- mistake for "my fix didn't work". It prints at boot: if the Output window
-- doesn't show this exact tag, Studio is running stale scripts (Rojo not
-- connected at Play time, or a duplicate script tree in the place file).
-- If it prints TWICE, there are two copies of the server running.
--
-- Every module below is loaded and started through Diagnostics, so one broken
-- system is one DEAD line in the manifest instead of a silently dead server.
-- The loads are guarded as well as the inits, because a module with a syntax
-- error throws at require time — before any init function exists to guard.
-- That is exactly how the LobbyService parse error took the whole game down.

local BUILD_TAG = "2026-08-11-W · server ballistics (NOD-133)"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Unguarded on purpose: if Diagnostics itself cannot load there is nothing left
-- to report the failure with, and a hard error here is the loudest option.
local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

-- Declared up front so a system that never runs at all still shows up as NEVER
-- REPORTED. Absent looks intentional; pending looks like the bug it is.
Diagnostics.expect(
	"Remotes",
	"Guard",
	"Rarity",
	"AssetTree",
	"ContentAudit",
	"CombatStats",
	"AssetRegistry",
	"Ballistics",
	"MapService",
	"LobbyService",
	"PlayerDataService",
	"EconomyService",
	"ShopService",
	"SettingsService",
	"GunShopService"
)

-- Bootstrap glue is deliberately untyped: the type safety lives inside each
-- module, and a guarded load cannot return a statically known type.
local Remotes: any = Diagnostics.load("Remotes", ReplicatedStorage.Shared.Net.Remotes)
local Guard: any = Diagnostics.load("Guard", ReplicatedStorage.Shared.Net.Guard)

local RarityConfig: any = Diagnostics.load("Rarity", ReplicatedStorage.Shared.Config.Rarity)
local AssetTree: any = Diagnostics.load("AssetTree", ReplicatedStorage.Shared.Systems.AssetTree)
local ContentAudit: any = Diagnostics.load("ContentAudit", ReplicatedStorage.Shared.Systems.ContentAudit)
local CombatStats: any = Diagnostics.load("CombatStats", ReplicatedStorage.Shared.Systems.CombatStats)
local AssetRegistry: any = Diagnostics.load("AssetRegistry", ReplicatedStorage.Shared.Systems.AssetRegistry)

local Ballistics: any = Diagnostics.load("Ballistics", script.Systems.Ballistics)

local MapService: any = Diagnostics.load("MapService", script.Services.MapService)
local LobbyService: any = Diagnostics.load("LobbyService", script.Services.LobbyService)
local PlayerDataService: any = Diagnostics.load("PlayerDataService", script.Services.PlayerDataService)
local EconomyService: any = Diagnostics.load("EconomyService", script.Services.EconomyService)
local ShopService: any = Diagnostics.load("ShopService", script.Services.ShopService)
local SettingsService: any = Diagnostics.load("SettingsService", script.Services.SettingsService)
local GunShopService: any = Diagnostics.load("GunShopService", script.Services.GunShopService)

-- Remotes must come up before anything else. If it didn't, say so plainly —
-- every client will otherwise sit in WaitForChild forever with no explanation.
if Remotes then
	Diagnostics.start("Remotes", Remotes.init)
end

if RarityConfig then
	Diagnostics.start("Rarity", RarityConfig.validate)
end

-- Runs before the services so every folder a service might look for already
-- exists. Creates only; never deletes, never moves.
if AssetTree then
	Diagnostics.start("AssetTree", AssetTree.init)
end

-- After AssetTree, so the folders it looks in are guaranteed to exist.
if ContentAudit then
	Diagnostics.start("ContentAudit", ContentAudit.run)
end

-- Checks every attachment and perk modifier against the MODIFIABLE whitelist.
-- A typo'd stat name is found here, once, rather than never.
if CombatStats then
	Diagnostics.start("CombatStats", CombatStats.validate)
end

-- After AssetTree, which creates the folders it scans.
if AssetRegistry then
	Diagnostics.start("AssetRegistry", AssetRegistry.load)
end

-- The weapon a shot is fired with comes from the SERVER's copy of the player's
-- loadout, never from the request. Injected here rather than required inside
-- Ballistics so the dependency runs Service → System and not back the other
-- way: ballistics has no business knowing that profiles exist.
if Ballistics and PlayerDataService then
	Ballistics.setWeaponResolver(function(player: Player): string?
		local profile = PlayerDataService.get(player)
		if not profile then
			return nil
		end
		local class = profile.classes and profile.classes[profile.activeClass]
		if class then
			return class.primary and class.primary.gunId or class.secondary and class.secondary.gunId
		end
		return profile.loadout and (profile.loadout.primary or profile.loadout.secondary)
	end)
end

local BOOT_ORDER: { { name: string, module: any } } = {
	-- Ballistics before the services that will feed it, so the remote handler
	-- exists before any client can reach it.
	{ name = "Ballistics", module = Ballistics },
	{ name = "MapService", module = MapService },
	{ name = "LobbyService", module = LobbyService },
	{ name = "PlayerDataService", module = PlayerDataService },
	{ name = "EconomyService", module = EconomyService },
	{ name = "ShopService", module = ShopService },
	{ name = "SettingsService", module = SettingsService },
	{ name = "GunShopService", module = GunShopService },
}

for _, service in BOOT_ORDER do
	-- A nil module was already marked DEAD by load(); don't overwrite that
	-- reason with a less useful one.
	if service.module then
		Diagnostics.start(service.name, service.module.init)
	end
end

-- Must run after every service has had its chance to attach handlers. Any
-- client-to-server remote still unclaimed at this point is a hole: the client
-- fires it, nothing happens, and there is no error to explain why.
if Remotes then
	Remotes.assertHandlers()
end

-- Guard has no init() of its own; it is alive if it loaded. Leaking a player's
-- rate-limit state on every leave would be a slow memory climb nobody notices,
-- so say so if it isn't there rather than skipping the cleanup quietly.
if Guard then
	Diagnostics.ok("Guard", "rate limiting active")
	Players.PlayerRemoving:Connect(function(player)
		Guard.clearPlayer(player)
	end)
end

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

Diagnostics.report(BUILD_TAG)
