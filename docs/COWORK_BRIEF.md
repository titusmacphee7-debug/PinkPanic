# Pink Panic — weapon and attachment asset brief

**The job is sourcing, recolouring and labelling — not modelling from scratch.**

For each item below: find a suitable free 3D asset, recolour it into the pink
palette, split and name its parts to the conventions here, and deliver it.

There are two stages, and only Stage 1 is in this brief:

| Stage | Who | What |
| --- | --- | --- |
| **1. Asset pass** | Cowork | Source, recolour, split and name parts. **This document.** |
| 2. Studio pass | Us | Add sockets and mount points, normalise scale, wire up in engine |

Nothing in Stage 1 requires Roblox. Deliver `.obj` + `.mtl` (or `.fbx`) with
named objects, and we do the rest.

---

## Licensing — before anything else

Every asset must be **usable in a commercial game**. This game is monetised.

- CC0 / public domain — fine, no conditions
- CC-BY — fine, but we must credit; record the required attribution
- CC-BY-NC or "non-commercial" — **not usable**
- "Free" asset-pack downloads — check the actual licence text, not the word
  "free" on the download button

**Deliver a licence line with every asset**: source URL, licence, and the
attribution string if one is required. An asset without this cannot ship, and
finding that out after it is in the game is expensive.

---

## Art direction

**Cute-pink.** Confectionery, stationery and toys — not military hardware.

There is **no grey-and-metal weapon in this game.** Recolour every asset into
the pink palette. Do not leave any part in a default grey, black or gunmetal on
the assumption something will cover it later — nothing will. Most of a weapon is
visible most of the time.

The names are the strongest steer on character. *Marshmallow* should read soft
and rounded, *Jawbreaker* heavy and blunt, *Stiletto* thin and sharp,
*Rolling Pin* comically chunky. Pick source assets whose silhouette already
suits the name — that choice matters more than the recolour.

### Palette

Pinks and creams, with a small amount of contrast so shapes read. Warm mid-pink
bodies, cream or white panels, deeper rose for grips, soft gold or pearl for
small hardware, and one saturated accent per weapon.

Avoid pure black and pure white — they flatten in Roblox lighting.

---

## Delivery

| | |
| --- | --- |
| Format | `.obj` + `.mtl`, or `.fbx` |
| **File name** | **Exactly the ID from the tables below.** Not the display name |
| Object names | The part names in §1. This is the part that matters most |
| Orientation | Weapon points down **−Z**, up is **+Y**, right is **+X** |
| Origin | At the **grip**, not the geometric centre |
| Scale | Roughly the length given per class. We normalise precisely in Stage 2 |
| Triangles | Under the ceiling per class in §3 — **reject assets over it** |

> **File names are IDs, not display names.** The asset for the rifle called
> *Grump* is the file `AssaultRifle_1`. Some IDs no longer describe the weapon —
> `SniperRifle_4` is a **marksman rifle** called *Star Crossed*, `Bullpup_1` is a
> **battle rifle** called *Marshmallow*. Build to the **Class** column, name the
> file with the **ID** column.

---

# 1. Part naming — the single most important requirement

Split each weapon into separate named objects. The game colours and animates
each one independently, so a part that is not split cannot be coloured or moved.

### Skin regions — every weapon needs these

| Object name | What it is |
| --- | --- |
| `Body` | The receiver — the main mass of the weapon |
| `Panel` | Handguard, upper, barrel shroud, any large secondary surface |
| `Grip` | The grip the hand wraps |
| `Hardware` | Trigger, screws, sights, hinges, small fittings |
| `Accent` | One feature part that gets its own colour — a charm, a stripe, a cap |

A weapon needs **at least one of `Body`/`Panel`** and **at least one of
`Grip`/`Hardware`/`Accent`**. Aim for all five.

> **Do not merge parts to reduce object count.** This is the single most common
> way an asset fails acceptance. Each region gets its own colour and material in
> game; a grip merged into the body cannot be coloured separately, and that
> weapon can never be skinned properly.
>
> If a sourced asset comes as one solid mesh, it needs splitting. If it cannot
> be split cleanly, **pick a different asset** — a well-separated mediocre model
> is worth more to us than a beautiful welded one.

### Moving parts — where the weapon has them

Named separately and modelled free of the body, because the game animates them:

| Object name | Motion in game |
| --- | --- |
| `Slide` | Blowback on each shot — pistols |
| `Bolt` | Reciprocates on each shot — rifles, SMGs, snipers |
| `Pump` | Stroked between shells — pump shotguns |
| `Cylinder` | Rotates one chamber per shot — revolvers |
| `Mag` | Drops out and is replaced on reload — magazine-fed weapons |

Include the ones the weapon actually has. **A part that is not named does not
move.**

### Do not use these names

Anything not in the lists above should have a descriptive name of its own —
`Barrel_Shroud`, `Stock_Cheek`. Avoid inventing new one-word names that could
collide with the reserved list in §6.

---

# 2. The 38 weapons

Lengths are the overall weapon length against a standard character. All players
are one fixed size, so consistent scale matters more than exact scale.

### SMG — 4 · ~2.2 studs
Compact, high rate of fire. Should read *fast* and light.

| ID | Name | Magazine | Notes |
| --- | --- | --- | --- |
| `SubmachineGun_1` | Chatterbox | 30 | The plain one — the class baseline |
| `SubmachineGun_2` | Bubbler | 32 | Chunkier, heavier-looking |
| `SubmachineGun_3` | Zoomie | 28 | Smallest and sleekest in the class |
| `SubmachineGun_4` | Jitterbug | 25 | Stubby, aggressive |

### Shotgun — 5 · ~2.9 studs
Wide-bore barrels. Pump or break action.

| ID | Name | Capacity | Notes |
| --- | --- | --- | --- |
| `Shotgun_1` | Big Boop | 6 | Classic pump |
| `Shotgun_3` | Homemaker | 5 | Widest, friendliest, most domestic |
| `Shotgun_4` | Double Trouble | 8 | Double-barrel or semi-auto |
| `Shotgun_ShortStock` | Scrunchie | 7 | Pump with a short stock |
| `Shotgun_SawedOff` | Shortcake | 2 | **Sawn-off — noticeably the smallest** |

### Rifle — 7 · ~3.4 studs
The most-seen weapons in the game. Give these the most attention.

| ID | Name | Magazine | Notes |
| --- | --- | --- | --- |
| `AssaultRifle_1` | Grump | 30 | The default weapon — the game's face |
| `AssaultRifle_2` | Gumdrop | 30 | Rounder, softer |
| `AssaultRifle_3` | Cherry Bomb | 30 | Precise, tidy |
| `AssaultRifle_4` | Picnic Punch | 24 | Heavier, bigger receiver |
| `AssaultRifle2_1` | Sweet Talker | 28 | Lightest rifle — nearly SMG-sized |
| `AssaultRifle2_3` | Sprinkler | 40 | **Visibly large magazine** |
| `AssaultRifle2_4` | Chunky | 30 | Thick, blocky |

### Battle rifle — 2 · ~3.7 studs
Longer and heavier than a rifle. More barrel, bigger receiver.

| ID | Name | Magazine | Notes |
| --- | --- | --- | --- |
| `Bullpup_1` | Marshmallow | 24 | Soft, rounded, pillowy |
| `Bullpup_2` | Toastie | 20 | Longest barrel of the two |

### LMG — 4 · ~4.2 studs
The biggest weapons in the game. Belt or drum feed, visibly heavy.

| ID | Name | Capacity | Notes |
| --- | --- | --- | --- |
| `LMG_1` | Big Sister | 100 | Box magazine |
| `LMG_2` | Rolling Pin | 150 | **Belt-fed, comically chunky** |
| `LMG_3` | Slumber Party | 80 | Smallest LMG, tidier |
| `LMG_4` | Cupcake Cannon | 125 | **Drum magazine** |

### Marksman — 4 · ~3.8 studs
Semi-automatic precision rifles. Long barrel, magazine-fed, scope-ready.

| ID | Name | Magazine | Notes |
| --- | --- | --- | --- |
| `Marksman_1` | Locket | 12 | Smallest, quickest-looking |
| `Marksman_2` | Keepsake | 10 | Ornate, heirloom |
| `SniperRifle_3` | Scout's Honor | 10 | Practical, scouty |
| `SniperRifle_4` | Star Crossed | 10 | Elegant, long |

### Sniper — 3 · ~4.0 studs
Bolt-action. Long barrels, heavy stocks. **Must have a visible `Bolt`.**

| ID | Name | Capacity | Notes |
| --- | --- | --- | --- |
| `SniperRifle_1` | Whisper | 5 | Slim, quiet-looking |
| `SniperRifle_2` | Long Kiss | 4 | **Longest weapon in the game** |
| `SniperRifle_5` | Heartstopper | 6 | Most ornate — the flagship |

### Pistol — 5 · ~1.5 studs
**Must have a visible `Slide` and `Mag`.**

| ID | Name | Magazine | Notes |
| --- | --- | --- | --- |
| `Pistol_1` | Pip | 12 | The starter — simple and friendly |
| `Pistol_3` | Stiletto | 10 | Thin, sharp, elegant |
| `Pistol_4` | Pixie | 15 | Small, fast, machine-pistol-ish |
| `Pistol_5` | Jawbreaker | 8 | **Hand cannon — heavy and blunt** |
| `Pistol_6` | Dolly | 14 | Compact, cute, snub |

### Revolver — 4 · ~1.7 studs
**Must have a visible `Cylinder` as its own object** — it rotates in game.

| ID | Name | Chambers | Notes |
| --- | --- | --- | --- |
| `Revolver_1` | Heartbreaker | 6 | Classic |
| `Revolver_3` | Longing | 6 | Long barrel |
| `Revolver_4` | Smooch | 7 | Snub, quick |
| `Revolver_5` | Drama Queen | 5 | **Biggest, most theatrical** |

---

# 3. Triangle ceilings

Sourced assets vary wildly. These are **rejection thresholds**, not targets — an
asset under them is fine at any count.

| Class | Ceiling |
| --- | --- |
| Pistol, Revolver | 2,500 |
| SMG | 3,500 |
| Shotgun | 3,500 |
| Rifle, Battle rifle | 4,500 |
| Marksman, Sniper | 5,000 |
| LMG | 6,000 |
| Any attachment | 1,200 |

If a good asset is over its ceiling, decimate it rather than discarding it —
these are stylised weapons at small screen size and detail is not the point.

**No LODs needed.** Roblox generates them.

---

# 4. The attachments

Same rules: source, recolour, split, name. Delivered as separate assets — each
one is used on **every weapon that accepts it**, so it is built once.

### Optics — 6, and they are universal

One optic model serves all 38 weapons.

| ID | Name | Notes |
| --- | --- | --- |
| `IronSights` | Iron Sights | The default. Small front post and rear notch |
| `RedDot` | Red Dot | Small tube or open frame |
| `HoloSight` | Holo Sight | Squarer window, larger glass |
| `Scope2x` | 2x Scope | Short scope |
| `Scope4x` | 4x Scope | Longer scope |
| `SniperScope` | Sniper Scope | Longest, biggest glass |

> **Every optic with glass needs its lens as a separate object named `Lens`.**
> The reticle is applied to that surface in game, and players choose from a set
> of cutesy reticles — hearts, stars, paw prints. Without a named `Lens` there
> is nowhere to put it.

### Muzzle — 6

| ID | Name |
| --- | --- |
| `Suppressor` | Suppressor |
| `Compensator` | Compensator |
| `MuzzleBrake` | Muzzle Brake |
| `FlashHider` | Flash Hider |
| `BarrelExtender` | Barrel Extender |
| `Choke` | Choke *(shotguns only)* |

### Barrel — 5

| ID | Name |
| --- | --- |
| `LongBarrel` | Long Barrel |
| `ShortBarrel` | Short Barrel |
| `HeavyBarrel` | Heavy Barrel |
| `LightBarrel` | Light Barrel |
| `MatchBarrel` | Match Barrel |

### Underbarrel — 6

| ID | Name |
| --- | --- |
| `VerticalGrip` | Vertical Grip |
| `AngledGrip` | Angled Grip |
| `Handstop` | Handstop |
| `Bipod` | Bipod *(big weapons only)* |
| `LightGrip` | Light Grip |
| `Foregrip` | Foregrip |

### Magazine — 6

| ID | Name |
| --- | --- |
| `ExtendedMag` | Extended Mag |
| `FastMag` | Fast Mag |
| `DrumMag` | Drum Mag |
| `LightMag` | Light Mag |
| `HeavyRounds` | Heavy Rounds |
| `LightRounds` | Light Rounds |

### Stock — 5

| ID | Name |
| --- | --- |
| `HeavyStock` | Heavy Stock |
| `LightStock` | Light Stock |
| `PaddedStock` | Padded Stock |
| `TacticalStock` | Tactical Stock |
| `NoStock` | No Stock *(a stub or cap, not an empty file)* |

### Rear grip — 5

| ID | Name |
| --- | --- |
| `QuickdrawGrip` | Quickdraw Grip |
| `AssaultGrip` | Assault Grip |
| `RubberGrip` | Rubber Grip |
| `StippledGrip` | Stippled Grip |
| `WeightedGrip` | Weighted Grip |

### Laser — 4

| ID | Name |
| --- | --- |
| `SteadyLaser` | Steady Laser |
| `TargetLaser` | Target Laser |
| `TacticalLaser` | Tactical Laser |
| `Rangefinder` | Rangefinder |

**Model the emitter only** — the beam is a runtime effect, not geometry.

**43 attachments in total.** Not every weapon accepts every one — a shotgun does
not take a bipod — but compatibility is decided in code, not in the model. Build
each attachment once.

---

# 5. Attachment part naming

Simpler than the weapons. Each attachment splits into:

| Object name | What it is |
| --- | --- |
| `<Name>_Body` | The main mass — e.g. `Suppressor_Body`, `RedDot_Body` |
| `<Name>_Detail` | Secondary surfaces, mounts, clamps |
| `Lens` | **Optics only** — the glass surface the reticle goes on |

Attachments are coloured as a unit rather than region by region, so they need
far less splitting than a weapon. `Lens` is the one that genuinely matters.

---

# 6. Reserved names — do not use these anywhere in an attachment

When an attachment is equipped it becomes part of the weapon, and the game finds
objects **by name**. An attachment containing an object named `Body` would be
treated as one of the weapon's skin regions.

**Never use inside an attachment:**

`Body` · `Panel` · `Grip` · `Hardware` · `Accent` · `Slide` · `Bolt` · `Pump` ·
`Cylinder` · `Mag` · `Muzzle` · `EjectPort` · `LeftGrip` · `Sight` · `MagWell`

This is why attachment parts are prefixed with the attachment's own name.
`Lens` is the single permitted exception, and only on optics.

---

# 7. Acceptance

Every delivered asset is run through an automated validator. It reports, per
item, exactly what is missing.

**A weapon is accepted when:**
- The named regions are present as separate objects
- Its moving parts are present and separate
- It is under the triangle ceiling for its class
- Nothing is left grey, black or gunmetal
- The licence line is supplied

**An attachment is accepted when:**
- Parts are prefixed with its own name
- Optics have a separate `Lens`
- No reserved-name collisions
- Under 1,200 triangles
- The licence line is supplied

## Please deliver two items first

**`AssaultRifle_1` (Grump) and `RedDot`**, before any batch.

We will run both end to end and confirm the conventions work before you commit
to volume. Every failure mode above is one that repeats across an entire
delivery if it is wrong once, and one round trip on two assets is much cheaper
than one on forty.
