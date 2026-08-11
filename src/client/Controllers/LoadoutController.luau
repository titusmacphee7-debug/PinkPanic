--!strict
-- LoadoutController — the real loadout screen for the 32-gun roster.
--
-- Replaces the dead starting-weapon picker in SettingsController, which still
-- listed the pre-roster names (Pistol/Rifle/Shotgun/Knife) and wrote a field
-- nothing ever read. See NOD-119.
--
-- Every gun in the catalog shows as a card with a LIVE 3D preview built from
-- the real model in ReplicatedStorage.GunModels — no rendered thumbnails to
-- upload, and the preview already wears whatever camo is equipped. Guns you
-- don't own render darkened behind a lock with their price.
--
-- The server owns all of this: EquipLoadout re-validates ownership, slot, and
-- lobby-only; EquipGunCosmetics re-validates camo ownership and fit. This file
-- only ever *asks*.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local GunModelLoader = require(ReplicatedStorage.Shared.Assets.GunModelLoader)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local PINK_WHITE = Color3.fromRGB(255, 245, 250)
local PANEL = Color3.fromRGB(38, 22, 34)
local CARD = Color3.fromRGB(56, 33, 50)
local LOCKED_TINT = Color3.fromRGB(18, 11, 16)

local RARITY: { [string]: Color3 } = {
	Common = Color3.fromRGB(196, 186, 192),
	Rare = Color3.fromRGB(120, 190, 255),
	Epic = Color3.fromRGB(206, 130, 255),
	Legendary = Color3.fromRGB(255, 198, 92),
}

local LoadoutController = {}

local gui: ScreenGui? = nil
local modal: TextButton? = nil
local grid: ScrollingFrame? = nil
local camoRow: ScrollingFrame? = nil
local statusLabel: TextLabel? = nil
local slotButtons: { [string]: TextButton } = {}

local activeSlot = "Primary"
local selectedGun: string? = nil
local busy = false
local spinners: { { viewport: ViewportFrame, model: Model, pivot: CFrame } } = {}

-- ---------------------------------------------------------------------------
-- Small UI helpers (same idiom as ShopController / SettingsController)
-- ---------------------------------------------------------------------------

local function mkText(parent: Instance, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function showStatus(text: string, isError: boolean)
	local label = statusLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = if isError then Color3.fromRGB(255, 130, 150) else PINK_WHITE
	task.delay(3, function()
		if label.Text == text then
			label.Text = ""
		end
	end)
end

-- One request in flight at a time; the server rate-limits independently.
local function request(fn: () -> any)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(fn)
		busy = false
		if not ok then
			showStatus("Something went wrong — try again.", true)
			return
		end
		if type(result) == "table" and result.ok ~= true then
			showStatus(tostring(result.error or "Nope!"), true)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- 3D preview: the real gun model, spinning, wearing its equipped camo
-- ---------------------------------------------------------------------------

local function buildPreview(parent: Frame, gunId: string, owned: boolean)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -12, 0, 78)
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = if owned then Color3.fromRGB(210, 200, 210) else Color3.fromRGB(70, 62, 70)
	viewport.LightColor = if owned then PINK_WHITE else Color3.fromRGB(120, 110, 120)
	viewport.Parent = parent

	local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
	local ok, model = pcall(function()
		return GunModelLoader.build(gunId, { skinId = skinId, camoId = camoId })
	end)
	if not ok or not model then
		return
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport

	local pivot, size = model:GetBoundingBox()
	local reach = math.max(size.X, size.Y, size.Z)
	local distance = math.max(reach * 1.7, 2)
	camera.CFrame = CFrame.lookAt(
		pivot.Position + Vector3.new(distance * 0.62, distance * 0.3, distance * 0.62),
		pivot.Position
	)

	table.insert(spinners, { viewport = viewport, model = model, pivot = pivot })
end

-- ---------------------------------------------------------------------------
-- Gun cards
-- ---------------------------------------------------------------------------

local function equipGun(gunId: string)
	local primary, secondary = ClientData.loadout()
	if activeSlot == "Primary" then
		primary = gunId
	else
		secondary = gunId
	end
	request(function()
		return Remotes.func("EquipLoadout"):InvokeServer(primary, secondary)
	end)
end

local function addGunCard(gunId: string, def: any, order: number)
	local container = grid
	if not container then
		return
	end

	local owned = ClientData.ownsGun(gunId)
	local primary, secondary = ClientData.loadout()
	local equipped = (activeSlot == "Primary" and primary == gunId)
		or (activeSlot == "Secondary" and secondary == gunId)

	local card = Instance.new("TextButton")
	card.Name = gunId
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(168, 176)
	card.BackgroundColor3 = CARD
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = container
	round(card, 14)

	local border = Instance.new("UIStroke")
	border.Thickness = if equipped then 3 else 1
	border.Color = if equipped then HOT_PINK else (RARITY[def.rarity] or PINK_WHITE)
	border.Transparency = if equipped then 0 else 0.55
	border.Parent = card

	buildPreview(card, gunId, owned)

	local name = mkText(card, 15, if owned then PINK_WHITE else Color3.fromRGB(150, 138, 148))
	name.Size = UDim2.new(1, -16, 0, 20)
	name.Position = UDim2.fromOffset(9, 88)
	name.Text = def.name
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local classLine = mkText(card, 12, RARITY[def.rarity] or PINK_WHITE)
	classLine.Size = UDim2.new(1, -16, 0, 16)
	classLine.Position = UDim2.fromOffset(9, 107)
	classLine.Text = `{def.class} · {def.rarity}`

	local stats = CombatStats.resolve(gunId)
	local statLine = mkText(card, 11, Color3.fromRGB(186, 172, 184))
	statLine.Size = UDim2.new(1, -16, 0, 15)
	statLine.Position = UDim2.fromOffset(9, 124)
	statLine.Text = `{math.floor(stats.damageNear + 0.5)} dmg · {math.floor(stats.fireRate * 60 + 0.5)} rpm`

	local footer = mkText(card, 13, PINK_WHITE)
	footer.Size = UDim2.new(1, -16, 0, 18)
	footer.Position = UDim2.fromOffset(9, 145)

	if equipped then
		footer.Text = "✓ EQUIPPED"
		footer.TextColor3 = HOT_PINK
	elseif owned then
		footer.Text = "Tap to equip"
	else
		footer.Text = `🔒 {def.price} 🪙`
		footer.TextColor3 = Color3.fromRGB(255, 206, 120)
	end

	-- Unowned guns sit behind a dark scrim with a lock, so the roster still
	-- reads as something to work toward instead of being hidden.
	if not owned then
		local scrim = Instance.new("Frame")
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.BackgroundColor3 = LOCKED_TINT
		scrim.BackgroundTransparency = 0.42
		scrim.ZIndex = 5
		scrim.Parent = card
		round(scrim, 14)

		local lock = mkText(scrim, 30, PINK_WHITE)
		lock.Size = UDim2.fromOffset(40, 40)
		lock.Position = UDim2.new(0.5, -20, 0, 26)
		lock.ZIndex = 6
		lock.Text = "🔒"
		lock.TextXAlignment = Enum.TextXAlignment.Center
	end

	card.Activated:Connect(function()
		selectedGun = gunId
		if not owned then
			showStatus(`{def.name} costs {def.price} coins — buy it in the Armory 💗`, true)
			LoadoutController.refresh()
			return
		end
		equipGun(gunId)
	end)
end

-- ---------------------------------------------------------------------------
-- Camo strip for the selected gun
-- ---------------------------------------------------------------------------

local function addCamoChip(camoId: string?, def: any, order: number)
	local row = camoRow
	local gunId = selectedGun
	if not row or not gunId then
		return
	end

	local _, equippedCamo = ClientData.gunCosmeticsFor(gunId)
	local isNone = camoId == nil
	local owned = isNone or ClientData.ownsCamo(camoId :: string)
	-- A camo whose PNG hasn't been uploaded to Roblox yet has no texture to
	-- show and can't be bought (GunShopService rejects it). Say so plainly.
	local unreleased = not isNone and def.textureId == ""
	local equipped = equippedCamo == camoId

	local chip = Instance.new("TextButton")
	chip.LayoutOrder = order
	chip.Size = UDim2.fromOffset(112, 46)
	chip.BackgroundColor3 = if equipped then HOT_PINK else CARD
	chip.AutoButtonColor = false
	chip.Font = Enum.Font.FredokaOne
	chip.TextSize = 13
	chip.TextColor3 = if unreleased then Color3.fromRGB(140, 130, 140) else PINK_WHITE
	chip.Text = if isNone
		then "No camo"
		elseif unreleased then `{def.name}\n(coming soon)`
		elseif owned then def.name
		else `🔒 {def.name}\n{def.price} 🪙`
	chip.Parent = row
	round(chip, 10)

	chip.Activated:Connect(function()
		if unreleased then
			showStatus(`{def.name} isn't uploaded yet 💗`, true)
			return
		end
		if not owned then
			showStatus(`{def.name} costs {def.price} coins.`, true)
			return
		end
		local skinId = select(1, ClientData.gunCosmeticsFor(gunId))
		request(function()
			return Remotes.func("EquipGunCosmetics"):InvokeServer(gunId, skinId, camoId)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- Rebuild
-- ---------------------------------------------------------------------------

function LoadoutController.refresh()
	local container = grid
	local row = camoRow
	if not container or not row then
		return
	end

	table.clear(spinners)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Owned first, then by price, so the next thing to save for is obvious.
	local entries: { { id: string, def: any } } = {}
	for gunId, def in GunCatalog.guns do
		if def.slot == activeSlot then
			table.insert(entries, { id = gunId, def = def })
		end
	end
	table.sort(entries, function(a, b)
		local aOwned, bOwned = ClientData.ownsGun(a.id), ClientData.ownsGun(b.id)
		if aOwned ~= bOwned then
			return aOwned
		end
		if a.def.price ~= b.def.price then
			return a.def.price < b.def.price
		end
		return a.def.name < b.def.name
	end)

	for index, entry in entries do
		addGunCard(entry.id, entry.def, index)
	end
	container.CanvasSize = UDim2.fromOffset(0, math.ceil(#entries / 4) * 186 + 12)

	-- Camos apply to whichever gun is selected; default to the equipped one.
	if not selectedGun then
		local primary, secondary = ClientData.loadout()
		selectedGun = if activeSlot == "Primary" then primary else secondary
	end

	if selectedGun then
		addCamoChip(nil, nil, 0)
		local order = 1
		for camoId, def in GunSkinCatalog.universal do
			addCamoChip(camoId, def, order)
			order += 1
		end
		row.CanvasSize = UDim2.fromOffset(order * 120 + 12, 0)
	end

	for slot, button in slotButtons do
		button.BackgroundColor3 = if slot == activeSlot then HOT_PINK else CARD
	end
end

function LoadoutController.setOpen(open: boolean)
	local screen = gui
	local button = modal
	if not screen or not button then
		return
	end
	screen.Enabled = open
	button.Visible = open
	ClientData.loadoutOpen = open
	ClientData.updateMouseUnlock()
	if open then
		selectedGun = nil
		LoadoutController.refresh()
	end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "LoadoutUI"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 8
	screen.Enabled = false
	screen.Parent = playerGui
	gui = screen

	-- Invisible Modal button: the sanctioned way to free the first-person
	-- mouse lock while a panel is open (same trick as ShopController).
	local modalButton = Instance.new("TextButton")
	modalButton.Size = UDim2.fromScale(1, 1)
	modalButton.BackgroundTransparency = 1
	modalButton.Text = ""
	modalButton.Modal = true
	modalButton.Visible = false
	modalButton.Parent = screen
	modal = modalButton

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(760, 560)
	panel.Position = UDim2.new(0.5, -380, 0.5, -280)
	panel.BackgroundColor3 = PANEL
	panel.Parent = screen
	round(panel, 20)

	local title = mkText(panel, 26, HOT_PINK)
	title.Size = UDim2.new(1, -40, 0, 34)
	title.Position = UDim2.fromOffset(24, 18)
	title.Text = "LOADOUT 💗"

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(38, 38)
	close.Position = UDim2.new(1, -52, 0, 16)
	close.BackgroundColor3 = CARD
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 20
	close.TextColor3 = PINK_WHITE
	close.Text = "✕"
	close.Parent = panel
	round(close, 12)
	close.Activated:Connect(function()
		LoadoutController.setOpen(false)
	end)

	-- Slot tabs
	local slots = { "Primary", "Secondary" }
	for index, slot in slots do
		local tab = Instance.new("TextButton")
		tab.Size = UDim2.fromOffset(132, 36)
		tab.Position = UDim2.fromOffset(24 + (index - 1) * 142, 62)
		tab.BackgroundColor3 = if slot == activeSlot then HOT_PINK else CARD
		tab.AutoButtonColor = false
		tab.Font = Enum.Font.FredokaOne
		tab.TextSize = 15
		tab.TextColor3 = PINK_WHITE
		tab.Text = slot
		tab.Parent = panel
		round(tab, 12)
		slotButtons[slot] = tab
		tab.Activated:Connect(function()
			activeSlot = slot
			selectedGun = nil
			LoadoutController.refresh()
		end)
	end

	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.new(1, -48, 0, 372)
	scroller.Position = UDim2.fromOffset(24, 108)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = HOT_PINK
	scroller.Parent = panel
	grid = scroller

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(168, 176)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	local camoTitle = mkText(panel, 14, PINK_WHITE)
	camoTitle.Size = UDim2.new(1, -48, 0, 18)
	camoTitle.Position = UDim2.fromOffset(24, 486)
	camoTitle.Text = "CAMO"

	local camos = Instance.new("ScrollingFrame")
	camos.Size = UDim2.new(1, -48, 0, 46)
	camos.Position = UDim2.fromOffset(24, 506)
	camos.BackgroundTransparency = 1
	camos.BorderSizePixel = 0
	camos.ScrollBarThickness = 4
	camos.ScrollBarImageColor3 = HOT_PINK
	camos.ScrollingDirection = Enum.ScrollingDirection.X
	camos.Parent = panel
	camoRow = camos

	local camoLayout = Instance.new("UIListLayout")
	camoLayout.FillDirection = Enum.FillDirection.Horizontal
	camoLayout.Padding = UDim.new(0, 8)
	camoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	camoLayout.Parent = camos

	local status = mkText(panel, 13, PINK_WHITE)
	status.Size = UDim2.new(1, -260, 0, 20)
	status.Position = UDim2.fromOffset(200, 66)
	status.Text = ""
	statusLabel = status
end

function LoadoutController.init()
	buildGui()

	-- Slow spin on every preview, so the cases feel alive.
	RunService.RenderStepped:Connect(function(dt)
		local screen = gui
		if not screen or not screen.Enabled then
			return
		end
		for _, entry in spinners do
			if entry.model.Parent then
				entry.model:PivotTo(entry.pivot * CFrame.Angles(0, os.clock() % (math.pi * 2), 0))
			end
		end
	end)

	-- Ownership, coins, and loadout all arrive on DataChanged.
	ClientData.changed:Connect(function()
		local screen = gui
		if screen and screen.Enabled then
			LoadoutController.refresh()
		end
	end)

	-- Loadout edits are lobby-only (the server enforces it); close on round start.
	ClientData.roundStateChanged:Connect(function(state)
		if state == "Active" then
			LoadoutController.setOpen(false)
		end
	end)
end

return LoadoutController
