# Pink Panic

A cute-pink FFA shooter for Roblox. Built by Titus with Leah. Work is tracked in
Linear (team **Nodewell**, `NOD-` prefix, projects "Pink Panic — MVP" and
"Post-MVP").

## Who does what

Claude writes and pushes code. Titus does everything Studio-side — importing
models, building the lobby and maps, playtesting — and reports how things
*feel*. When something needs to happen inside Studio, hand him either a Command
Bar script or precise Explorer steps; don't assume the place file changed.

**The place file is not in git.** Only `src/`, `docs/`, and the Rojo config are.
Models, maps, the lobby build, and anything in `ReplicatedStorage/GunModels`
live in Titus's local `.rbxl` and cannot be read or edited from a cloud session.

## Layout

Rojo 7.7 syncs three trees (see `default.project.json`):

| Repo | Studio |
|---|---|
| `src/server` | `ServerScriptService/Server` |
| `src/client` | `StarterPlayerScripts/Client` |
| `src/shared` | `ReplicatedStorage/Shared` |

Titus runs `.\rojo.exe serve` from the project folder in PowerShell.

- `src/server/Services/*` — one service per concern, each with `init()`, all
  called from `src/server/init.server.luau`. Order matters.
- `src/client/Controllers/*` — same pattern, client side.
- `src/client/UI/*` — `Theme.luau` holds every colour, font, radius and spacing
  value. Nothing else calls `Color3.fromRGB` for chrome.
- `src/shared/Config/*` — **data only, no behavior.** A config file containing
  an `if` is in the wrong folder. `GunCatalog.luau` is the single balance file;
  `Rarity.luau` is the one definition of the eight tiers.
- `src/shared/Systems/*` — deterministic logic both sides run, plus the
  infrastructure that keeps the project honest: `Diagnostics` (boot manifest),
  `AssetTree` (Studio folders), `ContentAudit` (config vs content).
- `src/shared/Loaders/*` — code that pulls content out of the place file.
  Named `Loaders`, not `Assets`, because `ReplicatedStorage/Assets` is the
  content itself and two folders called Assets meaning opposite halves of the
  same feature is exactly the confusion this rebuild is removing.
- `src/shared/Net/Remotes.luau` — **every** remote is declared here, nowhere
  else, each with its direction. `Guard.luau` does rate limiting and argument
  validation.

### Where content lives in Studio

`AssetTree.luau` declares the tree and **creates it at boot**, so the folder for
a feature exists before the feature does. Every folder carries a `Purpose`
attribute — select it in Studio and Properties tells you what belongs in it.

```
ReplicatedStorage/Assets/    Camos Outfits Charms KillEffects Tracers
                             Emotes Titles NameTags
                             Guns Attachments Viewmodel Effects
                             Audio/{Weapons,Impacts,UI,Music}
ServerStorage/               Streaks Templates Maps
```

It **only ever creates** — never deletes, moves or renames. The place file is
not in git, so anything destroyed there is gone. Misplaced content is reported,
not relocated. Run `AssetTree.ensure()` in **Edit** mode to persist the folders
into the saved place; at runtime they are rebuilt each boot and vanish with the
session.

### The five structural rules

1. **`shared/Config` is data.** A config file containing an `if` is wrong.
2. **`shared/Systems` owns every shared answer.** Client and server never
   compute the same number twice — they call the same resolver.
3. **Dependency direction is Service → Systems → Config.** A Config requires
   nothing but Config. A cycle is a bug.
4. **An asset folder name IS its config id.** `ContentAudit` checks both
   directions at boot: a config id with no asset is an item that is buyable and
   invisible; an asset with no config id is work the game will never show.
5. **Every remote is declared by the system that handles it**, never declared
   without a handler. Both boot assertions enforce this.

## Rules that aren't negotiable

- `--!strict` everywhere.
- **Absolute server authority.** The client predicts and animates; the server
  decides. Damage is computed server-side from server-simulated projectiles —
  the client never reports a hit.
- Every remote handler validates through `Guard` and rate-limits.
- Gun trials must never grant ownership. No glitch path to a free gun.
- Loadout changes are lobby-only.
- All purchases and ownership are server-derived from the profile, never from
  anything the client sends.

## Combat model

Server-side ballistics: per-gun muzzle velocity plus gravity drop, stepped as
segment raycasts on Heartbeat. Two-point COD-style falloff (`damageNear` /
`damageFar` over `rangeNear` / `rangeFar`), `travelMax = rangeFar * 1.6`.
Damage accumulates per victim per frame, so a shotgun lands as one hit event
rather than eight.

**Recoil has no bloom.** Bloom feels terrible and Titus vetoed it. Spread is a
fixed per-gun cone that never grows — `spreadDeg` hip, `adsSpreadDeg` aimed —
and the *camera* climbs instead (`recoilVert` / `recoilHoriz` /
`recoilRecovery`). `WeaponController.RECOIL_SCALE` is the master volume;
per-gun ceilings derive from each gun's own stats so a pistol and an LMG don't
share a cap. Target audience is new players: recoil should be readable and
learnable, never a fight.

## Render step ordering

Several systems write the camera every frame. They are chained deliberately —
breaking this order causes jitter that looks like a physics bug.

**`client/Camera/CameraRig.luau` owns every camera `BindToRenderStep`.** Ask it
for a slot; never pick a priority yourself:

```lua
CameraRig.claim("Aim", "WeaponController", stepRecoil)
```

```
PinkPanicMovement      Input+1   (after Roblox's control script, which
                                  writes MoveDirection at Input)
engine Camera (200)
  → Base        +1   PinkPanicCamera      the shot itself
  → Aim         +2   PinkPanicAim         recoil, always a delta
  → Effects     +3   PinkPanicSlideRoll   roll, dive tilt, landing dip, FOV
  → Viewmodel   +4   PinkPanicViewmodel   the gun (M11, unclaimed)
                Last-1  PinkPanicCameraAudit
  → MouseUnlock Last  PinkPanicMouseUnlock
```

The rig records what it wrote and checks at `Last-1` that the camera still says
that. Anything writing the camera outside the chain warns by name after half a
second of drift — verified by planting a rogue writer at Camera+5, which was
caught at 0.35 studs. This catches the SYMPTOM, not the syntax, so it works for
a plugin or a system nobody has written yet.

Camera tuning lives in `shared/Config/CameraConfig.luau` — all of it, including
the slide lean, which is caused by a movement state but is not a movement number.

Never bind at exactly `Input`: that is where Roblox's own control script lives,
and sharing a priority leaves the order down to whoever registered first —
which shows up as a frame of input lag that comes and goes between sessions.

## Animation

Procedural, not keyframed — Moon Animator was tried and abandoned. 11 Motor6D
joints, layered pose solver in `MovementAnimator.luau`. Animations own
`Transform`; we own `C0`. A limb bending the wrong way is a one-number flip in
the `SIGNS` table, not a rewrite.

Gun models are split into moving parts named `Slide`, `Bolt`, `Pump`,
`Cylinder`, `Mag` (on top of skin regions `Body` / `Panel` / `Grip` /
`Hardware` / `Accent`). `ViewmodelController` cycles them: slide blowback,
pump strokes, cylinder notches, mag drops on reload. Shells eject from the
real port and settle on the ground, then anchor — zero ongoing physics cost.

## Attribute conventions

Titus tags hand-built content instead of us generating it:

- Lobby pads: `PadName`, `PadAction` (`shop` / `loadout` / `portal`), `PadRadius`
- `CameraAnchor` part inside `workspace.Lobby`, with `MaxYawDeg` / `MaxPitchDeg`
- Armory displays: `GunDisplay`, `ArmoryMat`
- Arena: a Workspace folder named exactly `Arena`, `ArenaOrigin` attribute
- Runtime movement state: `PPMoveState`, the state machine's state by name —
  read this one. `PPSprinting` / `PPCrouching` / `PPProne` / `PPSliding` are the
  older booleans, kept because things are written against them.

## Hard-won gotchas

**Read Studio's console before anything else.** With the Studio MCP connected,
`get_console_output` is the first call of the session — not a fallback. On
2026-08-10 a single parse error in `LobbyService` (`(Vector3, Vector3)?`, which
Luau does not allow) had kept the *entire server dead* since commit `a09307c`:
no round loop, no combat, no lobby camera, no cursor release, no pads. Every
"separate bug" reported for days was that one dead server. The console said so
in one line.

**Never write source files with PowerShell.** `Set-Content -Encoding utf8` in
Windows PowerShell 5.1 does two things at once that both break Luau: it writes a
**UTF-8 BOM**, which Luau rejects outright (`Expected identifier when parsing
expression, got Unicode character U+feff`), and a `Get-Content -Raw | Set-Content`
round-trip **double-encodes every non-ASCII character** (`—` becomes `â€”`,
`⚠️` becomes `âš ï¸`). This codebase is full of em dashes and emoji, so the damage
is immediate and spread across the file. Use the Edit/Write tools, which handle
UTF-8 correctly. PowerShell is for git and processes, not for source.

**`execute_luau` has its OWN require cache.** A module you `require` from an
MCP script is a *different instance* from the one the game's scripts are
running — its `init()` never ran, so nothing it connected to `Heartbeat`,
`PlayerAdded` or a remote exists. The proof is one line:
`Diagnostics.snapshot()` from an MCP script returns the systems *that script*
touched, not the fourteen in the manifest. This looks exactly like "the system
is dead" and is not. Test a system by calling its functions directly and
driving its step function by hand — which is also why `Ballistics.step(dt)` is
public rather than only reachable through `Heartbeat`.

**Rojo syncs into the Edit DataModel, not a running Play session.** If a fix
"didn't work," check whether Studio was in Play mode when the file changed —
Play holds a snapshot from when it started. Stop, let Rojo sync, Play again.

**Reading `BUILD_TAG` out of the source does NOT prove the build is running.**
`script_grep` finding the current tag only proves Rojo synced the file. If the
module doesn't compile, the `print` never executes and Output still shows the
*previous* build. Verify the tag in the **console**, never in the source.

**Check `BUILD_TAG` first, always.** `src/server/init.server.luau` prints a
build tag at boot. If Titus reports "your fix didn't work," check the Output
window before touching code — he once spent days testing stale scripts
because his local branch had drifted from origin (`git pull` said "Already up
to date" while origin had moved). The fix was:

```
git fetch origin
git checkout claude/pink-panic-roblox-5g2w56
git reset --hard origin/claude/pink-panic-roblox-5g2w56
```

If the tag prints **twice**, there's a duplicate script tree in the place file.

**Never generate lobbies or maps.** Earlier versions built a placeholder plaza
and arena procedurally; it got baked into saved place files and kept coming
back after Titus built his own. All generator code was deleted on purpose, and
legacy folders are destroyed unconditionally at boot. Do not reintroduce it.

**Locked ≠ anchored.** Imported parts that are Locked but not Anchored will
explode the moment you press Play.

**A live Humanoid cannot be out-argued by a finite force, and that is why the
old movement flung people.** The Humanoid's controller is a servo driving
toward `MoveDirection * WalkSpeed`; with WalkSpeed at 0 that target is 0, so it
spends whatever it takes to hold the character still. Measured 2026-08-12,
driving a `LinearVelocity` at 24 studs/s for one second on a 14-mass rig:
`mass×90` → 0.60 studs, `mass×400` → 2.67, `mass×6400` → 9.93, `math.huge` →
24.30. Seventy times the force buys a third of the distance and the curve never
converges — `math.huge` is a different path through the solver, not a big
number, and it is the only value that works. It is also what resolves the
character out of any geometry it touches at whatever speed that takes. So
ground locomotion runs on `Humanoid.WalkSpeed`, with the speed still resolved by
`shared/Systems/Movement.speedFor`, never a local constant.

**So don't fight the Humanoid — drive it.** Every move in M2 does, and each one
was measured on 2026-08-12:

- `Humanoid:Move(worldDirection, false)` called from a render step bound at
  `Input+1` **fully overrides Roblox's control script** — 22.3 studs in one
  second at WalkSpeed 24, with `MoveDirection` exactly as written and no input
  touched. That is the slide: a locked heading plus a decaying WalkSpeed.
- Writing `AssemblyLinearVelocity` while **grounded does nothing** — the Running
  controller ate a 30-stud shove inside a single frame. Airborne, the same write
  sticks. So a dive launches with `ChangeState(Jumping)` (a code path the
  controller can't argue with) and only kicks its horizontal speed once it is
  off the ground.
- `PlatformStand = true` plus writing `root.CFrame` every frame lands within
  **0.05 studs** of where it was aimed, and releases cleanly. That is the mantle.

Because the Humanoid stays the mover in all three, a wall still stops you. The
mass-bounded actuator in `client/Movement/Actuator.luau` is attached and
bounded but drives nothing — it never needed to.

**A fixed sampling interval can be phase-locked.** `MoveAudit` originally
sampled positions every 0.5s and read a character teleporting 260 studs back
and forth every 0.25s as *perfectly stationary* — 0.0 studs moved, sixteen
samples in a row. Every sample landed on the same end of the trip. Any periodic
server-side check needs jitter, and anything that leaves and returns between two
samples is invisible to position sampling no matter what.

**Rounds never auto-start, and never start solo.** Titus asked for this
explicitly on 2026-08-10. `RoundService` holds in `Waiting` until *both*
`#Players >= GameConfig.minPlayers` (2) **and** the START GAME button fires
`EnterPortal`. There is no timer, no pad path, and no Studio exception —
walking somewhere can never drop you into a match.

**Until RoundService exists, standing in the `Arena` folder IS the round.**
`ClientData.fighting()` is the one answer — `not inLobby() or inArena()` — and
both the trigger and the camera read it. Before NOD-142 only the trigger did,
so you could shoot people in the arena while looking through the lobby's fixed
cinematic camera with a free mouse cursor. Delete `inArena` the day M9 lands.

The consequence: **a solo Studio session can't start a round**, so respawn,
scoring and payouts are only testable with `Test → Players → 2 Players`. The
lobby itself (camera, cursor, pads, armory, loadout) is still fully testable
alone — and so is **all** of movement, because the lobby profile now allows
slide, dive and mantle. It used to exclude them on the grounds that
the fixed lobby camera could not show an arc, which was a rule about the camera
written as a rule about the moves: with no round loop until M9, "not in the
lobby" meant "nowhere", and all three would have shipped never having run. The
camera fixes the camera — `PinkPanicSlideRoll` skips the lean while the fixed
lobby shot owns the CFrame.

## Git

Branch: `claude/pink-panic-roblox-5g2w56`. Push there and nowhere else. Do not
open a pull request unless Titus explicitly asks.

## Talking to Titus

He's new to Roblox and git, and he's sharp about how things feel. Lead with the
fix and what it changes in-game; skip the play-by-play. When he says something
is broken, believe him, but verify which build he's actually running before
rewriting anything.
