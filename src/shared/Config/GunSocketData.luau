--!strict
-- GunSocketData — authored sockets for the Pink Panic weapon roster.
-- Generated with the models; consumed by tools/RigGun.lua at import time.
-- Orientation is CONTENT, not inference: every gun here points -Z.

export type GunData = {
	class: string,
	bboxCentre: Vector3,
	colours: { [string]: Color3 },
	sockets: { [string]: CFrame },
}

local GunSocketData: { [string]: GunData } = {
	AssaultRifle_1 = {
		class = "Rifle",
		bboxCentre = Vector3.new(0.00000, -0.05712, -1.42711),
		colours = {
			Body = Color3.fromRGB(255, 245, 250),
			Panel = Color3.fromRGB(255, 227, 240),
			Grip = Color3.fromRGB(255, 130, 190),
			Hardware = Color3.fromRGB(92, 72, 88),
			Accent = Color3.fromRGB(255, 92, 168),
			Bolt = Color3.fromRGB(92, 72, 88),
			Mag = Color3.fromRGB(92, 72, 88),
		},
		sockets = {
			Muzzle = CFrame.new(0.00000, 0.32447, -3.13711, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Grip = CFrame.new(0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			EjectPort = CFrame.new(0.04000, 0.33447, -0.70879, 0.00000, 0.00000, -1.00000, 0.00000, 1.00000, 0.00000, 1.00000, 0.00000, 0.00000),
			LeftGrip = CFrame.new(0.00000, 0.20447, -1.69911, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Sight = CFrame.new(0.00000, 0.49892, -0.88311, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			MagWell = CFrame.new(0.00000, 0.24235, -1.02594, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Optic = CFrame.new(0.00000, 0.54447, -0.88311, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Barrel = CFrame.new(0.00000, 0.32447, -3.12711, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Under = CFrame.new(0.00000, 0.14447, -1.69911, -1.00000, 0.00000, 0.00000, 0.00000, -1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Laser = CFrame.new(-0.16000, 0.32447, -1.69911, 0.00000, -1.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Stock = CFrame.new(0.00000, 0.32447, 0.27289, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
			Mount_Charm = CFrame.new(0.00000, -0.10000, 0.10000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000),
		},
	},
}

return GunSocketData
