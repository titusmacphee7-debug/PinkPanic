--!strict
-- PistolModel — the pistol built from parts, shared by the first-person
-- viewmodel and the third-person gun welded to characters. Real meshes and
-- the skin system arrive in M5 (NOD-38); until then this is the on-theme
-- placeholder. Convention: the gun faces -Z (Roblox look direction), and the
-- Slide is the PrimaryPart with a "Muzzle" attachment at the barrel tip.

local WHITE = Color3.fromRGB(250, 244, 249)
local PINK = Color3.fromRGB(255, 130, 190)
local DARK = Color3.fromRGB(92, 72, 88)

local PistolModel = {}

local function mkPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false -- gunfire raycasts pass through guns, never eat shots
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	return part
end

function PistolModel.build(): Model
	local model = Instance.new("Model")
	model.Name = "Pistol"

	local slide = mkPart("Slide", Vector3.new(0.42, 0.48, 1.7), CFrame.new(0, 0, 0), WHITE)
	local grip = mkPart(
		"Grip",
		Vector3.new(0.36, 1.05, 0.55),
		CFrame.new(0, -0.66, 0.45) * CFrame.Angles(math.rad(-14), 0, 0),
		PINK
	)
	local guard = mkPart("Guard", Vector3.new(0.3, 0.12, 0.62), CFrame.new(0, -0.42, -0.1), DARK)
	local barrel = mkPart("Barrel", Vector3.new(0.2, 0.2, 0.4), CFrame.new(0, 0.06, -1.0), DARK)
	local charm = mkPart("Charm", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0.32, 0.55), PINK)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.06, -1.25)
	muzzle.Parent = slide

	model.PrimaryPart = slide
	for _, part in { grip, guard, barrel, charm } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = slide
		weld.Part1 = part
		weld.Parent = part
	end
	for _, part in { slide, grip, guard, barrel, charm } do
		part.Parent = model
	end

	return model
end

return PistolModel
