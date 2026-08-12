--!strict
-- Firing — the client half of the fire-intent contract (NOD-136).
--
-- The client's job is to feel instant. This module runs the SAME state machine
-- the server runs (shared/Systems/Weapon), predicts the shot locally, sends
-- intent, and reconciles when the server disagrees.
--
-- What goes on the wire is origin, direction, and the client's own guess at
-- its ammo count. No target, no hit, no damage — nothing the server would have
-- to take our word for. The ammo guess is not an exception: the server uses it
-- for exactly one thing, deciding whether to correct us, and a client that
-- lies about it gets its own magazine corrected, which is not much of a cheat.
--
-- Reconciliation has two modes and the distinction matters:
--
--   · A CORRECTION is the server telling us something we could not have
--     predicted — a rejected shot, a reload that landed, a weapon swap. It is
--     applied verbatim.
--   · A HEARTBEAT is the server restating the truth periodically so a dropped
--     correction repairs itself. Ammo from a heartbeat is taken as a MINIMUM,
--     never assigned, because between our shot and the server processing it we
--     are legitimately one round lower and snapping up would make the counter
--     flicker on every burst.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local Weapon = require(ReplicatedStorage.Shared.Systems.Weapon)
local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)

local SYSTEM = "Firing"

local Firing = {}

-- Fired the instant we predict a shot, before the server has seen anything.
-- The viewmodel, recoil and effects hang off this, which is what "instant"
-- actually means.
local firedEvent = Instance.new("BindableEvent")
Firing.fired = firedEvent.Event

-- Fired when the magazine, the reload or the held weapon changes, for the HUD.
local changedEvent = Instance.new("BindableEvent")
Firing.changed = changedEvent.Event

local state: Weapon.State? = nil
local weaponId: string? = nil
local slot: string = "Secondary"

-- Prediction accounting, surfaced as a rejection rate. The server keeps its
-- own; ours is what tells us whether OUR prediction is wrong, which is a
-- different question from whether somebody is cheating.
local predicted = 0
local corrections = 0

local function signalChange()
	changedEvent:Fire()
end

-- ---------------------------------------------------------------------------
-- Reading the state
-- ---------------------------------------------------------------------------

function Firing.ammo(): (number, number)
	local s = state
	if not s then
		return 0, 0
	end
	return s.ammo, s.stats.magSize
end

function Firing.reloading(): boolean
	local s = state
	return s ~= nil and Weapon.reloading(s)
end

function Firing.reloadProgress(): number
	local s = state
	return if s then Weapon.reloadProgress(s) else 0
end

function Firing.weapon(): (string?, CombatStats.Resolved?)
	local s = state
	return weaponId, s and s.stats
end

function Firing.slot(): string
	return slot
end

function Firing.state(): Weapon.State?
	return state
end

-- ---------------------------------------------------------------------------
-- Input edges. The controller owns the keys; this owns what they mean.
-- ---------------------------------------------------------------------------

function Firing.setTrigger(down: boolean)
	local s = state
	if not s then
		return
	end
	if down then
		Weapon.pressTrigger(s)
	else
		Weapon.releaseTrigger(s)
	end
end

function Firing.setSprinting(sprinting: boolean)
	local s = state
	if not s then
		return
	end
	Weapon.setSprinting(s, sprinting)
	Remotes.fireServer("SprintState", sprinting)
end

function Firing.reload()
	local s = state
	if not s then
		return
	end
	-- Predicted locally AND asked for. The server runs its own reload on its
	-- own clock; ours exists so the counter and the animation start on the
	-- frame you press R rather than a round trip later.
	if Weapon.beginReload(s) then
		Remotes.fireServer("ReloadWeapon")
		signalChange()
	end
end

function Firing.swap(toSlot: string)
	if toSlot ~= "Primary" and toSlot ~= "Secondary" then
		return
	end
	if toSlot == slot then
		return
	end
	-- Not predicted. The gun we are swapping to comes from the profile, which
	-- the server owns, so guessing here would mean guessing which weapon —
	-- and being wrong about that shows a stranger's gun in your hands.
	Remotes.fireServer("SwapWeapon", toSlot)
end

function Firing.setDead(dead: boolean)
	local s = state
	if s then
		Weapon.setDead(s, dead)
		signalChange()
	end
end

-- ---------------------------------------------------------------------------
-- The muzzle
-- ---------------------------------------------------------------------------

-- Bullets leave the HEAD, not the camera.
--
-- The server checks that the origin is within a few studs of the head and that
-- nothing is between the two, because a client that picks its own muzzle can
-- put the bullet's start point on the far side of the wall it is hiding
-- behind. Using the head is not a workaround for that check — it is the honest
-- answer to where a shot comes from, and it means the check never fires for a
-- legitimate client.
local function muzzle(): (Vector3?, Vector3?)
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not head or not head:IsA("BasePart") or not camera then
		return nil, nil
	end
	return head.Position, camera.CFrame.LookVector
end

-- ---------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------

-- Driven by the controller rather than binding its own Heartbeat, for the same
-- reason every other step function in this project is public: a machine only
-- reachable through Heartbeat can only be tested by waiting real seconds.
function Firing.step(deltaTime: number)
	local s = state
	if not s then
		return
	end

	local ammoBefore = s.ammo
	local reloadBefore = s.reload
	Weapon.step(s, deltaTime)

	local shot = Weapon.update(s)
	if shot then
		local origin, direction = muzzle()
		if origin and direction then
			predicted += 1
			Diagnostics.count(SYSTEM, "predicted")
			Remotes.fireServer("FireWeapon", origin, direction, s.ammo)
			firedEvent:Fire(origin, direction, s.stats)
		else
			-- No character to fire from. Give the round back rather than
			-- charging for a shot that was never sent.
			s.ammo += 1
		end
	end

	if s.ammo ~= ammoBefore or s.reload ~= reloadBefore then
		signalChange()
	end
end

-- ---------------------------------------------------------------------------
-- Reconciliation
-- ---------------------------------------------------------------------------

local function applyAmmoState(payload: any)
	if type(payload) ~= "table" or type(payload.weaponId) ~= "string" then
		return
	end

	local incoming = payload.weaponId
	local s = state

	-- A new gun, or the first one of the life.
	if not s or incoming ~= weaponId then
		-- Resolved with the attachment list the SERVER used, which is why it
		-- is on the wire at all. Resolving the bare gun here would put the two
		-- machines onto different magazine sizes and fire rates the moment an
		-- attachment touched either.
		local list: { string }? = if type(payload.attachments) == "table" then payload.attachments else nil
		local stats = CombatStats.forGun(incoming, list)
		if not stats then
			return
		end
		if s then
			Weapon.equip(s, stats, payload.ammo)
		else
			s = Weapon.create(stats)
			state = s
		end
		weaponId = incoming
	end

	local weaponState = s :: Weapon.State
	slot = if payload.slot == "Primary" then "Primary" else "Secondary"

	if type(payload.ammo) == "number" then
		if payload.correct then
			if payload.ammo ~= weaponState.ammo then
				corrections += 1
				Diagnostics.count(SYSTEM, "corrections")
			end
			weaponState.ammo = payload.ammo
		else
			-- Heartbeat. See the header: a minimum, never an assignment.
			weaponState.ammo = math.min(weaponState.ammo, payload.ammo)
		end
	end

	if type(payload.readyIn) == "number" then
		weaponState.readyAt = weaponState.clock + payload.readyIn
		if weaponState.nextShotAt < weaponState.readyAt then
			weaponState.nextShotAt = weaponState.readyAt
		end
	end

	if payload.reloading then
		if weaponState.reload == "none" then
			weaponState.reload = Weapon.reloadKind(weaponState.stats)
			weaponState.reloadStartedAt = weaponState.clock
		end
		local endsIn = if type(payload.reloadEndsIn) == "number" then payload.reloadEndsIn else 0
		weaponState.reloadEndsAt = weaponState.clock + endsIn
	elseif weaponState.reload ~= "none" and payload.correct then
		-- The server says the reload is over. Ours may still be running on a
		-- slightly different clock; the server's answer wins, always.
		Weapon.cancelReload(weaponState)
	end

	weaponState.dead = false
	signalChange()
end

-- The fraction of our predicted shots the server had to correct us about.
-- Nil until there are enough shots for the number to mean anything.
function Firing.correctionRate(): number?
	if predicted < 40 then
		return nil
	end
	return corrections / predicted
end

function Firing.init()
	Remotes.listen("AmmoState", applyAmmoState)
	Diagnostics.ok(SYSTEM, "predicting; server owns the magazine")
end

return Firing
