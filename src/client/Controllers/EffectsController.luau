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

local SHOT_SOUND = "rbxasset://sounds/snap.mp3"
local HIT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local TRACER_PINK = Color3.fromRGB(255, 150, 200)

local EffectsController = {}

local function playSound(soundId: string, volume: number, playbackSpeed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
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

function EffectsController.init()
	Remotes.event("ShotFired").OnClientEvent:Connect(function(shooter, origin, endpoint)
		-- The local player already drew their own effects at fire time.
		if shooter == Players.LocalPlayer then
			return
		end
		if typeof(origin) == "Vector3" and typeof(endpoint) == "Vector3" then
			EffectsController.drawTracer(origin, endpoint)
			EffectsController.playShotSound(0.35)
		end
	end)
end

return EffectsController
