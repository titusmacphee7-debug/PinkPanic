--!strict
-- EffectsController — shot visuals and sounds. Local shots draw effects
-- immediately at fire time; everyone else's validated shots arrive via the
-- ShotFired remote. Bullets fly as real projectiles (mesh + trail when a
-- Bullet template exists, neon streak fallback), and every shot ejects a
-- shell that tumbles with real physics then freezes where it lands, so
-- spent brass litters the floor all round at near-zero cost. Placeholder
-- audio uses engine-bundled sounds until the real SFX pass (NOD-40).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunModelLoader = require(ReplicatedStorage.Shared.Loaders.GunModelLoader)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)

local SHOT_SOUND = "rbxasset://sounds/snap.mp3"
local HIT_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local MAX_SHELLS = 180 -- oldest brass despawns past this
local SHELL_SIZE = 0.35 -- longest axis after import normalization, studs
local BULLET_SIZE = 0.45
local SHELL_EJECT_RANGE = 140 -- no shells for shooters further away than this

local EffectsController = {}

local rng = Random.new()

-- Player-set volume from settings scales every effect sound.
local function volumeMultiplier(): number
	local snap = ClientData.snapshot
	local settings = snap and snap.settings
	local value = settings and settings.volume
	return if type(value) == "number" then math.clamp(value, 0, 1) else 1
end

local function playSound(soundId: string, volume: number, playbackSpeed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume * volumeMultiplier()
	sound.PlaybackSpeed = playbackSpeed
	SoundService:PlayLocalSound(sound)
	task.delay(2, function()
		sound:Destroy()
	end)
end

function EffectsController.playShotSound(volume: number)
	-- Pitched up and randomized slightly so rapid shots don't sound robotic.
	playSound(SHOT_SOUND, volume, 1.5 + math.random() * 0.2)
end

function EffectsController.playHitSound()
	playSound(HIT_SOUND, 0.5, 1.4)
end

-- ============ Effect mesh templates ============
-- Drop MeshParts named "Bullet" and "Shell" into a ReplicatedStorage folder
-- called "EffectModels" (Studio-side, exactly like GunModels) and they're
-- picked up automatically — any import size works, they get normalized.
-- Until then a neon streak / brass cylinder stand in.

local preppedBullet: BasePart? = nil
local preppedShell: BasePart? = nil

local function findEffectPart(name: string): BasePart?
	local roots: { Instance } = {}
	local direct = ReplicatedStorage:FindFirstChild("EffectModels")
	if direct then
		table.insert(roots, direct)
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local assets = shared and shared:FindFirstChild("Assets")
	local nested = assets and assets:FindFirstChild("EffectModels")
	if nested then
		table.insert(roots, nested)
	end
	for _, root in roots do
		local found = root:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function prepEffectPart(source: BasePart, targetSize: number): BasePart
	local part = source:Clone()
	local size = part.Size
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		part.Size = size * (targetSize / longest)
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false -- brass must NEVER catch bullets or armory clicks
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = false
	return part
end

local function bulletTemplate(): BasePart?
	if preppedBullet then
		return preppedBullet
	end
	local source = findEffectPart("Bullet")
	if not source then
		return nil
	end
	local part = prepEffectPart(source, BULLET_SIZE)
	part.Anchored = true
	-- Pink tracer ribbon streams off the tail so fast rounds stay readable.
	local rear = part.Size.Z / 2
	local above = Instance.new("Attachment")
	above.Position = Vector3.new(0, 0.03, rear)
	above.Parent = part
	local below = Instance.new("Attachment")
	below.Position = Vector3.new(0, -0.03, rear)
	below.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = above
	trail.Attachment1 = below
	trail.Color = ColorSequence.new(Theme.color.primarySoft)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.Lifetime = 0.07
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = part
	preppedBullet = part
	return part
end

local function shellTemplate(): BasePart
	if preppedShell then
		return preppedShell
	end
	local source = findEffectPart("Shell")
	local part: BasePart
	if source then
		part = prepEffectPart(source, SHELL_SIZE)
	else
		local placeholder = Instance.new("Part")
		placeholder.Shape = Enum.PartType.Cylinder
		placeholder.Size = Vector3.new(SHELL_SIZE, 0.13, 0.13)
		placeholder.Color = Theme.color.brass
		placeholder.Material = Enum.Material.Metal
		part = prepEffectPart(placeholder, SHELL_SIZE)
	end
	part.CanCollide = true -- shells bounce off the world (but stay unclickable)
	part.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0.35, 1, 1)
	preppedShell = part
	return part
end

-- ============ Shell casings ============
local shellBin: Folder? = nil
local shells: { BasePart } = {}

local function ensureShellBin(): Folder
	local bin = shellBin
	if bin and bin.Parent then
		return bin
	end
	local folder = Instance.new("Folder")
	folder.Name = "ShellBin"
	folder.Parent = workspace
	shellBin = folder
	return folder
end

-- Freeze brass once it settles: anchored parts have zero physics cost, so
-- the floor can stay littered for the whole round.
local function settleShell(shell: BasePart, attempt: number)
	task.delay(1.4, function()
		if not shell.Parent then
			return
		end
		if shell.Position.Y < -150 then
			shell:Destroy() -- rolled off the map
			return
		end
		if shell.AssemblyLinearVelocity.Magnitude < 2.5 or attempt >= 2 then
			shell.Anchored = true
		else
			settleShell(shell, attempt + 1)
		end
	end)
end

-- Pops a shell out of the ejection port: right + up with tumble, exactly
-- like the guns it grew up watching.
function EffectsController.ejectShell(port: CFrame)
	local shell = shellTemplate():Clone()
	shell.CFrame = port * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.4, 0.4), 0)
	shell.AssemblyLinearVelocity = port.RightVector * rng:NextNumber(7, 11)
		+ port.UpVector * rng:NextNumber(5, 8)
		+ port.LookVector * rng:NextNumber(-1.5, 1.5)
	shell.AssemblyAngularVelocity = Vector3.new(
		rng:NextNumber(-25, 25),
		rng:NextNumber(-25, 25),
		rng:NextNumber(-25, 25)
	)
	shell.Parent = ensureShellBin()
	table.insert(shells, shell)
	if #shells > MAX_SHELLS then
		local oldest = table.remove(shells, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	settleShell(shell, 1)
end

function EffectsController.clearShells()
	table.clear(shells)
	local bin = shellBin
	if bin then
		bin:ClearAllChildren()
	end
end

function EffectsController.drawTracer(origin: Vector3, endpoint: Vector3)
	local distance = (endpoint - origin).Magnitude
	if distance < 1 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Theme.color.primarySoft
	tracer.Transparency = 0.15
	tracer.Size = Vector3.new(0.08, 0.08, distance)
	tracer.CFrame = CFrame.lookAt(origin, endpoint) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace

	TweenService:Create(tracer, TweenInfo.new(0.12), { Transparency = 1 }):Play()
	task.delay(0.15, function()
		tracer:Destroy()
	end)
end

-- Animated ballistic streaks: visuals fly with the same velocity/drop the
-- server simulates, so what you see is what the server computes.
type Streak = { part: BasePart, velocity: Vector3, drop: number, traveled: number, travelMax: number }
local streaks: { Streak } = {}

function EffectsController.launchProjectileVisual(
	origin: Vector3,
	direction: Vector3,
	velocity: number,
	drop: number,
	travelMax: number
)
	if velocity <= 0 then
		return
	end
	local template = bulletTemplate()
	local part: BasePart
	if template then
		part = template:Clone()
	else
		local streakPart = Instance.new("Part")
		streakPart.Anchored = true
		streakPart.CanCollide = false
		streakPart.CanQuery = false
		streakPart.CanTouch = false
		streakPart.CastShadow = false
		streakPart.Material = Enum.Material.Neon
		streakPart.Color = Theme.color.primarySoft
		streakPart.Transparency = 0.1
		streakPart.Size = Vector3.new(0.06, 0.06, math.clamp(velocity * 0.02, 1.5, 8))
		part = streakPart
	end
	part.CFrame = CFrame.lookAlong(origin, direction)
	part.Parent = workspace
	table.insert(streaks, {
		part = part,
		velocity = direction * velocity,
		drop = drop,
		traveled = 0,
		travelMax = travelMax,
	})
end

local function stepStreaks(deltaTime: number)
	for index = #streaks, 1, -1 do
		local streak = streaks[index]
		streak.velocity += Vector3.new(0, -streak.drop * deltaTime, 0)
		local step = streak.velocity * deltaTime
		local newPosition = streak.part.Position + step
		streak.traveled += step.Magnitude
		if streak.traveled >= streak.travelMax then
			streak.part:Destroy()
			table.remove(streaks, index)
		else
			streak.part.CFrame = CFrame.lookAlong(newPosition, streak.velocity.Unit)
		end
	end
end

-- Other players' shells pop from the gun welded to their hand.
-- Where shells come out.
--
-- The tagged EjectPort socket first (NOD-137), because it is the only answer
-- that is actually right. The offset-from-the-pivot fallback below is a guess
-- about a shape nobody measured, and it is the reason shells used to appear
-- out of the middle of a stock.
local function worldGunPort(shooter: Player): CFrame?
	local character = shooter.Character
	local gun = character and character:FindFirstChild("WorldGun")
	if not gun or not gun:IsA("Model") then
		return nil
	end

	local socket = GunModelLoader.socketCFrame(gun, "EjectPort")
	if socket then
		return socket
	end

	local primary = gun.PrimaryPart
	if primary then
		return primary.CFrame * CFrame.new(primary.Size.X / 2 + 0.05, primary.Size.Y * 0.2, 0)
	end
	return nil
end

function EffectsController.init()
	RunService.Heartbeat:Connect(stepStreaks)

	-- REBUILD: settled shells used to be swept on every round start ("fresh
	-- round, fresh floor") via RoundStateChanged. That remote went with the
	-- round loop, so nothing clears them now — call EffectsController.clearShells()
	-- from the new loop's round-start transition.

	-- Hitmarker feedback. Sent only to the shooter, and only when the SERVER
	-- decided a hit landed — so it never lies about a shot that missed, which
	-- is the whole reason a client-predicted hitmarker is worse than none.
	-- Visual treatment lands with the HUD in M12; the sound is real now,
	-- because silent hits are worse than plain ones.
	Remotes.listen("DamageDealt", function(amount, zone)
		if type(amount) ~= "number" then
			return
		end
		-- A headshot sounds different. It is the one distinction worth making
		-- before the UI pass, because it changes what you do next.
		playSound(HIT_SOUND, 0.55, if zone == "Head" then 1.75 else 1.4)
	end)

	Remotes.listen("ShotFired", function(shooter, origin, direction, velocity, drop, travelMax, pellets)
		-- The local player already drew their own effects at fire time.
		if shooter == Players.LocalPlayer then
			return
		end
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		if type(velocity) == "number" and velocity > 0 then
			local count = math.min(if type(pellets) == "number" then pellets else 1, 3)
			for _ = 1, count do
				EffectsController.launchProjectileVisual(
					origin, direction,
					velocity,
					if type(drop) == "number" then drop else 60,
					if type(travelMax) == "number" then travelMax else 300
				)
			end
			EffectsController.playShotSound(0.35)

			-- One shell per shot, skipped for far-away shooters nobody can see.
			local camera = workspace.CurrentCamera
			if
				camera
				and (origin - camera.CFrame.Position).Magnitude <= SHELL_EJECT_RANGE
				and typeof(shooter) == "Instance"
				and shooter:IsA("Player")
			then
				local port = worldGunPort(shooter)
					or CFrame.lookAlong(origin, direction) * CFrame.new(0.35, -0.15, 0.5)
				EffectsController.ejectShell(port)
			end
		elseif typeof(direction) == "Vector3" then
			-- Melee / legacy: instant short tracer.
			EffectsController.drawTracer(origin, origin + direction * 8)
			EffectsController.playShotSound(0.3)
		end
	end)
end

return EffectsController
