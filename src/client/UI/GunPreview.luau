--!strict
-- GunPreview — a live 3D gun render for a ViewportFrame.
--
-- Every gun image in the game is one of these. There are no thumbnails to
-- upload: this clones the real mesh from ReplicatedStorage.GunModels and
-- applies the player's equipped skin/camo, so a preview always shows exactly
-- what you'd carry.
--
-- Previews are pooled through a single RenderStepped loop rather than one
-- connection each — the Armory grid alone can hold 32 of them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GunModelLoader = require(ReplicatedStorage.Shared.Loaders.GunModelLoader)
local Theme = require(script.Parent.Theme)

local GunPreview = {}

export type Handle = {
	viewport: ViewportFrame,
	model: Model,
	centre: Vector3,
	basePivot: CFrame,
	yaw: number,
	dragging: boolean,
	spin: boolean,
}

local live: { Handle } = {}
local started = false

-- One loop for every preview on screen.
local function start()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(function(dt)
		for index = #live, 1, -1 do
			local handle = live[index]
			if not handle.model.Parent or not handle.viewport.Parent then
				table.remove(live, index)
				continue
			end
			-- Skip work for previews that aren't actually visible.
			if not handle.viewport.Visible then
				continue
			end
			if handle.spin and not handle.dragging then
				handle.yaw += dt * 0.6
			end
			-- Rotate about the BOUNDING-BOX centre, preserving the model's own
			-- pivot. PivotTo positions the PrimaryPart (GunModelLoader picks
			-- the part named "Body"), a different point from the bbox centre —
			-- feeding it the bbox CFrame shifts the gun off-centre, often clean
			-- out of a short viewport.
			local spin = CFrame.new(handle.centre)
				* CFrame.Angles(0, handle.yaw, 0)
				* CFrame.new(-handle.centre)
			handle.model:PivotTo(spin * handle.basePivot)
		end
	end)
end

-- Builds a preview into `parent`. `rarity` tints the backdrop glow.
function GunPreview.create(
	parent: GuiObject,
	gunId: string,
	skinId: string?,
	camoId: string?,
	spin: boolean
): Handle?
	start()

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Theme.color.surfaceSunken
	viewport.BackgroundTransparency = 0.25
	viewport.Ambient = Theme.color.viewportAmbient
	viewport.LightColor = Theme.color.surfaceRaised
	viewport.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.radius.card)
	corner.Parent = viewport

	local ok, model = pcall(function()
		return GunModelLoader.build(gunId, { skinId = skinId, camoId = camoId })
	end)
	if not ok or typeof(model) ~= "Instance" then
		return nil
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

	local handle: Handle = {
		viewport = viewport,
		model = model,
		centre = centre,
		basePivot = model:GetPivot(),
		yaw = 0,
		dragging = false,
		spin = spin,
	}
	table.insert(live, handle)
	return handle
end

-- Drag-to-orbit for the Detail hero. Idle spin resumes on release.
function GunPreview.makeDraggable(handle: Handle)
	local UserInputService = game:GetService("UserInputService")
	local lastX: number? = nil

	handle.viewport.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handle.dragging = true
			lastX = input.Position.X
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not handle.dragging or lastX == nil then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handle.yaw -= (input.Position.X - lastX) * 0.012
			lastX = input.Position.X
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handle.dragging = false
			lastX = nil
		end
	end)
end

-- The player's own avatar, for the Loadout character column.
--
-- This is an avatar THUMBNAIL, not a ViewportFrame clone, and that is
-- deliberate: a ViewportFrame does not composite Shirt/Pants onto R15 body
-- parts, so a cloned character renders naked with only its accessories
-- (hair, wings) showing — they're separate meshes. The thumbnail is the
-- avatar as Roblox actually draws it, clothes included.
--
-- There is no in-game outfit system yet; this shows the player's real
-- Roblox avatar.
-- The character you actually play, rendered live.
--
-- This used to be GetUserThumbnailAsync — the player's own Roblox avatar. That
-- was correct right up until NOD-167 made everyone a standard R15 rig with
-- LoadCharacterAppearance off: the loadout was then showing you a character
-- you can never be, complete with whatever hair and shirt you happen to own,
-- while the one in the lobby behind the panel looked like everyone else's.
--
-- Cloning the live character is also the surface the character creator
-- (NOD-168) writes to, so this column starts telling the truth for free the
-- moment outfits exist.
function GunPreview.createCharacter(parent: GuiObject): GuiObject?
	local player = Players.LocalPlayer

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Theme.color.surfaceSunken
	viewport.BackgroundTransparency = 0.25
	viewport.Ambient = Theme.color.viewportAmbient
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.radius.card)
	corner.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local function mount(character: Model)
		if not viewport.Parent then
			return
		end
		for _, child in viewport:GetChildren() do
			if child:IsA("Model") then
				child:Destroy()
			end
		end

		-- Roblox ships player characters with Archivable = false, so Clone()
		-- returns nil rather than erroring — the preview came up as an empty
		-- well with no message anywhere. Flipped for the one call and put back.
		local archivable = character.Archivable
		character.Archivable = true
		local ok, clone = pcall(function()
			return character:Clone()
		end)
		character.Archivable = archivable
		if not ok or not clone then
			return
		end

		-- Nothing in a preview should run. Anchoring every part is what makes
		-- the pose deterministic: a ViewportFrame has no physics, so unanchored
		-- limbs simply keep the world CFrames they were cloned with, and the
		-- Humanoid's state machine would spend frames deciding it is falling.
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.EvaluateStateMachine = false
		end
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				-- First person sets this to 1 on every part of your own body.
				-- It survives the clone, so without this the preview is an
				-- empty well any time the panel is opened from in-round.
				descendant.LocalTransparencyModifier = 0
			elseif descendant:IsA("BaseScript") or descendant:IsA("Animator") then
				descendant:Destroy()
			end
		end

		clone.Parent = viewport
		clone:PivotTo(CFrame.new())

		local bounds, size = clone:GetBoundingBox()
		local centre = bounds.Position
		local extent = math.max(size.Y, size.X * 1.4)
		local distance = (extent / 2) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.25

		-- A character pivoted to the identity CFrame looks down -Z, so the
		-- camera has to stand on that side to see its face rather than its back.
		camera.CFrame = CFrame.lookAt(centre + Vector3.new(0, size.Y * 0.04, -distance), centre)
	end

	local character = player.Character
	if character then
		mount(character)
	else
		task.spawn(function()
			mount(player.CharacterAdded:Wait())
		end)
	end

	return viewport
end

return GunPreview
