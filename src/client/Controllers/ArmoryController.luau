--!strict
-- ArmoryController — the Candy Armory glass-case shopping experience
-- (NOD-96 interaction layer). Works off tagged parts so it snaps onto the
-- hand-built interior:
--   · Part with attribute GunDisplay = "<GunId>"  → a display gun renders on it
--   · Part with attribute ArmoryMat = true        → the inspection mat
-- Hovering a display gun shows its card (name, rarity, key stats, spinning
-- mini gun in a viewport). Clicking asks "Take a look?" — accepting floats
-- the gun above the mat where you drag to rotate it, preview skins, read the
-- full stat card, and buy/equip. Visual polish comes from the design pass;
-- this file owns the behavior.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local CombatStats = require(ReplicatedStorage.Shared.Systems.CombatStats)
local GunModelLoader = require(ReplicatedStorage.Shared.Loaders.GunModelLoader)
local ClientData = require(script.Parent.Parent.ClientData)

local HOT_PINK = Color3.fromRGB(255, 92, 168)
local DEEP_PINK = Color3.fromRGB(214, 66, 143)
local BLUSH = Color3.fromRGB(255, 227, 240)
local ROW_WHITE = Color3.fromRGB(255, 245, 250)
local TEXT_DARK = Color3.fromRGB(96, 56, 78)
local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(150, 130, 145),
	Rare = Color3.fromRGB(90, 140, 235),
	Epic = Color3.fromRGB(170, 90, 220),
	Legendary = Color3.fromRGB(235, 160, 50),
}

local ArmoryController = {}

type DisplayRecord = { gunId: string, slot: BasePart, model: Model }

local displays: { [Model]: DisplayRecord } = {}
local displayFolder: Folder? = nil
local hoveredRecord: DisplayRecord? = nil
-- Module scope so updateHover can dismiss a dialog the player walked away
-- from. Left open, it holds armoryBusy true, which hides START GAME for the
-- rest of the session.
local pendingRecord: DisplayRecord? = nil
local DIALOG_WALK_AWAY = 28
local inspecting: { gunId: string, model: Model, base: CFrame, yaw: number, pitch: number }? = nil
local dragging = false
local previewSkinId: string? = nil

-- UI refs
local hoverCard: Frame
local hoverName: TextLabel
local hoverRarity: TextLabel
local hoverStats: TextLabel
local hoverViewport: ViewportFrame
local hoverViewportModel: Model? = nil
local dialog: Frame
local dialogTitle: TextLabel
local inspectPanel: Frame
local inspectName: TextLabel
local inspectRarity: TextLabel
local inspectStatsList: Frame
local inspectSkinRow: Frame
local inspectAction: TextButton
local inspectMessage: TextLabel
local busyRequest = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function mkText(parent: Instance, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
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

local function stylePanel(frame: Frame, radius: number)
	frame.BackgroundColor3 = BLUSH
	frame.BorderSizePixel = 0
	round(frame, radius)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HOT_PINK
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame
end

local function statLine(stats: CombatStats.Resolved): string
	local damage = if stats.pellets > 1
		then `{stats.damageNear}x{stats.pellets}`
		else `{stats.damageNear}`
	return `💥 {damage}  ·  {math.floor(stats.fireRate * 60 + 0.5)} RPM  ·  {stats.magSize} mag`
end

local function setBusy(busy: boolean)
	ClientData.armoryBusy = busy
end

-- ---------------------------------------------------------------------------
-- Display guns on tagged case slots
-- ---------------------------------------------------------------------------

local function clearDisplays()
	for model in displays do
		model:Destroy()
	end
	displays = {}
end

local function renderDisplays()
	clearDisplays()
	local folder = displayFolder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ArmoryDisplays"
		folder.Parent = workspace
		displayFolder = folder
	end

	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") and typeof(part:GetAttribute("GunDisplay")) == "string" then
			local gunId = part:GetAttribute("GunDisplay") :: string
			if not GunCatalog.get(gunId) then
				continue
			end
			local model = GunModelLoader.build(gunId, nil)
			for _, piece in model:GetDescendants() do
				if piece:IsA("BasePart") then
					piece.Anchored = true
					piece.CanQuery = true -- hover raycasts must hit display guns
				end
			end
			-- Rest the gun above the slot, aligned to the slot's facing.
			local _, size = model:GetBoundingBox()
			model:PivotTo(part.CFrame * CFrame.new(0, part.Size.Y / 2 + size.Y / 2 + 0.2, 0))
			model.Parent = folder
			displays[model] = { gunId = gunId, slot = part, model = model }
		end
	end
end

local function recordFromInstance(instance: Instance): DisplayRecord?
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local record = displays[model]
		if record then
			return record
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function findMat(near: BasePart): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("ArmoryMat") then
			local distance = (part.Position - near.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = part
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Hover card (design pass restyles; behavior lives here)
-- ---------------------------------------------------------------------------

local function setHoverViewport(gunId: string)
	if hoverViewportModel then
		hoverViewportModel:Destroy()
		hoverViewportModel = nil
	end
	local model = GunModelLoader.build(gunId, nil)
	model.Parent = hoverViewport
	hoverViewportModel = model
	local camera = hoverViewport.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = hoverViewport
		hoverViewport.CurrentCamera = camera
	end
end

local function showHover(record: DisplayRecord)
	local def = GunCatalog.get(record.gunId)
	if not def then
		return
	end
	local stats = CombatStats.resolve(record.gunId)
	hoverName.Text = def.name
	hoverRarity.Text = def.rarity
	hoverRarity.TextColor3 = RARITY_COLORS[def.rarity] or TEXT_DARK
	hoverStats.Text = statLine(stats)
	setHoverViewport(record.gunId)
	hoverCard.Visible = true
end

local function hideHover()
	hoverCard.Visible = false
	if hoverViewportModel then
		hoverViewportModel:Destroy()
		hoverViewportModel = nil
	end
end

-- The mini gun on the card spins slowly, tilted up at an angle; the real
-- display gun never moves.
local function spinHoverViewport()
	local model = hoverViewportModel
	local camera = hoverViewport.CurrentCamera
	if not model or not camera or not hoverCard.Visible then
		return
	end
	local pivot, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	model:PivotTo(
		CFrame.new(pivot.Position)
			* CFrame.Angles(0, os.clock() * 0.9, 0)
			* CFrame.Angles(math.rad(-18), 0, 0)
			* (pivot - pivot.Position)
	)
	camera.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, radius * 0.25, radius * 1.35), pivot.Position)
end

-- ---------------------------------------------------------------------------
-- Inspection ("Take a look")
-- ---------------------------------------------------------------------------

local function applyPreview()
	local current = inspecting
	if not current then
		return
	end
	GunModelLoader.applyCosmetics(current.model, current.gunId, { skinId = previewSkinId, camoId = nil })
	if not previewSkinId then
		-- Re-clone colors by rebuilding? Cheaper: reapply nothing — default
		-- mesh colors persist only until a skin was applied, so rebuild.
		local rebuilt = GunModelLoader.build(current.gunId, nil)
		for _, piece in rebuilt:GetDescendants() do
			if piece:IsA("BasePart") then
				piece.Anchored = true
				piece.CanQuery = false
			end
		end
		rebuilt:PivotTo(current.model:GetPivot())
		rebuilt.Parent = displayFolder
		current.model:Destroy()
		current.model = rebuilt
	end
end

local function populateInspect(gunId: string)
	local def = GunCatalog.get(gunId)
	if not def then
		return
	end
	local stats = CombatStats.resolve(gunId)
	inspectName.Text = def.name
	inspectRarity.Text = `{def.rarity} · {def.class} · {def.slot}`
	inspectRarity.TextColor3 = RARITY_COLORS[def.rarity] or TEXT_DARK

	for _, child in inspectStatsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local damageText = if stats.pellets > 1
		then `{stats.damageNear}x{stats.pellets} → {stats.damageFar}x{stats.pellets}`
		else `{stats.damageNear} → {stats.damageFar}`
	-- How much this gun slows you down. Shown as a percentage of base pace
	-- rather than absolute studs/s: the old row multiplied MovementConfig's
	-- walk/sprint/slide numbers, which meant it changed every time movement
	-- was retuned and printed the same values for every gun anyway.
	local weightPct = math.floor(stats.moveSpeedMult * 100 + 0.5)
	-- Recoil in plain words; the number is degrees of climb per shot.
	local recoilWord = if stats.recoilVert < 0.8
		then "Low"
		elseif stats.recoilVert < 1.5 then "Medium"
		elseif stats.recoilVert < 2.8 then "High"
		else "Heavy"
	local rows = {
		{ "Damage", damageText },
		{ "Falloff", `{stats.rangeNear}–{stats.rangeFar} studs` },
		{ "Fire rate", `{math.floor(stats.fireRate * 60 + 0.5)} RPM` },
		{ "Mag", `{stats.magSize}` },
		{ "Reload", `{stats.reloadSeconds}s` },
		{ "Velocity", `{stats.velocity} studs/s` },
		{ "Recoil", `{recoilWord} ({stats.recoilVert}°/shot)` },
		{ "Spread", `{stats.spreadDeg}° hip · {stats.adsSpreadDeg}° ADS` },
		{ "Headshot", `x{stats.headshotMult}` },
		{ "Mobility", `{weightPct}% move speed` },
		{ "Pull-out / ADS", `{stats.equipTime}s / {stats.adsTime}s` },
	}
	for index, row in rows do
		local label = mkText(inspectStatsList, 14, TEXT_DARK)
		label.LayoutOrder = index
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = `{row[1]}:  {row[2]}`
	end

	-- Skin chips: Default + the gun's three schemes.
	for _, child in inspectSkinRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local function skinChip(order: number, label: string, color: Color3, skinId: string?, owned: boolean, price: number?)
		local chip = Instance.new("TextButton")
		chip.LayoutOrder = order
		chip.Size = UDim2.fromOffset(74, 40)
		chip.BackgroundColor3 = color
		chip.Font = Enum.Font.FredokaOne
		chip.TextSize = 11
		chip.TextColor3 = ROW_WHITE
		chip.TextStrokeColor3 = TEXT_DARK
		chip.TextStrokeTransparency = 0.4
		chip.Text = if owned or not price then label else `{label}\n💗{price}`
		round(chip, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = if previewSkinId == skinId then HOT_PINK else Color3.fromRGB(240, 200, 220)
		stroke.Thickness = if previewSkinId == skinId then 3 else 1
		stroke.Parent = chip
		chip.MouseButton1Click:Connect(function()
			previewSkinId = skinId
			applyPreview()
			populateInspect(gunId) -- refresh chip strokes + action button
		end)
		chip.Parent = inspectSkinRow
	end
	skinChip(1, "Default", Color3.fromRGB(255, 245, 250), nil, true, nil)
	local skins = GunSkinCatalog.perGun[gunId]
	if skins then
		local order = 2
		for skinId, skin in skins do
			skinChip(order, skin.name, skin.body, skinId, ClientData.ownsGunSkin(skinId), skin.price)
			order += 1
		end
	end

	-- Action button state machine: buy gun → buy skin → equip skin → equip gun.
	local ownsGun = ClientData.ownsGun(gunId)
	local primary, secondary = ClientData.loadout()
	local equippedGun = if def.slot == "Primary" then primary == gunId else secondary == gunId
	local currentSkin, currentCamo = ClientData.gunCosmeticsFor(gunId)

	if not ownsGun then
		inspectAction.Text = `Buy — 💗 {def.price}`
	elseif previewSkinId and not ClientData.ownsGunSkin(previewSkinId) then
		local skin = skins and skins[previewSkinId]
		inspectAction.Text = `Buy skin — 💗 {if skin then skin.price else 0}`
	elseif previewSkinId ~= currentSkin then
		inspectAction.Text = "Equip this look 🎀"
	elseif not equippedGun then
		inspectAction.Text = `Equip {def.slot} 🎀`
	else
		inspectAction.Text = "Equipped ✓"
	end
end

local function closeInspect()
	local current = inspecting
	if current then
		current.model:Destroy()
	end
	inspecting = nil
	previewSkinId = nil
	inspectPanel.Visible = false
	setBusy(false)
end

local function startInspect(record: DisplayRecord)
	closeInspect()
	local mat = findMat(record.slot) or record.slot
	local model = GunModelLoader.build(record.gunId, nil)
	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.Anchored = true
			piece.CanQuery = false
		end
	end
	local base = mat.CFrame * CFrame.new(0, mat.Size.Y / 2 + 2.4, 0)
	model:PivotTo(base)
	model.Parent = displayFolder

	local _, currentCamo = ClientData.gunCosmeticsFor(record.gunId)
	previewSkinId = (ClientData.gunCosmeticsFor(record.gunId))
	inspecting = { gunId = record.gunId, model = model, base = base, yaw = 0, pitch = 0 }
	inspectMessage.Text = ""
	populateInspect(record.gunId)
	inspectPanel.Visible = true
	setBusy(true)
end

-- Floating + drag-to-rotate.
local function updateInspect(deltaTime: number)
	local current = inspecting
	if not current then
		return
	end
	if not dragging then
		current.yaw += deltaTime * 0.4 -- lazy idle spin
	end
	local bob = math.sin(os.clock() * 1.6) * 0.15
	current.model:PivotTo(
		current.base
			* CFrame.new(0, bob, 0)
			* CFrame.Angles(0, current.yaw, 0)
			* CFrame.Angles(current.pitch, 0, 0)
	)
end

local function onInspectAction()
	local current = inspecting
	if not current or busyRequest then
		return
	end
	local gunId = current.gunId
	local def = GunCatalog.get(gunId)
	if not def then
		return
	end
	busyRequest = true
	task.spawn(function()
		local ok, result = pcall(function(): any
			local ownsGun = ClientData.ownsGun(gunId)
			local primary, secondary = ClientData.loadout()
			local currentSkin, currentCamo = ClientData.gunCosmeticsFor(gunId)
			if not ownsGun then
				return Remotes.invoke("BuyGun", gunId)
			elseif previewSkinId and not ClientData.ownsGunSkin(previewSkinId) then
				return Remotes.invoke("BuyGunSkin", gunId, previewSkinId)
			elseif previewSkinId ~= currentSkin then
				return Remotes.invoke("EquipGunCosmetics", gunId, previewSkinId, currentCamo)
			else
				local newPrimary = if def.slot == "Primary" then gunId else primary
				local newSecondary = if def.slot == "Secondary" then gunId else secondary
				return Remotes.invoke("EquipLoadout", newPrimary, newSecondary)
			end
		end)
		busyRequest = false
		if not ok then
			inspectMessage.Text = "Something went wrong — try again."
			return
		end
		if type(result) == "table" and result.error then
			inspectMessage.Text = tostring(result.error)
		elseif type(result) == "table" and result.ok then
			inspectMessage.Text = "Done! 💗"
		end
		local stillOpen = inspecting
		if stillOpen then
			populateInspect(stillOpen.gunId)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- UI construction (functional; the design pass restyles per handoff)
-- ---------------------------------------------------------------------------

local function buildUi()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "ArmoryUI"
	screen.ResetOnSpawn = false

	-- Hover card (follows the lower-right of the cursor area; fixed pos MVP)
	hoverCard = Instance.new("Frame")
	hoverCard.AnchorPoint = Vector2.new(1, 1)
	hoverCard.Position = UDim2.new(1, -24, 1, -24)
	hoverCard.Size = UDim2.fromOffset(230, 200)
	stylePanel(hoverCard, 14)
	hoverCard.Visible = false
	hoverViewport = Instance.new("ViewportFrame")
	hoverViewport.Position = UDim2.new(0, 10, 0, 10)
	hoverViewport.Size = UDim2.new(1, -20, 0, 110)
	hoverViewport.BackgroundColor3 = ROW_WHITE
	hoverViewport.BackgroundTransparency = 0.2
	round(hoverViewport, 10)
	hoverViewport.Parent = hoverCard
	hoverName = mkText(hoverCard, 19, DEEP_PINK)
	hoverName.Position = UDim2.new(0, 12, 0, 124)
	hoverName.Size = UDim2.new(1, -24, 0, 22)
	hoverName.TextXAlignment = Enum.TextXAlignment.Left
	hoverRarity = mkText(hoverCard, 13, TEXT_DARK)
	hoverRarity.Position = UDim2.new(0, 12, 0, 146)
	hoverRarity.Size = UDim2.new(1, -24, 0, 16)
	hoverRarity.TextXAlignment = Enum.TextXAlignment.Left
	hoverStats = mkText(hoverCard, 13, TEXT_DARK)
	hoverStats.Position = UDim2.new(0, 12, 0, 166)
	hoverStats.Size = UDim2.new(1, -24, 0, 16)
	hoverStats.TextXAlignment = Enum.TextXAlignment.Left
	hoverCard.Parent = screen

	-- Take a look / Cancel dialog
	dialog = Instance.new("Frame")
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.6)
	dialog.Size = UDim2.fromOffset(280, 120)
	stylePanel(dialog, 16)
	dialog.Visible = false
	dialogTitle = mkText(dialog, 18, DEEP_PINK)
	dialogTitle.Position = UDim2.new(0, 0, 0, 12)
	dialogTitle.Size = UDim2.new(1, 0, 0, 24)
	local function dialogButton(text: string, x: number, color: Color3): TextButton
		local button = Instance.new("TextButton")
		button.Position = UDim2.new(0, x, 1, -48)
		button.Size = UDim2.fromOffset(120, 36)
		button.BackgroundColor3 = color
		button.Font = Enum.Font.FredokaOne
		button.TextSize = 16
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = text
		round(button, 12)
		button.Parent = dialog
		return button
	end
	local lookButton = dialogButton("Take a look 🎀", 14, HOT_PINK)
	local cancelButton = dialogButton("Cancel", 146, Color3.fromRGB(180, 150, 165))
	dialog.Parent = screen

	-- pendingRecord is declared at module scope (see the note there).
	lookButton.MouseButton1Click:Connect(function()
		dialog.Visible = false
		if pendingRecord then
			startInspect(pendingRecord)
		end
	end)
	cancelButton.MouseButton1Click:Connect(function()
		dialog.Visible = false
		pendingRecord = nil
		setBusy(false)
	end)
	ArmoryController._openDialog = function(record: DisplayRecord)
		pendingRecord = record
		dialogTitle.Text = (GunCatalog.get(record.gunId) or { name = record.gunId }).name
		dialog.Visible = true
		setBusy(true)
	end

	-- Inspection side panel
	inspectPanel = Instance.new("Frame")
	inspectPanel.AnchorPoint = Vector2.new(1, 0.5)
	inspectPanel.Position = UDim2.new(1, -24, 0.5, 0)
	inspectPanel.Size = UDim2.fromOffset(300, 500)
	stylePanel(inspectPanel, 16)
	inspectPanel.Visible = false
	inspectName = mkText(inspectPanel, 24, DEEP_PINK)
	inspectName.Position = UDim2.new(0, 16, 0, 12)
	inspectName.Size = UDim2.new(1, -32, 0, 28)
	inspectName.TextXAlignment = Enum.TextXAlignment.Left
	inspectRarity = mkText(inspectPanel, 14, TEXT_DARK)
	inspectRarity.Position = UDim2.new(0, 16, 0, 42)
	inspectRarity.Size = UDim2.new(1, -32, 0, 18)
	inspectRarity.TextXAlignment = Enum.TextXAlignment.Left
	inspectStatsList = Instance.new("Frame")
	inspectStatsList.Position = UDim2.new(0, 16, 0, 66)
	inspectStatsList.Size = UDim2.new(1, -32, 0, 198)
	inspectStatsList.BackgroundTransparency = 1
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = inspectStatsList
	inspectStatsList.Parent = inspectPanel
	local skinsLabel = mkText(inspectPanel, 15, DEEP_PINK)
	skinsLabel.Position = UDim2.new(0, 16, 0, 240)
	skinsLabel.Size = UDim2.new(1, -32, 0, 18)
	skinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	skinsLabel.Text = "Skins"
	inspectSkinRow = Instance.new("Frame")
	inspectSkinRow.Position = UDim2.new(0, 16, 0, 274)
	inspectSkinRow.Size = UDim2.new(1, -32, 0, 88)
	inspectSkinRow.BackgroundTransparency = 1
	local skinLayout = Instance.new("UIGridLayout")
	skinLayout.CellSize = UDim2.fromOffset(74, 40)
	skinLayout.CellPadding = UDim2.fromOffset(6, 6)
	skinLayout.Parent = inspectSkinRow
	inspectSkinRow.Parent = inspectPanel
	inspectAction = Instance.new("TextButton")
	inspectAction.Position = UDim2.new(0, 16, 1, -72)
	inspectAction.Size = UDim2.new(1, -32, 0, 38)
	inspectAction.BackgroundColor3 = HOT_PINK
	inspectAction.Font = Enum.Font.FredokaOne
	inspectAction.TextSize = 17
	inspectAction.TextColor3 = Color3.new(1, 1, 1)
	inspectAction.Text = ""
	round(inspectAction, 12)
	inspectAction.MouseButton1Click:Connect(onInspectAction)
	inspectAction.Parent = inspectPanel

	-- Free trial: server slots the gun for 60s (session-only, never owned).
	local tryButton = Instance.new("TextButton")
	tryButton.Position = UDim2.new(0, 16, 1, -112)
	tryButton.Size = UDim2.new(1, -32, 0, 32)
	tryButton.BackgroundColor3 = Color3.fromRGB(255, 130, 190)
	tryButton.Font = Enum.Font.FredokaOne
	tryButton.TextSize = 15
	tryButton.TextColor3 = Color3.new(1, 1, 1)
	tryButton.Text = "Not sure? Try it in the range! 💘"
	round(tryButton, 12)
	tryButton.MouseButton1Click:Connect(function()
		local current = inspecting
		if not current or busyRequest then
			return
		end
		local gunId = current.gunId
		busyRequest = true
		task.spawn(function()
			local ok, result = pcall(function(): any
				return Remotes.invoke("TryGun", gunId)
			end)
			busyRequest = false
			if ok and type(result) == "table" and result.ok then
				closeInspect()
			elseif ok and type(result) == "table" and result.error then
				inspectMessage.Text = tostring(result.error)
			else
				inspectMessage.Text = "Something went wrong — try again."
			end
		end)
	end)
	tryButton.Parent = inspectPanel
	inspectMessage = mkText(inspectPanel, 13, DEEP_PINK)
	inspectMessage.Position = UDim2.new(0, 16, 1, -30)
	inspectMessage.Size = UDim2.new(1, -32, 0, 18)
	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.BackgroundColor3 = HOT_PINK
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.TextSize = 14
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Text = "✕"
	round(closeButton, 14)
	closeButton.MouseButton1Click:Connect(closeInspect)
	closeButton.Parent = inspectPanel
	inspectPanel.Parent = screen

	screen.Parent = playerGui
end

-- ---------------------------------------------------------------------------
-- Input + loops
-- ---------------------------------------------------------------------------

local function updateHover()
	-- Walking away from an open "Take a look?" dialog used to strand it on
	-- screen with armoryBusy still true, which permanently hid START GAME.
	if dialog.Visible and pendingRecord then
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local slot = pendingRecord.slot
		if root and root:IsA("BasePart") and slot then
			if (root.Position - slot.Position).Magnitude > DIALOG_WALK_AWAY then
				dialog.Visible = false
				pendingRecord = nil
				setBusy(false)
			end
		end
	end

	if not ClientData.inLobby() or ClientData.menuOpen() or inspecting or dialog.Visible then
		if hoveredRecord then
			hoveredRecord = nil
			hideHover()
		end
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 200)
	local record = if result then recordFromInstance(result.Instance) else nil
	-- Hovering the slot part itself counts too.
	if not record and result then
		for _, candidate in displays do
			if candidate.slot == result.Instance then
				record = candidate
				break
			end
		end
	end
	if record ~= hoveredRecord then
		hoveredRecord = record
		if record then
			showHover(record)
		else
			hideHover()
		end
	end
end

function ArmoryController.init()
	buildUi()
	renderDisplays()

	ClientData.roundStateChanged:Connect(function()
		if ClientData.inLobby() then
			renderDisplays() -- interiors may have streamed in
		else
			closeInspect()
			hideHover()
			-- The dialog used to survive the round start: clicking "Take a
			-- look" mid-combat then spawned a gun in the world and opened an
			-- inspection panel over gameplay. Clearing armoryBusy also matters
			-- because LobbyController hides START GAME while it's set, so a
			-- dialog left open was a permanent soft-lock out of every round.
			dialog.Visible = false
			setBusy(false)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if gameProcessed then
				return
			end
			if inspecting then
				dragging = true
				return
			end
			local record = hoveredRecord
			if record and ClientData.inLobby() then
				ArmoryController._openDialog(record)
			end
		elseif input.KeyCode == Enum.KeyCode.Escape and inspecting then
			closeInspect()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local current = inspecting
		if current and dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			current.yaw -= input.Delta.X * 0.01
			current.pitch = math.clamp(current.pitch + input.Delta.Y * 0.008, -1, 1)
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		updateHover()
		updateInspect(deltaTime)
	end)
	RunService.RenderStepped:Connect(function()
		spinHoverViewport()
	end)
end

return ArmoryController
