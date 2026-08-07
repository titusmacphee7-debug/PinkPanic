--!strict
-- EconomyController — coins + level/XP display (top-left, Pink Panic style),
-- driven entirely by server DataChanged snapshots. Coin gains pop a little
-- "+n" so kills feel rewarding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local BLUSH = Color3.fromRGB(255, 227, 240)
local TEXT_DARK = Color3.fromRGB(96, 56, 78)
local GOLD = Color3.fromRGB(255, 196, 88)

local EconomyController = {}

local coins = 0
local panel: Frame
local coinsLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local xpText: TextLabel

local function mkText(parent: Instance, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "EconomyHUD"
	screen.ResetOnSpawn = false

	panel = Instance.new("Frame")
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.Size = UDim2.fromOffset(210, 74)
	panel.BackgroundColor3 = BLUSH
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = panel

	coinsLabel = mkText(panel, 20, TEXT_DARK)
	coinsLabel.Position = UDim2.new(0, 12, 0, 6)
	coinsLabel.Size = UDim2.new(1, -24, 0, 24)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsLabel.Text = "🪙 0"

	levelLabel = mkText(panel, 16, DEEP_PINK)
	levelLabel.Position = UDim2.new(0, 12, 0, 32)
	levelLabel.Size = UDim2.new(0, 70, 0, 18)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Text = "Lv 1"

	local xpBar = Instance.new("Frame")
	xpBar.Position = UDim2.new(0, 12, 0, 54)
	xpBar.Size = UDim2.new(1, -24, 0, 10)
	xpBar.BackgroundColor3 = Color3.fromRGB(255, 245, 250)
	xpBar.BorderSizePixel = 0
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = xpBar

	xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = HOT_PINK
	xpFill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = xpFill
	xpFill.Parent = xpBar
	xpBar.Parent = panel

	xpText = mkText(panel, 12, DEEP_PINK)
	xpText.AnchorPoint = Vector2.new(1, 0)
	xpText.Position = UDim2.new(1, -12, 0, 32)
	xpText.Size = UDim2.new(0, 110, 0, 18)
	xpText.TextXAlignment = Enum.TextXAlignment.Right

	panel.Parent = screen
	screen.Parent = playerGui
end

local function popCoinGain(amount: number)
	local pop = mkText(panel, 18, GOLD)
	pop.AnchorPoint = Vector2.new(0, 0)
	pop.Position = UDim2.new(1, 10, 0, 8)
	pop.Size = UDim2.fromOffset(80, 24)
	pop.TextXAlignment = Enum.TextXAlignment.Left
	pop.TextStrokeColor3 = TEXT_DARK
	pop.TextStrokeTransparency = 0.6
	pop.Text = `+{amount} 🪙`
	TweenService:Create(pop, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
		Position = UDim2.new(1, 10, 0, -22),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function()
		pop:Destroy()
	end)
end

local function applySnapshot(data: any)
	if type(data) ~= "table" then
		return
	end
	local newCoins = if type(data.coins) == "number" then data.coins else coins
	if newCoins > coins then
		popCoinGain(newCoins - coins)
	end
	coins = newCoins
	coinsLabel.Text = `🪙 {coins}`

	if type(data.level) == "number" then
		levelLabel.Text = `Lv {data.level}`
	end
	if type(data.xp) == "number" and type(data.xpToNext) == "number" and data.xpToNext > 0 then
		local alpha = math.clamp(data.xp / data.xpToNext, 0, 1)
		TweenService:Create(xpFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(alpha, 1) }):Play()
		xpText.Text = `{data.xp} / {data.xpToNext} xp`
	end
end

function EconomyController.init()
	buildGui()
	Remotes.event("DataChanged").OnClientEvent:Connect(applySnapshot)
end

return EconomyController
