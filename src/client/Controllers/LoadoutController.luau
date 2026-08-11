--!strict
-- LoadoutController — the full-screen gun menu: Loadout, Armory, and Gun
-- Detail behind one persistent tab bar.
--
-- Built from docs/design/ARMORY_LOADOUT_BRIEF.md and the Claude Design
-- handoff. Three surfaces, one controller, because the design puts them
-- under a single tab bar and they share all their state.
--
-- Not to be confused with ArmoryController, which is a different thing: the
-- physical Candy Armory interior with tagged GunDisplay parts.
--
-- Everything is read live from ClientData and never mirrored. The server owns
-- every decision — this file only ever asks, and shows what comes back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local CombatStats = require(ReplicatedStorage.Shared.Config.CombatStats)
local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local GunPreview = require(script.Parent.Parent.UI.GunPreview)
local StatBlock = require(script.Parent.Parent.UI.StatBlock)

local TOP_BAR = 64
local CARD = Vector2.new(204, 186)
local CLASSES = { "Pistol", "Revolver", "SMG", "Shotgun", "Rifle", "Carbine", "Bullpup", "Sniper" }

local LoadoutController = {}

-- state ---------------------------------------------------------------------
local screenName = "loadout" -- "loadout" | "armory" | "detail"
local detailId: string? = nil
local activeSlot = "Primary"
local picking = false
local filter = "All"
local busy = false
local lastSignature: string? = nil

-- instances -----------------------------------------------------------------
local gui: ScreenGui? = nil
local modal: TextButton? = nil
local coinLabel: TextLabel? = nil
local messageLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function message(text: string, ok: boolean)
	local label = messageLabel
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = if ok then Theme.color.success else Theme.color.danger
	task.delay(3, function()
		if label.Text == text then
			label.Text = ""
		end
	end)
end

-- One request in flight; the server rate-limits independently. `busy` is
-- cleared on every screen change too — InvokeServer has no timeout, and a
-- latched flag would silently deaden the whole menu.
local function request(fn: () -> any, successText: string?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(fn)
		busy = false
		if not ok then
			message("Something went wrong — try again.", false)
			return
		end
		if type(result) == "table" and result.ok ~= true then
			message(tostring(result.error or "Nope!"), false)
		elseif successText then
			message(successText, true)
		end
	end)
end

local function statLine(gunId: string): string
	local s = CombatStats.resolve(gunId)
	local rpm = math.floor(s.fireRate * 60 + 0.5)
	if s.pellets > 1 then
		return `{s.pellets}×{math.floor(s.damageNear + 0.5)} dmg · {rpm} rpm`
	end
	return `{math.floor(s.damageNear + 0.5)} dmg · {rpm} rpm`
end

local function ownedCount(): number
	local snap = ClientData.snapshot
	local list = snap and snap.ownedGuns
	return if type(list) == "table" then #list else 0
end

local function equipSlot(gunId: string, slot: string)
	local primary, secondary = ClientData.loadout()
	if slot == "Primary" then
		primary = gunId
	else
		secondary = gunId
	end
	local def = GunCatalog.get(gunId)
	request(function()
		return Remotes.func("EquipLoadout"):InvokeServer(primary, secondary)
	end, `Equipped {if def then def.name else gunId}`)
end

-- ---------------------------------------------------------------------------
-- Shared bits
-- ---------------------------------------------------------------------------

local function previewWell(parent: GuiObject, gunId: string, rarity: string, spin: boolean): GunPreview.Handle?
	local well = Instance.new("Frame")
	well.Size = UDim2.new(1, 0, 0, 96)
	well.BackgroundColor3 = Theme.color.surfaceSunken
	well.BorderSizePixel = 0
	well.ClipsDescendants = true
	well.Parent = parent
	Components.corner(well, Theme.radius.card)

	-- Rarity-tinted backdrop, so a Legendary reads as special before you've
	-- read a single word.
	local glow = Instance.new("Frame")
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundColor3 = Theme.rarityColor(rarity)
	glow.BackgroundTransparency = 0.86
	glow.BorderSizePixel = 0
	glow.Parent = well

	local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
	return GunPreview.create(well, gunId, skinId, camoId, spin)
end

local function scrollPanel(parent: Instance, area: UDim2, position: UDim2): (Frame, ScrollingFrame)
	local panel = Instance.new("Frame")
	panel.Size = area
	panel.Position = position
	panel.BackgroundColor3 = Theme.color.surfaceRaised
	panel.BorderSizePixel = 0
	panel.Parent = parent
	Components.corner(panel, Theme.radius.panel)
	Components.stroke(panel, Theme.color.primarySoft, 2, 0.45)

	local scroller = Components.scroller(panel)
	scroller.Size = UDim2.new(1, -Theme.space.lg * 2, 1, -Theme.space.lg * 2)
	scroller.Position = UDim2.fromOffset(Theme.space.lg, Theme.space.lg)
	Components.listLayout(scroller, Enum.FillDirection.Vertical, Theme.space.md)

	return panel, scroller
end

-- ---------------------------------------------------------------------------
-- Colour skins + camos (Detail, and the Loadout stat column)
-- ---------------------------------------------------------------------------

local function chip(parent: Instance, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(104, 62)
	button.LayoutOrder = order
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = Theme.color.surfaceRaised
	button.Parent = parent
	Components.corner(button, Theme.radius.chip)
	return button
end

local function buildSkins(parent: Instance, gunId: string, order: number)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 96)
	holder.BackgroundColor3 = Theme.color.surface
	holder.BorderSizePixel = 0
	holder.LayoutOrder = order
	holder.Parent = parent
	Components.corner(holder, Theme.radius.card)
	Components.padding(holder, Theme.space.md)

	Components.text(holder, {
		text = "COLOUR SKINS",
		size = Theme.text.label,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, 0, 0, 18),
	})

	local row = Components.scroller(holder, true)
	row.Size = UDim2.new(1, 0, 0, 62)
	row.Position = UDim2.fromOffset(0, 24)
	row.ScrollBarThickness = 4
	Components.listLayout(row, Enum.FillDirection.Horizontal, Theme.space.sm)

	local ownsGun = ClientData.ownsGun(gunId)
	local equippedSkin = select(1, ClientData.gunCosmeticsFor(gunId))
	local _, equippedCamo = ClientData.gunCosmeticsFor(gunId)

	local entries: { { id: string?, name: string, price: number, colour: Color3 } } = {
		{ id = nil, name = "Stock", price = 0, colour = Theme.color.surfaceSunken },
	}
	local skins = GunSkinCatalog.perGun[gunId]
	if skins then
		for skinId, def in skins do
			table.insert(entries, {
				id = skinId,
				name = def.name,
				price = def.price,
				colour = if typeof(def.body) == "Color3" then def.body else Theme.color.primarySoft,
			})
		end
	end

	for index, entry in entries do
		local isStock = entry.id == nil
		local owned = isStock or ClientData.ownsGunSkin(entry.id :: string)
		local equipped = equippedSkin == entry.id
		local button = chip(row, index)

		if equipped then
			button.BackgroundColor3 = Theme.color.primary
			Components.stroke(button, Theme.color.primaryDeep, 3, 0)
		elseif owned then
			Components.stroke(button, Theme.color.primarySoft, 2, 0.45)
		else
			button.BackgroundColor3 = Theme.color.surfaceSunken
			Components.stroke(button, Theme.color.primarySoft, 2, 0.55)
		end

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(1, -12, 0, 22)
		swatch.Position = UDim2.fromOffset(6, 6)
		swatch.BackgroundColor3 = entry.colour
		swatch.BorderSizePixel = 0
		swatch.Parent = button
		Components.corner(swatch, 6)

		Components.text(button, {
			text = if equipped then `✓ {entry.name}` else entry.name,
			size = Theme.text.caption,
			color = if equipped then Theme.color.textOnPrimary else Theme.color.text,
			area = UDim2.new(1, -12, 0, 14),
			position = UDim2.fromOffset(6, 30),
			truncate = true,
		})
		Components.text(button, {
			text = if equipped
				then "equipped"
				elseif isStock then "default"
				elseif owned then "owned"
				else `{entry.price} 🪙`,
			size = Theme.text.caption,
			color = if equipped
				then Theme.color.textOnPrimary
				elseif owned then Theme.color.textMuted
				else Theme.color.coin,
			area = UDim2.new(1, -12, 0, 14),
			position = UDim2.fromOffset(6, 44),
		})

		button.Activated:Connect(function()
			if not ownsGun then
				local def = GunCatalog.get(gunId)
				message(`Buy {if def then def.name else gunId} before dressing it up`, false)
				return
			end
			if owned then
				request(function()
					return Remotes.func("EquipGunCosmetics"):InvokeServer(gunId, entry.id, equippedCamo)
				end)
			else
				request(function()
					return Remotes.func("BuyGunSkin"):InvokeServer(gunId, entry.id)
				end, `Bought {entry.name}`)
			end
		end)
	end

	row.CanvasSize = UDim2.fromOffset(#entries * 112 + Theme.space.md, 0)
end

local function buildCamos(parent: Instance, gunId: string, order: number)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 100)
	holder.BackgroundColor3 = Theme.color.surface
	holder.BorderSizePixel = 0
	holder.LayoutOrder = order
	holder.Parent = parent
	Components.corner(holder, Theme.radius.card)
	Components.padding(holder, Theme.space.md)

	-- Gate on textureId, never a hardcoded flag: the row lights up on its own
	-- the moment the PNGs are uploaded and ids pasted into GunSkinCatalog.
	local released = 0
	for _, def in GunSkinCatalog.universal do
		if def.textureId ~= "" then
			released += 1
		end
	end

	Components.text(holder, {
		text = "CAMOS",
		size = Theme.text.label,
		color = Theme.color.primaryDeep,
		area = UDim2.new(0.4, 0, 0, 18),
	})
	if released == 0 then
		Components.text(holder, {
			text = "all 10 coming soon — textures still uploading",
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			align = Enum.TextXAlignment.Right,
			area = UDim2.new(0.6, 0, 0, 18),
			position = UDim2.new(0.4, 0, 0, 0),
		})
	end

	local row = Components.scroller(holder, true)
	row.Size = UDim2.new(1, 0, 0, 62)
	row.Position = UDim2.fromOffset(0, 24)
	row.ScrollBarThickness = 4
	Components.listLayout(row, Enum.FillDirection.Horizontal, Theme.space.sm)

	local equippedSkin = select(1, ClientData.gunCosmeticsFor(gunId))
	local _, equippedCamo = ClientData.gunCosmeticsFor(gunId)

	local order2 = 0
	for camoId, def in GunSkinCatalog.universal do
		order2 += 1
		local unreleased = def.textureId == ""
		local owned = ClientData.ownsCamo(camoId)
		local equipped = equippedCamo == camoId
		local button = chip(row, order2)

		if unreleased then
			button.BackgroundColor3 = Theme.color.surfaceSunken
			local dash = Components.stroke(button, Theme.color.textMuted, 2, 0.5)
			dash.LineJoinMode = Enum.LineJoinMode.Round
		elseif equipped then
			button.BackgroundColor3 = Theme.color.primary
			Components.stroke(button, Theme.color.primaryDeep, 3, 0)
		elseif owned then
			Components.stroke(button, Theme.color.primarySoft, 2, 0.45)
		else
			button.BackgroundColor3 = Theme.color.surfaceSunken
			Components.stroke(button, Theme.color.primarySoft, 2, 0.55)
		end

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(1, -12, 0, 22)
		swatch.Position = UDim2.fromOffset(6, 6)
		swatch.BackgroundColor3 = if unreleased then Theme.color.scrim else Theme.color.primarySoft
		swatch.BackgroundTransparency = if unreleased then 0.55 else 0
		swatch.BorderSizePixel = 0
		swatch.Parent = button
		Components.corner(swatch, 6)

		Components.text(button, {
			text = if equipped then `✓ {def.name}` else def.name,
			size = Theme.text.caption,
			color = if equipped then Theme.color.textOnPrimary else Theme.color.text,
			area = UDim2.new(1, -12, 0, 14),
			position = UDim2.fromOffset(6, 30),
			truncate = true,
		})
		Components.text(button, {
			text = if unreleased
				then "coming soon"
				elseif equipped then "equipped"
				elseif owned then "owned"
				else `{def.price} 🪙`,
			size = Theme.text.caption,
			color = if unreleased
				then Theme.color.textMuted
				elseif equipped then Theme.color.textOnPrimary
				elseif owned then Theme.color.textMuted
				else Theme.color.coin,
			area = UDim2.new(1, -12, 0, 14),
			position = UDim2.fromOffset(6, 44),
		})

		button.Activated:Connect(function()
			if not ClientData.ownsGun(gunId) then
				message("Buy this gun before dressing it up", false)
				return
			end
			if owned then
				request(function()
					return Remotes.func("EquipGunCosmetics"):InvokeServer(gunId, equippedSkin, camoId)
				end)
			else
				-- The server refuses unreleased camos; let its message speak.
				request(function()
					return Remotes.func("BuyCamo"):InvokeServer(camoId)
				end, `Bought {def.name}`)
			end
		end)
	end

	row.CanvasSize = UDim2.fromOffset(order2 * 112 + Theme.space.md, 0)
end

-- Fills a scroller with the stat block plus skins and camos.
local function buildStatColumn(scroller: ScrollingFrame, gunId: string, big: number)
	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local height = StatBlock.build(scroller, gunId, big)
	buildSkins(scroller, gunId, 7)
	buildCamos(scroller, gunId, 8)
	scroller.CanvasSize = UDim2.fromOffset(0, height + 96 + 100 + Theme.space.md * 2)
end

-- ---------------------------------------------------------------------------
-- Screen 1 — Loadout
-- ---------------------------------------------------------------------------

local charWell: Frame? = nil
local weaponsBody: Frame? = nil
local loadoutStats: ScrollingFrame? = nil
local loadoutTitle: TextLabel? = nil
local loadoutSub: TextLabel? = nil

local refreshLoadout: () -> ()

local function slotCard(parent: Instance, slot: string, gunId: string?, order: number)
	local selected = slot == activeSlot
	local card = Instance.new("TextButton")
	card.Size = UDim2.new(1, 0, 0.5, -6)
	card.LayoutOrder = order
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = Theme.color.surface
	card.ClipsDescendants = true
	card.Parent = parent
	Components.corner(card, Theme.radius.card)
	Components.stroke(
		card,
		if selected then Theme.color.primary else Theme.color.primarySoft,
		3,
		if selected then 0 else 0.5
	)

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 0, 22)
	strip.BackgroundColor3 = if selected then Theme.color.primary else Theme.color.surfaceSunken
	strip.BackgroundTransparency = if selected then 0 else 0.1
	strip.BorderSizePixel = 0
	strip.Parent = card

	Components.text(strip, {
		text = string.upper(slot),
		size = Theme.text.caption,
		color = if selected then Theme.color.textOnPrimary else Theme.color.textMuted,
		area = UDim2.new(0.6, -10, 1, 0),
		position = UDim2.fromOffset(10, 0),
	})
	if selected then
		Components.text(strip, {
			text = "SHOWING",
			size = Theme.text.caption,
			color = Theme.color.textOnPrimary,
			align = Enum.TextXAlignment.Right,
			area = UDim2.new(0.4, -10, 1, 0),
			position = UDim2.new(0.6, 0, 0, 0),
		})
	end

	if gunId then
		local def = GunCatalog.get(gunId)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -20, 1, -22 - 46 - 10)
		holder.Position = UDim2.fromOffset(10, 28)
		holder.BackgroundTransparency = 1
		holder.Parent = card
		previewWell(holder, gunId, if def then def.rarity else "Common", true)

		local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
		local dressing = "Stock"
		if camoId then
			local camo = GunSkinCatalog.universal[camoId]
			dressing = if camo then camo.name else "Camo"
		elseif skinId then
			local skins = GunSkinCatalog.perGun[gunId]
			local skin = skins and skins[skinId]
			dressing = if skin then skin.name else "Skin"
		end

		Components.text(card, {
			text = if def then def.name else gunId,
			size = Theme.text.body,
			color = Theme.color.text,
			area = UDim2.new(1, -80, 0, 18),
			position = UDim2.new(0, 10, 1, -40),
			truncate = true,
		})
		Components.text(card, {
			text = `{if def then def.class else "?"} · {dressing}`,
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			area = UDim2.new(1, -80, 0, 14),
			position = UDim2.new(0, 10, 1, -22),
		})
		Components.text(card, {
			text = "Swap",
			size = Theme.text.caption,
			color = Theme.color.primaryDeep,
			align = Enum.TextXAlignment.Right,
			area = UDim2.fromOffset(60, 18),
			position = UDim2.new(1, -70, 1, -40),
		})
	else
		Components.text(card, {
			text = "Empty — tap to choose",
			size = Theme.text.label,
			color = Theme.color.textMuted,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, 20),
			position = UDim2.new(0, 0, 0.5, -10),
		})
	end

	card.Activated:Connect(function()
		if selected then
			picking = true
		else
			activeSlot = slot
			picking = false
		end
		refreshLoadout()
	end)
end

local function buildPicker(parent: Instance)
	local primary, secondary = ClientData.loadout()
	local equipped = if activeSlot == "Primary" then primary else secondary

	local back = Components.button(parent, {
		text = "←",
		size = Theme.text.heading,
		area = UDim2.fromOffset(30, 30),
	})
	back.Activated:Connect(function()
		picking = false
		refreshLoadout()
	end)

	local owned: { string } = {}
	for gunId, def in GunCatalog.guns do
		if def.slot == activeSlot and ClientData.ownsGun(gunId) then
			table.insert(owned, gunId)
		end
	end
	table.sort(owned, function(a, b)
		return GunCatalog.guns[a].price < GunCatalog.guns[b].price
	end)

	Components.text(parent, {
		text = activeSlot,
		size = Theme.text.heading,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -46, 0, 18),
		position = UDim2.fromOffset(40, 0),
	})
	Components.text(parent, {
		text = `{#owned} owned`,
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -46, 0, 14),
		position = UDim2.fromOffset(40, 18),
	})

	local list = Components.scroller(parent)
	list.Size = UDim2.new(1, 0, 1, -40)
	list.Position = UDim2.fromOffset(0, 40)
	Components.listLayout(list, Enum.FillDirection.Vertical, Theme.space.sm)

	for index, gunId in owned do
		local def = GunCatalog.guns[gunId]
		local isEquipped = gunId == equipped
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 52)
		row.LayoutOrder = index
		row.AutoButtonColor = false
		row.Text = ""
		row.BackgroundColor3 = Theme.color.surface
		row.Parent = list
		Components.corner(row, Theme.radius.card)
		Components.stroke(
			row,
			if isEquipped then Theme.color.primary else Theme.color.primarySoft,
			if isEquipped then 3 else 2,
			if isEquipped then 0 else 0.5
		)

		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(56, 40)
		well.Position = UDim2.fromOffset(6, 6)
		well.BackgroundTransparency = 1
		well.Parent = row
		local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
		GunPreview.create(well, gunId, skinId, camoId, false)

		Components.text(row, {
			text = def.name,
			size = Theme.text.body,
			color = Theme.color.text,
			area = UDim2.new(1, -140, 0, 18),
			position = UDim2.fromOffset(70, 7),
			truncate = true,
		})
		Components.text(row, {
			text = `{def.class} · {statLine(gunId)}`,
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			area = UDim2.new(1, -140, 0, 14),
			position = UDim2.fromOffset(70, 27),
		})
		if isEquipped then
			Components.text(row, {
				text = "✓",
				size = Theme.text.heading,
				color = Theme.color.primaryDeep,
				align = Enum.TextXAlignment.Right,
				area = UDim2.fromOffset(40, 20),
				position = UDim2.new(1, -50, 0, 16),
			})
		end

		row.Activated:Connect(function()
			equipSlot(gunId, activeSlot)
			picking = false
			refreshLoadout()
		end)
	end

	list.CanvasSize = UDim2.fromOffset(0, #owned * 60 + Theme.space.md)
end

function refreshLoadout()
	local well = charWell
	local body = weaponsBody
	local stats = loadoutStats
	if not well or not body or not stats then
		return
	end

	-- Character column
	for _, child in well:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- Isolated: this column is the least important of the three, and a throw
	-- here used to abort refreshLoadout before the weapons and stats columns
	-- were built at all — one dead column blanked the entire screen.
	local charOk, charView = pcall(GunPreview.createCharacter, well)
	if not charOk or not charView then
		Components.text(well, {
			text = "Character unavailable",
			size = Theme.text.label,
			color = Theme.color.textMuted,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, 20),
			position = UDim2.new(0, 0, 0.5, -10),
		})
	end

	-- Weapons column
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local primary, secondary = ClientData.loadout()
	if picking then
		buildPicker(body)
	else
		local stack = Instance.new("Frame")
		stack.Size = UDim2.fromScale(1, 1)
		stack.BackgroundTransparency = 1
		stack.Parent = body
		Components.listLayout(stack, Enum.FillDirection.Vertical, Theme.space.md)
		slotCard(stack, "Primary", primary, 1)
		slotCard(stack, "Secondary", secondary, 2)
	end

	-- Stat column
	local showing = if activeSlot == "Primary" then primary else secondary
	if showing then
		local def = GunCatalog.get(showing)
		if loadoutTitle then
			loadoutTitle.Text = if def then def.name else showing
		end
		if loadoutSub then
			loadoutSub.Text = `{if def then def.class else "?"} · {if def then def.rarity else ""}`
			loadoutSub.TextColor3 = Theme.rarityColor(if def then def.rarity else nil)
		end
		buildStatColumn(stats, showing, Theme.text.title)
	else
		if loadoutTitle then
			loadoutTitle.Text = "No gun equipped"
		end
		if loadoutSub then
			loadoutSub.Text = "Pick one from the Armory"
			loadoutSub.TextColor3 = Theme.color.textMuted
		end
		for _, child in stats:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Screen 2 — Armory
-- ---------------------------------------------------------------------------

local armoryGrid: ScrollingFrame? = nil
local armoryCount: TextLabel? = nil
local filterRow: ScrollingFrame? = nil

local showScreen: (string) -> ()
local refreshArmory: () -> ()

local function gunCard(parent: Instance, gunId: string, def: any, order: number)
	local owned = ClientData.ownsGun(gunId)
	local primary, secondary = ClientData.loadout()
	local equipped = primary == gunId or secondary == gunId

	local card = Instance.new("TextButton")
	card.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	card.LayoutOrder = order
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = Theme.color.surfaceRaised
	card.ClipsDescendants = true
	card.Parent = parent
	Components.corner(card, Theme.radius.card)

	previewWell(card, gunId, def.rarity, false)

	Components.text(card, {
		text = def.name,
		size = Theme.text.body,
		color = Theme.color.text,
		area = UDim2.new(1, -20, 0, 18),
		position = UDim2.fromOffset(10, 102),
		truncate = true,
	})
	Components.text(card, {
		text = `{def.class} · {def.rarity}`,
		size = Theme.text.caption,
		color = Theme.rarityColor(def.rarity),
		area = UDim2.new(1, -20, 0, 14),
		position = UDim2.fromOffset(10, 122),
	})
	Components.text(card, {
		text = statLine(gunId),
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -20, 0, 14),
		position = UDim2.fromOffset(10, 138),
	})

	-- Footer sits ABOVE the scrim so a locked price is always fully legible.
	local footer = Instance.new("Frame")
	footer.Size = UDim2.new(1, 0, 0, 26)
	footer.Position = UDim2.new(0, 0, 1, -26)
	footer.BorderSizePixel = 0
	footer.ZIndex = 12
	footer.Parent = card

	local footerText, footerColour
	if equipped then
		footer.BackgroundColor3 = Theme.color.primary
		footerText, footerColour = "✓ EQUIPPED", Theme.color.textOnPrimary
	elseif owned then
		footer.BackgroundColor3 = Theme.color.surfaceSunken
		footerText, footerColour = "Owned", Theme.color.text
	else
		footer.BackgroundColor3 = Theme.color.scrim
		footer.BackgroundTransparency = 0.18
		footerText, footerColour = `🔒 {comma(def.price)} 🪙`, Theme.color.coin
	end

	Components.text(footer, {
		text = footerText,
		size = Theme.text.label,
		color = footerColour,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromScale(1, 1),
		zIndex = 13,
	})

	if not owned then
		-- Covers the art only, never the footer. Locked reads as aspirational.
		local scrim = Instance.new("Frame")
		scrim.Size = UDim2.new(1, 0, 1, -26)
		scrim.BackgroundColor3 = Theme.color.scrim
		scrim.BackgroundTransparency = 0.55
		scrim.BorderSizePixel = 0
		scrim.ZIndex = 10
		scrim.Parent = card
		Components.corner(scrim, Theme.radius.card)

		Components.text(scrim, {
			text = "🔒",
			size = 26,
			color = Theme.color.textOnPrimary,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, 30),
			position = UDim2.new(0, 0, 0.28, 0),
			zIndex = 11,
		})
	end

	-- Rarity ring drawn last, above the scrim, so the card never shifts
	-- between states.
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 14
	ring.Parent = card
	Components.corner(ring, Theme.radius.card)
	Components.stroke(
		ring,
		if equipped then Theme.color.primary else Theme.rarityColor(def.rarity),
		3,
		if equipped then 0 else 0.5
	)

	card.Activated:Connect(function()
		detailId = gunId
		showScreen("detail")
	end)
end

function refreshArmory()
	local grid = armoryGrid
	local row = filterRow
	if not grid or not row then
		return
	end

	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local counts: { [string]: number } = {}
	for _, def in GunCatalog.guns do
		counts[def.class] = (counts[def.class] or 0) + 1
	end

	local chips: { { key: string, label: string } } = { { key = "All", label = "All 32" } }
	for _, class in CLASSES do
		table.insert(chips, { key = class, label = `{class} {counts[class] or 0}` })
	end

	for index, entry in chips do
		local selected = filter == entry.key
		local button = Components.button(row, {
			text = entry.label,
			area = UDim2.fromOffset(if index == 1 then 74 else 108, 32),
			radius = Theme.radius.pill,
			selected = selected,
		})
		button.LayoutOrder = index
		Components.stroke(
			button,
			if selected then Theme.color.primaryDeep else Theme.color.primarySoft,
			2,
			if selected then 0 else 0.45
		)
		button.Activated:Connect(function()
			filter = entry.key
			refreshArmory()
		end)
	end
	row.CanvasSize = UDim2.fromOffset(74 + #CLASSES * 116 + Theme.space.md, 0)

	local entries: { { id: string, def: any } } = {}
	for gunId, def in GunCatalog.guns do
		if filter == "All" or def.class == filter then
			table.insert(entries, { id = gunId, def = def })
		end
	end
	-- Owned first, then price ascending, so the next affordable thing sits at
	-- the front of the locked run.
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
		gunCard(grid, entry.id, entry.def, index)
	end

	local columns = math.max(math.floor(grid.AbsoluteSize.X / (CARD.X + Theme.space.sm)), 1)
	grid.CanvasSize =
		UDim2.fromOffset(0, math.ceil(#entries / columns) * (CARD.Y + Theme.space.sm) + Theme.space.md)

	if armoryCount then
		armoryCount.Text = `{#entries} of 32 guns · {ownedCount()} owned`
	end
end

-- ---------------------------------------------------------------------------
-- Screen 3 — Gun Detail
-- ---------------------------------------------------------------------------

local detailLeft: Frame? = nil
local detailStats: ScrollingFrame? = nil

local function refreshDetail()
	local left = detailLeft
	local stats = detailStats
	local gunId = detailId
	if not left or not stats or not gunId then
		return
	end
	local def = GunCatalog.get(gunId)
	if not def then
		return
	end

	for _, child in left:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local back = Components.button(left, {
		text = "←",
		size = Theme.text.heading,
		area = UDim2.fromOffset(30, 30),
	})
	back.Activated:Connect(function()
		showScreen("armory")
	end)
	Components.text(left, {
		text = "Back to Armory",
		size = Theme.text.label,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -40, 0, 30),
		position = UDim2.fromOffset(40, 0),
	})

	local hero = Instance.new("Frame")
	hero.Size = UDim2.new(1, 0, 1, -190)
	hero.Position = UDim2.fromOffset(0, 40)
	hero.BackgroundTransparency = 1
	hero.Parent = left

	local skinId, camoId = ClientData.gunCosmeticsFor(gunId)
	local handle = GunPreview.create(hero, gunId, skinId, camoId, true)
	if handle then
		GunPreview.makeDraggable(handle)
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromOffset(120, 26)
		pill.Position = UDim2.new(0.5, -60, 1, -36)
		pill.BackgroundColor3 = Theme.color.surfaceRaised
		pill.BackgroundTransparency = 0.15
		pill.BorderSizePixel = 0
		pill.Parent = hero
		Components.corner(pill, Theme.radius.pill)
		Components.text(pill, {
			text = "drag to rotate",
			size = Theme.text.caption,
			color = Theme.color.textMuted,
			align = Enum.TextXAlignment.Center,
			area = UDim2.fromScale(1, 1),
		})
	end

	local owned = ClientData.ownsGun(gunId)
	local primary, secondary = ClientData.loadout()
	local equipped = primary == gunId or secondary == gunId

	Components.text(left, {
		text = def.name,
		size = Theme.text.display,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -120, 0, 40),
		position = UDim2.new(0, 0, 1, -142),
	})
	Components.text(left, {
		text = `{def.class} · {def.rarity} · {def.slot}`,
		size = Theme.text.body,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -120, 0, 20),
		position = UDim2.new(0, 0, 1, -102),
	})
	Components.text(left, {
		text = if owned then "Owned" else `{comma(def.price)} 🪙`,
		size = Theme.text.body,
		color = if owned then Theme.color.textMuted else Theme.color.coin,
		align = Enum.TextXAlignment.Right,
		area = UDim2.fromOffset(110, 40),
		position = UDim2.new(1, -110, 1, -142),
	})

	local cta = Components.button(left, {
		area = UDim2.new(0.62, -6, 0, 48),
		position = UDim2.new(0, 0, 1, -56),
		radius = Theme.radius.pill,
		selected = not equipped,
		size = Theme.text.body,
		text = if equipped
			then `✓ Equipped in {if primary == gunId then "Primary" else "Secondary"}`
			elseif owned then `Equip to {def.slot}`
			else `Buy · {comma(def.price)} 🪙`,
	})
	if equipped then
		cta.BackgroundColor3 = Theme.color.surface
		Components.stroke(cta, Theme.color.primary, 3, 0)
	end
	cta.Activated:Connect(function()
		if equipped then
			activeSlot = if primary == gunId then "Primary" else "Secondary"
			showScreen("loadout")
		elseif owned then
			equipSlot(gunId, def.slot)
		else
			request(function()
				return Remotes.func("BuyGun"):InvokeServer(gunId)
			end, `Bought {def.name}`)
		end
	end)

	if not owned then
		local try = Components.button(left, {
			text = "Try it · 60s",
			area = UDim2.new(0.38, -6, 0, 48),
			position = UDim2.new(0.62, 6, 1, -56),
			radius = Theme.radius.pill,
			size = Theme.text.body,
		})
		Components.stroke(try, Theme.color.primary, 2, 0.2)
		try.Activated:Connect(function()
			request(function()
				return Remotes.func("TryGun"):InvokeServer(gunId)
			end, `Trying {def.name} for 60s — lobby only`)
		end)
	end

	buildStatColumn(stats, gunId, Theme.text.display)
end

-- ---------------------------------------------------------------------------
-- Shell
-- ---------------------------------------------------------------------------

function showScreen(name: string)
	screenName = name
	for key, page in pages do
		page.Visible = key == name
	end
	for key, button in tabButtons do
		-- The Armory tab stays lit while inspecting a gun.
		local lit = key == name or (key == "armory" and name == "detail")
		button.BackgroundColor3 = if lit then Theme.color.primary else Theme.color.surfaceRaised
		button.TextColor3 = if lit then Theme.color.textOnPrimary else Theme.color.textMuted
	end
	busy = false
	if name == "loadout" then
		refreshLoadout()
	elseif name == "armory" then
		refreshArmory()
	else
		refreshDetail()
	end
end

-- Everything the menu draws. Coins deliberately excluded: they arrive on the
-- same DataChanged event, change constantly, and only the coin pill cares.
function LoadoutController.signature(): string
	local snap = ClientData.snapshot
	local owned = if type(snap) == "table" and type(snap.ownedGuns) == "table"
		then table.concat(snap.ownedGuns :: { string }, ",")
		else ""
	local camos = if type(snap) == "table" and type(snap.ownedCamos) == "table"
		then table.concat(snap.ownedCamos :: { string }, ",")
		else ""
	local skins = if type(snap) == "table" and type(snap.ownedGunSkins) == "table"
		then table.concat(snap.ownedGunSkins :: { string }, ",")
		else ""
	local primary, secondary = ClientData.loadout()
	local focus = if screenName == "detail" then detailId else (if activeSlot == "Primary" then primary else secondary)
	local skinId: string?, camoId: string? = nil, nil
	if focus then
		skinId, camoId = ClientData.gunCosmeticsFor(focus)
	end
	return table.concat({
		screenName, filter, activeSlot, tostring(picking), tostring(detailId),
		tostring(primary), secondary, tostring(skinId), tostring(camoId),
		owned, skins, camos,
	}, "|")
end

local function refreshCoins()
	local label = coinLabel
	if not label then
		return
	end
	local snap = ClientData.snapshot
	local coins = if type(snap) == "table" and type(snap.coins) == "number" then snap.coins else 0
	label.Text = `🪙 {comma(coins)}`
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
	busy = false
	if open then
		picking = false
		lastSignature = nil
		-- Open on a slot that actually holds a gun. Defaulting to Primary
		-- meant a new player — who owns only the starter pistol — landed on an
		-- empty stat column reading "No gun equipped".
		local primary = select(1, ClientData.loadout())
		activeSlot = if primary then "Primary" else "Secondary"
		refreshCoins()
		showScreen("loadout")
	end
end

function LoadoutController.refresh()
	refreshCoins()
	if screenName == "loadout" then
		refreshLoadout()
	elseif screenName == "armory" then
		refreshArmory()
	else
		refreshDetail()
	end
	lastSignature = LoadoutController.signature()
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "LoadoutUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 8
	screen.Enabled = false
	screen.Parent = playerGui
	gui = screen

	modal = Components.modalBlocker(screen)

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.color.surface
	root.BorderSizePixel = 0
	root.Parent = screen

	-- Top bar
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, TOP_BAR)
	bar.BackgroundColor3 = Theme.color.surfaceRaised
	bar.BorderSizePixel = 0
	bar.Parent = root

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.Position = UDim2.new(0, 0, 1, -2)
	divider.BackgroundColor3 = Theme.color.primarySoft
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.Parent = bar

	Components.text(bar, {
		text = "Pink Panic",
		size = Theme.text.heading,
		color = Theme.color.primaryDeep,
		area = UDim2.fromOffset(140, TOP_BAR),
		position = UDim2.fromOffset(Theme.space.lg, 0),
	})

	local tabs = { { key = "loadout", label = "Loadout" }, { key = "armory", label = "Armory" } }
	for index, tab in tabs do
		local button = Components.button(bar, {
			text = tab.label,
			area = UDim2.fromOffset(118, 36),
			position = UDim2.fromOffset(170 + (index - 1) * 128, 14),
			radius = Theme.radius.pill,
			size = Theme.text.body,
		})
		Components.stroke(button, Theme.color.primarySoft, 2, 0.45)
		tabButtons[tab.key] = button
		button.Activated:Connect(function()
			showScreen(tab.key)
		end)
	end

	messageLabel = Components.text(bar, {
		size = Theme.text.label,
		color = Theme.color.danger,
		align = Enum.TextXAlignment.Center,
		area = UDim2.new(1, -900, 0, TOP_BAR),
		position = UDim2.fromOffset(440, 0),
	})

	local coinPill = Instance.new("Frame")
	coinPill.Size = UDim2.fromOffset(120, 36)
	coinPill.Position = UDim2.new(1, -186, 0, 14)
	coinPill.BackgroundColor3 = Theme.color.surface
	coinPill.BorderSizePixel = 0
	coinPill.Parent = bar
	Components.corner(coinPill, Theme.radius.pill)
	Components.stroke(coinPill, Theme.color.coin, 2, 0.25)
	coinLabel = Components.text(coinPill, {
		text = "🪙 0",
		size = Theme.text.body,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromScale(1, 1),
	})

	local close = Components.button(bar, {
		text = "✕",
		area = UDim2.fromOffset(38, 38),
		position = UDim2.new(1, -52, 0, 13),
		radius = Theme.radius.pill,
		size = Theme.text.heading,
	})
	close.Activated:Connect(function()
		LoadoutController.setOpen(false)
	end)

	local function page(name: string): Frame
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 1, -TOP_BAR)
		frame.Position = UDim2.fromOffset(0, TOP_BAR)
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Parent = root
		pages[name] = frame
		return frame
	end

	-- Loadout: three columns
	local loadout = page("loadout")
	local pad, gap = Theme.space.lg, Theme.space.lg

	local col1 = Instance.new("Frame")
	col1.Size = UDim2.new(0.30, -gap, 1, -pad * 2)
	col1.Position = UDim2.fromOffset(pad, pad)
	col1.BackgroundColor3 = Theme.color.surfaceRaised
	col1.BorderSizePixel = 0
	col1.Parent = loadout
	Components.corner(col1, Theme.radius.panel)
	Components.stroke(col1, Theme.color.primarySoft, 2, 0.45)
	Components.text(col1, {
		text = "Your character",
		size = Theme.text.heading,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -pad * 2, 0, 24),
		position = UDim2.fromOffset(pad, pad),
	})
	local charHolder = Instance.new("Frame")
	charHolder.Size = UDim2.new(1, -pad * 2 - 106, 1, -pad * 2 - 34)
	charHolder.Position = UDim2.fromOffset(pad, pad + 34)
	charHolder.BackgroundTransparency = 1
	charHolder.Parent = col1
	charWell = charHolder

	-- Reserved space for a future outfit system. Deliberately inert — no
	-- controls, because no outfit system exists yet.
	Components.text(col1, {
		text = "Room reserved for outfit slots",
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.fromOffset(96, 28),
		position = UDim2.new(1, -pad - 96, 0, pad + 34),
	})
	for slotIndex = 1, 4 do
		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.new(0, 96, 0.2, -8)
		ghost.Position = UDim2.new(1, -pad - 96, 0, pad + 66 + (slotIndex - 1) * 78)
		ghost.BackgroundTransparency = 1
		ghost.Parent = col1
		Components.corner(ghost, 12)
		Components.stroke(ghost, Theme.color.textMuted, 2, 0.6)
	end

	local col2 = Instance.new("Frame")
	col2.Size = UDim2.new(0.26, -gap, 1, -pad * 2)
	col2.Position = UDim2.new(0.30, 0, 0, pad)
	col2.BackgroundColor3 = Theme.color.surfaceRaised
	col2.BorderSizePixel = 0
	col2.Parent = loadout
	Components.corner(col2, Theme.radius.panel)
	Components.stroke(col2, Theme.color.primarySoft, 2, 0.45)
	Components.text(col2, {
		text = "Weapons",
		size = Theme.text.heading,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -pad * 2, 0, 24),
		position = UDim2.fromOffset(pad, pad),
	})
	local weapons = Instance.new("Frame")
	weapons.Size = UDim2.new(1, -pad * 2, 1, -pad * 2 - 34)
	weapons.Position = UDim2.fromOffset(pad, pad + 34)
	weapons.BackgroundTransparency = 1
	weapons.Parent = col2
	weaponsBody = weapons

	local col3, statScroll = scrollPanel(
		loadout,
		UDim2.new(0.44, -pad - gap, 1, -pad * 2),
		UDim2.new(0.56, gap, 0, pad)
	)
	loadoutTitle = Components.text(col3, {
		size = Theme.text.title,
		color = Theme.color.primaryDeep,
		area = UDim2.new(1, -pad * 2, 0, 30),
		position = UDim2.fromOffset(pad, pad - 6),
	})
	loadoutSub = Components.text(col3, {
		size = Theme.text.label,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -pad * 2, 0, 16),
		position = UDim2.fromOffset(pad, pad + 24),
	})
	statScroll.Size = UDim2.new(1, -pad * 2, 1, -pad * 2 - 46)
	statScroll.Position = UDim2.fromOffset(pad, pad + 46)
	loadoutStats = statScroll

	-- Armory
	local armory = page("armory")
	local chipRow = Components.scroller(armory, true)
	chipRow.Size = UDim2.new(1, -pad * 2, 0, 34)
	chipRow.Position = UDim2.fromOffset(pad, pad)
	chipRow.ScrollBarThickness = 4
	Components.listLayout(chipRow, Enum.FillDirection.Horizontal, Theme.space.sm)
	filterRow = chipRow

	armoryCount = Components.text(armory, {
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -pad * 2, 0, 16),
		position = UDim2.fromOffset(pad, pad + 38),
	})

	local grid = Components.scroller(armory)
	grid.Size = UDim2.new(1, -pad * 2, 1, -pad * 2 - 60)
	grid.Position = UDim2.fromOffset(pad, pad + 60)
	Components.gridLayout(grid, CARD, Theme.space.sm)
	armoryGrid = grid

	-- Detail
	local detail = page("detail")
	local leftPanel = Instance.new("Frame")
	leftPanel.Size = UDim2.new(0.5, -pad - gap / 2, 1, -pad * 2)
	leftPanel.Position = UDim2.fromOffset(pad, pad)
	leftPanel.BackgroundColor3 = Theme.color.surfaceRaised
	leftPanel.BorderSizePixel = 0
	leftPanel.Parent = detail
	Components.corner(leftPanel, Theme.radius.panel)
	Components.stroke(leftPanel, Theme.color.primarySoft, 2, 0.45)
	local leftBody = Instance.new("Frame")
	leftBody.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	leftBody.Position = UDim2.fromOffset(pad, pad)
	leftBody.BackgroundTransparency = 1
	leftBody.Parent = leftPanel
	detailLeft = leftBody

	local rightPanel, rightScroll = scrollPanel(
		detail,
		UDim2.new(0.5, -pad - gap / 2, 1, -pad * 2),
		UDim2.new(0.5, gap / 2, 0, pad)
	)
	Components.text(rightPanel, {
		text = "Stats",
		size = Theme.text.heading,
		color = Theme.color.primaryDeep,
		area = UDim2.fromOffset(80, 24),
		position = UDim2.fromOffset(pad, pad - 4),
	})
	Components.text(rightPanel, {
		text = "bars compare within class · numbers are the real values",
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -pad * 2 - 80, 0, 24),
		position = UDim2.fromOffset(pad + 80, pad - 2),
	})
	rightScroll.Size = UDim2.new(1, -pad * 2, 1, -pad * 2 - 30)
	rightScroll.Position = UDim2.fromOffset(pad, pad + 30)
	detailStats = rightScroll
end

function LoadoutController.init()
	buildGui()

	ClientData.changed:Connect(function()
		local screen = gui
		if not screen or not screen.Enabled then
			return
		end
		-- Coins move constantly and only the pill cares; everything else waits
		-- for a signature change, because a rebuild here re-clones dozens of
		-- gun models into ViewportFrames.
		refreshCoins()
		local signature = LoadoutController.signature()
		if signature ~= lastSignature then
			LoadoutController.refresh()
		end
	end)

	ClientData.roundStateChanged:Connect(function(state)
		if state == "Active" then
			LoadoutController.setOpen(false)
		end
	end)
end

return LoadoutController
