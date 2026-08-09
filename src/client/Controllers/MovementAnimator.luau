--!strict
-- MovementAnimator (NOD-100) — procedural movement poses for EVERY character,
-- driven purely by observed velocity, so no replication is needed: sprinters
-- lean forward, sliders tilt back low. Applied via the torso joint's C0
-- (animations own Transform; C0 is ours), smoothed per character. Authored
-- animation clips can replace this in the art pass.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SPRINT_SPEED_THRESHOLD = 26
local SLIDE_SPEED_THRESHOLD = 36
local SPRINT_LEAN = math.rad(9) -- forward
local SLIDE_LEAN = math.rad(-24) -- backward, low
local SMOOTHING = 10

local MovementAnimator = {}

type PoseState = {
	joint: Motor6D,
	originalC0: CFrame,
	pitch: number,
}

local states: { [Model]: PoseState } = {}

local function stateFor(model: Model): PoseState?
	local existing = states[model]
	if existing and existing.joint.Parent then
		return existing
	end
	local lowerTorso = model:FindFirstChild("LowerTorso")
	local joint = lowerTorso and lowerTorso:FindFirstChild("Root")
	if not joint or not joint:IsA("Motor6D") then
		return nil -- R6 or still loading; skip quietly
	end
	local fresh = { joint = joint, originalC0 = joint.C0, pitch = 0 }
	states[model] = fresh
	return fresh
end

local function update(deltaTime: number)
	local alpha = math.min(deltaTime * SMOOTHING, 1)
	for _, player in Players:GetPlayers() do
		local model = player.Character
		if not model then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local pose = stateFor(model)
		if not pose then
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local target = 0
		if speed >= SLIDE_SPEED_THRESHOLD then
			target = SLIDE_LEAN
		elseif speed >= SPRINT_SPEED_THRESHOLD then
			target = SPRINT_LEAN
		end

		pose.pitch += (target - pose.pitch) * alpha
		if math.abs(pose.pitch) > 0.005 then
			pose.joint.C0 = pose.originalC0 * CFrame.Angles(pose.pitch, 0, 0)
		else
			pose.joint.C0 = pose.originalC0
		end
	end

	-- Drop states for despawned characters.
	for model in states do
		if not model.Parent then
			states[model] = nil
		end
	end
end

function MovementAnimator.init()
	RunService.Heartbeat:Connect(update)
end

return MovementAnimator
