# Hooking your hand-built lobby into the game

The code looks for a **`Lobby`** folder in `workspace`. Inside it, three
kinds of tagged objects drive everything — where players spawn, where the
camera sits, and which pads do what. You place them; the code does the rest
(floating name signs, banners, panel auto-open, spawn switching, the
fixed-pivot camera).

## 1. One-paste bootstrap

In Studio, move the camera so you're looking at the fountain, then paste
this whole block into the **Command Bar** (View tab → Command Bar) and hit
Enter. It creates everything in a ring around the camera focus, glowing
pink so you can see and drag each piece into place:

```lua
local origin = workspace.CurrentCamera.Focus.Position
local lobby = Instance.new("Folder") lobby.Name = "Lobby" lobby.Parent = workspace
local anchor = Instance.new("Part") anchor.Name = "CameraAnchor"
anchor.Size = Vector3.new(2,2,2) anchor.Anchored = true anchor.CanCollide = false
anchor.Transparency = 0.5 anchor.Color = Color3.fromRGB(120,200,255)
anchor.CFrame = CFrame.lookAt(origin + Vector3.new(0,14,46), origin + Vector3.new(0,4,0))
anchor:SetAttribute("MaxYawDeg", 20) anchor:SetAttribute("MaxPitchDeg", 10)
anchor.Parent = lobby
for i = 1, 8 do
	local a = math.rad(i * 45)
	local s = Instance.new("SpawnLocation")
	s.Name = "LobbySpawn"..i s.Size = Vector3.new(5,0.6,5)
	s.CFrame = CFrame.new(origin + Vector3.new(math.cos(a)*14, 1, math.sin(a)*14))
	s.Color = Color3.fromRGB(255,130,190) s.Material = Enum.Material.Neon
	s.Transparency = 0.5 s.Anchored = true s.Neutral = true s.Duration = 0
	s.Parent = lobby
end
local pads = {
	{"The Bow-tique 🎀","shop"},{"Candy Armory 🍭","loadout"},
	{"The Cutie Closet 👗","closet"},{"Heartbreaker Range 💘","range"},
	{"The Café ☕","cafe"},{"The Panic Portal 💗","portal"},
}
for i, def in pads do
	local a = math.rad(i * 60 - 30)
	local p = Instance.new("Part")
	p.Name = "Pad_"..def[2] p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.6,7,7) p.Anchored = true p.CanCollide = false
	p.Color = Color3.fromRGB(255,92,168) p.Material = Enum.Material.Neon p.Transparency = 0.3
	p.CFrame = CFrame.new(origin + Vector3.new(math.cos(a)*30, 0.5, math.sin(a)*30)) * CFrame.Angles(0,0,math.rad(90))
	p:SetAttribute("PadName", def[1]) p:SetAttribute("PadAction", def[2])
	p:SetAttribute("PadRadius", 8)
	p.Parent = lobby
end
print("Lobby scaffold created — drag everything into place!")
```

## 2. Drag things where they belong

- **Pads** → in front of their matching storefronts. Stepping within
  `PadRadius` studs shows the name banner and (for now) opens the shop
  (`shop`) or armory panel (`loadout`); `closet` / `range` / `cafe` /
  `portal` are banner-only until their interiors exist. A floating name
  sign appears above each pad automatically at runtime.
- **Spawn pads** → scatter them around the plaza floor. They're the only
  live spawns between rounds (the arena takes over during rounds
  automatically).
- **CameraAnchor** → this IS the camera. Put it where the shot should be
  taken from (elevated, looking across the plaza at the storefront row) and
  **rotate it so its front face points at what the camera should see**. The
  camera pivots from this exact spot to follow players — never more than
  `MaxYawDeg` (20°) sideways / `MaxPitchDeg` (10°) vertically, so it can't
  swing around and reveal unbuilt areas. Tune those attributes live in the
  Properties panel while play-testing.

## 3. Save, publish, done

The pieces are part of the place file (not Rojo-synced), so just save. The
scaffold parts are neon so you can see them — the code doesn't care about
looks; feel free to make pads prettier or fully transparent once placed.

## Gun model imports (reminder)

Gun meshes live in `ReplicatedStorage/GunModels` or
`ReplicatedStorage/Shared/Assets/GunModels` (either works — if Rojo ever
deletes the second one on connect, drag the folder to ReplicatedStorage
root). Camo texture ids get pasted into
`src/shared/Config/GunSkinCatalog.luau`.
