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
-- don't own render behind a lock scrim with their price.
--
-- All chrome comes from UI/Theme + UI/Components; this file declares no
-- colours of its own.
--
-- The server owns the decisions: EquipLoadout re-validates ownership, slot,
-- and lobby-only; EquipGunCosmetics re-validates camo ownership and fit. This
-- file only ever *asks*.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local GunModelLoader = require(ReplicatedStorage.Shared.Assets.GunModelLoader)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local CARD_SIZE = Vector2.new(168, 176)
local COLUMNS = 4

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
local spinners: { { model: Model, centre: Vector3, basePivot: CFrame } } = {}
local lastSignature: string? = nil

local function showStatus(text: string, isError: boolean)
	local label = statusLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = if isError then Theme.color.danger else Theme.color.text
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

local function buildPreview(card: GuiObject, gunId: string, owned: boolean)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -Theme.space.md, 0, 78)
	viewport.Position = UDim2.fromOffset(Theme.space.sm - 2, Theme.space.sm - 2)
	viewport.BackgroundColor3 = Theme.color.surfaceSunken
	viewport.BackgroundTransparency = if owned then 0.35 else 0.1
	viewport.Ambient = if owned
		then Color3.fromRGB(220, 210, 218)
		else Color3.fromRGB(130, 120, 128)
	viewport.LightColor = Theme.color.surfaceRaised
	viewport.Parent = card
	Components.corner(viewport, Theme.radius.chip)

	local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
	local ok, model = pcall(function()
		return GunModelLoader.build(gunId, { skinId = skinId, camoId = camoId })
	end)
	if not ok or typeof(model) ~= "Instance" then
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

	local bounds, size = model:GetBoundingBox()
	local centre = bounds.Position
	local distance = math.max(math.max(size.X, size.Y, size.Z) * 1.7, 2)
	camera.CFrame = CFrame.lookAt(
		centre + Vector3.new(distance * 0.62, distance * 0.3, distance * 0.62),
		centre
	)

	-- Spin about the BOUNDING-BOX centre while preserving the model's own
	-- pivot. PivotTo positions the PrimaryPart (GunModelLoader picks the part
	-- named "Body"), which is a different point from the bbox centre — so
	-- handing the bbox CFrame straight to PivotTo shifts the gun by
	-- (bboxCentre - bodyCentre) on its very first frame. On a rifle that is a
	-- large fraction of its length, enough to leave a 78px viewport empty.
	table.insert(spinners, { model = model, centre = centre, basePivot = model:GetPivot() })
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

	local card = Components.card(container, {
		area = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		accent = Theme.rarityColor(def.rarity),
		selected = equipped,
		order = order,
	})
	card.Name = gunId

	buildPreview(card, gunId, owned)

	Components.text(card, {
		text = def.name,
		size = Theme.text.body,
		color = if owned then Theme.color.text else Theme.color.textMuted,
		area = UDim2.new(1, -18, 0, 20),
		position = UDim2.fromOffset(10, 90),
		truncate = true,
	})

	Components.text(card, {
		text = `{def.class} · {def.rarity}`,
		size = Theme.text.caption,
		color = Theme.rarityColor(def.rarity),
		area = UDim2.new(1, -18, 0, 16),
		position = UDim2.fromOffset(10, 110),
	})

	local stats = CombatStats.resolve(gunId)
	Components.text(card, {
		text = `{math.floor(stats.damageNear + 0.5)} dmg · {math.floor(stats.fireRate * 60 + 0.5)} rpm`,
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -18, 0, 15),
		position = UDim2.fromOffset(10, 127),
	})

	if equipped then
		Components.text(card, {
			text = "✓ EQUIPPED",
			size = Theme.text.label,
			color = Theme.color.primary,
			area = UDim2.new(1, -18, 0, 18),
			position = UDim2.fromOffset(10, 147),
		})
	elseif owned then
		Components.text(card, {
			text = "Tap to equip",
			size = Theme.text.label,
			color = Theme.color.textMuted,
			area = UDim2.new(1, -18, 0, 18),
			position = UDim2.fromOffset(10, 147),
		})
	else
		-- Locked guns stay legible behind the scrim: the roster should read as
		-- something to work toward, not as disabled UI.
		Components.lockedScrim(card, `{def.price} 🪙`)
	end

	card.Activated:Connect(function()
		if not owned then
			-- Deliberately does NOT set selectedGun: pointing the camo strip at
			-- a gun the player doesn't own makes every camo tap round-trip to a
			-- guaranteed "You don't own that gun" from the server, about a gun
			-- they never meant to target.
			showStatus(`{def.name} costs {def.price} coins — buy it in the Armory 💗`, true)
			return
		end
		selectedGun = gunId
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

	local chip = Components.button(row, {
		area = UDim2.fromOffset(112, 46),
		selected = equipped,
		text = if isNone
			then "No camo"
			elseif unreleased then `{def.name}\n(coming soon)`
			elseif owned then def.name
			else `🔒 {def.name}\n{def.price} 🪙`,
	})
	chip.LayoutOrder = order
	if unreleased then
		chip.TextColor3 = Theme.color.textMuted
	elseif not owned and not isNone then
		chip.TextColor3 = Theme.color.coin
	end

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

-- Everything the panel actually draws, as one cheap comparable string. Coins
-- and XP deliberately do NOT appear here: they arrive on the same DataChanged
-- event, change constantly, and change nothing on this screen.
function LoadoutController.signature(): string
	local snap = ClientData.snapshot
	local owned = if type(snap) == "table" and type(snap.ownedGuns) == "table"
		then table.concat(snap.ownedGuns :: { string }, ",")
		else ""
	local camos = if type(snap) == "table" and type(snap.ownedCamos) == "table"
		then table.concat(snap.ownedCamos :: { string }, ",")
		else ""
	local primary, secondary = ClientData.loadout()
	local skinId: string?, camoId: string? = nil, nil
	if selectedGun then
		skinId, camoId = ClientData.gunCosmeticsFor(selectedGun)
	end
	return table.concat({
		activeSlot,
		tostring(selectedGun),
		tostring(primary),
		secondary,
		tostring(skinId),
		tostring(camoId),
		owned,
		camos,
	}, "|")
end

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
	container.CanvasSize =
		UDim2.fromOffset(0, math.ceil(#entries / COLUMNS) * (CARD_SIZE.Y + Theme.space.sm) + Theme.space.md)

	-- Camos apply to whichever gun is selected; default to the equipped one.
	if not selectedGun then
		local primary, secondary = ClientData.loadout()
		selectedGun = if activeSlot == "Primary" then primary else secondary
	end

	if selectedGun then
		-- A camo whose PNG was never uploaded has textureId "" and the server
		-- refuses to sell it, so listing it produces chips that can only fail.
		-- Today that is all ten of them. Show the real ones; if there are none
		-- yet, say so once instead of rendering a row of dead buttons.
		local available = 0
		for _, def in GunSkinCatalog.universal do
			if def.textureId ~= "" then
				available += 1
			end
		end

		if available == 0 then
			Components.text(row, {
				text = "Camos coming soon 💗",
				size = Theme.text.label,
				color = Theme.color.textMuted,
				area = UDim2.fromOffset(220, 46),
			})
			row.CanvasSize = UDim2.fromOffset(0, 0)
		else
			addCamoChip(nil, nil, 0)
			local order = 1
			for camoId, def in GunSkinCatalog.universal do
				if def.textureId ~= "" then
					addCamoChip(camoId, def, order)
					order += 1
				end
			end
			row.CanvasSize = UDim2.fromOffset(order * 120 + Theme.space.md, 0)
		end
	end

	for slot, button in slotButtons do
		local selected = slot == activeSlot
		button.BackgroundColor3 = if selected then Theme.color.primary else Theme.color.surfaceRaised
		button.TextColor3 = if selected then Theme.color.textOnPrimary else Theme.color.text
	end

	lastSignature = LoadoutController.signature()
end

function LoadoutController.setOpen(open: boolean)
	local screen = gui
	local blocker = modal
	if not screen or not blocker then
		return
	end
	screen.Enabled = open
	blocker.Visible = open
	ClientData.loadoutOpen = open
	ClientData.updateMouseUnlock()
	-- Always clear the in-flight guard on open/close. InvokeServer has no
	-- timeout, so a handler that yields forever would otherwise latch `busy`
	-- true and silently deaden every card and chip for the rest of the
	-- session, with reopening the panel powerless to recover it.
	busy = false
	if open then
		selectedGun = nil
		lastSignature = nil
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

	modal = Components.modalBlocker(screen)

	local panel = Components.panel(screen, {
		area = UDim2.fromOffset(760, 560),
		centered = true,
	})

	Components.text(panel, {
		text = "LOADOUT 💗",
		size = Theme.text.title,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -Theme.space.xl, 0, 34),
		position = UDim2.fromOffset(Theme.space.lg, 18),
	})

	local close = Components.button(panel, {
		text = "✕",
		size = Theme.text.heading,
		area = UDim2.fromOffset(38, 38),
		position = UDim2.new(1, -52, 0, 16),
	})
	close.Activated:Connect(function()
		LoadoutController.setOpen(false)
	end)

	for index, slot in { "Primary", "Secondary" } do
		local tab = Components.button(panel, {
			text = slot,
			area = UDim2.fromOffset(132, 36),
			position = UDim2.fromOffset(Theme.space.lg + (index - 1) * 142, 62),
			selected = slot == activeSlot,
		})
		slotButtons[slot] = tab
		tab.Activated:Connect(function()
			activeSlot = slot
			selectedGun = nil
			LoadoutController.refresh()
		end)
	end

	statusLabel = Components.text(panel, {
		size = Theme.text.label,
		color = Theme.color.text,
		area = UDim2.new(1, -320, 0, 20),
		position = UDim2.fromOffset(300, 70),
	})

	local scroller = Components.scroller(panel)
	scroller.Size = UDim2.new(1, -Theme.space.xl - Theme.space.sm, 0, 372)
	scroller.Position = UDim2.fromOffset(Theme.space.lg, 108)
	Components.gridLayout(scroller, CARD_SIZE, Theme.space.sm)
	grid = scroller

	Components.text(panel, {
		text = "CAMO",
		size = Theme.text.label,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -Theme.space.xl, 0, 18),
		position = UDim2.fromOffset(Theme.space.lg, 486),
	})

	local camos = Components.scroller(panel, true)
	camos.Size = UDim2.new(1, -Theme.space.xl - Theme.space.sm, 0, 46)
	camos.Position = UDim2.fromOffset(Theme.space.lg, 506)
	camos.ScrollBarThickness = 4
	Components.listLayout(camos, Enum.FillDirection.Horizontal, Theme.space.sm)
	camoRow = camos
end

function LoadoutController.init()
	buildGui()

	-- Slow spin on every preview, so the cases feel alive.
	RunService.RenderStepped:Connect(function()
		local screen = gui
		if not screen or not screen.Enabled then
			return
		end
		local angle = os.clock() % (math.pi * 2)
		for _, entry in spinners do
			if entry.model.Parent then
				local spin = CFrame.new(entry.centre)
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(-entry.centre)
				entry.model:PivotTo(spin * entry.basePivot)
			end
		end
	end)

	-- Ownership, coins and loadout all arrive on the same DataChanged event,
	-- but a refresh destroys and re-clones every gun model on the tab (up to
	-- 25 ViewportFrames, the most expensive GUI object Roblox has). Coins tick
	-- on every kill, so refreshing blindly would hitch the panel constantly —
	-- and equipping pushes data by definition, so every tap paid for a full
	-- rebuild. Only rebuild when something the panel actually draws changed.
	ClientData.changed:Connect(function()
		local screen = gui
		if not screen or not screen.Enabled then
			return
		end
		local signature = LoadoutController.signature()
		if signature ~= lastSignature then
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
