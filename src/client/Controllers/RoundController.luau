--!strict
-- RoundController — round HUD in the Pink Panic aesthetic: status pill up
-- top, always-on PLAYERS panel with placement + kill count (styled after the
-- lobby concept art), hold-Tab kills/deaths detail, and results overlay
-- (NOD-22/NOD-23 client side).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local BLUSH = Color3.fromRGB(255, 227, 240)
local ROW_WHITE = Color3.fromRGB(255, 245, 250)
local TEXT_DARK = Color3.fromRGB(96, 56, 78)

local RoundController = {}

local state = "Waiting"
local endsAt = 0
local scoreTarget = 0
local scores: { any } = {}
local winnerName: string? = nil

local statusLabel: TextLabel
local leaderboardRows: Frame
local detailFrame: Frame
local detailRows: Frame
local resultsFrame: Frame
local resultsTitle: TextLabel
local resultsStats: TextLabel

local function stylePanel(frame: Frame, cornerRadius: number)
	frame.BackgroundColor3 = BLUSH
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerRadius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = frame
end

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

local function mkListPanel(screen: ScreenGui, title: string, position: UDim2, width: number): (Frame, Frame)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = position
	panel.Size = UDim2.fromOffset(width, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	stylePanel(panel, 14)

	local header = mkText(panel, 20, DEEP_PINK)
	header.Size = UDim2.new(1, 0, 0, 34)
	header.Text = title

	local rows = Instance.new("Frame")
	rows.Position = UDim2.new(0, 0, 0, 34)
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = rows
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = rows
	rows.Parent = panel

	panel.Parent = screen
	return panel, rows
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "RoundHUD"
	screen.ResetOnSpawn = false

	-- Status pill, top center
	local statusPill = Instance.new("Frame")
	statusPill.AnchorPoint = Vector2.new(0.5, 0)
	statusPill.Position = UDim2.new(0.5, 0, 0, 10)
	statusPill.Size = UDim2.fromOffset(340, 38)
	stylePanel(statusPill, 19)
	statusLabel = mkText(statusPill, 20, DEEP_PINK)
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusPill.Parent = screen

	-- Always-on players panel, top right: place · name · kills
	local _playersPanel, playersRows = mkListPanel(screen, "🎀 PLAYERS 🎀", UDim2.new(1, -12, 0, 12), 240)
	leaderboardRows = playersRows

	-- Hold Tab: kills/deaths detail, centered
	detailFrame, detailRows = mkListPanel(screen, "🎀 SCOREBOARD · K / D 🎀", UDim2.new(1, 0, 0, 0), 300)
	detailFrame.AnchorPoint = Vector2.new(0.5, 0)
	detailFrame.Position = UDim2.new(0.5, 0, 0, 64)
	detailFrame.Visible = false

	-- Results overlay
	resultsFrame = Instance.new("Frame")
	resultsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultsFrame.Position = UDim2.fromScale(0.5, 0.4)
	resultsFrame.Size = UDim2.fromOffset(380, 150)
	stylePanel(resultsFrame, 18)
	resultsFrame.Visible = false
	resultsTitle = mkText(resultsFrame, 28, DEEP_PINK)
	resultsTitle.AnchorPoint = Vector2.new(0.5, 0)
	resultsTitle.Position = UDim2.new(0.5, 0, 0, 22)
	resultsTitle.Size = UDim2.new(1, 0, 0, 40)
	resultsStats = mkText(resultsFrame, 20, TEXT_DARK)
	resultsStats.AnchorPoint = Vector2.new(0.5, 0)
	resultsStats.Position = UDim2.new(0.5, 0, 0, 78)
	resultsStats.Size = UDim2.new(1, 0, 0, 30)
	resultsFrame.Parent = screen

	screen.Parent = playerGui
end

local function placeText(index: number): string
	if index == 1 then
		return "👑"
	end
	return `{index}.`
end

local function addRow(parent: Frame, index: number, row: any, rightText: string, width: number)
	local isYou = row.name == Players.LocalPlayer.Name

	local rowFrame = Instance.new("Frame")
	rowFrame.LayoutOrder = index
	rowFrame.Size = UDim2.fromOffset(width, 32)
	rowFrame.BackgroundColor3 = if isYou then HOT_PINK else ROW_WHITE
	rowFrame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = rowFrame

	local textColor = if isYou then Color3.new(1, 1, 1) else TEXT_DARK

	local place = mkText(rowFrame, 17, textColor)
	place.Position = UDim2.new(0, 8, 0, 0)
	place.Size = UDim2.new(0, 30, 1, 0)
	place.Text = placeText(index)

	local name = mkText(rowFrame, 17, textColor)
	name.Position = UDim2.new(0, 42, 0, 0)
	name.Size = UDim2.new(1, -110, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = row.name

	local right = mkText(rowFrame, 17, if isYou then Color3.new(1, 1, 1) else DEEP_PINK)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -10, 0, 0)
	right.Size = UDim2.new(0, 62, 1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Text = rightText

	rowFrame.Parent = parent
end

local function clearRows(parent: Frame)
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function refreshPanels()
	clearRows(leaderboardRows)
	clearRows(detailRows)
	for index, row in scores do
		addRow(leaderboardRows, index, row, `💗 {row.kills}`, 224)
		addRow(detailRows, index, row, `{row.kills} / {row.deaths}`, 284)
	end
end

local function showResults()
	local yourKills, yourDeaths = 0, 0
	for _, row in scores do
		if row.name == Players.LocalPlayer.Name then
			yourKills, yourDeaths = row.kills, row.deaths
		end
	end
	resultsTitle.Text = if winnerName then `🏆 {winnerName} wins! 🎀` else "Round over!"
	resultsStats.Text = `You: {yourKills} kills · {yourDeaths} deaths`
	resultsFrame.Visible = true
end

local function applyPayload(data: any)
	if type(data) ~= "table" then
		return
	end
	state = data.state or state
	ClientData.setRoundState(state)
	endsAt = data.endsAt or 0
	scoreTarget = data.scoreTarget or scoreTarget
	if type(data.scores) == "table" then
		scores = data.scores
		refreshPanels()
	end
	winnerName = data.winner

	if state == "RoundEnd" then
		showResults()
	else
		resultsFrame.Visible = false
	end
end

local function updateStatus()
	local remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
	local clock = string.format("%d:%02d", remaining // 60, remaining % 60)
	if state == "Waiting" then
		statusLabel.Text = "Waiting for players… 🎀"
	elseif state == "Intermission" then
		statusLabel.Text = `💗 Round starts in {clock} 💗`
	elseif state == "Active" then
		statusLabel.Text = `{clock}  ·  first to {scoreTarget} 💗`
	elseif state == "RoundEnd" then
		statusLabel.Text = "Round over! 🎀"
	end
end

function RoundController.init()
	buildGui()

	Remotes.event("RoundStateChanged").OnClientEvent:Connect(applyPayload)
	Remotes.event("ScoreUpdated").OnClientEvent:Connect(function(rows)
		if type(rows) == "table" then
			scores = rows
			refreshPanels()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Tab then
			detailFrame.Visible = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			detailFrame.Visible = false
		end
	end)

	RunService.Heartbeat:Connect(updateStatus)
end

return RoundController
