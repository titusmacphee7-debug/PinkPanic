--!strict
-- Components — the shared UI builders every controller uses.
--
-- mkText was copy-pasted into seven controllers and round() into four, each
-- with slightly different defaults, which is why panels never quite matched.
-- These are the one implementation. All colour/size defaults come from Theme,
-- so a palette change lands everywhere at once.
--
-- Every builder takes an options table and returns the real Instance, so
-- callers can still set anything the options don't cover.

local Theme = require(script.Parent.Theme)

local Components = {}

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

function Components.corner(instance: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.radius.card)
	corner.Parent = instance
	return corner
end

-- Round only the TOP two corners, or only the BOTTOM two.
--
-- Roblox gives you neither for free. UICorner always rounds all four, and
-- ClipsDescendants clips to the parent's RECTANGLE, not to its rounded shape —
-- verified in Studio, because assuming otherwise is what made every gun card
-- in the armory a rounded picture sitting on two square blocks. A child that
-- touches a rounded parent's edge punches its square corners straight back out
-- through the radius.
--
-- So: round all four, then square off the two that should stay flat with a
-- patch of the frame's own colour.
--
-- Two rules for callers:
--   · Set BackgroundColor3 and BackgroundTransparency BEFORE calling. The
--     patch copies them.
--   · The frame must be OPAQUE. The patch overlaps the rounded frame's own
--     background, and two semi-transparent layers composite darker than one —
--     which shows up as a bar that is subtly darker at one end.
local function halfRound(frame: GuiObject, radius: number?, top: boolean): Frame
	local r = radius or Theme.radius.card
	Components.corner(frame, r)

	local patch = Instance.new("Frame")
	patch.Name = if top then "SquareBottom" else "SquareTop"
	patch.Size = UDim2.new(1, 0, 0, r)
	patch.Position = if top then UDim2.new(0, 0, 1, -r) else UDim2.fromOffset(0, 0)
	patch.BackgroundColor3 = frame.BackgroundColor3
	patch.BackgroundTransparency = frame.BackgroundTransparency
	patch.BorderSizePixel = 0
	-- Same ZIndex as the frame, so real content (which sits higher) still draws
	-- over it and only the empty corner region is filled.
	patch.ZIndex = frame.ZIndex
	patch.Parent = frame
	return patch
end

function Components.roundTop(frame: GuiObject, radius: number?): Frame
	return halfRound(frame, radius, true)
end

function Components.roundBottom(frame: GuiObject, radius: number?): Frame
	return halfRound(frame, radius, false)
end

function Components.stroke(
	instance: GuiObject,
	color: Color3?,
	thickness: number?,
	transparency: number?
): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.color.primaryDeep
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = instance
	return stroke
end

function Components.padding(instance: GuiObject, all: number?): UIPadding
	local value = UDim.new(0, all or Theme.space.md)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = value
	padding.PaddingBottom = value
	padding.PaddingLeft = value
	padding.PaddingRight = value
	padding.Parent = instance
	return padding
end

export type TextOptions = {
	text: string?,
	size: number?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	position: UDim2?,
	area: UDim2?,
	truncate: boolean?,
	zIndex: number?,
}

function Components.text(parent: Instance, options: TextOptions?): TextLabel
	local opts = options or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.font
	label.TextSize = opts.size or Theme.text.body
	label.TextColor3 = opts.color or Theme.color.text
	label.TextXAlignment = opts.align or Enum.TextXAlignment.Left
	label.Text = opts.text or ""
	if opts.area then
		label.Size = opts.area
	end
	if opts.position then
		label.Position = opts.position
	end
	if opts.truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if opts.zIndex then
		label.ZIndex = opts.zIndex
	end
	label.Parent = parent
	return label
end

-- ---------------------------------------------------------------------------
-- Containers
-- ---------------------------------------------------------------------------

export type PanelOptions = {
	area: UDim2?,
	position: UDim2?,
	color: Color3?,
	radius: number?,
	centered: boolean?,
}

-- The standard floating panel: blush surface, rounded, soft pink border.
function Components.panel(parent: Instance, options: PanelOptions?): Frame
	local opts = options or {}
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = opts.color or Theme.color.surface
	if opts.area then
		frame.Size = opts.area
	end
	if opts.centered and opts.area then
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
	elseif opts.position then
		frame.Position = opts.position
	end
	frame.Parent = parent
	Components.corner(frame, opts.radius or Theme.radius.panel)
	Components.stroke(frame, Theme.color.primary, 2, 0.55)
	return frame
end

export type ButtonOptions = {
	text: string?,
	area: UDim2?,
	position: UDim2?,
	color: Color3?,
	textColor: Color3?,
	size: number?,
	radius: number?,
	selected: boolean?,
}

function Components.button(parent: Instance, options: ButtonOptions?): TextButton
	local opts = options or {}
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Font = Theme.font
	button.TextSize = opts.size or Theme.text.label
	button.BackgroundColor3 = opts.color
		or (if opts.selected then Theme.color.primary else Theme.color.surfaceRaised)
	button.TextColor3 = opts.textColor
		or (if opts.selected then Theme.color.textOnPrimary else Theme.color.text)
	button.Text = opts.text or ""
	if opts.area then
		button.Size = opts.area
	end
	if opts.position then
		button.Position = opts.position
	end
	button.Parent = parent
	Components.corner(button, opts.radius or Theme.radius.chip)
	return button
end

-- A card is a button so the whole surface is clickable — used for gun tiles,
-- shop items, and armory rows.
export type CardOptions = {
	area: UDim2?,
	accent: Color3?,
	selected: boolean?,
	order: number?,
}

function Components.card(parent: Instance, options: CardOptions?): TextButton
	local opts = options or {}
	local card = Instance.new("TextButton")
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = Theme.color.surfaceRaised
	if opts.area then
		card.Size = opts.area
	end
	if opts.order then
		card.LayoutOrder = opts.order
	end
	card.Parent = parent
	Components.corner(card, Theme.radius.card)
	Components.stroke(
		card,
		if opts.selected then Theme.color.primary else (opts.accent or Theme.color.primaryDeep),
		if opts.selected then 3 else 1,
		if opts.selected then 0 else 0.6
	)
	return card
end

-- ---------------------------------------------------------------------------
-- Patterns
-- ---------------------------------------------------------------------------

-- The locked overlay: one implementation so an unowned gun, an unowned skin,
-- and an unowned camo all read the same way.
function Components.lockedScrim(card: GuiObject, label: string?): Frame
	local scrim = Instance.new("Frame")
	scrim.Name = "LockedScrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.color.scrim
	scrim.BackgroundTransparency = Theme.locked.scrimTransparency
	scrim.ZIndex = 10
	scrim.Parent = card
	Components.corner(scrim, Theme.radius.card)

	Components.text(scrim, {
		text = Theme.locked.icon,
		size = 30,
		color = Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Center,
		area = UDim2.new(1, 0, 0, 36),
		position = UDim2.new(0, 0, 0.32, 0),
		zIndex = 11,
	})

	if label then
		Components.text(scrim, {
			text = label,
			size = Theme.text.label,
			color = Theme.color.coin,
			align = Enum.TextXAlignment.Center,
			area = UDim2.new(1, 0, 0, 20),
			position = UDim2.new(0, 0, 0.32, 38),
			zIndex = 11,
		})
	end

	return scrim
end

-- An invisible Modal button. While visible, Roblox releases the first-person
-- mouse lock — the sanctioned way to free the cursor for a panel.
function Components.modalBlocker(parent: Instance): TextButton
	local blocker = Instance.new("TextButton")
	blocker.Name = "ModalBlocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.Modal = true
	blocker.Visible = false
	blocker.Parent = parent
	return blocker
end

function Components.gridLayout(parent: Instance, cell: Vector2, gap: number?): UIGridLayout
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(gap or Theme.space.sm, gap or Theme.space.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function Components.listLayout(
	parent: Instance,
	direction: Enum.FillDirection?,
	gap: number?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or Theme.space.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function Components.scroller(parent: Instance, horizontal: boolean?): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Theme.color.primary
	scroller.ScrollingDirection = if horizontal
		then Enum.ScrollingDirection.X
		else Enum.ScrollingDirection.Y
	scroller.Parent = parent
	return scroller
end

return Components
