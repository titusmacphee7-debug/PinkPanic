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

local BUILD_TAG = "2026-08-12-N · TTK table and balance regression checks (NOD-148)"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Unguarded on purpose: if Diagnostics itself cannot load there is nothing left
-- to report the failure with, and a hard error here is the loudest option.
local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)

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
	"Health",
	"Score",
	"Spawns",
	"Movement",
	"Handling",
	"Recoil",
	"Balance",
	"MoveAudit",
	"WeaponService",
	"CharacterService",
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
local Health: any = Diagnostics.load("Health", script.Systems.Health)
local Score: any = Diagnostics.load("Score", script.Systems.Score)
local Spawns: any = Diagnostics.load("Spawns", script.Systems.Spawns)
local MovementSystem: any = Diagnostics.load("Movement", ReplicatedStorage.Shared.Systems.Movement)
-- Handling (NOD-143). Shared, and loaded on the SERVER too: the server enforces
-- the same draw, reload and sprint gates the client predicts with, and its
-- validate() is what measures whether those timings actually land where the
-- config says they do.
local HandlingSystem: any = Diagnostics.load("Handling", ReplicatedStorage.Shared.Systems.Handling)
-- Recoil (NOD-144). Nothing on the server fires it, and it is loaded here on
-- purpose: its validate() is the boot check that no gun's aimed cone is wider
-- than its hip cone, which is the no-bloom rule with a number behind it.
local RecoilSystem: any = Diagnostics.load("Recoil", ReplicatedStorage.Shared.Systems.Recoil)
-- Balance (NOD-148). Server-only: it is an audit of the catalog, not a thing
-- either side runs during play. Its validate() is what notices that a gun kills
-- as fast at 100 studs as at 10 — a failure nobody can feel in a playtest,
-- because it reads as "that gun is good".
local BalanceSystem: any = Diagnostics.load("Balance", ReplicatedStorage.Shared.Systems.Balance)
local MoveAudit: any = Diagnostics.load("MoveAudit", script.Systems.MoveAudit)

local WeaponService: any = Diagnostics.load("WeaponService", script.Services.WeaponService)
local CharacterService: any = Diagnostics.load("CharacterService", script.Services.CharacterService)
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

-- The movement state graph: every edge names a real state, and every state is
-- reachable from Idle. An unreachable state is a move nobody can ever perform,
-- which is invisible until somebody asks why sliding does nothing.
if MovementSystem then
	Diagnostics.start("Movement", MovementSystem.validate)
end
if HandlingSystem then
	Diagnostics.start("Handling", HandlingSystem.validate)
end
if RecoilSystem then
	Diagnostics.start("Recoil", RecoilSystem.validate)
end
-- After CombatStats, whose resolver it reads every gun through.
if BalanceSystem then
	Diagnostics.start("Balance", BalanceSystem.validate)
end

-- After AssetTree, which creates the folders it scans.
if AssetRegistry then
	Diagnostics.start("AssetRegistry", AssetRegistry.load)
end

-- The weapon a shot is fired with comes from the SERVER's copy of the player's
-- loadout, never from the request. Injected here rather than required inside
-- WeaponService so the dependency runs Service → Systems and not back the
-- other way: the trigger has no business knowing how profiles are stored.
if WeaponService and PlayerDataService then
	WeaponService.setLoadoutResolver(function(player: Player)
		local profile = PlayerDataService.get(player)
		if not profile then
			return nil
		end

		local class = profile.classes and profile.classes[profile.activeClass]
		if class then
			local attachments: { [string]: { string } } = {}
			if class.primary and class.primary.gunId then
				attachments[class.primary.gunId] = class.primary.attachments
			end
			if class.secondary and class.secondary.gunId then
				attachments[class.secondary.gunId] = class.secondary.attachments
			end
			return {
				primary = class.primary and class.primary.gunId,
				secondary = class.secondary and class.secondary.gunId,
				attachments = attachments,
			}
		end

		local loadout = profile.loadout
		if not loadout then
			return nil
		end
		return { primary = loadout.primary, secondary = loadout.secondary }
	end)
end

-- Score is the only thing that mints currency for combat, and it reaches the
-- profile through here rather than requiring EconomyService itself: a System
-- requiring a Service is the dependency direction backwards (rule 3), and this
-- one would drag the whole DataStore layer in behind it.
if Score and EconomyService then
	Score.setPayout(function(player: Player, xp: number, coins: number)
		EconomyService.award(player, xp, coins)
	end)
end

-- The equipped kill effect, read from the profile and checked for ownership
-- here rather than trusted from the client. Same seam shape and the same
-- reason: Score has no business knowing how profiles are stored.
if Score and PlayerDataService then
	Score.setKillEffectResolver(function(player: Player): string?
		local profile = PlayerDataService.get(player)
		if not profile then
			return nil
		end
		local equipped = profile.equippedCosmetics
		local id = equipped and equipped.killEffect
		if type(id) ~= "string" then
			return nil
		end
		-- Owned, or it does not play. An item that fell out of the catalog, or
		-- one equipped before a refund, is not a licence to keep wearing it.
		local owned = profile.owned and profile.owned.killEffects
		if type(owned) ~= "table" or not table.find(owned, id) then
			return nil
		end
		return id
	end)
end

-- How heavy the gun in a player's hands is, for the speed ceiling MoveAudit
-- checks against. Injected for the same reason as everything else here: a
-- System reaching into a Service is the dependency direction backwards.
if MoveAudit and WeaponService then
	MoveAudit.setWeightResolver(function(player: Player): number?
		local state = WeaponService.stateOf(player)
		return state and state.stats and state.stats.moveSpeedMult
	end)
end

local BOOT_ORDER: { { name: string, module: any } } = {
	-- Ballistics before the services that will feed it, so the remote handler
	-- exists before any client can reach it.
	{ name = "Ballistics", module = Ballistics },
	-- After Ballistics, whose hit handler it registers for.
	{ name = "Health", module = Health },
	-- After Health, whose kill event it listens for. Before the respawn loop
	-- below registers its own listener, so on a kill the score lands first and
	-- the corpse is dealt with second — which is the order they read in.
	{ name = "Score", module = Score },
	-- Before anything that touches a character. It hooks CharacterAdded, and a
	-- player who spawns before it is listening keeps their own Roblox avatar
	-- for that life — which is a different-sized target than everyone else.
	{ name = "CharacterService", module = CharacterService },
	{ name = "MapService", module = MapService },
	-- AFTER MapService, which decides which arena is live and can destroy a
	-- stale one. Counting spawn points before that runs counts them in a map
	-- that is about to stop existing, and reports a number that was never true.
	{ name = "Spawns", module = Spawns },
	-- After Movement's graph check above, whose maxSpeed it takes its ceiling
	-- from rather than defining a second one.
	{ name = "MoveAudit", module = MoveAudit },
	-- After Ballistics, which it calls into, and before assertHandlers, which
	-- is what proves FireWeapon/ReloadWeapon/SwapWeapon actually got claimed.
	{ name = "WeaponService", module = WeaponService },
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

-- The respawn loop. Composed here rather than inside either system, because
-- "a kill happened" and "put this player somewhere good five seconds later"
-- are separate concerns that would otherwise import each other.
--
-- Registered as a LISTENER, not the handler: scoring, the killfeed and streaks
-- all want this same event, and a single slot means whoever registers second
-- silently replaces the first.
if Health and Spawns then
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(Spawns.step)

	-- Spawn protection, made real. Without these two lines it is a number in a
	-- config file that nothing reads — and it ends the moment you fire, so it
	-- can never be used as a free opening trade.
	Health.addDamageFilter(function(character)
		local victim = Players:GetPlayerFromCharacter(character)
		return not (victim and Spawns.isProtected(victim))
	end)
	if Ballistics then
		Ballistics.onFire(Spawns.clearProtection)
	end

	Health.onKill(function(kill)
		local character = kill.victim
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			-- Where someone died is where the fight still is, so the point
			-- nearest it gets penalised for the next few seconds.
			Spawns.markDeath(root.Position)
		end

		local player = kill.victimPlayer
		if not player then
			return -- a bot or a prop; nothing to respawn
		end

		-- The trigger goes dead the instant they do. Without this a shot
		-- already in flight from the client arrives at a corpse and is
		-- accepted, which is a free posthumous kill.
		if WeaponService then
			WeaponService.onDied(player)
		end

		task.delay(SpawnConfig.respawnSeconds, function()
			if player.Parent == nil then
				return -- left during the timer
			end
			player:LoadCharacter()
			-- One frame for CharacterService to standardise the rig before it
			-- gets moved; pivoting first would be undone by ApplyDescription.
			task.wait()
			Spawns.place(player)
			if WeaponService then
				WeaponService.onSpawned(player)
			end
		end)
	end)
end

-- Lifetime K/D on the profile. Separate from Score, which owns the MATCH
-- ledger and resets it: kills you got last round still count toward the number
-- on your card, and the number on the scoreboard has to start at zero.
if Health and EconomyService then
	Health.onKill(function(kill)
		local victim = kill.victimPlayer
		if victim then
			EconomyService.awardKill(victim, kill.killer, kill.weaponId)
		end
	end)
end

-- The first draw of a life, for every path into a character that is NOT the
-- respawn loop above: joining, a Studio playtest, an admin reset. Without it a
-- player who never died would hold nothing and every shot would be rejected as
-- "noweapon" — which reads exactly like combat being broken.
if WeaponService then
	local function armed(player: Player)
		player.CharacterAdded:Connect(function()
			-- One frame, for the same reason the respawn path waits: the rig is
			-- still being standardised.
			task.wait()
			WeaponService.onSpawned(player)
		end)
		if player.Character then
			task.spawn(WeaponService.onSpawned, player)
		end
	end

	for _, player in Players:GetPlayers() do
		task.spawn(armed, player)
	end
	Players.PlayerAdded:Connect(armed)
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
