-- Pink Panic — colour imported weapons by part name.
-- Studio's 3D Importer ignores the flat colours in the .mtl, so models arrive
-- white. Select the imported model(s) in Explorer, open the Command Bar
-- (View -> Command Bar, or Ctrl+9), paste this in and press Enter.

local PALETTE = {
	Body      = Color3.fromRGB(238, 146, 186), -- warm mid-pink
	Panel     = Color3.fromRGB(255, 240, 231), -- cream
	Grip      = Color3.fromRGB(176,  82, 120), -- deeper rose
	Hardware  = Color3.fromRGB(226, 190, 130), -- soft gold
	Accent    = Color3.fromRGB(255,  79, 163), -- the one saturated accent
	Slide     = Color3.fromRGB(232, 205, 214), -- pearl
	Bolt      = Color3.fromRGB(226, 190, 130),
	Pump      = Color3.fromRGB(176,  82, 120),
	Cylinder  = Color3.fromRGB(226, 190, 130),
	Mag       = Color3.fromRGB(176,  82, 120),
	Lens      = Color3.fromRGB(255,  79, 163), -- optics only
}

-- Attachments are named <Name>_Body / <Name>_Detail, so fall back on the suffix.
local function colourFor(name)
	if PALETTE[name] then return PALETTE[name] end
	if name:match("_Detail$") then return PALETTE.Hardware end
	if name:match("_Body$")   then return PALETTE.Body end
	return nil
end

local n, missed = 0, {}
for _, root in ipairs(game.Selection:Get()) do
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") then
			local c = colourFor(d.Name)
			if c then
				d.Color = c
				d.Material = Enum.Material.SmoothPlastic
				if d.Name == "Lens" then
					d.Material = Enum.Material.Neon
				end
				n = n + 1
			else
				missed[d.Name] = true
			end
		end
	end
end

local unknown = {}
for k in pairs(missed) do table.insert(unknown, k) end
print(("Pink Panic: coloured %d parts"):format(n))
if #unknown > 0 then
	warn("Unrecognised part names (left as-is): " .. table.concat(unknown, ", "))
	warn("If you see 'default' or a single mesh here, re-import with Merge Meshes OFF.")
end
