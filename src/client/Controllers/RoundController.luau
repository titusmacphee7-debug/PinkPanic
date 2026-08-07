--!strict
-- RoundController — round state HUD, Tab scoreboard, and results screen
-- (NOD-22/NOD-23 client side). Deliberately plain; the pink UI kit (M5)
-- restyles all of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local PINK = Color3.fromRGB(255, 105, 180)
local PANEL = Color3.fromRGB(40, 30, 38)

local RoundController = {}

local state = "Waiting"
local endsAt = 0
local scoreTarget = 0
local scores: { any } = {}
local winnerName: string? = nil

local statusLabel: TextLabel
local resultsFrame: Frame
local resultsTitle: TextLabel
local resultsStats: TextLabel
local scoreboardFrame: Frame
local scoreboardList: Frame

local function mkLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = PINK
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "RoundHUD"
	screen.ResetOnSpawn = false

	statusLabel = mkLabel(screen, UDim2.new(0.5, 0, 0, 34), UDim2.new(0.5, 0, 0, 8), 26)

	-- Results overlay (round end)
	resultsFrame = Instance.new("Frame")
	resultsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultsFrame.Position = UDim2.fromScale(0.5, 0.4)
	resultsFrame.Size = UDim2.fromOffset(340, 140)
	resultsFrame.BackgroundColor3 = PANEL
	resultsFrame.BackgroundTransparency = 0.15
	resultsFrame.Visible = false
	local resultsCorner = Instance.new("UICorner")
	resultsCorner.CornerRadius = UDim.new(0, 16)
	resultsCorner.Parent = resultsFrame
	resultsTitle = mkLabel(resultsFrame, UDim2.new(1, 0, 0, 44), UDim2.new(0.5, 0, 0, 16), 28)
	resultsStats = mkLabel(resultsFrame, UDim2.new(1, 0, 0, 30), UDim2.new(0.5, 0, 0, 72), 20)
	resultsFrame.Parent = screen

	-- Tab scoreboard
	scoreboardFrame = Instance.new("Frame")
	scoreboardFrame.AnchorPoint = Vector2.new(0.5, 0)
	scoreboardFrame.Position = UDim2.new(0.5, 0, 0, 60)
	scoreboardFrame.Size = UDim2.fromOffset(320, 0)
	scoreboardFrame.AutomaticSize = Enum.AutomaticSize.Y
	scoreboardFrame.BackgroundColor3 = PANEL
	scoreboardFrame.BackgroundTransparency = 0.2
	scoreboardFrame.Visible = false
	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 12)
	boardCorner.Parent = scoreboardFrame

	scoreboardList = Instance.new("Frame")
	scoreboardList.Size = UDim2.new(1, 0, 0, 0)
	scoreboardList.AutomaticSize = Enum.AutomaticSize.Y
	scoreboardList.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scoreboardList
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scoreboardList
	scoreboardList.Parent = scoreboardFrame
	scoreboardFrame.Parent = screen

	screen.Parent = playerGui
end

local function refreshScoreboard()
	for _, child in scoreboardList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for index, row in scores do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = index
		label.Size = UDim2.new(1, 0, 0, 26)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 18
		label.TextColor3 = if row.name == Players.LocalPlayer.Name then PINK else Color3.new(1, 1, 1)
		label.Text = `{index}.  {row.name}   {row.kills} / {row.deaths}`
		label.Parent = scoreboardList
	end
end

local function showResults()
	local yourKills, yourDeaths = 0, 0
	for _, row in scores do
		if row.name == Players.LocalPlayer.Name then
			yourKills, yourDeaths = row.kills, row.deaths
		end
	end
	resultsTitle.Text = if winnerName then `🏆 {winnerName} wins!` else "Round over!"
	resultsStats.Text = `You: {yourKills} kills / {yourDeaths} deaths`
	resultsFrame.Visible = true
end

local function applyPayload(data: any)
	if type(data) ~= "table" then
		return
	end
	state = data.state or state
	endsAt = data.endsAt or 0
	scoreTarget = data.scoreTarget or scoreTarget
	if type(data.scores) == "table" then
		scores = data.scores
		refreshScoreboard()
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
		statusLabel.Text = `Round starts in {clock}`
	elseif state == "Active" then
		local topKills = if scores[1] then scores[1].kills else 0
		statusLabel.Text = `{clock}  ·  first to {scoreTarget}  ·  top {topKills}`
	elseif state == "RoundEnd" then
		statusLabel.Text = "Round over!"
	end
end

function RoundController.init()
	buildGui()

	Remotes.event("RoundStateChanged").OnClientEvent:Connect(applyPayload)
	Remotes.event("ScoreUpdated").OnClientEvent:Connect(function(rows)
		if type(rows) == "table" then
			scores = rows
			refreshScoreboard()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Tab then
			refreshScoreboard()
			scoreboardFrame.Visible = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			scoreboardFrame.Visible = false
		end
	end)

	RunService.Heartbeat:Connect(updateStatus)
end

return RoundController
