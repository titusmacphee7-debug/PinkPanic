--!strict
-- SettingsController — ⚙️ panel (NOD-44): mouse sensitivity + volume sliders
-- and the starting-weapon loadout picker (NOD-28), all persisted server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local BLUSH = Color3.fromRGB(255, 227, 240)
local ROW_WHITE = Color3.fromRGB(255, 245, 250)
local TEXT_DARK = Color3.fromRGB(96, 56, 78)

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local SettingsController = {}

local panel: Frame
local modalUnlock: TextButton
local weaponButtons: { [string]: TextButton } = {}
local sensSlider: { set: (number) -> () }
local volSlider: { set: (number) -> () }
local suppressCallbacks = false

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

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function applySensitivity(value: number)
	-- Scriptable in live games; pcall in case a platform locks it.
	pcall(function()
		UserGameSettings.MouseSensitivity = value
	end)
end

local function persist(payload: { [string]: any })
	task.spawn(function()
		pcall(function()
			return Remotes.func("UpdateSettings"):InvokeServer(payload)
		end)
	end)
end

-- A draggable slider: returns a handle with set(value) for external sync.
-- onChanged fires live while dragging; onCommitted once on release.
local function mkSlider(
	parent: Instance,
	yOffset: number,
	min: number,
	max: number,
	onChanged: (number) -> (),
	onCommitted: (number) -> ()
): { set: (number) -> () }
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 24, 0, yOffset)
	bar.Size = UDim2.new(1, -48, 0, 10)
	bar.BackgroundColor3 = ROW_WHITE
	bar.BorderSizePixel = 0
	round(bar, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = HOT_PINK
	fill.BorderSizePixel = 0
	round(fill, 5)
	fill.Parent = bar

	local knob = Instance.new("TextButton")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0.5, 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.BackgroundColor3 = DEEP_PINK
	knob.Text = ""
	round(knob, 9)
	knob.Parent = bar
	bar.Parent = parent

	local value = min
	local dragging = false

	local function setAlpha(alpha: number, fire: boolean)
		alpha = math.clamp(alpha, 0, 1)
		value = min + (max - min) * alpha
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		if fire then
			onChanged(value)
		end
	end

	local function alphaFromX(x: number): number
		return (x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
	end

	local function beginDrag(x: number)
		dragging = true
		setAlpha(alphaFromX(x), true)
	end

	knob.MouseButton1Down:Connect(function()
		dragging = true
	end)
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			beginDrag(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setAlpha(alphaFromX(input.Position.X), true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			onCommitted(value)
		end
	end)

	return {
		set = function(newValue: number)
			local alpha = (newValue - min) / math.max(max - min, 0.0001)
			setAlpha(alpha, false)
		end,
	}
end

local function highlightWeapon(selected: string)
	for weaponId, button in weaponButtons do
		local isSelected = weaponId == selected
		button.BackgroundColor3 = if isSelected then HOT_PINK else ROW_WHITE
		button.TextColor3 = if isSelected then Color3.new(1, 1, 1) else TEXT_DARK
	end
end

local function setOpen(open: boolean)
	ClientData.settingsOpen = open
	panel.Visible = open
	modalUnlock.Visible = open
	modalUnlock.Modal = open
	ClientData.updateMouseUnlock()
end

local function applySnapshot(data: any)
	if type(data) ~= "table" then
		return
	end
	suppressCallbacks = true
	local settings = data.settings
	if type(settings) == "table" then
		if type(settings.sensitivity) == "number" then
			sensSlider.set(settings.sensitivity)
			applySensitivity(settings.sensitivity)
		end
		if type(settings.volume) == "number" then
			volSlider.set(settings.volume)
		end
	end
	local equipped = data.equipped
	if type(equipped) == "table" and type(equipped.weapon) == "string" then
		highlightWeapon(equipped.weapon)
	end
	suppressCallbacks = false
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "SettingsUI"
	screen.ResetOnSpawn = false

	modalUnlock = Instance.new("TextButton")
	modalUnlock.Size = UDim2.fromOffset(1, 1)
	modalUnlock.Position = UDim2.new(0, -10, 0, -10)
	modalUnlock.BackgroundTransparency = 1
	modalUnlock.Text = ""
	modalUnlock.Visible = false
	modalUnlock.Modal = false
	modalUnlock.Parent = screen

	local openButton = Instance.new("TextButton")
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 160, 1, -12)
	openButton.Size = UDim2.fromOffset(42, 42)
	openButton.BackgroundColor3 = HOT_PINK
	openButton.Font = Enum.Font.FredokaOne
	openButton.TextSize = 20
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "⚙️"
	round(openButton, 21)
	openButton.MouseButton1Click:Connect(function()
		setOpen(not panel.Visible)
	end)
	openButton.Parent = screen

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(400, 330)
	panel.BackgroundColor3 = BLUSH
	panel.Visible = false
	round(panel, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = mkText(panel, 24, DEEP_PINK)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Text = "🎀 SETTINGS 🎀"

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = HOT_PINK
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "✕"
	round(close, 15)
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)
	close.Parent = panel

	local sensLabel = mkText(panel, 17, TEXT_DARK)
	sensLabel.Position = UDim2.new(0, 24, 0, 56)
	sensLabel.Size = UDim2.new(1, -48, 0, 20)
	sensLabel.TextXAlignment = Enum.TextXAlignment.Left
	sensLabel.Text = "Mouse sensitivity"
	sensSlider = mkSlider(panel, 84, 0.2, 3, function(value)
		if not suppressCallbacks then
			applySensitivity(value)
		end
	end, function(value)
		persist({ sensitivity = value })
	end)

	local volLabel = mkText(panel, 17, TEXT_DARK)
	volLabel.Position = UDim2.new(0, 24, 0, 112)
	volLabel.Size = UDim2.new(1, -48, 0, 20)
	volLabel.TextXAlignment = Enum.TextXAlignment.Left
	volLabel.Text = "Sound volume"
	volSlider = mkSlider(panel, 140, 0, 1, function() end, function(value)
		persist({ volume = value })
	end)

	local loadoutLabel = mkText(panel, 17, TEXT_DARK)
	loadoutLabel.Position = UDim2.new(0, 24, 0, 176)
	loadoutLabel.Size = UDim2.new(1, -48, 0, 20)
	loadoutLabel.TextXAlignment = Enum.TextXAlignment.Left
	loadoutLabel.Text = "Starting weapon (next spawn)"

	local row = Instance.new("Frame")
	row.Position = UDim2.new(0, 24, 0, 204)
	row.Size = UDim2.new(1, -48, 0, 40)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	for _, weaponId in GameConfig.loadout do
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(82, 36)
		button.BackgroundColor3 = ROW_WHITE
		button.Font = Enum.Font.FredokaOne
		button.TextSize = 14
		button.TextColor3 = TEXT_DARK
		button.Text = WeaponConfig[weaponId].displayName
		round(button, 10)
		button.MouseButton1Click:Connect(function()
			highlightWeapon(weaponId)
			persist({ startingWeapon = weaponId })
		end)
		button.Parent = row
		weaponButtons[weaponId] = button
	end
	row.Parent = panel

	local hint = mkText(panel, 14, DEEP_PINK)
	hint.Position = UDim2.new(0, 24, 1, -60)
	hint.Size = UDim2.new(1, -48, 0, 40)
	hint.TextWrapped = true
	hint.Text = "Controls: 1–4 switch · R reload · B shop · Tab scoreboard"

	panel.Parent = screen
	screen.Parent = playerGui
end

function SettingsController.init()
	buildGui()

	ClientData.changed:Connect(applySnapshot)
	if ClientData.snapshot then
		applySnapshot(ClientData.snapshot)
	end
end

return SettingsController
