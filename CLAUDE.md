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
- `src/shared/Config/*` — data only, no behavior. `GunCatalog.luau` is the
  single balance file (32 guns); `CombatStats.luau` is the one resolver both
  sides use so client prediction and server truth can't drift.
- `src/shared/Net/Remotes.luau` — **every** remote is declared here, nowhere
  else. `Guard.luau` does rate limiting and argument validation.

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
breaking this order causes jitter that looks like a physics bug:

```
engine Camera (200)
  → PinkPanicCamera      +1
  → PinkPanicAim         +2   (recoil)
  → PinkPanicSlideRoll   +3
  → PinkPanicViewmodel   +4
PinkPanicSkid          Input+1
PinkPanicMouseUnlock   Last
```

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
- Runtime stance flags: `PPSliding`, `PPCrouching`

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

**Rounds never auto-start, and never start solo.** Titus asked for this
explicitly on 2026-08-10. `RoundService` holds in `Waiting` until *both*
`#Players >= GameConfig.minPlayers` (2) **and** the START GAME button fires
`EnterPortal`. There is no timer, no pad path, and no Studio exception —
walking somewhere can never drop you into a match.

The consequence: **a solo Studio session can't start a round**, so combat,
respawn, scoring and payouts are only testable with `Test → Players → 2
Players`. The lobby itself (camera, cursor, pads, armory, loadout) is still
fully testable alone.

## Git

Branch: `claude/pink-panic-roblox-5g2w56`. Push there and nowhere else. Do not
open a pull request unless Titus explicitly asks.

## Talking to Titus

He's new to Roblox and git, and he's sharp about how things feel. Lead with the
fix and what it changes in-game; skip the play-by-play. When he says something
is broken, believe him, but verify which build he's actually running before
rewriting anything.
