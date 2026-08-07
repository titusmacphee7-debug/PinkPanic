--!strict
-- HitFeedbackController — the juice (NOD-17 first pass): crosshair, hitmarker
-- flash, floating damage numbers. The pink UI kit (M5) will restyle all of
-- this; for now it's functional and lightly on-theme.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local EffectsController = require(script.Parent.EffectsController)

local PINK = Color3.fromRGB(255, 105, 180)
local KILL_RED = Color3.fromRGB(255, 64, 96)

local HitFeedbackController = {}

local hitmarker: TextLabel? = nil

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatFeedback"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(4, 4)
	crosshair.BackgroundColor3 = PINK
	crosshair.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = crosshair
	crosshair.Parent = screen

	local marker = Instance.new("TextLabel")
	marker.Name = "Hitmarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(40, 40)
	marker.BackgroundTransparency = 1
	marker.Text = "✕"
	marker.TextSize = 28
	marker.TextColor3 = PINK
	marker.TextTransparency = 1
	marker.Parent = screen
	hitmarker = marker

	screen.Parent = playerGui
end

local function flashHitmarker(killed: boolean)
	local marker = hitmarker
	if not marker then
		return
	end
	marker.TextColor3 = if killed then KILL_RED else PINK
	marker.TextTransparency = 0
	TweenService:Create(marker, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
end

local function showDamageNumber(amount: number, worldPosition: Vector3, killed: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = worldPosition
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.StudsOffset = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(amount)
	label.TextSize = if killed then 26 else 20
	label.TextColor3 = if killed then KILL_RED else Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Parent = billboard

	TweenService:Create(billboard, TweenInfo.new(0.6), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	task.delay(0.7, function()
		anchor:Destroy()
	end)
end

function HitFeedbackController.init()
	buildGui()

	Remotes.event("DamageDealt").OnClientEvent:Connect(function(amount, worldPosition, killed)
		flashHitmarker(killed == true)
		EffectsController.playHitSound()
		if type(amount) == "number" and typeof(worldPosition) == "Vector3" then
			showDamageNumber(amount, worldPosition, killed == true)
		end
	end)

	-- Killfeed UI proper lands with the HUD (NOD-37); log entries until then.
	Remotes.event("Killfeed").OnClientEvent:Connect(function(entry)
		if type(entry) == "table" then
			local killer = entry.killer or "the void"
			print(`[Killfeed] {killer} → {entry.victim}`)
		end
	end)
end

return HitFeedbackController
