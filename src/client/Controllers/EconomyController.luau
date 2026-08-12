--!strict
-- EconomyController — coins and level/XP, top-left, driven entirely by server
-- DataChanged snapshots.
--
-- This used to be one 210x74 blush slab with four things stacked inside it,
-- and it sat on the lobby like a sticker. It is now two pills on the same row:
-- a level badge with its XP bar, and the coin count. Same information, but it
-- reads as HUD instead of as a window, and the coin pill grows with the number
-- rather than clipping at seven figures.
--
-- Nothing here calls Color3.fromRGB — every value comes from Theme.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientData = require(script.Parent.Parent.ClientData)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local PILL_HEIGHT = 38
local BADGE = 28
local LEVEL_PILL_WIDTH = 178

local EconomyController = {}

local coins = 0
local level = 1
-- Whether a snapshot has landed yet. Without this the first one — which is
-- everything the player already owns — reads as a gain and pops "+1240" in
-- their face the moment they join.
local seeded = false

local hud: ScreenGui
local hudRow: Frame
local coinPill: Frame
local coinsLabel: TextLabel
local levelBadge: Frame
local levelLabel: TextLabel
local xpFill: Frame
local xpText: TextLabel

-- 1240 -> "1,240". Coins run to six figures by mid-game and an unbroken run of
-- digits is unreadable at a glance, which is the only way a HUD is ever read.
local function comma(value: number): string
	local text = tostring(math.floor(value))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function pill(parent: Instance, accent: Color3): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.color.surfaceRaised
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Components.corner(frame, Theme.radius.pill)
	Components.stroke(frame, accent, 2, 0.4)
	return frame
end

local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "EconomyHUD"
	screen.ResetOnSpawn = false
	hud = screen

	-- Left at the default inset so the pills tuck under Roblox's own topbar
	-- instead of fighting the chat and menu buttons for the same corner.
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(Theme.space.md, Theme.space.md)
	row.Size = UDim2.fromOffset(0, PILL_HEIGHT)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = screen
	hudRow = row
	Components.listLayout(row, Enum.FillDirection.Horizontal, Theme.space.sm)

	-- Level + XP.
	local levelPill = pill(row, Theme.color.primary)
	levelPill.Size = UDim2.fromOffset(LEVEL_PILL_WIDTH, PILL_HEIGHT)
	levelPill.LayoutOrder = 1

	levelBadge = Instance.new("Frame")
	levelBadge.Size = UDim2.fromOffset(BADGE, BADGE)
	levelBadge.Position = UDim2.fromOffset((PILL_HEIGHT - BADGE) / 2, (PILL_HEIGHT - BADGE) / 2)
	levelBadge.BackgroundColor3 = Theme.color.primary
	levelBadge.BorderSizePixel = 0
	levelBadge.Parent = levelPill
	Components.corner(levelBadge, Theme.radius.pill)

	levelLabel = Components.text(levelBadge, {
		text = "1",
		size = Theme.text.body,
		color = Theme.color.textOnPrimary,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromScale(1, 1),
	})

	local trackLeft = PILL_HEIGHT + Theme.space.xs
	local trackRight = Theme.space.md

	xpText = Components.text(levelPill, {
		size = Theme.text.caption,
		color = Theme.color.textMuted,
		area = UDim2.new(1, -trackLeft - trackRight, 0, 14),
		position = UDim2.fromOffset(trackLeft, 5),
	})

	local xpBar = Instance.new("Frame")
	xpBar.Size = UDim2.new(1, -trackLeft - trackRight, 0, 7)
	xpBar.Position = UDim2.fromOffset(trackLeft, 21)
	xpBar.BackgroundColor3 = Theme.color.surfaceSunken
	xpBar.BorderSizePixel = 0
	xpBar.Parent = levelPill
	Components.corner(xpBar, Theme.radius.pill)

	xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Theme.color.primary
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBar
	Components.corner(xpFill, Theme.radius.pill)

	-- Coins. Auto-sized on X so the pill grows with the number instead of
	-- truncating it — the one thing a currency readout must never do.
	coinPill = pill(row, Theme.color.coin)
	coinPill.Size = UDim2.fromOffset(0, PILL_HEIGHT)
	coinPill.AutomaticSize = Enum.AutomaticSize.X
	coinPill.LayoutOrder = 2

	local coinPadding = Instance.new("UIPadding")
	coinPadding.PaddingLeft = UDim.new(0, Theme.space.md)
	coinPadding.PaddingRight = UDim.new(0, Theme.space.md)
	coinPadding.Parent = coinPill

	coinsLabel = Components.text(coinPill, {
		text = `{Theme.glyph.coin} 0`,
		size = Theme.text.heading,
		color = Theme.color.text,
		align = Enum.TextXAlignment.Center,
		area = UDim2.fromOffset(0, PILL_HEIGHT),
	})
	coinsLabel.AutomaticSize = Enum.AutomaticSize.X

	screen.Parent = playerGui
end

-- Parented to the ScreenGui, NOT to the coin pill.
--
-- The pill is AutomaticSize.X, and a child sitting past its right edge counts
-- toward that measurement — so putting the "+n" inside it would make the pill
-- lurch 90px wider for the second the pop is alive, every single kill.
local function popCoinGain(amount: number)
	local x = Theme.space.md + hudRow.AbsoluteSize.X + Theme.space.sm
	local y = Theme.space.md + 8

	local pop = Components.text(hud, {
		text = `+{comma(amount)}`,
		size = Theme.text.body,
		color = Theme.color.coin,
		align = Enum.TextXAlignment.Left,
		area = UDim2.fromOffset(90, 22),
		position = UDim2.fromOffset(x, y),
	})
	pop.Text = `+{comma(amount)} {Theme.glyph.coin}`
	pop.TextStrokeColor3 = Theme.color.text
	pop.TextStrokeTransparency = 0.6
	TweenService:Create(pop, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(x, y - 28),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function()
		pop:Destroy()
	end)
end

-- The badge swells and settles. Levelling is the one moment in the economy
-- that deserves to be felt, and it costs one tween.
local function popLevelUp()
	levelBadge.Size = UDim2.fromOffset(BADGE + 10, BADGE + 10)
	levelBadge.Position = UDim2.fromOffset((PILL_HEIGHT - BADGE - 10) / 2, (PILL_HEIGHT - BADGE - 10) / 2)
	TweenService:Create(levelBadge, Theme.easing.enter, {
		Size = UDim2.fromOffset(BADGE, BADGE),
		Position = UDim2.fromOffset((PILL_HEIGHT - BADGE) / 2, (PILL_HEIGHT - BADGE) / 2),
	}):Play()
end

local function applySnapshot(data: any)
	if type(data) ~= "table" then
		return
	end

	local newCoins = if type(data.coins) == "number" then data.coins else coins
	if seeded and newCoins > coins then
		popCoinGain(newCoins - coins)
	end
	coins = newCoins
	coinsLabel.Text = `{Theme.glyph.coin} {comma(coins)}`

	if type(data.level) == "number" then
		if seeded and data.level > level then
			popLevelUp()
		end
		level = data.level
		levelLabel.Text = tostring(level)
	end

	if type(data.xp) == "number" and type(data.xpToNext) == "number" and data.xpToNext > 0 then
		local alpha = math.clamp(data.xp / data.xpToNext, 0, 1)
		TweenService:Create(xpFill, Theme.easing.value, { Size = UDim2.fromScale(alpha, 1) }):Play()
		xpText.Text = `{comma(data.xp)} / {comma(data.xpToNext)} XP`
	end

	seeded = true
end

function EconomyController.init()
	buildGui()
	ClientData.changed:Connect(applySnapshot)
	if ClientData.snapshot then
		applySnapshot(ClientData.snapshot)
	end
end

return EconomyController
