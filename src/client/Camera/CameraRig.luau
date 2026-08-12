--!strict
-- CameraRig — the only place `BindToRenderStep` is called for camera work
-- (NOD-142).
--
-- Several systems write the camera every frame. They must run in a fixed order,
-- and getting it wrong produces jitter that looks exactly like a physics bug and
-- gets debugged as one. That order was hard-won, so it is not written down in a
-- comment and hoped for — it is a table here, and a system asks for a SLOT
-- rather than picking a number:
--
--     engine Camera (200)
--       → Base       +1   the shot itself (lobby chase, or the engine's own)
--       → Aim        +2   recoil, which is a delta and never an absolute
--       → Effects    +3   slide roll, dive tilt, landing dip, FOV
--       → Viewmodel  +4   the gun (M11)
--     MouseUnlock  Last   not camera work, but it is in the chain
--
-- Two claims on one slot is a real conflict and says so. A slot nobody claims
-- simply does not bind.
--
-- **It knows nothing about the controllers.** The rig reads the player's
-- movement state off the character's `PPMoveState` attribute rather than by
-- requiring MovementController, which is why the roll, the tilt and the dip can
-- live here at all — a camera module that had to require the movement
-- controller, the weapon controller and ClientData would be a cycle waiting for
-- someone to add one more edge.
--
-- **Breathing is published, not applied.** See `CameraRig.breath()`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Config = require(ReplicatedStorage.Shared.Config.CameraConfig)

local SYSTEM = "CameraRig"

local CameraRig = {}

export type Slot = "Base" | "Aim" | "Effects" | "Viewmodel" | "MouseUnlock"

-- The chain, as data. Priorities are exported so a new system asks for a slot
-- by name; the bind NAMES are the ones in CLAUDE.md and in Studio's own
-- profiler, so what you read there matches what you read here.
local SLOTS: { { slot: Slot, bind: string, priority: number, writesCamera: boolean } } = {
	{ slot = "Base", bind = "PinkPanicCamera", priority = Enum.RenderPriority.Camera.Value + 1, writesCamera = true },
	{ slot = "Aim", bind = "PinkPanicAim", priority = Enum.RenderPriority.Camera.Value + 2, writesCamera = true },
	{
		slot = "Effects",
		bind = "PinkPanicSlideRoll",
		priority = Enum.RenderPriority.Camera.Value + 3,
		writesCamera = true,
	},
	{
		slot = "Viewmodel",
		bind = "PinkPanicViewmodel",
		priority = Enum.RenderPriority.Camera.Value + 4,
		writesCamera = true,
	},
	-- Last, and deliberately after everything: the first-person camera scripts
	-- re-lock the mouse every render step, so winning that fight means being the
	-- one who writes last.
	{
		slot = "MouseUnlock",
		bind = "PinkPanicMouseUnlock",
		priority = Enum.RenderPriority.Last.Value,
		writesCamera = false,
	},
}

local AUDIT_BIND = "PinkPanicCameraAudit"

local byName: { [Slot]: { slot: Slot, bind: string, priority: number, writesCamera: boolean } } = {}
for _, entry in SLOTS do
	byName[entry.slot] = entry
end

CameraRig.PRIORITY = {} :: { [Slot]: number }
for _, entry in SLOTS do
	CameraRig.PRIORITY[entry.slot] = entry.priority
end

local owners: { [Slot]: string } = {}

-- What the rig last left the camera at, for the foreign-writer check.
local lastWritten: CFrame? = nil
local driftFrames = 0
local driftReported = false

-- Effect state. Declared up here rather than beside the step that uses them
-- because `setCombat` restores `baselineFov`, and a local declared further down
-- the file is not the same name — it is a nil global that happens to read the
-- same in the editor.
local roll = 0
local tilt = 0
local dip = 0
local dipTarget = 0
local currentFov = Config.baseFov
local baselineFov: number? = nil
local breathClock = 0

-- ---------------------------------------------------------------------------
-- Claiming a slot
-- ---------------------------------------------------------------------------

-- `owner` is the system's name, used only in the conflict message — which is
-- the whole reason it is a required argument rather than inferred: "two systems
-- claimed Effects" is not actionable, "CombatHUD and MovementController both
-- claimed Effects" is.
function CameraRig.claim(slot: Slot, owner: string, step: (deltaTime: number) -> ())
	local entry = byName[slot]
	if not entry then
		Diagnostics.warn(SYSTEM, `{owner} asked for camera slot "{slot}", which does not exist`)
		return
	end

	local existing = owners[slot]
	if existing and existing ~= owner then
		Diagnostics.warn(
			SYSTEM,
			`{owner} and {existing} both claimed the {slot} slot — {owner} wins, and one of them is now `
				.. `writing the camera at a priority it did not choose`
		)
	end
	owners[slot] = owner

	local wrapped = step
	if entry.writesCamera then
		-- Recording after every camera-writing slot means `lastWritten` is
		-- always what the LAST rig step left behind, whichever slots happen to
		-- be claimed. The audit compares against that rather than against a
		-- fixed slot, so adding the viewmodel later does not turn it into a
		-- false positive generator.
		wrapped = function(deltaTime: number)
			step(deltaTime)
			local camera = workspace.CurrentCamera
			if camera then
				lastWritten = camera.CFrame
			end
		end
	end

	RunService:BindToRenderStep(entry.bind, entry.priority, wrapped)
end

function CameraRig.release(slot: Slot)
	local entry = byName[slot]
	if not entry or not owners[slot] then
		return
	end
	owners[slot] = nil
	RunService:UnbindFromRenderStep(entry.bind)
end

function CameraRig.owner(slot: Slot): string?
	return owners[slot]
end

-- ---------------------------------------------------------------------------
-- Mode
--
-- The lobby's camera is a fixed hand-placed shot of the storefront row. Rolling
-- it tilts the storefront; kicking its FOV re-composes it. Both are effects
-- about a FIRST-PERSON view, so in the lobby the rig leaves the shot alone and
-- writes nothing but what the Base slot put there.
-- ---------------------------------------------------------------------------

local combat = false

function CameraRig.setCombat(active: boolean)
	if combat == active then
		return
	end
	combat = active
	if not active then
		-- Hand the FOV back exactly as it was found. Titus composed the lobby
		-- shot at the place file's FOV and it is not ours to leave changed.
		local camera = workspace.CurrentCamera
		if camera and baselineFov then
			camera.FieldOfView = baselineFov
		end
	end
end

-- ---------------------------------------------------------------------------
-- Player-facing settings
-- ---------------------------------------------------------------------------

local preferredFov = Config.baseFov

function CameraRig.setFov(fov: number)
	preferredFov = math.clamp(fov, Config.fovMin, Config.fovMax)
end

function CameraRig.fov(): number
	return preferredFov
end

-- ---------------------------------------------------------------------------
-- Aiming
--
-- The seam NOD-143 drives. Nothing calls it yet, and that is the point: the FOV
-- half of ADS is camera work and belongs here, so when the handling layer lands
-- it sets a number rather than reaching for the camera.
-- ---------------------------------------------------------------------------

local aimFraction = 0
local aimClass: string? = nil

function CameraRig.setAim(fraction: number, gunClass: string?)
	aimFraction = math.clamp(fraction, 0, 1)
	aimClass = gunClass
end

-- ---------------------------------------------------------------------------
-- State, read off the character
-- ---------------------------------------------------------------------------

local player = Players.LocalPlayer

local function moveState(): string
	local character = player.Character
	if not character then
		return "Idle"
	end
	local state = character:GetAttribute("PPMoveState")
	return if type(state) == "string" then state else "Idle"
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ---------------------------------------------------------------------------
-- The effects step
-- ---------------------------------------------------------------------------

-- Slide heading, published by whoever is sliding. The rig does not compute it:
-- the slide owns its own heading and this is a number, not a dependency.
local slideHeading: Vector3? = nil

function CameraRig.setSlideHeading(heading: Vector3?)
	slideHeading = heading
end

-- An exponential approach with a time constant, which is frame-rate
-- independent — a lerp with a fixed alpha is not, and it is why effects that
-- felt right at 60fps feel wrong at 144.
local function approach(current: number, target: number, seconds: number, deltaTime: number): number
	if seconds <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-deltaTime / seconds))
end

-- Fall speed at the moment of the last landing, so the dip is proportional to
-- the drop rather than the same thump every time.
local wasAirborne = false
local fallSpeed = 0

local function updateLanding(state: string)
	local root = rootPart()
	if not root then
		return
	end
	local airborne = state == "Air" or state == "Dive"
	if airborne then
		fallSpeed = math.max(fallSpeed, -root.AssemblyLinearVelocity.Y)
	elseif wasAirborne then
		local dipConfig = Config.landingDip
		if fallSpeed >= dipConfig.minFallSpeed then
			local span = math.max(dipConfig.maxFallSpeed - dipConfig.minFallSpeed, 1e-3)
			local strength = math.clamp((fallSpeed - dipConfig.minFallSpeed) / span, 0, 1)
			dipTarget = dipConfig.maxStuds * strength
		end
		fallSpeed = 0
	end
	wasAirborne = airborne
end

local function effects(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not baselineFov then
		baselineFov = camera.FieldOfView
	end

	local state = moveState()
	breathClock += deltaTime
	updateLanding(state)

	if not combat then
		-- Lobby: the shot is Titus's. Every effect below is about a view you are
		-- looking THROUGH, and this one you are looking AT.
		roll = approach(roll, 0, Config.slideRollOutSeconds, deltaTime)
		tilt = approach(tilt, 0, Config.diveTiltOutSeconds, deltaTime)
		dip, dipTarget = 0, 0
		return
	end

	-- FOV. Rising fast and settling slowly, because a snap back to base at the
	-- end of a sprint reads as a stutter.
	local target = preferredFov + (Config.fovKick[state] or 0)
	if aimFraction > 0 then
		local scale = (aimClass and Config.adsFovScale[aimClass]) or 0.8
		target += (preferredFov * scale - target) * aimFraction
	end
	local fovSeconds = if target > currentFov then Config.fovSeconds else Config.fovReleaseSeconds
	currentFov = approach(currentFov, target, fovSeconds, deltaTime)
	camera.FieldOfView = currentFov

	-- Roll: the carve. Zero on a straight slide, full on a hard one.
	local rollTarget = 0
	local heading = slideHeading
	if state == "Slide" and heading then
		local root = rootPart()
		if root then
			local right = root.CFrame.RightVector
			local flat = Vector3.new(right.X, 0, right.Z)
			if flat.Magnitude > 1e-4 then
				rollTarget = math.rad(Config.slideRollDegrees) * math.clamp(flat.Unit:Dot(heading), -1, 1)
			end
		end
	end
	local rollSeconds = if math.abs(rollTarget) > math.abs(roll)
		then Config.slideRollInSeconds
		else Config.slideRollOutSeconds
	roll = approach(roll, rollTarget, rollSeconds, deltaTime)

	-- Tilt: nose down through a dive.
	local tiltTarget = if state == "Dive" then math.rad(Config.diveTiltDegrees) else 0
	local tiltSeconds = if tiltTarget > tilt then Config.diveTiltInSeconds else Config.diveTiltOutSeconds
	tilt = approach(tilt, tiltTarget, tiltSeconds, deltaTime)

	-- Dip: the knees, on landing.
	local dipSeconds = if dipTarget > dip then Config.landingDip.inSeconds else Config.landingDip.outSeconds
	dip = approach(dip, dipTarget, dipSeconds, deltaTime)
	if dipTarget > 0 and dip >= dipTarget * 0.9 then
		dipTarget = 0 -- reached the bottom; come back up
	end

	-- One multiply, on top of whatever the shot already is. Never an absolute
	-- CFrame: an absolute write would overwrite the player's own mouse every
	-- frame, which reads as the camera fighting you.
	if math.abs(roll) < 1e-5 and math.abs(tilt) < 1e-5 and math.abs(dip) < 1e-5 then
		return
	end
	camera.CFrame = camera.CFrame * CFrame.Angles(-tilt, 0, roll) + Vector3.new(0, -dip, 0)
end

-- ---------------------------------------------------------------------------
-- Breathing — published, never applied
--
-- Returns the offset a viewmodel should apply, in its own local space, scaled by
-- stance. The camera does NOT move: breathing the view is what makes people
-- motion-sick, and it makes the stillness check below unanswerable. CoD breathes
-- the weapon. So does this, the day there is a weapon to breathe (M11).
-- ---------------------------------------------------------------------------

function CameraRig.breath(): Vector3
	local scale = Config.breathing.byState[moveState()] or 0.6
	local phase = breathClock * Config.breathing.rate * math.pi * 2
	local amount = Config.breathing.amplitude * scale
	-- A figure of eight rather than a line: a straight bob is a metronome, and
	-- a metronome is the one motion the eye locks onto and cannot unsee.
	return Vector3.new(math.sin(phase) * amount, math.sin(phase * 2) * amount * 0.5, 0)
end

-- ---------------------------------------------------------------------------
-- The foreign-writer check
-- ---------------------------------------------------------------------------

local function audit()
	local camera = workspace.CurrentCamera
	local expected = lastWritten
	if not camera or not expected then
		return
	end

	local actual = camera.CFrame
	local moved = (actual.Position - expected.Position).Magnitude
	local turned = math.abs(actual.LookVector:Dot(expected.LookVector))
	if moved <= Config.auditPositionStuds and turned >= Config.auditAngleDot then
		driftFrames = 0
		return
	end

	driftFrames += 1
	if driftFrames < Config.auditFrames or driftReported then
		return
	end
	driftReported = true
	Diagnostics.warn(
		SYSTEM,
		`something outside the rig is writing the camera — it has drifted {string.format("%.2f", moved)} studs `
			.. `from what the chain last wrote, {driftFrames} frames running. Every camera write belongs in a `
			.. `CameraRig slot; find the BindToRenderStep that is not one.`
	)
end

-- ---------------------------------------------------------------------------
-- Stillness check (the jitter test)
--
-- Samples the camera for `seconds` and reports the worst frame-to-frame change.
-- Public and callable at any time rather than a one-off script, because "the
-- camera is jittery" is a thing someone says about a build months from now and
-- the answer should be a number they can produce themselves.
-- ---------------------------------------------------------------------------

function CameraRig.stillness(seconds: number?): (number, number, number)
	local duration = seconds or 5
	local camera = workspace.CurrentCamera
	if not camera then
		return 0, 0, 0
	end

	local previous = camera.CFrame
	local worst, total, frames = 0, 0, 0
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		RunService.RenderStepped:Wait()
		local current = camera.CFrame
		local delta = (current.Position - previous.Position).Magnitude
			+ math.deg(math.acos(math.clamp(current.LookVector:Dot(previous.LookVector), -1, 1)))
		worst = math.max(worst, delta)
		total += delta
		frames += 1
		previous = current
	end

	return worst, (if frames > 0 then total / frames else 0), frames
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

function CameraRig.init()
	-- The rig owns Effects itself: roll, tilt, dip and FOV are camera work with
	-- no other home, and giving them to a controller is how they ended up spread
	-- across three files in the first place.
	CameraRig.claim("Effects", SYSTEM, effects)

	-- Last minus one, so it runs after every camera slot and before MouseUnlock.
	RunService:BindToRenderStep(AUDIT_BIND, Enum.RenderPriority.Last.Value - 1, audit)

	local claimed: { string } = {}
	for _, entry in SLOTS do
		table.insert(claimed, entry.slot)
	end
	Diagnostics.ok(
		SYSTEM,
		`{#SLOTS} slots: {table.concat(claimed, " → ")} · FOV {Config.fovMin}-{Config.fovMax}, base {Config.baseFov} · `
			.. `combat only · foreign-writer check armed`
	)
end

return CameraRig
