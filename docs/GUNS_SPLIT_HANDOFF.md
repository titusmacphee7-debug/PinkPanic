# Pink Panic — Gun Animation Split Handoff (Cowork round 2)

The 32-gun set you delivered is fully live in-game. This round is a
**re-export of the same guns, split into named moving parts**, so guns can
actually cycle: pistol slides blow back, rifle bolts rack and show the
chamber, pumps pump, cylinders swing, mags drop during reloads, and shells
eject from a real port. **No redesigns** — same silhouettes, proportions,
scale, and style as the shipped set.

## 1. Where your meshes live today (don't break this)

- Files: `assets/meshes/guns/<GunId>.obj` — one OBJ per gun, 32 total.
  Same IDs, same paths; this round overwrites them in place.
- Each OBJ object (`o Name`) becomes a separate MeshPart named `Name` when
  imported into Studio. Current guns ship `Body / Panel / Grip / Hardware /
  Accent` — these five are the **skin regions**: 96 color skins recolor
  parts by exactly those names, and universal camos texture every MeshPart
  (so clean UVs stay required everywhere).
- Orientation: **-Z is forward** (muzzle direction), +Y up. The engine
  auto-places the muzzle at the bounding box's -Z tip, welds parts, and
  picks `Body` as the root — all runtime; you never do Studio setup.

## 2. What the guns do in-game now (context for your modeling calls)

- Full COD-style ballistics: per-gun bullet velocity (800–2590 studs/s),
  gravity drop, two-point damage falloff, server-simulated projectiles.
- Recoil + ADS just shipped: camera climb per shot, hip vs ADS spread,
  right-mouse aim that pulls the gun to screen center.
- Shell casings eject from the gun's right side, tumble with physics, and
  stay on the floor. A `Bullet` and `Shell` mesh convention already exists
  (`ReplicatedStorage/EffectModels`) — this split gives shells a REAL port
  to pop from.
- Attachments are a PLANNED feature, not a live one: nothing is
  purchasable or equippable yet. The stat framework is coded and inert
  (Barrel/Grip/Mag/Stock/Sight slots; recoil is its centerpiece stat), and
  when the feature ships, mount points will be computed at runtime from
  part bounding boxes — so you don't model mounts, but cleaner part
  separation = better mounts later. Don't model any attachment geometry
  onto the guns themselves.

## 3. The split spec

Keep the five skin-region objects. **Add** moving parts from this exact
vocabulary (names are code contracts — spelling matters):

| Object name | What it is | Which guns |
|---|---|---|
| `Slide` | Reciprocating top of the frame | All 5 pistols (`Pistol_*`) |
| `Bolt` | Bolt/charging handle piece, visible in the ejection port | SMGs, Rifles, Carbines, Bullpups, Snipers |
| `Pump` | Fore-end pump | Pump shotguns (your call which of the 5 `Shotgun_*` are pump vs break/semi — `Shotgun_4` "Double Trouble" is a double-barrel, so give it none) |
| `Cylinder` | Swing-out cylinder | All 4 revolvers (`Revolver_*`) |
| `Mag` | Detachable magazine | Every mag-fed gun (not revolvers, not tube-fed shotguns) |

Rules:

1. **Max 3 moving parts per gun** on top of the five regions (perf budget:
   every gun exists as viewmodel + world clones for 8+ players).
2. **Model what the motion reveals.** When the Slide/Bolt is back there
   must be real geometry underneath: barrel top, chamber face, an open
   ejection port. This is the whole point of the round — the "Glock top
   goes back and you can see the chamber" moment.
3. **Ejection port on the RIGHT side** (+X when facing -Z). The port's
   position on the Slide/Bolt is where shells will pop from.
4. Moving parts are modeled **in rest position**, watertight on their own
   (they get offset by code — no shared walls with the frame that would
   tear open).
5. Colors: moving parts inherit skin-region colors by a fixed code mapping
   — `Slide`→Panel, `Bolt`/`Cylinder`/`Mag`→Hardware, `Pump`→Grip. Design
   with that in mind so skins still look intentional.
6. UVs on every object (camos texture all MeshParts, world-scale tiling).
7. A gun with no sensible moving part keeps working — code falls back to
   no cycle animation — but every gun should get at least its class part.

## 4. Deliverables

- 32 updated OBJs at `assets/meshes/guns/<GunId>.obj` (overwrite in place,
  same IDs).
- Updated previews in `assets/previews/` if you regenerate them.
- A short manifest table in your reply or commit message: gun → moving
  parts included (so the animation pass knows what it got).
- Work on a branch off `claude/pink-panic-roblox-5g2w56`, same as last time.

Code-side (not your problem, but so you know it's real): a GunAnimator will
drive Slide/Bolt blowback per shot, pump strokes between shots, cylinder
spin + mag drop during the existing reload choreography, and shell ejection
timed to the cycle. The runtime loader, skins, camos, and ballistics all
keep working with zero changes if the names above are right.
