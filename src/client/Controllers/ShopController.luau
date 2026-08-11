--!strict
-- ShopController — the pink shop (NOD-34): browse skins/charms, buy with
-- server validation, equip owned items. Opens with B or the bottom-left
-- button; unlocks the mouse while open and blocks firing via
-- ClientData.shopOpen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CatalogConfig = require(ReplicatedStorage.Shared.Config.CatalogConfig)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)

local ShopController = {}

local panel: Frame
local grid: Frame
local messageLabel: TextLabel
-- Invisible Modal button: while visible, Roblox releases the first-person
-- mouse lock — the sanctioned way to free the cursor for UI.
local modalUnlock: TextButton
local busy = false

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

function ShopController.setOpen(open: boolean)
	if panel.Visible == open then
		return
	end
	ClientData.shopOpen = open
	panel.Visible = open
	modalUnlock.Visible = open
	modalUnlock.Modal = open
	ClientData.updateMouseUnlock()
	if open then
		messageLabel.Text = ""
		ShopController.refresh()
	end
end

local function showMessage(text: string, isError: boolean)
	messageLabel.TextColor3 = if isError then Theme.color.danger else Theme.color.primaryDeep
	messageLabel.Text = text
end

-- One request in flight at a time; the server rate-limits too.
local function request(fn: () -> any)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(fn)
		busy = false
		if not ok then
			showMessage("Something went wrong — try again.", true)
			return
		end
		if type(result) == "table" and result.ok then
			showMessage("Done! 💗", false)
		elseif type(result) == "table" and result.error then
			showMessage(result.error, true)
		end
		ShopController.refresh()
	end)
end

local function cardClicked(kind: string, itemId: string, def: any)
	local equipped = if kind == "skin" then ClientData.equippedSkin() else ClientData.equippedCharm()
	local owned = def.price <= 0 or ClientData.owns(kind, itemId)

	if equipped == itemId then
		if kind == "charm" then
			request(function()
				return Remotes.invoke("EquipItem", "charm", nil)
			end)
		end
	elseif owned then
		request(function()
			return Remotes.invoke("EquipItem", kind, itemId)
		end)
	else
		request(function()
			return Remotes.invoke("PurchaseItem", itemId)
		end)
	end
end

local function addCard(kind: string, itemId: string, def: any, order: number)
	local equipped = if kind == "skin" then ClientData.equippedSkin() else ClientData.equippedCharm()
	local isEquipped = equipped == itemId or (kind == "skin" and equipped == nil and itemId == "SkinDefault")
	local owned = def.price <= 0 or ClientData.owns(kind, itemId)

	local card = Instance.new("TextButton")
	card.Name = itemId
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(136, 126)
	card.BackgroundColor3 = Theme.color.surfaceRaised
	card.Text = ""
	card.AutoButtonColor = true
	round(card, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = if isEquipped then Theme.color.primary else Theme.color.border
	stroke.Thickness = if isEquipped then 3 else 1
	stroke.Parent = card

	-- Preview swatch: skin = two color bars, charm = a colored dot.
	local preview = Instance.new("Frame")
	preview.Position = UDim2.new(0, 10, 0, 10)
	preview.Size = UDim2.new(1, -20, 0, 40)
	preview.BackgroundColor3 = if kind == "skin" then def.slide else Theme.color.surface
	preview.BorderSizePixel = 0
	round(preview, 8)
	if kind == "skin" then
		local half = Instance.new("Frame")
		half.AnchorPoint = Vector2.new(0, 1)
		half.Position = UDim2.new(0, 0, 1, 0)
		half.Size = UDim2.new(1, 0, 0.45, 0)
		half.BackgroundColor3 = def.grip
		half.BorderSizePixel = 0
		round(half, 8)
		half.Parent = preview
	else
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(26, 26)
		dot.BackgroundColor3 = def.color
		dot.BorderSizePixel = 0
		round(dot, 13)
		dot.Parent = preview
	end
	preview.Parent = card

	local nameLabel = mkText(card, 15, Theme.color.text)
	nameLabel.Position = UDim2.new(0, 6, 0, 54)
	nameLabel.Size = UDim2.new(1, -12, 0, 18)
	nameLabel.Text = def.name

	local rarityLabel = mkText(card, 12, Theme.rarityColor(def.rarity))
	rarityLabel.Position = UDim2.new(0, 6, 0, 72)
	rarityLabel.Size = UDim2.new(1, -12, 0, 14)
	rarityLabel.Text = def.rarity

	local action = mkText(card, 15, Theme.color.primaryDeep)
	action.Position = UDim2.new(0, 6, 1, -32)
	action.Size = UDim2.new(1, -12, 0, 24)
	if isEquipped then
		action.Text = "Equipped ✓"
		action.TextColor3 = Theme.color.primary
	elseif owned then
		action.Text = "Equip 🎀"
	else
		action.Text = `💗 {def.price}`
	end

	card.MouseButton1Click:Connect(function()
		cardClicked(kind, itemId, def)
	end)
	card.Parent = grid
end

function ShopController.refresh()
	for _, child in grid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Stable ordering: skins by price then charms by price.
	local order = 0
	local function addSection(kind: string, items: { [string]: any })
		local sorted = {}
		for itemId, def in items do
			table.insert(sorted, { id = itemId, def = def })
		end
		table.sort(sorted, function(a, b)
			return a.def.price < b.def.price
		end)
		for _, entry in sorted do
			order += 1
			addCard(kind, entry.id, entry.def, order)
		end
	end
	addSection("skin", CatalogConfig.skins)
	addSection("charm", CatalogConfig.charms)
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "ShopUI"
	screen.ResetOnSpawn = false

	-- FULL-SCREEN, deliberately. This used to be a 1x1 button parked offscreen
	-- at (-10,-10): it released the mouse lock but blocked nothing, so clicks
	-- on the panel passed straight through into the game and fired a lobby
	-- shot. Created before the panel, so the panel still draws on top.
	modalUnlock = Instance.new("TextButton")
	modalUnlock.Name = "ModalUnlock"
	modalUnlock.Size = UDim2.fromScale(1, 1)
	modalUnlock.BackgroundTransparency = 1
	modalUnlock.Text = ""
	modalUnlock.Visible = false
	modalUnlock.Modal = false
	modalUnlock.Parent = screen

	-- Bottom-left open button
	local openButton = Instance.new("TextButton")
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 12, 1, -12)
	openButton.Size = UDim2.fromOffset(140, 42)
	openButton.BackgroundColor3 = Theme.color.primary
	openButton.Font = Enum.Font.FredokaOne
	openButton.TextSize = 18
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "🛍️ Shop  [B]"
	round(openButton, 21)
	openButton.MouseButton1Click:Connect(function()
		ShopController.setOpen(not panel.Visible)
	end)
	openButton.Parent = screen

	-- Shop panel
	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 460)
	panel.BackgroundColor3 = Theme.color.surface
	panel.Visible = false
	round(panel, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.color.primary
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = mkText(panel, 26, Theme.color.primaryDeep)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.Size = UDim2.new(1, 0, 0, 32)
	title.Text = "🎀 PINK SHOP 🎀"

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = Theme.color.primary
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 18
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "✕"
	round(close, 16)
	close.MouseButton1Click:Connect(function()
		ShopController.setOpen(false)
	end)
	close.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 16, 0, 52)
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.color.primary
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()

	grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(136, 126)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	grid.Parent = scroll
	scroll.Parent = panel

	messageLabel = mkText(panel, 17, Theme.color.primaryDeep)
	messageLabel.AnchorPoint = Vector2.new(0.5, 1)
	messageLabel.Position = UDim2.new(0.5, 0, 1, -12)
	messageLabel.Size = UDim2.new(1, -32, 0, 24)

	panel.Parent = screen
	screen.Parent = playerGui
end

function ShopController.init()
	buildGui()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.B then
			ShopController.setOpen(not panel.Visible)
		end
	end)

	-- Ownership/coins changed elsewhere (kills, purchases): keep cards fresh.
	ClientData.changed:Connect(function()
		if panel.Visible then
			ShopController.refresh()
		end
	end)
end

return ShopController
