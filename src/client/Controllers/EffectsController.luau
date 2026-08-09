--!strict
-- EffectsController — shot tracers and sounds. Local shots draw effects
-- immediately at fire time; everyone else's validated shots arrive via the
-- ShotFired remote. Placeholder audio uses engine-bundled sounds until the
-- real SFX pass (NOD-40).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ClientData = require(script.Parent.Parent.ClientData)

local SHOT_SOUND = "rbxasset://sounds/snap.mp3"
local HIT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local TRACER_PINK = Color3.fromRGB(255, 150, 200)

local EffectsController = {}

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
	tracer.Color = TRACER_PINK
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
	local length = math.clamp(velocity * 0.02, 1.5, 8)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = TRACER_PINK
	part.Transparency = 0.1
	part.Size = Vector3.new(0.06, 0.06, length)
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

function EffectsController.init()
	game:GetService("RunService").Heartbeat:Connect(stepStreaks)

	Remotes.event("ShotFired").OnClientEvent:Connect(function(shooter, origin, direction, velocity, drop, travelMax, pellets)
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
		elseif typeof(direction) == "Vector3" then
			-- Melee / legacy: instant short tracer.
			EffectsController.drawTracer(origin, origin + direction * 8)
			EffectsController.playShotSound(0.3)
		end
	end)
end

return EffectsController
