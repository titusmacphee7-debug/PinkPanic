--!strict
-- WeaponModels — part-built models for every weapon, shared by viewmodel and
-- world guns. Conventions: the weapon faces -Z, PrimaryPart is "Slide" with a
-- "Muzzle" attachment at the tip, and parts named Slide/Grip/Charm are the
-- ones skins recolor (WeaponCosmetics). Real meshes replace these in M5.

local WHITE = Color3.fromRGB(250, 244, 249)
local PINK = Color3.fromRGB(255, 130, 190)
local DARK = Color3.fromRGB(92, 72, 88)

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
}

local WeaponModels = {}

local function assemble(specs: { PartSpec }, muzzleOffset: Vector3): Model
	local model = Instance.new("Model")

	local slide: Part? = nil
	local parts: { Part } = {}
	for _, spec in specs do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.CFrame = spec.cframe
		part.Color = spec.color
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		table.insert(parts, part)
		if spec.name == "Slide" then
			slide = part
		end
	end
	assert(slide, "weapon spec must include a Slide part")

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = muzzleOffset
	muzzle.Parent = slide

	model.PrimaryPart = slide
	for _, part in parts do
		if part ~= slide then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = slide
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end
	return model
end

local builders: { [string]: () -> Model } = {}

builders.Pistol = function()
	return assemble({
		{ name = "Slide", size = Vector3.new(0.42, 0.48, 1.7), cframe = CFrame.new(0, 0, 0), color = WHITE },
		{
			name = "Grip",
			size = Vector3.new(0.36, 1.05, 0.55),
			cframe = CFrame.new(0, -0.66, 0.45) * CFrame.Angles(math.rad(-14), 0, 0),
			color = PINK,
		},
		{ name = "Guard", size = Vector3.new(0.3, 0.12, 0.62), cframe = CFrame.new(0, -0.42, -0.1), color = DARK },
		{ name = "Barrel", size = Vector3.new(0.2, 0.2, 0.4), cframe = CFrame.new(0, 0.06, -1.0), color = DARK },
		{ name = "Charm", size = Vector3.new(0.14, 0.14, 0.14), cframe = CFrame.new(0, 0.32, 0.55), color = PINK },
	}, Vector3.new(0, 0.06, -1.25))
end

builders.Rifle = function()
	return assemble({
		{ name = "Slide", size = Vector3.new(0.42, 0.5, 2.6), cframe = CFrame.new(0, 0, -0.2), color = WHITE },
		{
			name = "Grip",
			size = Vector3.new(0.36, 0.95, 0.5),
			cframe = CFrame.new(0, -0.6, 0.55) * CFrame.Angles(math.rad(-12), 0, 0),
			color = PINK,
		},
		{ name = "Stock", size = Vector3.new(0.34, 0.55, 0.8), cframe = CFrame.new(0, -0.12, 1.45), color = DARK },
		{
			name = "Mag",
			size = Vector3.new(0.3, 0.7, 0.4),
			cframe = CFrame.new(0, -0.55, -0.15) * CFrame.Angles(math.rad(8), 0, 0),
			color = PINK,
		},
		{ name = "Barrel", size = Vector3.new(0.16, 0.16, 0.7), cframe = CFrame.new(0, 0.08, -1.8), color = DARK },
		{ name = "Charm", size = Vector3.new(0.14, 0.14, 0.14), cframe = CFrame.new(0, 0.36, 0.3), color = PINK },
	}, Vector3.new(0, 0.28, -1.95))
end

builders.Shotgun = function()
	return assemble({
		{ name = "Slide", size = Vector3.new(0.5, 0.55, 2.2), cframe = CFrame.new(0, 0, -0.1), color = WHITE },
		{
			name = "Grip",
			size = Vector3.new(0.4, 1.0, 0.6),
			cframe = CFrame.new(0, -0.68, 0.75) * CFrame.Angles(math.rad(-16), 0, 0),
			color = PINK,
		},
		{ name = "Pump", size = Vector3.new(0.44, 0.3, 0.65), cframe = CFrame.new(0, -0.42, -0.75), color = PINK },
		{ name = "Barrel", size = Vector3.new(0.24, 0.24, 0.5), cframe = CFrame.new(0, 0.12, -1.4), color = DARK },
		{ name = "Charm", size = Vector3.new(0.15, 0.15, 0.15), cframe = CFrame.new(0, 0.38, 0.4), color = PINK },
	}, Vector3.new(0, 0.12, -1.7))
end

builders.Knife = function()
	return assemble({
		{ name = "Slide", size = Vector3.new(0.08, 0.42, 1.15), cframe = CFrame.new(0, 0.08, -0.5), color = WHITE },
		{ name = "Grip", size = Vector3.new(0.16, 0.24, 0.55), cframe = CFrame.new(0, 0, 0.4), color = PINK },
		{ name = "Guard", size = Vector3.new(0.32, 0.32, 0.1), cframe = CFrame.new(0, 0.04, 0.08), color = DARK },
		{ name = "Charm", size = Vector3.new(0.12, 0.12, 0.12), cframe = CFrame.new(0, -0.2, 0.65), color = PINK },
	}, Vector3.new(0, 0.1, -1.1))
end

function WeaponModels.build(weaponId: string): Model
	local builder = builders[weaponId] or builders.Pistol
	local model = builder()
	model.Name = weaponId
	return model
end

return WeaponModels
