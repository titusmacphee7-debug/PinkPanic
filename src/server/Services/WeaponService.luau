--!strict
-- WeaponService — what each player is holding, and whether it may fire
-- (NOD-136).
--
-- The seam this issue is about runs right through here. The client's job is to
-- feel instant: it predicts the flash, the sound, the kick, the tracer and the
-- ammo counter the frame you click. This service's job is to be right. It owns
-- the magazine, the reload, the draw timer and the sprint delay, it decides
-- whether an arriving intent was legal, and it is the only thing that ever
-- reaches Ballistics.
--
-- **The intent carries no claim.** Origin, direction, and the client's own
-- prediction of its ammo count — which is used for exactly one thing: deciding
-- whether to send a correction back. It is never trusted, never written, and a
-- client that lies about it gets its own screen corrected, which is not a very
-- good exploit.
--
-- The weapon comes from the profile, never from the request. This is the same
-- reasoning as everywhere else in the project: a client that could name its own
-- weapon would name the best one in the game regardless of what it owns.
--
-- Rejections are counted by REASON. "shot rejected" is not a diagnosis —
-- "empty" is a client whose magazine drifted, "cadence" is a client firing
-- faster than its gun, and "drawing" is a client shooting through its own
-- equip animation. They point at three different bugs and must never share a
-- counter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Weapon = require(ReplicatedStorage.Shared.Systems.Weapon)
local Config = require(ReplicatedStorage.Shared.Config.FiringConfig)

local Ballistics = require(script.Parent.Parent.Systems.Ballistics)

local SYSTEM = "WeaponService"

export type Slot = "Primary" | "Secondary"

type Held = {
	slot: Slot,
	state: Weapon.State,
	-- The magazine of the gun NOT in hand, so swapping away and back is not a
	-- free reload.
	stowedAmmo: { [string]: number },
	lastPushAt: number,
	weaponId: string,
	-- Replicated with the weapon so the client resolves the SAME stats we did.
	-- Without it the client would resolve the bare gun and an attachment that
	-- changes magazine size or fire rate would put the two machines onto
	-- different numbers — which is precisely the drift running one shared
	-- state machine exists to prevent.
	attachments: { string },
}

local WeaponService = {}

local held: { [Player]: Held } = {}
local clock = 0

-- Shots accepted vs rejected, by reason. Surfaced as a rate at boot and on
-- demand, because a rejection rate is the single number that says whether the
-- client and server disagree about anything.
local accepted = 0
local rejected: { [string]: number } = {}

local function countRejection(reason: string)
	rejected[reason] = (rejected[reason] or 0) + 1
	Diagnostics.count(SYSTEM, `rejected:{reason}`)
end

-- ---------------------------------------------------------------------------
-- Loadout
-- ---------------------------------------------------------------------------

-- Injected rather than required, so the dependency runs Service → Systems and
-- not back the other way. WeaponService has no business knowing how profiles
-- are stored; it only needs to be told what is equipped.
local resolveLoadout: ((Player) -> { primary: string?, secondary: string?, attachments: { [string]: { string } }? }?)? =
	nil

function WeaponService.setLoadoutResolver(
	resolver: (Player) -> { primary: string?, secondary: string?, attachments: { [string]: { string } }? }?
)
	resolveLoadout = resolver
end

local function gunFor(player: Player, slot: Slot): (string?, { string }?)
	local resolver = resolveLoadout
	if not resolver then
		return nil, nil
	end
	local loadout = resolver(player)
	if not loadout then
		return nil, nil
	end
	local id = if slot == "Primary" then loadout.primary else loadout.secondary
	if not id then
		return nil, nil
	end
	local attachments = loadout.attachments and loadout.attachments[id]
	return id, attachments
end

-- ---------------------------------------------------------------------------
-- Replication
-- ---------------------------------------------------------------------------

-- `correct` is the difference between "here is the truth, use it" and "here is
-- the truth, in case you missed the last one". The client applies a correction
-- verbatim and treats a heartbeat's ammo as a floor, because between its shot
-- and this service processing it the client is legitimately one round lower
-- and snapping up would make the counter flicker on every burst.
local function push(player: Player, entry: Held, correct: boolean)
	entry.lastPushAt = clock
	local state = entry.state
	Remotes.fireClient("AmmoState", player, {
		weaponId = entry.weaponId,
		slot = entry.slot,
		attachments = entry.attachments,
		ammo = state.ammo,
		magSize = state.stats.magSize,
		reloading = state.reload ~= "none",
		reloadEndsIn = math.max(state.reloadEndsAt - state.clock, 0),
		readyIn = math.max(state.readyAt - state.clock, 0),
		correct = correct,
	})
end

-- ---------------------------------------------------------------------------
-- Equipping
-- ---------------------------------------------------------------------------

local function equip(player: Player, slot: Slot): boolean
	local gunId, attachments = gunFor(player, slot)
	if not gunId then
		return false
	end

	local list = attachments or {}
	local stats = CombatStats.resolve(gunId, list)
	local entry = held[player]

	if not entry then
		entry = {
			slot = slot,
			state = Weapon.create(stats),
			stowedAmmo = {},
			lastPushAt = 0,
			weaponId = gunId,
			attachments = list,
		}
		held[player] = entry
	else
		-- Bank the magazine of what was in hand before it goes away.
		entry.stowedAmmo[entry.weaponId] = entry.state.ammo
		entry.slot = slot
		entry.weaponId = gunId
		entry.attachments = list
		Weapon.equip(entry.state, stats, entry.stowedAmmo[gunId])
	end

	push(player, entry, true)
	return true
end

function WeaponService.equipSlot(player: Player, slot: Slot): boolean
	return equip(player, slot)
end

-- How long to keep trying to put a gun in someone's hands before admitting it
-- is not going to happen.
local ARM_TIMEOUT_SECONDS = 15

-- One token per player so two overlapping arm attempts — die, respawn fast,
-- die again — cannot both be running and fight over the same slot.
local armToken: { [Player]: number } = {}

-- A fresh life: a new gun, drawn from scratch, with a full magazine. Called by
-- the respawn path rather than inferred from CharacterAdded here, so the
-- ordering against CharacterService is explicit at the bootstrap.
--
-- **This retries, and it must.** The loadout comes from the profile, and the
-- profile is a DataStore round trip that has usually not finished when the
-- first character spawns. The first version tried exactly once, found no
-- profile, and armed nobody — silently. Every shot then came back "noweapon",
-- which on a player's screen is a gun that does nothing at all.
function WeaponService.onSpawned(player: Player)
	-- Both magazines reset. Dying and respawning is not a reload you have to
	-- earn, and carrying a spent magazine across a death would be.
	held[player] = nil

	local token = (armToken[player] or 0) + 1
	armToken[player] = token

	task.spawn(function()
		local deadline = os.clock() + ARM_TIMEOUT_SECONDS
		while player.Parent ~= nil and armToken[player] == token do
			-- Primary if they have one, otherwise the secondary they always do.
			if equip(player, "Primary") or equip(player, "Secondary") then
				return
			end
			if os.clock() > deadline then
				Diagnostics.warn(
					SYSTEM,
					`{player.Name} spawned but never got a weapon — their profile did not load within `
						.. `{ARM_TIMEOUT_SECONDS}s, or its loadout names a gun that is not in the catalog. `
						.. `Every shot they fire will be rejected.`
				)
				return
			end
			task.wait(0.25)
		end
	end)
end

function WeaponService.onDied(player: Player)
	local entry = held[player]
	if entry then
		Weapon.setDead(entry.state, true)
	end
end

function WeaponService.stateOf(player: Player): Weapon.State?
	local entry = held[player]
	return entry and entry.state
end

-- ---------------------------------------------------------------------------
-- Remote handlers
-- ---------------------------------------------------------------------------

local function onFireWeapon(player: Player, origin: any, direction: any, predictedAmmo: any)
	-- A coarse ceiling above any legitimate fire rate, purely to stop a flood
	-- of malformed calls reaching the real validation. The per-weapon cadence
	-- check below is the one that matters.
	if not Guard.checkRate(player, "FireWeapon", 30, 1) then
		return
	end
	if not Guard.isVector3(origin) or not Guard.isUnitVector(direction) then
		return
	end
	-- Optional and untrusted. Its only job is to tell us whether the client's
	-- counter has drifted, so a malformed one is simply ignored rather than
	-- rejecting an otherwise legal shot.
	local claimed = if Guard.isNumberInRange(predictedAmmo, 0, 1000) then predictedAmmo :: number else nil

	local entry = held[player]
	if not entry then
		countRejection("noweapon")
		return
	end

	local ok, reason = Weapon.commitShot(entry.state)
	if not ok then
		countRejection(reason or "unknown")
		-- Always correct a rejected shot. The client believes it fired and has
		-- already decremented; leaving it wrong is how a magazine ends up
		-- permanently one round out of step.
		push(player, entry, true)
		return
	end

	local fired, why = Ballistics.fire(player, entry.weaponId, origin, direction)
	if not fired then
		-- Ballistics said no after the magazine already paid for it. Give the
		-- round back: charging for a shot that never existed is worse than the
		-- rejection itself, and it compounds.
		entry.state.ammo += 1
		countRejection(`ballistics:{why or "unknown"}`)
		push(player, entry, true)
		return
	end

	accepted += 1
	Diagnostics.count(SYSTEM, "accepted")

	if claimed and math.abs(claimed - entry.state.ammo) > Config.ammoDesyncTolerance then
		push(player, entry, true)
	end
end

local function onReloadWeapon(player: Player)
	if not Guard.checkRate(player, "ReloadWeapon", 8, 1) then
		return
	end
	local entry = held[player]
	if not entry then
		return
	end
	if Weapon.beginReload(entry.state) then
		push(player, entry, true)
	end
end

local function onSwapWeapon(player: Player, slot: any)
	if not Guard.checkRate(player, "SwapWeapon", 8, 1) then
		return
	end
	if slot ~= "Primary" and slot ~= "Secondary" then
		return
	end
	local entry = held[player]
	if entry and entry.slot == slot then
		return
	end
	equip(player, slot :: Slot)
end

-- Sprint is movement's business, not ours, but the trigger has to know about
-- it: sprintToFire is a real handling stat and a weapon that ignores it is a
-- weapon with one fewer thing separating it from every other weapon.
--
-- Client-reported and deliberately so. It is not exploitable in the direction
-- that matters: claiming you are sprinting only ever DELAYS your own shots.
local function onSprintState(player: Player, sprinting: any)
	if type(sprinting) ~= "boolean" then
		return
	end
	if not Guard.checkRate(player, "SprintState", 20, 1) then
		return
	end
	local entry = held[player]
	if entry then
		Weapon.setSprinting(entry.state, sprinting)
	end
end

-- ---------------------------------------------------------------------------
-- Stepping
-- ---------------------------------------------------------------------------

function WeaponService.step(deltaTime: number)
	clock += deltaTime

	for player, entry in held do
		local before = entry.state.ammo
		local reloadingBefore = entry.state.reload ~= "none"
		Weapon.step(entry.state, deltaTime)

		-- Reload payout and completion are the two things the client predicts
		-- on its own clock, which is close but never identical. Confirming both
		-- is what keeps a reload from ever ending in a counter that disagrees.
		local changed = entry.state.ammo ~= before or (entry.state.reload ~= "none") ~= reloadingBefore
		if changed then
			push(player, entry, true)
		elseif clock - entry.lastPushAt >= Config.ammoHeartbeatSeconds then
			push(player, entry, false)
		end
	end
end

-- The rejection rate, as a fraction. Nil below the noise floor: one rejection
-- out of three is 33% and means nothing.
function WeaponService.rejectionRate(): number?
	local total = accepted
	for _, count in rejected do
		total += count
	end
	if total < Config.rejectionRateMinShots then
		return nil
	end
	return (total - accepted) / total
end

-- How often the rejection rate is checked. Long, because the number only
-- becomes meaningful over hundreds of shots and a warning that repeats every
-- few seconds is a warning people learn to scroll past.
local REPORT_INTERVAL_SECONDS = 60

function WeaponService.report()
	local rate = WeaponService.rejectionRate()
	if not rate then
		return
	end
	if rate <= Config.rejectionRateWarn then
		return
	end

	local worst, worstCount = "?", 0
	for reason, count in rejected do
		if count > worstCount then
			worst, worstCount = reason, count
		end
	end
	Diagnostics.warn(
		SYSTEM,
		`{math.floor(rate * 100 + 0.5)}% of shots rejected — mostly "{worst}" ({worstCount}). `
			.. `Either the client and server disagree about ammo, or somebody is firing faster than their gun.`
	)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function WeaponService.init()
	Remotes.handleEvent("FireWeapon", onFireWeapon)
	Remotes.handleEvent("ReloadWeapon", onReloadWeapon)
	Remotes.handleEvent("SwapWeapon", onSwapWeapon)
	Remotes.handleEvent("SprintState", onSprintState)

	RunService.Heartbeat:Connect(WeaponService.step)

	Players.PlayerRemoving:Connect(function(player)
		held[player] = nil
		armToken[player] = nil
	end)

	-- The rejection rate, on a slow loop. A `report` function nothing ever
	-- calls is the same thing as no report at all — which is the failure mode
	-- this project keeps finding, so it gets a caller in the same commit.
	task.spawn(function()
		while true do
			task.wait(REPORT_INTERVAL_SECONDS)
			WeaponService.report()
		end
	end)

	Diagnostics.ok(
		SYSTEM,
		`ammo enforced server-side · reload pays out at {math.floor(Config.reloadAmmoFraction * 100)}% · `
			.. `holster {Config.holsterSeconds}s`
	)
end

return WeaponService
