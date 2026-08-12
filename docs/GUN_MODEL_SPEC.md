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

### Mount points — and why they must AGREE, not merely exist

`Mount_Optic` · `Mount_Barrel` · `Mount_Under` · `Mount_Laser` · `Mount_Stock` ·
`Mount_Charm`

Only needed where the gun can physically take that attachment. Reported, never
demanded — a gun with no under-barrel rail is a design decision.

> **An attachment is built once and fits the whole roster.** One red dot serves
> all 38 guns. That is the entire economics of the attachment system: ~32
> attachment models, not 32 × 38.
>
> It only holds if the mounts are **standardised**, not just present. If
> `Mount_Optic` sits at a different height above the bore on each gun, the same
> red dot buries itself in one receiver and floats over the next, and the only
> fixes are per-gun offset tables maintained by hand forever, or per-gun optics.
> Both of those are the thing this spec exists to avoid.

Every mount is an `Attachment` whose **orientation defines the mounting frame**:
+Y is away from the gun (up out of a rail, down off an under-barrel), −Z is
forward along the weapon. An attachment's `Anchor` is aligned to it directly, so
a mount rotated 90° puts the optic on its side.

| Mount | Position | Standard |
| --- | --- | --- |
| `Mount_Optic` | Top rail, centred on the bore axis | **0.22 studs above the bore centreline**, on every gun that has one |
| `Mount_Barrel` | Muzzle end, on the bore axis | On the bore centreline. Concentric, or a suppressor sits crooked |
| `Mount_Under` | Under the handguard, centred | **0.18 studs below the bore centreline** |
| `Mount_Laser` | Side of the handguard, left | **0.16 studs left of the bore centreline** |
| `Mount_Stock` | Rear of the receiver, on the bore axis | On the bore centreline |
| `Mount_Charm` | Anywhere it hangs nicely | No standard — charms are decorative and per-gun |

The bore centreline is the axis through `Muzzle`. These offsets are the
contract: a gun whose rail is physically taller than 0.22 studs models the rail
as geometry and still puts the **socket** at 0.22.

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

Attachments are budgeted per slot in §7 and add up to ~1,260 more per gun — most
of a second weapon. Five attachments on all 24 guns would be another 30k, which
is why they LOD out hard rather than being budgeted smaller: a vertical grip at
90 studs is not information, and deleting it is cheaper than modelling it twice.

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

## 7. Attachment models

Attachments are their own models, stored in `ReplicatedStorage/Assets/Attachments/`,
one per attachment, **file name = the attachment id** — the same rule as the
guns. They are welded to a gun's `Mount_*` socket at runtime and hidden when not
equipped.

### Every attachment carries `Anchor`

An `Attachment` named `Anchor`, at the point that mates with the gun's mount.
Position **and** orientation are used: `Anchor` is aligned to the mount frame
directly, so +Y points back into the gun and −Z runs forward.

Get this wrong and the attachment mounts inside the receiver or upside down.
There is no code-side correction, by design — that is exactly the inference the
old build did and why seven guns pointed backwards forever.

### Optics additionally carry `AimPoint`

**The single hardest thing here to retrofit.** `AimPoint` is where the camera
sits when the player aims — the centre of the reticle, at the eye relief the
optic is meant to be used at.

Without it there is no sight alignment: aiming down a scope looks through the
side of it, and no amount of tuning in code recovers a number that was never
authored. Every optic has one. Iron sights are an optic too (see below).

### Reserved names — the collision that bites at runtime

A mounted attachment becomes a descendant of the gun model, and the loaders scan
descendants by name. So an attachment containing a part named `Body` is counted
as one of the gun's camo regions, and an attachment containing an `Attachment`
named `Muzzle` becomes the gun's muzzle.

**Inside an attachment model, never use:**

- Socket names — `Muzzle`, `Grip`, `EjectPort`, `LeftGrip`, `Sight`, `MagWell`
- Region names — `Body`, `Panel`, `Grip`, `Hardware`, `Accent`
- Moving-part names — `Slide`, `Bolt`, `Pump`, `Cylinder`, `Mag`

Prefix parts with the attachment's own name (`Suppressor_Shell`,
`RedDot_Housing`) or use neutral ones.

The one case that legitimately needs to move a socket is a **suppressor or
barrel that changes where the bullet leaves**. That uses `MuzzleOverride`, not
`Muzzle` — a distinct name so the scan stays unambiguous and the loader can
prefer it deliberately rather than by accident of search order.

### Attachments never take camo

They keep their own materials — that is what makes a built gun look *assembled*
rather than shrink-wrapped. The consequence for the modeller is that an
attachment is **never** partially finished: there is no skin layer coming later
to cover a grey block. Author each one complete, in the pink palette.

### Iron sights are a real attachment

`IronSights` is the default "no optic" case and it is a model like any other,
with an `AimPoint`. Making it the absence of a thing means the ADS path has two
branches that drift apart; making it an attachment means there is one path and
iron sights are simply the one you start with.

### Poly budgets, per slot

| Slot | Budget | Notes |
| --- | --- | --- |
| Optic | 350 | Glass, housing and mount. The most-seen attachment |
| Stock | 260 | |
| Barrel | 250 | |
| Muzzle | 220 | Suppressors are mostly a tube |
| Magazine | 180 | Drums cost more; stay inside it |
| Underbarrel | 150 | |
| RearGrip | 100 | |
| Laser | 90 | The emitter. The beam is an effect, not geometry |

Worst case is five of the largest on one gun — about **1,260 triangles**, which
is most of a second weapon. That is why the LOD rule below exists.

### Attachment LOD

| Distance | Attachments |
| --- | --- |
| 0–30 studs | Full |
| 30–90 studs | ~40%, merged to one part per attachment |
| 90+ studs | **Hidden entirely**, except `Optic` and `Muzzle`, which drop to a silhouette block |

Optic and muzzle survive at distance because they change the weapon's outline,
and the outline is the only thing you can read at 90 studs. A vertical grip is
not information at that range.

---

## 8. The checklist a model is accepted against

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
- [ ] Mount sockets at the standard offsets in §2, not just present
- [ ] Every part `Anchored` **and** `Locked` — *locked is not anchored*, and an
      imported part that is locked but not anchored explodes the moment you
      press Play

### And for an attachment

- [ ] `Anchor` present, positioned **and oriented** to mate with its mount
- [ ] `AimPoint` present if it is an optic
- [ ] No reserved names anywhere inside it (§7)
- [ ] Fully finished in the pink palette — nothing takes camo, so nothing is
      waiting to be covered
- [ ] Inside its slot's budget, with the two LOD steps

---

## 9. The Cowork brief

Everything below is the text to hand over, with the reference gun and the
reference optic attached.

> **Pink Panic — weapons and attachments**
>
> We need **38 stylised weapons and ~32 attachments** for a Roblox first-person
> shooter. The art direction is **cute-pink**: think confectionery and
> stationery, not military hardware. There is no grey-and-metal weapon in this
> game.
>
> **Attached: one reference gun and one reference optic, both built to spec.**
> Match their conventions exactly — names, orientation, part split, UV layout,
> mount offsets. They are the contract; this document explains it.
>
> ---
>
> ## Part A — the 38 weapons
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
>    wherever the weapon could physically take one — **at the standard offsets
>    below**, which matter more than they look like they do.
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
> **Mount offsets — please read this one twice.** Each attachment is built ONCE
> and fits all 38 guns. That only works if the mounts agree: `Mount_Optic`
> **0.22 studs above the bore centreline**, `Mount_Under` **0.18 below**,
> `Mount_Laser` **0.16 left**, `Mount_Barrel` and `Mount_Stock` **on the bore
> axis**. If a gun's rail is physically taller, model the rail as geometry and
> still place the socket at 0.22. A mount at the wrong height means that gun
> needs its own optics, which multiplies the attachment set by the roster.
>
> ---
>
> ## Part B — the ~32 attachments
>
> Separate models, one per attachment, welded to the mounts above at runtime.
> Roughly four per slot across eight slots: **Optic, Muzzle, Barrel,
> Underbarrel, Magazine, Stock, RearGrip, Laser**.
>
> 1. **Every attachment carries an `Attachment` named `Anchor`** at the point
>    that mates with the gun's mount. Position *and* orientation are used —
>    +Y back into the gun, −Z forward. There is no code-side correction.
> 2. **Every optic additionally carries `AimPoint`** — where the player's eye
>    goes, at the centre of the reticle at proper eye relief. This is the one
>    thing here that cannot be fixed later: without it, aiming looks through
>    the side of the scope and there is no number to tune. Iron sights are an
>    optic too and need one.
> 3. **Reserved names — do not use these inside an attachment.** A mounted
>    attachment becomes part of the gun, and our loaders find parts by name.
>    Avoid `Muzzle`, `Grip`, `EjectPort`, `LeftGrip`, `Sight`, `MagWell`,
>    `Body`, `Panel`, `Hardware`, `Accent`, `Slide`, `Bolt`, `Pump`,
>    `Cylinder`, `Mag`. Prefix parts with the attachment's own name instead —
>    `Suppressor_Shell`, `RedDot_Housing`. A suppressor that moves where the
>    bullet leaves uses `MuzzleOverride`.
> 4. **Attachments never take camo.** They keep their own materials, which is
>    what makes a built gun look assembled rather than shrink-wrapped. So each
>    one must be **completely finished** — there is no skin layer coming later
>    to cover a grey block.
>
> **Attachment budgets** (triangles): optic 350 · stock 260 · barrel 250 ·
> muzzle 220 · magazine 180 · underbarrel 150 · rear grip 100 · laser 90.
> Two LOD steps: ~40% merged at 30 studs, and hidden entirely past 90 except
> optics and muzzle devices, which drop to a silhouette block.
>
> ---
>
> **Acceptance:** we run an automated validator against every model. For guns it
> reports which sockets are missing and whether the region split survived; for
> attachments it checks `Anchor`, `AimPoint` on optics, and reserved-name
> collisions. A model is accepted on a clean row — please check against the
> reference models before delivering a batch.

---

## 9. Before commissioning anything

**Build one reference gun and one reference optic by hand, in Studio, and prove
the spec on them.** Order matters here: everything above is a claim until a real
model has been through it, and a wrong claim multiplied by 38 weapons and 32
attachments is the expensive version of this mistake.

**Two** reference models, not one. The optic is what proves the half of the spec
the gun cannot: `Anchor` alignment, `AimPoint` eye relief, and the reserved-name
rule. A gun alone never exercises any of them, and those are the parts a
commissioned batch would get wrong 32 times over.

The five proofs, in order:

1. **Sockets.** Validator row clean, gun points forward, muzzle flash comes out
   of the barrel, shells leave the port.
2. **Universal camo.** Apply one universal test texture. It must map correctly
   with no seams across the `Body`/`Panel` quadrants.
3. **Camo *and* skin together.** Every region painted, nothing reading as bare
   metal, and the parts a camo does not texture still take the skin's colour.
4. **The optic mounts.** Weld it to `Mount_Optic` and confirm it sits on the
   rail the right way up, with its own materials intact and no camo on it.
5. **The mount standard holds.** Weld the *same* optic to a **second** gun.
   If it sits correctly on both without a per-gun offset, the 0.22-stud
   convention is real. If it does not, fix the convention now — this is the
   single check that decides whether attachments are commissioned once or
   thirty-eight times.

Only after all five does the brief in §9 go out.
