# Pink Panic — Master Plan

A Call of Duty–class shooter, pink. Written 2026-08-11. Target: ~3 months.

This is the authoritative plan. [REBUILD.md](REBUILD.md) holds the post-mortem
and the non-negotiable rules that came out of it — read that first, it explains
*why* this document is shaped the way it is.

---

## 0. The shape of the thing

CoD is not one system. It is eight systems that agree with each other:

```
                       ┌─────────────┐
                       │   Loadout   │  what you bring
                       └──────┬──────┘
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌───────────┐      ┌────────────┐      ┌────────────┐
    │  Weapons  │◄─────┤ Attachments│      │Perks / Gear│
    └─────┬─────┘      └────────────┘      └──────┬─────┘
          │                                       │
          ▼                                       ▼
    ┌───────────┐      ┌────────────┐      ┌────────────┐
    │  Combat   │─────►│   Score    │─────►│Scorestreaks│
    └─────┬─────┘      └──────┬─────┘      └────────────┘
          │                   │
          ▼                   ▼
    ┌───────────┐      ┌────────────┐
    │ Movement  │      │ Game Modes │
    └───────────┘      └────────────┘
```

Every arrow is a contract. The rule for this build: **one module owns each
contract, and both sides read it from the same place.** Client prediction and
server truth cannot drift if they are literally resolving the same function.

---

## 1. Organization

The last build died partly because nobody could tell which of two systems was
real. So the layout is strict and the rules are short.

### 1.1 Repo

```
src/
  server/
    Services/        one per concern, each exposes init(), ordered in init.server
    Systems/         pure logic, no side effects on require (ballistics, scoring)
  client/
    Controllers/     one per concern, each exposes init()
    UI/
      Screens/       full-screen surfaces (Loadout, Shop, Scoreboard, Results)
      Components/    reusable widgets built on the design tokens
      Theme.luau     every colour, font, radius, spacing. No raw Color3 elsewhere.
  shared/
    Config/          DATA ONLY. No behaviour, no requires except sibling config.
      Guns/          one file per weapon class, see §3
      Attachments/   one file per slot
      Perks/
      Modes/
      Progression/
    Systems/         deterministic logic BOTH sides run (stat resolution, spread)
    Net/             Remotes.luau (declarations) + Guard.luau (validation)
    Types/           shared type definitions, no runtime code
```

**Rules**

1. `shared/Config` is data. If a config file contains an `if`, it is wrong.
2. `shared/Systems` is where "the answer" lives. If the client and server both
   need to know a number, neither computes it — both call the same resolver.
3. A `Service` may require `Systems` and `Config`. A `Config` may require
   nothing but other `Config`. This is checked in review; a cycle is a bug.
4. Every remote is declared by the system that handles it, and never declared
   without a handler.

### 1.2 In the place file (Titus's side)

```
ReplicatedStorage/
  Assets/
    Guns/
      <GunId>/              Model, see the spec in §3.4
    Attachments/
      <AttachmentId>/       Model, mounts to a socket
    Equipment/              grenades, tacticals
    Effects/                bullet, shell, impact decals
    Characters/             the standard rig, outfits
  Remotes/                  created at boot, never hand-edited

Workspace/
  Lobby/                    hand-built. pads, CameraAnchor
  Maps/
    <MapName>/              hand-built, tagged per §10
```

**One naming rule that prevents an entire class of bug:** an asset's folder
name IS its config id. `Assets/Guns/AR_Sweetheart` ↔ `GunCatalog.AR_Sweetheart`.
The loader warns loudly on either side of a mismatch, at boot, naming both.

---

## 2. Foundations (built before anything else)

### 2.1 The diagnostics layer

This is new, and it is the highest-leverage thing in the document. Every
failure we hit last build was silent. So:

```lua
Diagnostics.expect(condition, system, whatWasExpected, whatWasFound)
Diagnostics.require(instance, path)   -- warns naming the exact path it wanted
Diagnostics.report()                  -- boot summary: every system, OK or DEAD
```

At boot the server prints a manifest:

```
[PinkPanic] build 2026-08-11-A
  ✅ Remotes        41 declared, 41 handled
  ✅ GunCatalog     38 guns, 38 models found
  ⚠️  Attachments   26 defined, 24 models found — MISSING: Muzzle_Compensator, Optic_Holo
  ✅ Movement       online
  ❌ Scorestreaks   DEAD — Config/Streaks.luau failed to load: attempt to index nil
```

Nothing is ever silently off again. This gets built in M0 and every system
after it registers with it.

### 2.2 Net layer

- `Remotes.luau` — declarations, with the owning system named per remote.
- `Guard.luau` — rate limit + type/range validation, per remote, mandatory.
- Every handler: `Guard.check(player, "RemoteName", ...)` or it does not ship.
- Boot asserts every declared remote has a handler bound.

### 2.3 Stat resolution

One function, both sides:

```lua
CombatStats.resolve(gunId, attachmentIds, perkIds) -> Resolved
```

Attachments and perks modify only fields on an explicit `MODIFIABLE` whitelist.
A typo'd field name is a loud error, not a silent no-op. Client prediction and
server truth call this identically — drift becomes structurally impossible.

---

## 3. Weapons

### 3.1 The stat block

This is the heart of the game's feel, and it is deliberately CoD-shaped. Every
field is per-gun.

```lua
type GunDef = {
  -- identity
  id: string, displayName: string,
  class: "AR"|"SMG"|"LMG"|"Shotgun"|"Marksman"|"Sniper"|"Pistol"|"Melee",
  slot: "Primary"|"Secondary"|"Melee",
  unlockLevel: number, price: number, rarity: Rarity,

  -- damage: multi-point falloff, CoD-style (not two-point)
  damageProfile: { { range: number, damage: number } },
  headshotMult: number, torsoMult: number, limbMult: number,
  pellets: number,

  -- fire
  rpm: number,
  fireMode: "Auto"|"Semi"|"Burst",
  burstCount: number?, burstDelayMs: number?,
  velocity: number,          -- studs/s, real projectiles
  dropFactor: number,        -- gravity multiplier

  -- accuracy & recoil (NO BLOOM, EVER)
  hipSpreadDeg: number, adsSpreadDeg: number,
  recoilPattern: { Vector2 },  -- per-shot camera kick, REPEATABLE
  recoilRecovery: number, visualKick: number,

  -- HANDLING — the pull-out times
  adsTime: number,           -- hip → fully aimed
  sprintToFire: number,      -- sprint release → able to fire
  tacSprintToFire: number,   -- tactical sprint is slower to recover
  equipTime: number,         -- draw / pull-out
  holsterTime: number,       -- put away (swap = holster + equip)
  reloadTime: number,        -- tactical reload, rounds still in mag
  reloadEmptyTime: number,   -- from empty, longer (bolt/slide release)
  reloadCancelTime: number,  -- when ammo ACTUALLY lands, before the anim ends
  shellReloadTime: number?,  -- per-shell for tube-fed, interruptible

  -- mobility
  moveSpeedMult: number, adsMoveSpeedMult: number,
  sprintSpeedMult: number, tacSprintSpeedMult: number,

  -- ammo
  magSize: number, startingMags: number,

  -- attachments
  slots: { AttachmentSlot },
}
```

**Three details that make it read as CoD rather than a Roblox shooter:**

- **`reloadCancelTime`.** Ammo lands before the animation finishes, so you can
  sprint-cancel the tail. Every good CoD player does this constantly without
  knowing the name for it. Its absence is felt immediately.
- **Separate `reloadTime` and `reloadEmptyTime`.** Emptying the mag costs you.
- **`recoilPattern` as an array, not a random cone.** The gun kicks the same way
  every time, so it is *learnable*. This is the promise of "no bloom" kept
  properly: mastery is possible, luck is not involved.

### 3.2 Ballistics

Server-simulated projectiles, stepped as segment raycasts on Heartbeat.
Muzzle velocity + gravity drop. Damage accumulates per victim per frame so a
shotgun lands as one hit event, not eight. **The client never reports a hit.**

### 3.3 Weapon classes and target counts

| Class | Count | Identity |
|---|---|---|
| AR | 8 | The baseline. Versatile, 4-shot kill, moderate everything |
| SMG | 7 | Fast handling and movement, falls off hard past mid |
| LMG | 4 | Big mags, worst handling, best sustained control |
| Shotgun | 4 | One-shot inside a knife-fight range, useless outside |
| Marksman | 4 | Semi-auto, 2-3 shot, rewards accuracy |
| Sniper | 4 | One-shot upper-chest-and-above, slow ADS |
| Pistol | 5 | Secondary. Fast draw is the whole point |
| Melee | 2 | Secondary. Instant, no ammo |

**38 weapons.** Built one at a time, and the first one is finished completely
before the second one starts.

### 3.4 Gun model spec — hand this to Cowork

Every gun model, no exceptions. This spec exists so no gun is ever backwards
again, and so attachments can mount without per-gun code.

**Orientation & scale**
- Barrel points **+Z**. Up is **+Y**. Model is built at real scale for a Roblox
  R15 rig (an AR is roughly 3.2–3.8 studs long).
- Model has a `PrimaryPart` set to the part named `Body`.

**Required Attachments (the tags — this is the contract)**

| Attachment name | Where | Purpose |
|---|---|---|
| `Muzzle` | barrel tip, pointing **down the bore** | bullet origin, flash, the forward axis of truth |
| `Eject` | ejection port, pointing out and slightly back | shell casings |
| `GripRight` | where the right hand holds | welds to the rig |
| `GripLeft` | where the support hand holds | welds to the rig |
| `Sight` | top rail, at iron-sight eye height | ADS aligns the camera to this |

**Attachment mount sockets** — only where the gun supports that slot:
`Mount_Muzzle`, `Mount_Barrel`, `Mount_Optic`, `Mount_Underbarrel`,
`Mount_Magazine`, `Mount_Stock`, `Mount_Laser`, `Mount_RearGrip`

**Moving parts** (named parts, separate from the body):
`Slide`, `Bolt`, `Pump`, `Cylinder`, `Mag`, `ChargingHandle`, `Trigger`, `Hammer`

**Skin regions** (for camos, must have clean UVs, shared layout per class):
`Body`, `Barrel`, `Stock`, `Grip`, `Magazine`, `Accent`

If any required attachment is missing, the loader refuses the model, warns
naming the gun and the missing tag, and substitutes a placeholder. A broken
import can never ship silently.

---

## 4. Attachments

CoD's system: **5 equipped from 8 possible slots**, so every build is a
trade-off rather than a strict upgrade.

| Slot | Typical effect axis |
|---|---|
| Muzzle | recoil, flash concealment, range |
| Barrel | range, velocity, ADS, mobility |
| Optic | sight picture, ADS time |
| Underbarrel | recoil control, ADS penalty |
| Magazine | mag size vs reload and mobility |
| Stock | ADS/aim-walk vs mobility |
| Laser | hip spread vs visibility to enemies |
| Rear Grip | recoil recovery, ADS |

**Rules**
- Every attachment has at least one **downside**. No strict upgrades.
- Modifiers apply through the `MODIFIABLE` whitelist in `CombatStats`.
- Attachments unlock through **weapon XP** — use the gun, earn its parts.
- Visual: the model mounts to the matching `Mount_*` socket. Missing socket =
  loud warning, attachment still applies its stats.

Target: ~30 attachments at launch, spread across slots, plus per-class
availability so an SMG and an LMG don't share a stock list.

---

## 5. Loadout / Create-A-Class

The CoD structure, exactly:

```
Class (player-named, 5 slots to start, more unlock)
  Primary        + up to 5 attachments
  Secondary      + up to 5 attachments
  Perk 1 / 2 / 3
  Lethal         (frag, semtex, throwing knife)
  Tactical       (flash, stun, smoke)
  Field Upgrade  (trophy, dead silence, munitions box)
  Scorestreaks   (3 slots)
```

**Non-negotiable:** loadout edits are lobby-only, everything is server-derived
from the profile, and the client's claim about what it has equipped is never
trusted — the server reads the profile and tells the client what it is holding.

---

## 6. Progression

Three parallel tracks, because one is not enough to keep anyone playing:

1. **Player level** — unlocks weapons, perks, equipment, extra class slots.
2. **Weapon level** — per-gun XP unlocks that gun's attachments and camos.
3. **Challenges** — per-gun and general, unlock camos and titles.

Score sources (CoD values, scaled): kill 100, assist 50, objective 200-ish,
headshot bonus, streak bonuses, mode-specific actions. Every value in
`Config/Progression`, none hardcoded anywhere.

---

## 7. Scorestreaks

Earned with **score, not kills** (so objective play competes with slaying), and
**score resets on death** (streaks are a risk, not an accumulation).

| Tier | Cost | Examples |
|---|---|---|
| Low | 500 | UAV (spot enemies), Care Package |
| Mid | 1200 | Counter-UAV, Sentry, Airstrike |
| High | 2500+ | Chopper Gunner, Juggernaut |

Pink versions: the UAV is a heart-shaped drone, the airstrike drops glitter.
Same mechanics, different dress.

Each streak is its own module implementing a common interface, registered in a
table. Adding one never touches the streak system itself.

---

## 8. Perks & Equipment

- **Perk 1** — movement/stealth (fast hands, lightweight, ghost)
- **Perk 2** — combat awareness (hardline, scavenger, tracker)
- **Perk 3** — utility (dead silence, tune-up, high alert)
- **Lethal / Tactical** — real physics grenades, cooked timers, bounce
- **Field upgrades** — charge over time, one active

Perks modify stats through the same whitelist as attachments. There is one
modifier pipeline in this game, not three.

---

## 9. Game modes

Built on a `GameMode` interface so a mode is a config plus a handful of hooks,
never a fork of the round loop.

| Mode | Priority | Notes |
|---|---|---|
| Team Deathmatch | M9 first | The baseline |
| Free-For-All | M9 | Already the old shape |
| Domination | M9 | 3 flags, capture and hold |
| Kill Confirmed | M10 | Dog tags — trivially built on TDM |
| Hardpoint | M10 | Rotating zone |
| Search & Destroy | M11 | Round-based, no respawn. The hardest one. |

---

## 10. Maps (Titus builds, I provide the framework)

A map is a Workspace folder under `Workspace/Maps` with tagged content:

- `MapName` attribute, `MapAuthor`, `MapModes` (comma list of supported modes)
- Spawn groups tagged `SpawnGroup` with a `Team` attribute
- Objective anchors tagged `ObjectiveType` (`DomA`, `DomB`, `DomC`, `Hardpoint1`…)
- `MapBounds` part defining the playable volume (out-of-bounds timer)
- Optional `CoverHint` volumes for future bot navigation

The map loader validates every one of these at load and refuses to start a mode
whose required anchors are missing, naming what it wanted. Three-lane layout is
the CoD standard and the one I'd recommend for the first map.

---

## 11. Animation

Deliberately last, because animation on top of a system still being tuned is
work done twice.

**The split:**

- **Procedural** (code, no export step): stride cycle, directional blending,
  lean, slide, crouch, air, landing, recoil kick, weapon sway, ADS transition.
  Scales with any speed and never desyncs.
- **Keyframed** (Moon Animator, one-shots where procedural is weak): reload
  variants, inspect, dive, execution/finisher, mantle.

They compose: **clips own `Transform`, the procedural layer owns the joint
base.** This is not either/or, and it is why the rig work matters.

Rig note carried forward: the character uses `AnimationConstraint`, not
`Motor6D`. The C0 analogue is `Attachment0.CFrame`. Measured and verified.

**What Titus provides here:** Moon Animator clips against a spec I'll write
(frame counts, timing, which joints, export naming). That spec is its own issue
and lands before any clip work starts.

---

## 12. UI

Also late, and built on tokens from day one so the pass at the end is a pass
and not a rewrite.

Surfaces: HUD, Loadout/Create-A-Class, Weapon detail + attachment browser,
Scoreboard, Results, Progression/Challenges, Shop, Settings, Killfeed,
Scorestreak wheel, After-action report.

**What goes to Claude Design:** the visual direction for each surface once the
data behind it exists. I'll write the briefs with real field lists so nothing
gets designed around imaginary content.

---

## 13. Milestones

| # | Milestone | Weeks | Gate |
|---|---|---|---|
| M0 | Foundations & Conventions | 1 | Boot manifest prints, all green |
| M1 | Core Combat Slice | 1–2 | Two players, one gun, kill each other, score |
| M2 | Movement System | 2–3 | Omnimovement feels right in Titus's hands |
| M3 | Weapon Depth | 3–5 | Handling, ADS, recoil patterns, reload, swap |
| M4 | Attachment System | 5 | 5-of-8 slots, stats + models, no strict upgrades |
| M5 | Loadout / Create-A-Class | 5–6 | Build a class, spawn with it |
| M6 | Progression & Unlocks | 6–7 | Player XP, weapon XP, challenges |
| M7 | Scorestreaks | 7–8 | Earn, call in, three tiers working |
| M8 | Perks & Equipment | 8–9 | Grenades, tacticals, perks, field upgrades |
| M9 | Game Modes I | 9–10 | TDM, FFA, Domination |
| M10 | Maps & Modes II | 10–11 | Map framework, KC, Hardpoint |
| M11 | Animation | 11–12 | Procedural set + keyframe pipeline |
| M12 | UI/UX Pass | 12 | Every surface on the design system |
| M13 | Audio & Juice | 12–13 | Weapon audio, hit feedback, music |
| M14 | Hardening & Launch | 13 | Anti-cheat audit, perf, analytics, soft launch |

Weeks are sequence, not deadline. **A milestone is not done until it has been
verified running in Studio.**

---

## 14. What Titus does, and when

Nothing here is needed yet — this is the heads-up so none of it is a surprise.

| When | What | Where it goes |
|---|---|---|
| M0 | Turn on Studio API access | so DataStores work in test |
| M1 | Nothing — I need one gun and I'll use a placeholder | |
| M3 | **Gun models, batch 1** (8 ARs) to the §3.4 spec | Cowork |
| M4 | Attachment models to the §4 socket spec | Cowork |
| M9 | First map, three-lane, tagged per §10 | Studio |
| M11 | Moon Animator clips against my spec | Moon Animator |
| M12 | Visual direction per surface | Claude Design |
| M13 | Weapon audio | wherever you like |

Cowork prompts get written as part of the M3 and M4 issues, not now — they need
the final socket names, and those get proven on the placeholder first.
