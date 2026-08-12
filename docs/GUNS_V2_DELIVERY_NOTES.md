# Pink Panic — first delivery (1 weapon + 1 optic)

Per the brief's own instruction: `AssaultRifle_1` (Grump) and `RedDot`, before
the batch. Built from the same CC0 source (Quaternius Ultimate Guns, public
domain) and the same shipped pink palette, re-authored to `GUN_MODEL_SPEC.md`.

## Files

| File | What it is |
| --- | --- |
| `AssaultRifle_1.obj` | The weapon. 7 named objects, quadrant UVs, origin at the grip |
| `pinkpanic.mtl` | The palette, so the OBJ carries pink outside Roblox too |
| `RedDot.rbxmx` | The optic — a **complete Roblox Model**, opens in Studio, no import |
| `GunSocketData.luau` | Authored sockets + colours per gun. Goes in `ReplicatedStorage/Shared/Config` |
| `RigGun.lua` | Command-bar script: rigs an imported weapon to spec in one paste |
| `AssaultRifle_1.meta.json` | Machine-readable report (regions, tris, every socket) |

## Self-validation — AssaultRifle_1

```
PASS  all six sockets present        PASS  Muzzle oriented -Z
PASS  Mount_Optic = bore + 0.22      PASS  EjectPort oriented +X
PASS  Mount_Under = bore - 0.18      PASS  Grip socket at the pivot
PASS  Mount_Laser = 0.16 left        PASS  Body and Panel separate
PASS  Mount_Barrel on bore axis      PASS  Grip / Hardware / Accent separate
PASS  Mount_Stock on bore axis       PASS  movers named and free of the body
PASS  class length 3.40 studs        PASS  poly budget 1308 / 1800
```

Regions: `Body` 64 · `Panel` 348 · `Grip` 116 · `Hardware` 604 · `Accent` 60,
movers `Bolt` 24 · `Mag` 92. Nothing merged, nothing default grey.

`RedDot`: 312 / 350 tris, `Anchor` + `AimPoint` present, no reserved-name
collisions, fully authored in palette.

**Mount check.** I simulated `Anchor -> Mount_Optic` numerically: the optic's
lowest point lands at 0.5745 against a mount at 0.5445 — it sits *on* the rail,
upright, and its `AimPoint` ends up 0.405 studs above the bore. Because the
mount offset is a constant and not derived from this gun's geometry, the same
result holds for any weapon that carries `Mount_Optic`.

---

## Two things I need your call on

### 1. The reference models were not attached

Nothing on disk anywhere — no `.rbxm`/`.rbxmx` in the repo or elsewhere. The
brief says they are the contract and beat the document, so I have built to
`GUN_MODEL_SPEC.md` and listed every assumption below rather than guess
silently. **Send them and I will diff against them before the batch.**

### 2. `Anchor` orientation — the one that cannot be fixed later

§B1 says `Anchor` is aligned to the mount frame directly, with "+Y pointing back
into the gun". §2 says a mount's "+Y is away from the gun". Those two read as
opposites: if the anchor's +Y pointed into the gun *and* aligned to a mount
whose +Y points away, the optic would mount buried in the receiver.

I built the geometrically correct reading — **`Anchor` sits on the optic's
mating face with its +Y running up the optic body**, so aligning it to
`Mount_Optic` seats the optic on the rail (verified above). If your loader wants
the other convention it is one line in `build_reddot.py`. This is exactly the
thing the reference optic would settle.

---

## A real bug I found on the way in

**19 of the 40 source guns have their muzzle pointing +Z**, including this one.
That is the failure §1 describes — "seven of thirty-two models had neither
`Grip` nor `Mag`, so those guns pointed backwards forever".

Affected: all 4 `AssaultRifle_*`, all 4 `AssaultRifle2_*`, `Bullpup_1`,
`Pistol_4`, `Pistol_5`, `Shotgun_1..3`, `SubmachineGun_1/2/4/5`, plus dropped
variants.

The rebuild detects the muzzle from geometry (the muzzle end is the thin end,
measured as silhouette height in the outer 15% of the length) and rotates the
model 180° about Y so it points −Z. Orientation is then **authored** — written
into `GunSocketData.luau` — so nothing downstream has to infer it again. I
verified the detector by eye on six guns across every class before trusting it.

---

## Still to do for the batch — not in this delivery

Being explicit so nothing is assumed done:

1. **LODs.** §A4/§6 wants 3 LOD steps per weapon and 2 per attachment. Not
   built yet — I would generate them by decimation once the base models are
   accepted, since a rejected base makes its LODs waste.
2. **`LMG_1..4` and `Marksman_1..2`** have no source in the current pack — the
   CC0 set has no belt-fed weapons. Options: promote the 8 previously-dropped
   variants (a stretched `AssaultRifle2_2` reads fine as an LMG receiver), or
   pull a second CC0 pack. Say which and I will build to it.
3. **The other 30 attachments.** `RedDot` proves the pattern; the rest are the
   same shape of work and go fast once the `Anchor` convention is confirmed.

## Why the weapon is an OBJ and the optic is an .rbxmx

A `MeshPart` needs an uploaded mesh asset, and I have no Open Cloud key from
here — a MeshPart-based model file would ship with an empty `MeshId`. So the
weapon ships as geometry plus `RigGun.lua`, which builds the spec-compliant
Model at import: palette, `Anchored` **and** `Locked`, `PrimaryPart = Body`,
pivot moved to the grip, and all twelve sockets placed from the authored table.
Two steps in Studio, and every acceptance property is set by script rather than
by hand.

Attachments are small enough that primitives beat meshes at their budgets, so
`RedDot.rbxmx` is a finished Roblox Model — drag it in and it is done.

If you would rather have the weapons as native `.rbxmx` too, there are two
routes: give me an Open Cloud API key and I upload the meshes and emit real
MeshPart models, or I rebuild the weapons out of Roblox primitives. Say the word
— the second one also permanently kills the "imports come in white" problem.

## Import steps

1. **File → Import 3D** → `AssaultRifle_1.obj`. **Merge Meshes OFF** (it is what
   collapses the named parts into one "default" object). Scale unit: Studs.
2. Put `GunSocketData.luau` in `ReplicatedStorage/Shared/Config`.
3. Select the imported Model, paste `RigGun.lua` into the Command Bar (Ctrl+9),
   Enter. It prints what it rigged.
4. `RedDot.rbxmx`: right-click `ReplicatedStorage/Assets/Attachments` → Insert
   from File. No import, no script.
5. Run the real validator:
   `require(game.ReplicatedStorage.Shared.Loaders.GunSockets).printReport()`
