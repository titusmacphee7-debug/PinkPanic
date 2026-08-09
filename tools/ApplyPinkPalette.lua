-- ApplyPinkPalette — Studio command-bar utility for Pink Panic mesh imports.
-- Roblox's 3D Importer ignores .mtl flat colors, so imported OBJs arrive
-- white. Part NAMES survive, so this walks whatever is selected in the
-- Explorer and colors parts by name (plus per-façade overrides by model
-- name). Select imported models, then run this file's contents in the
-- command bar. Safe to run repeatedly.
--
-- Guns/pistol use the generic table. Façades use per-model overrides.
-- Buildings (assets/meshes/buildings) need NO coloring — they carry a real
-- texture (colormap_pink.png) which the importer applies automatically.

local WHITE = Color3.fromRGB(255, 245, 250)
local BLUSH = Color3.fromRGB(255, 227, 240)
local PINK = Color3.fromRGB(255, 130, 190)
local HOT = Color3.fromRGB(255, 92, 168)
local DEEP = Color3.fromRGB(214, 66, 143)
local PLUM = Color3.fromRGB(92, 72, 88)
local GOLD = Color3.fromRGB(255, 196, 88)
local MINT = Color3.fromRGB(152, 216, 184)

local GENERIC = {
	-- 32-gun roster parts
	Body = WHITE, Panel = BLUSH, Grip = PINK, Hardware = PLUM, Accent = HOT, Mag = PINK,
	Curb = WHITE, Grass = MINT,
	-- marshmallow pistol parts
	Slide = WHITE, Frame = BLUSH, Guard = PLUM, Barrel = PLUM, Tip = HOT, Charm = HOT,
	-- façade defaults (overridden per model below)
	Wall = BLUSH, Trim = WHITE, Door = PLUM, Frames = WHITE, Windows = BLUSH,
	AwningA = HOT, AwningB = WHITE, Sign = DEEP, Roof = HOT, Topper = HOT, TopperB = GOLD,
	-- portal
	Pillars = WHITE, Bases = PINK, Lintel = HOT, Heart = HOT,
}

local FACADES: { [string]: { [string]: Color3 } } = {
	facade_bowtique = { Wall = BLUSH, Roof = HOT, AwningA = HOT, AwningB = WHITE, Trim = WHITE, Frames = WHITE, Windows = WHITE, Topper = HOT },
	facade_candyarmory = { Wall = WHITE, Roof = PINK, AwningA = PINK, AwningB = WHITE, Trim = BLUSH, Frames = PINK, Windows = BLUSH, Topper = HOT, TopperB = GOLD },
	facade_cutiecloset = { Wall = PINK, Roof = WHITE, AwningA = WHITE, AwningB = HOT, Trim = WHITE, Frames = WHITE, Windows = BLUSH, Topper = GOLD },
	facade_cafe = { Wall = WHITE, Roof = BLUSH, AwningA = DEEP, AwningB = WHITE, Trim = BLUSH, Frames = PINK, Windows = BLUSH, Sign = PLUM, Topper = WHITE, TopperB = PLUM },
	facade_heartbreakerrange = { Wall = PINK, Roof = WHITE, AwningA = HOT, AwningB = WHITE, Trim = WHITE, Frames = WHITE, Windows = BLUSH, Topper = HOT, TopperB = GOLD },
	facade_flowers = { Wall = WHITE, Roof = PINK, AwningA = PINK, AwningB = WHITE, Trim = BLUSH, Frames = PINK, Windows = BLUSH, Topper = PLUM, TopperB = HOT },
	facade_sweets = { Wall = BLUSH, Roof = WHITE, AwningA = WHITE, AwningB = HOT, Trim = WHITE, Frames = WHITE, Windows = WHITE, Topper = HOT, TopperB = GOLD },
}

local function colorPart(part: BasePart, model: Instance?)
	local override = model and FACADES[model.Name]
	local color = (override and override[part.Name]) or GENERIC[part.Name]
	if color then
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		return 1
	end
	return 0
end

local count = 0
for _, sel in game:GetService("Selection"):Get() do
	if sel:IsA("BasePart") then
		count += colorPart(sel, sel.Parent)
	end
	for _, inst in sel:GetDescendants() do
		if inst:IsA("BasePart") then
			local model = inst:FindFirstAncestorOfClass("Model")
			count += colorPart(inst, model)
		end
	end
end
print("Pink Panic: colored " .. count .. " parts 🎀")
