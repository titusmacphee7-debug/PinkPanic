-- RigGun — turns a freshly imported Pink Panic weapon mesh into a
-- spec-compliant Model (GUN_MODEL_SPEC.md).
--
-- HOW TO USE
--   1. File -> Import 3D, pick assets/meshes/guns/<GunId>.obj.
--      Turn "Merge Meshes" OFF so the named parts survive.
--   2. Rename the imported Model to the GunId if the importer didn't.
--   3. Select that Model in the Explorer.
--   4. Paste this whole script into the Command Bar (Ctrl+9) and press Enter.
--
-- It sets the palette, anchors AND locks every part, sets PrimaryPart to Body,
-- moves the model pivot to the grip, and creates all six sockets plus the
-- Mount_* points at the authored offsets. Safe to re-run.

local Selection = game:GetService("Selection")
local DATA_PATH = game.ReplicatedStorage:FindFirstChild("Shared")
	and game.ReplicatedStorage.Shared:FindFirstChild("Config")
	and game.ReplicatedStorage.Shared.Config:FindFirstChild("GunSocketData")

local DATA = DATA_PATH and require(DATA_PATH) or nil
if not DATA then
	warn("[RigGun] GunSocketData not found. Put GunSocketData.luau in "
		.. "ReplicatedStorage/Shared/Config first.")
	return
end

local SOCKETS = {
	"Muzzle", "Grip", "EjectPort", "LeftGrip", "Sight", "MagWell",
	"Mount_Optic", "Mount_Barrel", "Mount_Under", "Mount_Laser",
	"Mount_Stock", "Mount_Charm",
}

local function rig(model: Model)
	local data = DATA[model.Name]
	if not data then
		warn(("[RigGun] no socket data for '%s' — rename the model to its GunId")
			:format(model.Name))
		return false
	end

	-- every part anchored AND locked; locked alone explodes on Play
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Locked = true
			d.CanCollide = false
			d.CastShadow = true
			local c = data.colours[d.Name]
			if c then
				d.Color = c
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		warn(("[RigGun] %s has no Body part — cannot set PrimaryPart"):format(model.Name))
		return false
	end
	model.PrimaryPart = body

	-- model-space origin (the grip) recovered from the bounding box, so this
	-- does not depend on how the importer chose each part's pivot
	local bbCF, _ = model:GetBoundingBox()
	local originCF = bbCF * CFrame.new(-data.bboxCentre)

	for _, name in SOCKETS do
		local local_ = data.sockets[name]
		if local_ then
			local a = body:FindFirstChild(name)
			if not (a and a:IsA("Attachment")) then
				if a then a:Destroy() end
				a = Instance.new("Attachment")
				a.Name = name
				a.Parent = body
			end
			a.WorldCFrame = originCF * local_
		end
	end

	-- pivot at the grip, not the geometric centre
	local grip = body:FindFirstChild("Grip")
	if grip and grip:IsA("Attachment") then
		model.WorldPivot = grip.WorldCFrame
	end

	local parts, atts = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
		if d:IsA("Attachment") then atts += 1 end
	end
	print(("[RigGun] %s rigged — %d parts, %d attachments, pivot at grip 🎀")
		:format(model.Name, parts, atts))
	return true
end

local n = 0
for _, sel in Selection:Get() do
	if sel:IsA("Model") and rig(sel) then n += 1 end
end
if n == 0 then
	warn("[RigGun] select the imported gun Model(s) first")
else
	print(("[RigGun] done — %d model(s)"):format(n))
end
