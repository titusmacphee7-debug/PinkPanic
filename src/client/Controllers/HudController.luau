--!strict
-- HudController — in-round HUD (NOD-37): health bar, ammo + weapon name, and
-- the killfeed, all in the Pink Panic style. Coins/level live in
-- EconomyController's panel; crosshair/hitmarker in HitFeedbackController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local BLUSH = Color3.fromRGB(255, 227, 240)
local TEXT_DARK = Color3.fromRGB(96, 56, 78)
local HEALTH_LOW = Color3.fromRGB(235, 90, 90)

local HudController = {}

local combatPanel: Frame
local healthFill: Frame
local healthText: TextLabel
local weaponLabel: TextLabel
local ammoLabel: TextLabel
local killfeedList: Frame

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

local function stylePanel(frame: Frame, radius: number)
	frame.BackgroundColor3 = BLUSH
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = frame
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatHUD"
	screen.ResetOnSpawn = false

	-- Bottom-center: health + ammo (combat only; hidden in the lobby)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -14)
	panel.Size = UDim2.fromOffset(380, 58)
	stylePanel(panel, 16)
	combatPanel = panel

	local healthBar = Instance.new("Frame")
	healthBar.Position = UDim2.new(0, 14, 0, 12)
	healthBar.Size = UDim2.new(0, 180, 0, 16)
	healthBar.BackgroundColor3 = Color3.fromRGB(255, 245, 250)
	healthBar.BorderSizePixel = 0
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = healthBar
	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = HOT_PINK
	healthFill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = healthFill
	healthFill.Parent = healthBar
	healthBar.Parent = panel

	healthText = mkText(panel, 14, TEXT_DARK)
	healthText.Position = UDim2.new(0, 14, 0, 32)
	healthText.Size = UDim2.new(0, 180, 0, 18)
	healthText.Text = "💗 100"

	weaponLabel = mkText(panel, 16, DEEP_PINK)
	weaponLabel.AnchorPoint = Vector2.new(1, 0)
	weaponLabel.Position = UDim2.new(1, -14, 0, 8)
	weaponLabel.Size = UDim2.new(0, 150, 0, 20)
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
	weaponLabel.Text = "Pistol"

	ammoLabel = mkText(panel, 20, TEXT_DARK)
	ammoLabel.AnchorPoint = Vector2.new(1, 0)
	ammoLabel.Position = UDim2.new(1, -14, 0, 28)
	ammoLabel.Size = UDim2.new(0, 150, 0, 24)
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoLabel.Text = "12 / 12"

	panel.Parent = screen

	-- Killfeed: right side, under the players panel
	killfeedList = Instance.new("Frame")
	killfeedList.AnchorPoint = Vector2.new(1, 0)
	killfeedList.Position = UDim2.new(1, -12, 0, 320)
	killfeedList.Size = UDim2.fromOffset(240, 0)
	killfeedList.AutomaticSize = Enum.AutomaticSize.Y
	killfeedList.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = killfeedList
	killfeedList.Parent = screen

	screen.Parent = playerGui
end

local killfeedOrder = 0

local function addKillfeedRow(killer: string?, victim: string)
	killfeedOrder += 1
	local row = Instance.new("Frame")
	row.LayoutOrder = killfeedOrder
	row.Size = UDim2.fromOffset(0, 26)
	row.AutomaticSize = Enum.AutomaticSize.X
	stylePanel(row, 13)

	local label = mkText(row, 15, TEXT_DARK)
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Position = UDim2.new(0, 0, 0, 0)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
	local you = Players.LocalPlayer.Name
	local killerText = killer or "☁️"
	label.Text = `{killerText} 💥 {victim}`
	if killer == you or victim == you then
		label.TextColor3 = DEEP_PINK
	end

	row.Parent = killfeedList
	task.delay(4, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 })
		TweenService:Create(row, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		tween:Play()
		tween.Completed:Wait()
		row:Destroy()
	end)
end

local function updateHealth()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = if humanoid then math.max(0, math.floor(humanoid.Health + 0.5)) else 0
	local maxHealth = if humanoid then math.max(humanoid.MaxHealth, 1) else 100
	local alpha = math.clamp(health / maxHealth, 0, 1)
	healthFill.Size = UDim2.fromScale(alpha, 1)
	healthFill.BackgroundColor3 = if alpha < 0.3 then HEALTH_LOW else HOT_PINK
	healthText.Text = `💗 {health}`
end

local function applyAmmo(data: any)
	if type(data) ~= "table" then
		return
	end
	local config = WeaponConfig[data.weaponId]
	weaponLabel.Text = if type(data.name) == "string"
		then data.name
		elseif config then config.displayName
		else tostring(data.gunId or data.weaponId)
	if type(data.magSize) == "number" and data.magSize <= 0 then
		ammoLabel.Text = "∞"
	elseif data.reloading then
		ammoLabel.Text = "Reloading…"
	else
		ammoLabel.Text = `{data.ammo} / {data.magSize}`
	end
end

function HudController.init()
	buildGui()

	RunService.Heartbeat:Connect(updateHealth)
	combatPanel.Visible = not ClientData.inLobby()
	ClientData.roundStateChanged:Connect(function()
		combatPanel.Visible = not ClientData.inLobby()
	end)
	Remotes.event("AmmoChanged").OnClientEvent:Connect(applyAmmo)
	Remotes.event("Killfeed").OnClientEvent:Connect(function(entry)
		if type(entry) == "table" and type(entry.victim) == "string" then
			addKillfeedRow(entry.killer, entry.victim)
		end
	end)
end

return HudController
