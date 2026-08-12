# Pink Panic — weapon and attachment commission

Everything in this document is the brief. Two reference models are attached: one
weapon and one optic. **They are the contract** — where this document and the
reference models disagree, the models win.

---

## What we need

- **38 weapons**
- **~31 attachments**

For a Roblox first-person shooter. Delivered as Roblox `Model` instances,
one file per item.

## Art direction

**Cute-pink.** Think confectionery, stationery and toys — not military hardware.

There is **no grey-and-metal weapon in this game.** Every weapon is authored in
the pink palette from the start. Do not leave base materials as default grey
plastic on the assumption that a skin will cover them: most of a weapon is
visible most of the time, and a partially-covered gun is the normal case rather
than the exception.

The names are the strongest steer on character — a gun called *Marshmallow*
should read soft and rounded, *Jawbreaker* should read heavy and blunt,
*Stiletto* should read thin and sharp. Lean on them.

---

## Delivery

| | |
| --- | --- |
| Format | Roblox `Model`, one per file |
| **File name** | **Exactly the ID in the tables below.** Not the display name |
| Parts | Every part `Anchored` **and** `Locked` |
| Orientation | Weapon points down **−Z**. Up is **+Y**, right is **+X** |
| Pivot | At the **grip**, not the geometric centre |
| PrimaryPart | The `Body` part |

> **File names are IDs, not display names.** The model for the rifle called
> *Grump* is the file `AssaultRifle_1`. The IDs are historical and some of them
> no longer describe the weapon — `SniperRifle_4` is a marksman rifle called
> *Star Crossed*. Please use the ID column exactly as written; the display name
> column is there so you know what you are building.

---

# PART A — the 38 weapons

## The roster

Sizes are the length of the weapon, measured against a standard Roblox R15
character. Every player in this game is the same fixed size, so a weapon that
scales correctly on one character scales correctly on all of them.

### SMG — 4 · ~2.2 studs

Compact, high rate of fire, short. Should read *fast*.

| ID | Name | Magazine |
| --- | --- | --- |
| `SubmachineGun_1` | Chatterbox | 30 |
| `SubmachineGun_2` | Bubbler | 32 |
| `SubmachineGun_3` | Zoomie | 28 |
| `SubmachineGun_4` | Jitterbug | 25 |

### Shotgun — 5 · ~2.9 studs

Wide-bore barrel, pump or break action. *Shortcake* is a sawn-off and should be
noticeably the smallest.

| ID | Name | Magazine |
| --- | --- | --- |
| `Shotgun_1` | Big Boop | 6 |
| `Shotgun_3` | Homemaker | 5 |
| `Shotgun_4` | Double Trouble | 8 |
| `Shotgun_ShortStock` | Scrunchie | 7 |
| `Shotgun_SawedOff` | Shortcake | 2 |

### Rifle — 7 · ~3.4 studs

The most-seen weapons in the game. Give these the most attention.

| ID | Name | Magazine |
| --- | --- | --- |
| `AssaultRifle_1` | Grump | 30 |
| `AssaultRifle_2` | Gumdrop | 30 |
| `AssaultRifle_3` | Cherry Bomb | 30 |
| `AssaultRifle_4` | Picnic Punch | 24 |
| `AssaultRifle2_1` | Sweet Talker | 28 |
| `AssaultRifle2_3` | Sprinkler | 40 |
| `AssaultRifle2_4` | Chunky | 30 |

### Battle rifle — 2 · ~3.7 studs

Longer and heavier than a rifle. More barrel, bigger receiver.

| ID | Name | Magazine |
| --- | --- | --- |
| `Bullpup_1` | Marshmallow | 24 |
| `Bullpup_2` | Toastie | 20 |

### LMG — 4 · ~4.2 studs

The biggest weapons in the game. Belt or drum feed, visibly heavy.

| ID | Name | Magazine |
| --- | --- | --- |
| `LMG_1` | Big Sister | 100 |
| `LMG_2` | Rolling Pin | 150 |
| `LMG_3` | Slumber Party | 80 |
| `LMG_4` | Cupcake Cannon | 125 |

### Marksman — 4 · ~3.8 studs

Semi-automatic precision rifles. Long barrel, magazine-fed, scope-ready.

| ID | Name | Magazine |
| --- | --- | --- |
| `Marksman_1` | Locket | 12 |
| `Marksman_2` | Keepsake | 10 |
| `SniperRifle_3` | Scout's Honor | 10 |
| `SniperRifle_4` | Star Crossed | 10 |

### Sniper — 3 · ~4.0 studs

Bolt-action. Long barrels, heavy stocks.

| ID | Name | Magazine |
| --- | --- | --- |
| `SniperRifle_1` | Whisper | 5 |
| `SniperRifle_2` | Long Kiss | 4 |
| `SniperRifle_5` | Heartstopper | 6 |

### Pistol — 5 · ~1.5 studs

| ID | Name | Magazine |
| --- | --- | --- |
| `Pistol_1` | Pip | 12 |
| `Pistol_3` | Stiletto | 10 |
| `Pistol_4` | Pixie | 15 |
| `Pistol_5` | Jawbreaker | 8 |
| `Pistol_6` | Dolly | 14 |

### Revolver — 4 · ~1.7 studs

Visible cylinder — it rotates in game, so it must be its own part.

| ID | Name | Chambers |
| --- | --- | --- |
| `Revolver_1` | Heartbreaker | 6 |
| `Revolver_3` | Longing | 6 |
| `Revolver_4` | Smooch | 7 |
| `Revolver_5` | Drama Queen | 5 |

---

## A1. Separate named parts — the one that is not negotiable

Each weapon splits into parts with these **exact names**:

| Part | What it is | In game |
| --- | --- | --- |
| `Body` | The receiver | Takes the camo **texture** |
| `Panel` | Handguard, upper, large flat faces | Takes the camo **texture** |
| `Grip` | The grip | Takes the camo's **palette colour** |
| `Hardware` | Trigger, screws, sights, small metal | Takes the camo's **palette colour** |
| `Accent` | One feature part that gets its own colour | Takes the camo's **palette colour** |

A weapon needs **at least one of `Body`/`Panel`** and **at least one of
`Grip`/`Hardware`/`Accent`**. Most should have all five.

> **Do not merge parts to reduce part count.** The game paints each of these
> independently. A grip merged into the body gets textured along with the
> receiver, the colour layer underneath it disappears, and that weapon can no
> longer be skinned. This is the single most common way a model fails
> acceptance.

### Moving parts

Named separately and modelled free of the body, because the game animates them:

| Part | Motion in game |
| --- | --- |
| `Slide` | Blowback on each shot |
| `Bolt` | Reciprocates on each shot |
| `Pump` | Stroked between shells |
| `Cylinder` | Rotates one chamber per shot |
| `Mag` | Drops out and is replaced on reload |

Include the ones the weapon actually has — a revolver has no slide. **A part
that is not named does not move.**

---

## A2. Attachments — six per weapon, exact names

Roblox `Attachment` instances, not parts.

| Attachment | Where |
| --- | --- |
| `Muzzle` | End of the barrel, **pointing −Z** (forward, out of the bore) |
| `Grip` | Where the right hand closes |
| `EjectPort` | The ejection port, **pointing +X** (out of the port) |
| `LeftGrip` | Where the left hand rests — forend, or the magazine on a pistol |
| `Sight` | On the rail, at iron-sight height |
| `MagWell` | Where the magazine seats |

`Muzzle` and `EjectPort` use their **orientation**, not just position. Point
them the way the bullet and the shell actually leave.

### Mount points — please read this section twice

Add these wherever the weapon could physically take one:

`Mount_Optic` · `Mount_Barrel` · `Mount_Under` · `Mount_Laser` · `Mount_Stock` ·
`Mount_Charm`

**Each attachment in Part B is built once and must fit all 38 weapons.** That is
only possible if the mounts agree across the roster:

| Mount | Standard position |
| --- | --- |
| `Mount_Optic` | **0.22 studs above the bore centreline** |
| `Mount_Under` | **0.18 studs below the bore centreline** |
| `Mount_Laser` | **0.16 studs left of the bore centreline** |
| `Mount_Barrel` | **On the bore centreline**, at the muzzle end, concentric |
| `Mount_Stock` | **On the bore centreline**, at the rear of the receiver |
| `Mount_Charm` | No standard — decorative, place it where it hangs nicely |

The bore centreline is the axis through `Muzzle`. **If a weapon's rail is
physically taller than 0.22 studs, model the rail as geometry and still place
the socket at 0.22.**

Orientation matters as much as position: **+Y away from the weapon** (up out of
a top rail, down off an under-barrel), **−Z forward**. A mount rotated 90° puts
the optic on its side.

> If a mount ends up at a different height on some weapons, that weapon needs
> its own set of optics, which multiplies the attachment count by the roster.
> This one convention is the difference between 31 attachment models and
> hundreds.

---

## A3. Shared UV layout — `Body` and `Panel` only

Most weapon skins in the game are painted per weapon and need nothing here. Some
are **universal** — one texture that drops onto the entire roster — and those
need every weapon unwrapped identically.

`Body` and `Panel` are the only parts that receive a texture, so they are the
only ones that must agree. Both unwrap into a **single 1024 × 1024**:

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

- **Left half `Body`, right half `Panel`.** On every weapon, always.
- **Top row is the weapon's left side, bottom row its right side.**
- **Each quadrant filled edge to edge.** A short pistol receiver and a long LMG
  receiver both stretch to fill their quadrant. A camo is a *pattern*, not a
  decal, so stretching is correct — unwrapping each weapon at its own true
  scale is exactly what makes a universal texture impossible.
- **No mirroring.** Unwrap both sides independently so asymmetric patterns and
  text read correctly on both.
- Small hardware — trigger, screws, sights — does **not** need to be in this
  layout. Those parts take a flat colour and their UVs are unused.

---

## A4. Weapon poly budgets

Triangles per model, including nothing but the weapon itself.

| Class | Budget |
| --- | --- |
| Pistol, Revolver | 900 |
| SMG | 1,400 |
| Shotgun | 1,500 |
| Rifle, Battle rifle | 1,800 |
| Marksman | 1,900 |
| Sniper | 2,000 |
| LMG | 2,400 |

### Three LODs per weapon

| Distance | Requirement |
| --- | --- |
| 0–30 studs | Full model |
| 30–90 studs | ~50% of budget. Merge hardware, drop interior geometry |
| 90+ studs | ~25%. Silhouette only |

**The named parts from §A1 must survive at every LOD.** If a distant LOD merges
`Hardware` into `Body`, that weapon changes colour as the player walks away from
it.

---

# PART B — the ~31 attachments

Separate models, welded to the mount points above at runtime and hidden when not
equipped. Each one is built **once** and used on every weapon that has the
matching mount.

## The set

| Slot | ID | Name |
| --- | --- | --- |
| Optic | `IronSights` | Iron Sights |
| Optic | `RedDot` | Red Dot |
| Optic | `HoloSight` | Holo Sight |
| Optic | `Scope3x` | 3x Scope |
| Optic | `SniperScope` | Sniper Scope |
| Muzzle | `Suppressor` | Suppressor |
| Muzzle | `Compensator` | Compensator |
| Muzzle | `MuzzleBrake` | Muzzle Brake |
| Muzzle | `FlashHider` | Flash Hider |
| Barrel | `LongBarrel` | Long Barrel |
| Barrel | `ShortBarrel` | Short Barrel |
| Barrel | `HeavyBarrel` | Heavy Barrel |
| Barrel | `LightBarrel` | Light Barrel |
| Underbarrel | `VerticalGrip` | Vertical Grip |
| Underbarrel | `AngledGrip` | Angled Grip |
| Underbarrel | `Bipod` | Bipod |
| Underbarrel | `Handstop` | Handstop |
| Magazine | `ExtendedMag` | Extended Mag |
| Magazine | `FastMag` | Fast Mag |
| Magazine | `DrumMag` | Drum Mag |
| Magazine | `LightMag` | Light Mag |
| Stock | `HeavyStock` | Heavy Stock |
| Stock | `LightStock` | Light Stock |
| Stock | `NoStock` | No Stock |
| Stock | `PaddedStock` | Padded Stock |
| Rear grip | `QuickdrawGrip` | Quickdraw Grip |
| Rear grip | `AssaultGrip` | Assault Grip |
| Rear grip | `RubberGrip` | Rubber Grip |
| Laser | `SteadyLaser` | Steady Laser |
| Laser | `TargetLaser` | Target Laser |
| Laser | `TacticalLaser` | Tactical Laser |

## B1. Every attachment carries `Anchor`

An `Attachment` named `Anchor`, at the point that mates with the weapon's mount.

**Position and orientation are both used** — `Anchor` is aligned directly to the
mount frame, so **+Y points back into the weapon** and **−Z runs forward**.
There is no correction applied in code, deliberately. If `Anchor` is wrong, the
attachment mounts inside the receiver or upside down.

## B2. Every optic additionally carries `AimPoint`

An `Attachment` named `AimPoint`, at **the centre of the reticle, at the eye
relief the optic is meant to be used at**. This is where the player's camera
sits when aiming down the sight.

**This is the one thing here that cannot be fixed later.** Without it, aiming
looks through the side of the optic and there is no authored number to correct
it with. Every optic needs one — including `IronSights`, which is a real
attachment in this game rather than the absence of one.

## B3. Reserved names — do not use these inside an attachment

When an attachment is equipped it becomes part of the weapon, and the game finds
parts and attachments **by name**. An attachment containing a part named `Body`
would be treated as one of the weapon's skin regions; one containing an
`Attachment` named `Muzzle` would be treated as the weapon's muzzle.

**Never use, anywhere inside an attachment model:**

`Muzzle` · `Grip` · `EjectPort` · `LeftGrip` · `Sight` · `MagWell` · `Body` ·
`Panel` · `Hardware` · `Accent` · `Slide` · `Bolt` · `Pump` · `Cylinder` · `Mag`

Prefix parts with the attachment's own name instead — `Suppressor_Shell`,
`RedDot_Housing`, `Bipod_LegLeft`.

**One exception:** a suppressor or barrel that changes where the bullet leaves
the weapon carries an `Attachment` named **`MuzzleOverride`** — a distinct name,
so it is never confused with the weapon's own muzzle.

## B4. Attachments never take a camo

They keep their own materials permanently. That is what makes an assembled
weapon look built rather than shrink-wrapped.

The consequence for modelling: **an attachment is never partly finished.** There
is no skin layer coming later to cover a grey block. Author every one complete,
in the pink palette.

## B5. Attachment poly budgets

| Slot | Budget |
| --- | --- |
| Optic | 350 |
| Stock | 260 |
| Barrel | 250 |
| Muzzle | 220 |
| Magazine | 180 |
| Underbarrel | 150 |
| Rear grip | 100 |
| Laser | 90 |

The laser **beam** is a runtime effect, not geometry — model only the emitter.

### Two LOD steps per attachment

| Distance | Requirement |
| --- | --- |
| 30 studs | ~40%, merged to a single part |
| 90+ studs | **Hidden entirely**, except optics and muzzle devices, which drop to a silhouette block |

Optics and muzzle devices survive at distance because they change the weapon's
outline, and the outline is the only thing readable at 90 studs. A vertical grip
is not information at that range.

---

# Acceptance

We run an automated validator against every delivered model.

**For a weapon it checks:** all six `Attachment` sockets present with the exact
names; the named parts from §A1 surviving as separate parts; mount points at the
standard offsets; poly budget.

**For an attachment it checks:** `Anchor` present; `AimPoint` present on optics;
no reserved-name collisions; poly budget.

A model is accepted on a clean report. **Please validate a single model against
the attached reference models before producing a batch** — every failure mode
above is one that repeats across a whole delivery if it is wrong once.

## First delivery

Before the full roster, please deliver **one weapon and one optic** so we can
run them end to end. Suggested: `AssaultRifle_1` (Grump) and `RedDot`.

We will confirm both pass, and specifically that the same `RedDot` mounts
correctly on a second weapon — that is the check that proves the mount standard
in §A2 holds across the roster.
