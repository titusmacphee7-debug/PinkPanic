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
local Theme = require(script.Parent.Parent.UI.Theme)


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
			return Remotes.invoke("UpdateSettings", payload)
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
	bar.BackgroundColor3 = Theme.color.surfaceRaised
	bar.BorderSizePixel = 0
	round(bar, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = Theme.color.primary
	fill.BorderSizePixel = 0
	round(fill, 5)
	fill.Parent = bar

	local knob = Instance.new("TextButton")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0.5, 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.BackgroundColor3 = Theme.color.primaryDeep
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
		button.BackgroundColor3 = if isSelected then Theme.color.primary else Theme.color.surfaceRaised
		button.TextColor3 = if isSelected then Color3.new(1, 1, 1) else Theme.color.text
	end
end

function SettingsController.setOpen(open: boolean)
	if panel.Visible == open then
		return
	end
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

	-- FULL-SCREEN, deliberately — see the note in ShopController. A 1x1 button
	-- parked offscreen frees the cursor but sinks no clicks, so every click on
	-- this panel also fired a lobby shot through it.
	modalUnlock = Instance.new("TextButton")
	modalUnlock.Size = UDim2.fromScale(1, 1)
	modalUnlock.BackgroundTransparency = 1
	modalUnlock.Text = ""
	modalUnlock.Visible = false
	modalUnlock.Modal = false
	modalUnlock.Parent = screen

	-- No floating gear button. Titus asked for it gone along with the shop
	-- button — settings is not a thing you want on screen while you play, and
	-- two chrome buttons parked over his lobby art was the whole complaint. The
	-- keybind below is how you open it.

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(400, 330)
	panel.BackgroundColor3 = Theme.color.surface
	panel.Visible = false
	round(panel, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.color.primary
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = mkText(panel, 24, Theme.color.primaryDeep)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Text = "🎀 SETTINGS 🎀"

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = Theme.color.primary
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	-- Was "✕" (U+2715), which FredokaOne does not have; it rendered as nothing.
	close.Text = Theme.glyph.close
	round(close, 15)
	close.MouseButton1Click:Connect(function()
		SettingsController.setOpen(false)
	end)
	close.Parent = panel

	local sensLabel = mkText(panel, 17, Theme.color.text)
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

	local volLabel = mkText(panel, 17, Theme.color.text)
	volLabel.Position = UDim2.new(0, 24, 0, 112)
	volLabel.Size = UDim2.new(1, -48, 0, 20)
	volLabel.TextXAlignment = Enum.TextXAlignment.Left
	volLabel.Text = "Sound volume"
	volSlider = mkSlider(panel, 140, 0, 1, function() end, function(value)
		persist({ volume = value })
	end)

	local loadoutLabel = mkText(panel, 17, Theme.color.text)
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
		button.BackgroundColor3 = Theme.color.surfaceRaised
		button.Font = Enum.Font.FredokaOne
		button.TextSize = 14
		button.TextColor3 = Theme.color.text
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

	local hint = mkText(panel, 14, Theme.color.primaryDeep)
	hint.Position = UDim2.new(0, 24, 1, -60)
	hint.Size = UDim2.new(1, -48, 0, 40)
	hint.TextWrapped = true
	hint.Text = "Controls: 1–4 switch · R reload · B shop · Tab scoreboard"

	panel.Parent = screen
	screen.Parent = playerGui
end

function SettingsController.init()
	buildGui()

	-- The gear button WAS the only way in. Removing it without this would have
	-- made sensitivity and volume unreachable — chrome nobody wanted traded for
	-- settings nobody can open. O for options, same pattern as the shop's [B].
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.O then
			SettingsController.setOpen(not panel.Visible)
		end
	end)

	ClientData.changed:Connect(applySnapshot)
	if ClientData.snapshot then
		applySnapshot(ClientData.snapshot)
	end
end

return SettingsController
