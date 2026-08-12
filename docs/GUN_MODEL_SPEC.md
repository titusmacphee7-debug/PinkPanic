# Gun model spec — Pink Panic

Every gun model in the game is built to this document. Two of the three
requirements below **cannot be retrofitted**: a model that misses them has to be
rebuilt, not patched. That is why the spec exists before the models do.

The validator that enforces it is one line in the Studio Command Bar:

```lua
require(game.ReplicatedStorage.Shared.Loaders.GunSockets).printReport()
```

It prints a table naming every gun and what it is missing. **A model is accepted
when it has a clean row.** Nothing else counts as done.

---

## 0. The one-paragraph version, for a modeller in a hurry

Build the gun **pink**, out of **separate named parts**, pointing **down −Z**,
with **six Attachments** in it. Do not merge the grip into the body to save a
part. Do not leave anything default grey on the assumption a skin will cover it
— most of the gun is visible most of the time. Name the moving pieces even if
you are not animating them; the game animates them.

---

## 1. Orientation, pivot and scale

- The gun points along **−Z** (Roblox "forward"). Up is **+Y**, right is **+X**.
- The model's **PrimaryPart is the receiver** — the `Body` part.
- The pivot sits at the **grip**, not at the geometric centre. The viewmodel
  rotates the gun around where the hand holds it; a centre pivot makes the
  weapon swing like it is on a stick.
- Scale: a rifle is **≈ 3.4 studs** long. A pistol is **≈ 1.5**. An LMG is
  **≈ 4.2**. These are held against the standard R15 rig (see NOD-167), which is
  one fixed size for every player, so a gun that looks right on one character
  looks right on all of them.

> **Why this is not inferred.** The old build worked orientation out from
> whether a part named `Grip` existed. Seven of thirty-two models had neither
> `Grip` nor `Mag`, so those guns pointed **backwards forever** and there was no
> fix available in code. Orientation is now content, and content is tagged.

---

## 2. Sockets — six Attachments, exact names

`Attachment` instances. **Not parts.** A part named `Muzzle` is a piece of
geometry someone named hopefully; the loader ignores it.

| Attachment | Where it goes | What breaks without it |
| --- | --- | --- |
| `Muzzle` | The end of the barrel, pointing **−Z** | Bullets leave from the wrong place; the flash spawns inside the gun |
| `Grip` | Where the right hand closes | The gun does not attach to the hand |
| `EjectPort` | The ejection port, pointing **+X** | Shells spray out of the receiver |
| `LeftGrip` | Where the left hand rests (forend, or the magazine on a pistol) | The left arm has nothing to solve to |
| `Sight` | On the rail, at iron-sight height | Aiming down sights points at nothing |
| `MagWell` | Where the magazine seats | The mag-drop reload animation has no target |

`Muzzle` and `EjectPort` are **directional** — their orientation is used, not
just their position. Point them the way the bullet and the shell actually leave.

### Optional mount points

Only needed where the gun can physically take that attachment. Reported, never
demanded — a gun with no under-barrel rail is a design decision.

`Mount_Optic` · `Mount_Barrel` · `Mount_Under` · `Mount_Laser` · `Mount_Stock` ·
`Mount_Charm`

---

## 3. Regions — the part split, and why it is not negotiable

**A camo textures part of the gun and colours the rest.** Like CoD, but pink:
there are no grey-and-metal weapons in this game.

| Region | Painted by | Notes |
| --- | --- | --- |
| `Body` | camo **texture** | The receiver. Usually the PrimaryPart. |
| `Panel` | camo **texture** | Handguard, upper, any large flat face |
| `Grip` | camo **palette**, else the skin's colour | |
| `Hardware` | camo **palette**, else the skin's colour | Bolt, trigger, screws, sights |
| `Accent` | camo **palette**, else the skin's colour | The one part that gets to be a different pink |

Every region is always painted by something. There is no state in which a
surface is left bare.

> **This is a modelling requirement, not a code one.** If the grip is merged
> into the body to save a part, that grip gets textured with the receiver, the
> skin underneath disappears, and there is no layer left to make it pink.
> **Regions must survive into the built model as separate parts.**

The validator flags both ways of getting this wrong:

- **No `Body` or `Panel`** → the gun can never wear a camo at all.
- **No `Grip`/`Hardware`/`Accent`** → nothing for a palette to colour, so it
  reads as bare metal the moment a camo goes on.

A gun needs at least one of each. Most guns should have all five.

### Per-part override

A `TakesCamo` boolean attribute on any part overrides its region default — for a
gun that wants a painted stock, or a deliberately bare receiver.

**Attachments never take camo.** An optic and a suppressor keep their own
materials. That is what makes a built gun look *assembled* rather than
shrink-wrapped.

---

## 4. Moving parts

The viewmodel cycles these by name. **A part that is not named does not move.**

| Part | Motion |
| --- | --- |
| `Slide` | Blowback on each shot |
| `Bolt` | Reciprocates on each shot |
| `Pump` | Stroked between shells |
| `Cylinder` | Notches round one chamber per shot |
| `Mag` | Drops and is replaced on reload |

Optional per gun — a revolver has no slide. Include the ones the weapon
actually has, as separate parts, free of the body.

---

## 5. Shared UV layout — for the universal camos

Most camos are **gun-specific**: authored against one weapon's own UV, filed
under `Assets/Camos/PerGun/<GunId>/`, and they need nothing from this section
beyond the region names above.

**Some camos are universal**, and those need every gun laid out identically in
UV space. Get this right and a universal camo is one texture file for the whole
roster. Skip it and there are no universal camos: every look has to be redrawn
per weapon, and a set of 20 becomes 20 × 38.

### The layout

`Body` and `Panel` are the only regions that receive a texture, so they are the
only ones that need to agree. Both unwrap into a **single 1024 × 1024 square**,
divided as:

```
    0                 0.5                 1
  0 +-------------------+-------------------+
    |                   |                   |
    |      BODY         |      PANEL        |
    |   left face       |   left face       |
    |                   |                   |
0.5 +-------------------+-------------------+
    |                   |                   |
    |      BODY         |      PANEL        |
    |   right face      |   right face      |
    |                   |                   |
  1 +-------------------+-------------------+
```

- **Left half is `Body`, right half is `Panel`.** Always, on every gun.
- **Top row is the left side of the weapon, bottom row is the right side.**
- Each quadrant is filled to its edges: a short pistol receiver and a long LMG
  receiver both stretch to fill their quadrant. A camo is a *pattern*, not a
  decal — stretching is correct, and the alternative (every gun unwrapped at its
  own true scale) is exactly what makes universal camos impossible.
- **No mirroring.** Both sides are unwrapped independently so text and
  asymmetric patterns read correctly on both.
- Small hardware — trigger, screws, sights — does **not** need to be in this
  layout. Those regions take a flat palette colour and their UVs are unused.

---

## 6. Poly budget

Twelve players, two guns each, plus a viewmodel at full detail. The budget is
per **model**, triangles, including attachments.

| Class | Budget | Notes |
| --- | --- | --- |
| Pistol, Revolver | 900 | Small on screen except in the viewmodel |
| SMG | 1,400 | |
| Shotgun | 1,500 | |
| Rifle, BattleRifle | 1,800 | The most-seen guns in the game |
| Marksman | 1,900 | |
| Sniper | 2,000 | Long barrels cost geometry |
| LMG | 2,400 | Belt and drum |

Worst case is 24 world guns at ~1,800 = **43k triangles** of weaponry, plus one
viewmodel. That is the number the budget is sized against.

Attachments are budgeted separately at **250 triangles** each, up to five
mounted at once.

### LOD

Third-person guns at distance do not need barrels you can see down.

| Distance | Requirement |
| --- | --- |
| 0–30 studs | Full model |
| 30–90 studs | ~50% of budget. Merge hardware, drop interior geometry |
| 90+ studs | ~25%. Silhouette only |

Regions must survive at every LOD — a distant gun still wears its camo. If a LOD
merges `Hardware` into `Body`, that gun changes colour as you walk away from it.

---

## 7. The checklist a model is accepted against

Run the validator. The row must be clean. Specifically:

- [ ] Points down −Z, pivot at the grip, correct scale for its class
- [ ] All six Attachments present, exact names, `Muzzle` and `EjectPort`
      oriented
- [ ] At least one of `Body` / `Panel`, as its own part
- [ ] At least one of `Grip` / `Hardware` / `Accent`, as its own part
- [ ] Moving parts named and free of the body
- [ ] `Body` and `Panel` unwrapped to the shared quadrant layout
- [ ] Inside the poly budget for its class
- [ ] **Nothing default grey.** Authored in the pink palette
- [ ] Every part `Anchored` **and** `Locked` — *locked is not anchored*, and an
      imported part that is locked but not anchored explodes the moment you
      press Play

---

## 8. The Cowork brief

Everything below is the text to hand over, with the reference gun attached.

> **Pink Panic — weapon models**
>
> We need a roster of 38 stylised weapons for a Roblox first-person shooter.
> The art direction is **cute-pink**: think confectionery and stationery, not
> military hardware. There is no grey-and-metal weapon in this game.
>
> **Attached: one reference gun built to spec.** Match its conventions exactly —
> names, orientation, part split, UV layout. It is the contract; this document
> explains it.
>
> **The three things that matter most**, in order:
>
> 1. **Separate named parts.** Each gun splits into `Body`, `Panel`, `Grip`,
>    `Hardware`, `Accent`, plus any of `Slide` / `Bolt` / `Pump` / `Cylinder` /
>    `Mag` the weapon has. These are not cosmetic names — the game paints and
>    animates each one independently. **Do not merge parts to reduce count.** A
>    merged grip cannot be coloured separately and the weapon becomes
>    undressable.
> 2. **Six Attachments per gun**, named exactly: `Muzzle`, `Grip`, `EjectPort`,
>    `LeftGrip`, `Sight`, `MagWell`. `Muzzle` points forward out of the barrel;
>    `EjectPort` points out of the ejection port. Add `Mount_Optic`,
>    `Mount_Barrel`, `Mount_Under`, `Mount_Laser`, `Mount_Stock`, `Mount_Charm`
>    wherever the weapon could physically take one.
> 3. **Shared UV layout on `Body` and `Panel` only.** Single 1024², left half
>    `Body` and right half `Panel`, top row the weapon's left side and bottom
>    row its right side, each quadrant filled edge to edge. Identical on every
>    gun in the roster — this is what lets one texture file skin all 38.
>
> **Colour:** author in the pink palette from the start. Base materials must not
> be default grey on the assumption a skin will cover them — a partially covered
> gun is the normal case, not the exception.
>
> **Orientation:** −Z forward, +Y up. Pivot at the grip.
>
> **Poly budgets** (triangles, per model): pistol 900 · SMG 1,400 ·
> shotgun 1,500 · rifle 1,800 · marksman 1,900 · sniper 2,000 · LMG 2,400.
> Three LODs at roughly 100% / 50% / 25%, and **regions must survive at every
> LOD** — a gun that merges its hardware at distance changes colour as you walk
> away.
>
> **Every part `Anchored` and `Locked`.**
>
> **Acceptance:** we run an automated validator against every model. It reports
> per gun which sockets are missing and whether the region split survived. A
> model is accepted on a clean row — please check against the reference gun
> before delivering a batch.

---

## 9. Before commissioning anything

**Build one reference gun by hand, in Studio, and prove the spec on it.** Order
matters here: everything above is a claim until a real model has been through
it, and a wrong claim multiplied by 38 commissioned models is the expensive
version of this mistake.

The three proofs, in order:

1. **Sockets.** Validator row clean, gun points forward, muzzle flash comes out
   of the barrel, shells leave the port.
2. **Universal camo.** Apply one universal test texture. It must map correctly
   with no seams across the `Body`/`Panel` quadrants.
3. **Camo *and* skin together.** Every region painted, nothing reading as bare
   metal, and the parts a camo does not texture still take the skin's colour.

Only after all three does the brief in §8 go out.
