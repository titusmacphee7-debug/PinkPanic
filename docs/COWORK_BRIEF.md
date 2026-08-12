# Pink Panic — weapon and attachment asset brief

**The job is sourcing, recolouring and labelling — not modelling from scratch.**

For each item below: find a suitable free 3D asset **of the real weapon named in
the table**, recolour it into the pink palette, split and name its parts to the
conventions here, and deliver it.

There are two stages, and only Stage 1 is in this brief:

| Stage | Who | What |
| --- | --- | --- |
| **1. Asset pass** | Cowork | Source, recolour, split and name parts. **This document.** |
| 2. Studio pass | Us | Add sockets and mount points, normalise scale, wire up in engine |

Nothing in Stage 1 requires Roblox. Deliver `.obj` + `.mtl` (or `.fbx`) with
named objects, and we do the rest.

---

## The one thing to get right

**Every weapon is a real gun.** The names are jokes; the models are not. When
the table says `Rifle_M4A1` / "Bestie", you are looking for a free **M4A1**
model. Search the archetype, never the name — "Bestie" will find you nothing.

The joke name matters for one reason only: it tells you the *character* to aim
for when two candidate models are both accurate. Between two M4s, take the one
that looks friendlier.

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

**Cute-pink.** Confectionery, toys, makeup and slumber-party — not military
hardware. The shape stays a real gun; everything about the finish does not.

There is **no grey-and-metal weapon in this game.** Recolour every asset into
the pink palette. Do not leave any part in a default grey, black or gunmetal on
the assumption something will cover it later — nothing will. Most of a weapon is
visible most of the time.

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

> **IDs are `Class_Archetype`.** `Rifle_M4A1`, `Sniper_M82`, `SMG_MP5`. The ID
> never changes even if we rename the gun, which is why it is the archetype and
> not the joke.

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

---

# 2. The 50 weapons

Lengths are the overall weapon length against a standard character (5'8", one
fixed size for every player, so consistent scale matters more than exact scale).

## Pistol — 5 · ~1.5 studs · **needs `Slide` and `Mag`**

| ID | Real gun | Name |
| --- | --- | --- |
| `Pistol_Glock17` | Glock 17 | Glitter 17 |
| `Pistol_M1911` | M1911 | Jawbreaker |
| `Pistol_DesertEagle` | Desert Eagle | Dessert Eagle |
| `Pistol_M9` | Beretta M9 | Barrette M9 |
| `Pistol_CZ75` | CZ-75 | Cozy 75 |

## Machine pistol — 3 · ~1.7 studs · **needs `Slide`/`Bolt` and `Mag`**

| ID | Real gun | Name |
| --- | --- | --- |
| `MachinePistol_TEC9` | TEC-9 | Yappy |
| `MachinePistol_MicroUzi` | Micro Uzi | Oozi |
| `MachinePistol_MAC10` | MAC-10 | Mac & Cheese |

## Revolver — 3 · ~1.7 studs · **needs `Cylinder` as its own object**

| ID | Real gun | Name |
| --- | --- | --- |
| `Revolver_Python` | Colt Python | Charm Python |
| `Revolver_SW500` | S&W 500 | Sweet & Wesson |
| `Revolver_Snub38` | Snub-nose .38 | Button Nose |

## SMG — 6 · ~2.2 studs

| ID | Real gun | Name |
| --- | --- | --- |
| `SMG_MP5` | MP5 | Mixtape 5 |
| `SMG_P90` | P90 | Pom-Pom 90 |
| `SMG_Vector` | KRISS Vector | Scribble |
| `SMG_Thompson` | Thompson | Teddy Gun |
| `SMG_MP7` | MP7 | Pipsqueak 7 |
| `SMG_UMP45` | UMP-45 | Bumper 45 |

## Shotgun — 5 · ~2.9 studs

| ID | Real gun | Name | Note |
| --- | --- | --- | --- |
| `Shotgun_M870` | Remington 870 | Thumper 870 | **needs `Pump`** |
| `Shotgun_DoubleBarrel` | Double-barrel | Double Trouble | break action |
| `Shotgun_Saiga12` | Saiga-12 | Sparkler 12 | mag-fed, needs `Mag` |
| `Shotgun_SawedOff` | Sawed-off | Shortcake | **the smallest** |
| `Shotgun_BenelliM4` | Benelli M4 | Bossy | semi-auto |

## Assault rifle — 8 · ~3.4 studs

The most-seen weapons in the game. Give these the most attention.

| ID | Real gun | Name |
| --- | --- | --- |
| `Rifle_M4A1` | M4A1 | Bestie |
| `Rifle_AK47` | AK-47 | cAKe-47 |
| `Rifle_SCARL` | SCAR-L | Buttercup |
| `Rifle_G36C` | G36C | Giggle 36 |
| `Rifle_FAMAS` | FAMAS | Tutu |
| `Rifle_AUG` | AUG | Hug |
| `Rifle_Galil` | Galil | Lunchbox |
| `Rifle_M16A4` | M16A4 | Tick Tock |

## Battle rifle — 3 · ~3.7 studs

| ID | Real gun | Name |
| --- | --- | --- |
| `BattleRifle_FAL` | FN FAL | Big Softie |
| `BattleRifle_G3` | HK G3 | Grumpy |
| `BattleRifle_M14` | M14 | Old Faithful |

## LMG — 4 · ~4.2 studs

The biggest weapons in the game. Visibly heavy.

| ID | Real gun | Name |
| --- | --- | --- |
| `LMG_M249` | M249 SAW | Seesaw |
| `LMG_RPD` | RPD | Chatterbox |
| `LMG_PKM` | PKM | Pillow Fight |
| `LMG_M60` | M60 | Tiny |

## Marksman — 4 · ~3.8 studs

Semi-automatic precision rifles. Long barrel, magazine-fed, scope-ready.

| ID | Real gun | Name |
| --- | --- | --- |
| `Marksman_SKS` | SKS | Nitpick |
| `Marksman_SVD` | Dragunov SVD | Peekaboo |
| `Marksman_Mk14` | Mk14 EBR | Slowpoke |
| `Marksman_SCARH` | SCAR-H | Hall Monitor |

## Sniper — 4 · ~4.0 studs · **bolt guns need a visible `Bolt`**

| ID | Real gun | Name |
| --- | --- | --- |
| `Sniper_M700` | Remington 700 | Night Night |
| `Sniper_Mosin` | Mosin-Nagant | Granny |
| `Sniper_M82` | Barrett M82 | Big Boo Boo |
| `Sniper_AWP` | AWP / L96 | Whisper |

## Launcher — 3 · ~3.5 studs

| ID | Real gun | Name |
| --- | --- | --- |
| `Launcher_RPG7` | RPG-7 | Lipstick Launcher |
| `Launcher_M79` | M79 | Bubble Blower |
| `Launcher_M32` | M32 MGL | Party Popper |

## Melee — 2

| ID | Real object | Name | Length |
| --- | --- | --- | --- |
| `Melee_Knife` | Combat knife | Butter Knife | ~0.9 studs |
| `Melee_Bat` | Baseball bat | Rolling Pin | ~2.4 studs |

---

# 3. Triangle ceilings

Sourced assets vary wildly. These are **rejection thresholds**, not targets — an
asset under them is fine at any count.

| Class | Ceiling |
| --- | --- |
| Pistol, Machine pistol, Revolver, Melee | 2,500 |
| SMG, Shotgun | 3,500 |
| Assault rifle, Battle rifle | 4,500 |
| Marksman, Sniper, Launcher | 5,000 |
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

One optic model serves all 50 weapons.

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

`Suppressor` · `Compensator` · `MuzzleBrake` · `FlashHider` · `BarrelExtender` ·
`Choke` *(shotguns only)*

### Barrel — 5

`LongBarrel` · `ShortBarrel` · `HeavyBarrel` · `LightBarrel` · `MatchBarrel`

### Underbarrel — 6

`VerticalGrip` · `AngledGrip` · `Handstop` · `Bipod` *(big weapons only)* ·
`LightGrip` · `Foregrip`

### Magazine — 6

`ExtendedMag` · `FastMag` · `DrumMag` · `LightMag` · `HeavyRounds` ·
`LightRounds`

### Stock — 5

`HeavyStock` · `LightStock` · `PaddedStock` · `TacticalStock` · `NoStock`
*(a stub or cap, not an empty file)*

### Rear grip — 5

`QuickdrawGrip` · `AssaultGrip` · `RubberGrip` · `StippledGrip` · `WeightedGrip`

### Laser — 4

`SteadyLaser` · `TargetLaser` · `TacticalLaser` · `Rangefinder`

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
- It is recognisably the real gun named in the table
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

**`Rifle_M4A1` (Bestie) and `RedDot`**, before any batch.

We will run both end to end and confirm the conventions work before you commit
to volume. Every failure mode above is one that repeats across an entire
delivery if it is wrong once, and one round trip on two assets is much cheaper
than one on fifty.

---

## Suggested order

Not binding, but this is the order we can use them in:

1. **Assault rifles (8)** — the game's face, and the class most players hold
2. **SMGs (6)** and **pistols (5)** — the next most-seen
3. **Shotguns (5)**, **snipers (4)**, **marksman (4)**
4. **Battle rifles (3)**, **LMGs (4)**
5. **Machine pistols (3)**, **revolvers (3)**, **melee (2)**
6. **Launchers (3)** — last; they are the least-used class
