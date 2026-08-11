# Pink Panic — Rebuild Design

Written 2026-08-11, immediately after wiping combat, weapons, movement and the
round loop. Read this before writing any code for those systems.

Nothing here is final. It is written to be argued with — the parts most likely
to be wrong are marked **OPEN** and listed again at the end.

---

## 1. What actually happened

A week of work produced a game that was never playable. It is worth being
precise about why, because the obvious explanation is wrong.

The obvious explanation is "too many systems built on each other." That was the
instinct behind the rewrite. But when the codebase was audited, the failures had
nothing to do with coupling. Three examples, all found on a single day:

| What broke | Why | What you saw |
|---|---|---|
| The entire procedural animation layer | Resolved joints with `IsA("Motor6D")`; the live rig uses `AnimationConstraint` | Characters never animated. No error. |
| All movement friction / skid | Gated on `PlayerModule`, which is not under `PlayerScripts` on the current character system | Instant stops, forever. No error. |
| 7 gun models incl. every sniper | Flip detection looked for a part named `Grip`; those models have none | Guns pointed backwards. No error. |

Every one is the same shape:

> a lookup returns nil → a guard quietly returns → an entire feature evaporates
> → the console says nothing.

A rewrite does not fix this. A rewrite produces new code with the same
blindness. **The disease is silent guessing, not architecture.**

There was a second failure alongside it. At the moment of the wipe, 22 Linear
issues were marked **Done** for code that no longer existed, while
"Make the game playable end-to-end" had sat **In Progress** the entire week. The
board tracked code written rather than game working, so there was no signal
anywhere — not in the console, not in the tracker — that the thing was broken.

---

## 2. Rules

These are the point of the rebuild. The systems below matter less than these.

1. **Fail loud.** Any system that cannot find what it needs warns with *what it
   looked for* and *what it found instead*. Silence is never an acceptable
   failure mode. If a feature can turn itself off, it must say so.
2. **Tag content, don't infer it.** `CLAUDE.md` already says Titus tags
   hand-built content — lobby pads, camera anchor, armory displays, the arena.
   Guns were the one place we inferred geometry instead of reading a tag, and
   guns are the one place that shipped broken.
3. **Verified in Studio, or not done.** Done means observed running: console
   output, or a measurement. Reading a `BUILD_TAG` out of a source file only
   proves Rojo synced it — if the module fails to compile, the print never runs
   and Output still shows the previous build.
4. **One playable thing at a time.** No system starts until the previous one is
   verified in a live session.
5. **No declared-but-unhandled remotes.** A remote with no handler is a silent
   hole by construction. Remotes are declared by the system that handles them,
   when it is built.

---

## 3. What survived the wipe

Still in the repo and still working:

- **Lobby** — `LobbyService`, `LobbyController`, `CameraController`, pads,
  the fixed anchor camera, balloon shooting
- **Economy** — coins, XP, levels, server-authoritative minting
- **Data** — `PlayerDataService`, `PlayerDataSchema`, profiles, persistence
- **Shop / Armory / Loadout** — purchase, ownership, equip, gun previews
- **Settings**
- **Content config** — `GunCatalog` (all 32 guns), `CombatStats`,
  `WeaponConfig`, `AttachmentConfig`, `GunSkinCatalog`
- **Model pipeline** — `GunModelLoader`, `WeaponModels`

Deleted, to be rebuilt: `CombatService`, `WeaponService`, `RoundService`,
`MovementStateService`, `WeaponController`, `ViewmodelController`,
`HitFeedbackController`, `MovementController`, `MovementAnimator`,
`HudController`, `RoundController`, `MovementConfig`.

Recover anything with:

```bash
git checkout pre-rewrite-2026-08-11 -- src/
```

Seams left behind are marked `REBUILD` in-line. Grep for it.

---

## 4. The content contract

**This is the highest-value item in the document.** It is the fix for the whole
class of bug above, and it costs Titus about an hour once.

Gun orientation is currently *inferred* from geometry: find a part named `Grip`,
decide the model is reversed, place a muzzle at one end of the bounding box.
Three guesses in a row, none of which look at the actual barrel, and no error
when any of them is wrong.

Replace all of it with a tag:

> **Every gun model in `ReplicatedStorage/GunModels` gets an `Attachment` named
> `Muzzle`, placed by hand at the barrel tip, pointing down the barrel.**

Then:

- The loader **reads** the muzzle instead of computing one.
- Gun forward is `Muzzle.WorldCFrame.LookVector`. Nothing else is guessed.
- Any model missing a `Muzzle` produces a loud startup warning naming the model,
  and falls back to a part-built placeholder so a bad import can never silently
  ship a backwards weapon.
- New guns work on import with no code change.

Measured state as of the wipe: 32 models, `PrimaryPart` inconsistent
(`Body` / `Hardware` / `Grip`), and 7 models with no `Grip` or `Mag` part at all
(`SniperRifle_1`–`5`, `Revolver_5`, `Shotgun_1`) which is exactly the set that
was never flipped.

**OPEN:** whether Titus places 32 muzzle attachments by hand, or we write a
one-shot Studio script that places a best guess he then nudges. The second is
faster but reintroduces a guess — though a *visible* one he corrects, which is
categorically different from a hidden one.

---

## 5. Movement

### Target

Call of Duty Omnimovement, tuned for readability. Fast and expressive on the
ground, near-passive in the air. Omnidirectional means sprinting, sliding and
diving **in any direction on the ground** — it has nothing to do with air
control.

The audience is average Roblox players, explicitly including people who bounced
off movement-heavy shooters. The design constraint that follows:

> Speed is earned on the ground and spent in the air.
> The air gives you direction, never speed.

Air-strafe acceleration and bunny-hop chaining are permanently out. They hand a
small number of players unbounded speed and mid-air direction changes nobody can
lead. That is the single biggest reason an average player quits a shooter.

### Architecture — proven, not proposed

All of this was measured live in Studio on 2026-08-11 before the wipe:

- **`Humanoid` is a sensor, not a mover.** `WalkSpeed = 0`. Its mover has no
  acceleration curve, no friction and no air model, and that instant snap is the
  clunk itself.
- **Drive with a `LinearVelocity` constraint** in `Plane` mode on world X/Z.
  Y is untouched, so gravity, jump arcs and ragdolls stay stock.
  *Measured: commanded 45, achieved mean 43.88.*
- **Input from `Humanoid.MoveDirection`**, which keeps reporting camera-relative
  player input at `WalkSpeed = 0`. *Measured: 1.000.* No `PlayerModule`
  dependency, which is what killed the last one.
- **Source-derived accel/friction on the ground.**
  *Measured: 0 → 20.4 studs/s in ~0.15s; release decays 19.6 → 6.5 → 0 in ~0.3s.*
  These ramps make players **easier** to hit than the old instant snaps, because
  instant direction changes are the hardest thing for a human to track.
- **Air ceiling locked on takeoff.** *Measured: takeoff 30.73, max airborne
  30.74 across 261 frames while deliberately strafing — gain +0.01.*

**Use `MaxForce` proportional to mass, not `math.huge`.** Infinite force holding
a character inside geometry is the reported "you get flung by the cart" bug —
depenetration has to go somewhere and it goes vertical.

### Feature list

| Feature | Notes |
|---|---|
| Omnidirectional walk / sprint | Sprint in any direction |
| Slide | Steerable, telegraphed, committal. Blocked in the lobby (fixed camera) |
| Jump | Coyote time + jump buffer. Invisible to opponents, pure forgiveness |
| Crouch | |
| Dive | **OPEN** — signature Omnimovement move, needs a pose. Not in M1 |

### Known open bug

Sliding was blocked in the lobby at Titus's request (the fixed anchor camera
makes a carved slide read as skating). But solo Studio sessions are *always*
lobby, so slides became untestable alone. **OPEN:** either allow slides in the
lobby for testing, or accept that slide testing needs `Test → 2 Players`.

---

## 6. Weapons

### What already exists and should not be rebuilt

The weapon *data* layer is good and survived. Per-gun, across all 32:

- `equipTime` — pull-out, 0.16s (pistol) to 0.4s (LMG)
- `sprintToFire`
- `adsTime`
- `moveSpeedMult` — per-gun weight
- damage / falloff / velocity / recoil / spread / mag / reload

Already resolved through `CombatStats` and already displayed in the armory. The
handling-time design Titus wanted is **already the architecture** — it just
never had a working weapon system underneath it.

### To build

1. **Model pipeline** — `GunModelLoader` reads the `Muzzle` tag (§4), welds,
   applies cosmetics. Loud warning on any untagged model.
2. **Server weapons** — ownership, loadout resolution, equip/holster timing.
   All from the profile, never from client input.
3. **Server ballistics** — muzzle velocity + gravity drop, segment raycasts on
   Heartbeat, two-point falloff, damage accumulated per victim per frame so a
   shotgun lands as one hit event. The client never reports a hit.
4. **Client prediction** — viewmodel, firing input, recoil, tracers.
5. **Recoil** — **no bloom**, permanently. Fixed per-gun cone (`spreadDeg` hip,
   `adsSpreadDeg` aimed) that never grows; the *camera* climbs instead.

### Order of work

Build **one gun end to end** — `Pistol_1`, which is already correctly oriented —
and do not touch the other 31 until two players can kill each other with it.
The last attempt built the framework for 32 guns before one gun worked.

---

## 7. Animation

### What we learned

The character rig uses **`AnimationConstraint`**, not `Motor6D`. The C0
analogue is `Attachment0.CFrame` (the parent-side rig attachment). Verified:
identical sign convention (+0.436 rad in → +0.436 rad out), and translation
applies despite `MaxForce` being 0.

`Transform` is owned by the Animator on both rig generations. Writing it is
overwritten every frame — which is exactly what lets keyframe clips and a
procedural layer compose instead of fight. **Animations own `Transform`; we own
the joint base.** Keyframed clips and procedural layers are not an either/or.

### The actual gap

There is **no stride cycle**. There never was. The old system had lean, bob,
slide, crouch and air poses, but nothing ever swung a hip or bent a knee. Legs
were frozen at every speed.

This is the single biggest reason the game "feels like a 5th grader made it,"
and it is worth more than any movement tuning. Omnidirectional sprint is
meaningless visually until strafing and backpedalling animate differently from
running forward.

### Plan

1. **Procedural stride cycle first** — phase accumulator driven by actual
   velocity, feeding hips/knees/shoulders/elbows. Scales with any speed, never
   desyncs from how fast you are really moving, no export step.
2. **Directional blending** — forward / strafe / backpedal read differently.
   This is what sells Omnimovement.
3. **Keyframe clips after**, for one-shots where procedural is weak: reload,
   inspect, dive.

**OPEN:** Titus asked for a Moon Animator 2 settings and timing sheet. Still
owed. It becomes relevant at step 3, not before.

---

## 8. Milestones

Each is verified in a live Studio session before the next starts.

**M1 — Two players shoot each other.**
One gun (`Pistol_1`). Server ballistics, server damage, death, respawn, a score.
Movement is stock Humanoid — deliberately, so combat is not debugged through a
half-built movement system. Ugly is fine. *Done = two clients, one kills the
other, score increments.*

**M2 — It feels good to move.**
The velocity controller from §5. Walk, sprint, slide, jump with coyote and
buffer. Tuned with Titus's hands, not measurements alone.

**M3 — It looks like a game.**
Stride cycle and directional blending. Viewmodel, muzzle flash, tracers, hit
feedback.

**M4 — The other 31 guns.**
Muzzle tags on every model. Loadout, armory try-gun, cosmetics, balance.

**M5 — The round loop.**
State machine, timer, win condition, scoreboard, results, payouts. START GAME
works again.

Note that M5 is last. The round loop was among the first things built last time
and it framed everything after it, while the thing it framed did not work.

---

## 9. Open decisions

Listed together so they are easy to answer:

1. **Muzzle tags** — Titus places 32 by hand, or a script places a guess he
   corrects? (§4)
2. **Slides in the lobby** — allow for solo testing, or require 2-player tests?
   (§5)
3. **Dive** — in scope, and at which milestone? (§5)
4. **Moon Animator sheet** — still owed; needed at M3/step 3 or earlier? (§7)
5. **Studio API access** — DataStores are off, so nothing saves in Studio and
   every session runs on an ephemeral profile. Worth turning on before M4.
6. **Stock Humanoid movement during M1** — confirm this is acceptable. It means
   M1 will feel bad on purpose, so combat can be verified in isolation.
