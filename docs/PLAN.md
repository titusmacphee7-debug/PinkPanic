# Pink Panic — Master Plan

A Call of Duty–class shooter, pink. Written 2026-08-11. Target: ~3 months.

This is the authoritative plan. [REBUILD.md](REBUILD.md) holds the post-mortem
and the non-negotiable rules that came out of it — read that first, it explains
*why* this document is shaped the way it is.

---

## 0. Creative direction — Leah's brief

Pink Panic is Leah's idea. This section is her answers, and it outranks the rest
of this document. Where anything below contradicts it, this wins.

> *"A cute pink themed multiplayer shooter, adorable cosmetics."*

**Tone: cute AND competitive.** Not a joke game with pink paint, and not a
military shooter with a hue shift. A real shooter that is genuinely adorable —
"cozy but competitive". This is why the systems are CoD-grade underneath: the
competition has to be real for the cuteness to land as charm rather than excuse.

**Aesthetic:** pink, white, pastels. Bows, hearts, glitter. Cute UI. Reference
points, in her words: **Hello Kitty, coquette, soft aesthetic, Y2K pink.** Both
palettes at once — soft pastel *and* candy-saturated, not one or the other.

**Played with friends.** Social first. 5–10 minute matches.

**The hook is the guns.** Asked what would actually make her play it: *"good
cutesy guns."* Weapon models and camos are not the polish pass, they are the
retention mechanic. Treat them accordingly.

**Characters:** Roblox avatars, kept — with outfits layered on, **like Arsenal**.
Players stay themselves. We do not replace the avatar.

**Hit vs kill feedback — a real distinction she drew:** hearts and sparkles on
every *hit* is a maybe-not. On a **kill**, absolutely. So hitmarkers stay crisp
and readable for competitive clarity, and the celebration goes on the kill.

**Cosmetic categories she named:** gun skins · knife skins · charms · stickers ·
kill effects · death effects · emotes · player titles · outfits.

**Economy: crates**, opened with currency earned in game, or bought with gems.

**Everything should feel nice to touch** — cutesy click effects, sparkles, cute
sounds throughout the UI. Juice is not optional here, it is the product.

**Her maps** (these are her six, and they define the art targets):
Candy Factory · Pink Mall · Princess Castle · Toy Store · Luxury Mansion ·
Dream Bedroom.

**Her future list:** trading, inventory, crafting, ranked mode, guilds, emotes.

---

## 0.1 The shape of the thing

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

**Skin regions** (for camos): `Body`, `Barrel`, `Stock`, `Grip`, `Magazine`,
`Accent`

**THE SHARED UV LAYOUT — the single most important line in this document**

Every gun in the game is UV-unwrapped to the **same normalized layout**. Not
per-gun. Not even per-class. One layout, all 38 weapons.

Why it decides whether camos are a feature or a graveyard:

|  | per-gun UVs | shared UVs |
|---|---|---|
| 100 camos across 38 guns | **3,800 textures** | **100 textures** |
| adding gun #39 | re-author every camo | works instantly |
| adding camo #101 | 38 exports | drop in one file |

With a shared layout a camo is one texture that works everywhere, forever. Get
this wrong and the camo system is dead on arrival regardless of how good the
art is. **This must be specified to Cowork before a single model is built.**

Requirements:
- 0–1 UV space, no overlapping shells, consistent texel density across guns
- The same *region of the texture* corresponds to the same *part of the gun* on
  every weapon: receiver top-left, barrel along the top strip, stock lower-left,
  magazine lower-right, grip and accents bottom strip
- Test asset: a numbered grid texture that must read correctly on all 38 guns

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

## 4.5 Camos and character skins

Titus is generating a very large number of cutesy-pink camos. The engineering
requirement is therefore not "make camos work" — it is **make adding the 300th
camo cost nothing.**

### Convention over configuration

There is no per-camo code and no per-camo config entry. A camo exists because a
texture exists.

```
ReplicatedStorage/Assets/Camos/
  Camo_StrawberryMilk        (Texture asset or a StringValue holding an id)
  Camo_BubblegumSwirl
  Camo_HeartCheck
  Camo_SleepyClouds
  ...
```

`CamoRegistry` scans that folder at boot and derives everything:

- **id** — the instance name (`Camo_StrawberryMilk`)
- **display name** — de-prefixed and de-camel-cased (`Strawberry Milk`)
- **rarity / price / unlock** — from an *optional* override table. Anything not
  listed gets sane defaults, so a camo with no config entry still works.

Drop a texture in the folder → it is in the game, in the shop, previewable, and
equippable. No code change, no restart of the pipeline, no PR.

### Applying it

One texture ID written to the skin-region MeshParts:

```lua
for _, part in gun:GetDescendants() do
    if part:IsA("MeshPart") and SKIN_REGIONS[part.Name] then
        part.TextureID = camo.textureId
    end
end
```

Because of the shared UV layout (§3.4) this is the *entire* application logic
for every gun in the game. Optional `SurfaceAppearance` support layers on later
for PBR camos (normal/roughness/metalness) without changing this path.

### Character outfits — Arsenal-style, per Leah

**Players keep their own Roblox avatar.** We do not standardize or replace it.
Outfits layer on top: clothing texture IDs and accessory models applied over
whatever character the player brought.

Same registry pattern — `ReplicatedStorage/Assets/Outfits/<OutfitId>`, scanned
at boot, no per-outfit code.

The cost of keeping avatars is that hitboxes vary with body type. We solve that
where it actually matters rather than by taking the avatar away: **damage is
resolved against a normalized hit volume** derived from the rig, not against
whatever mesh the player is wearing. Fairness comes from the hit resolution, not
from making everyone look the same.

### The full cosmetic set

Nine categories, all of them Leah's list, all on the same registry pattern:

| Category | Applies to | Notes |
|---|---|---|
| Gun camo | skin-region MeshParts | shared UV, one texture fits all guns |
| Knife skin | melee model | same pipeline |
| Charm | `Mount_Charm` socket | dangles, small physics |
| Sticker | decals on gun surfaces | placed per-gun, slot positions in the model |
| Kill effect | plays on YOUR kill | **hearts and sparkles live here** |
| Death effect | plays on YOUR death | |
| Emote | rig animation | wheel |
| Title | nameplate + scoreboard | text + colour |
| Outfit | avatar layer | clothing + accessories |

### Rules

- All of it is **cosmetic only**. Never a stat, never a real hitbox change.
- Ownership is server-derived from the profile. Equipping something unowned is
  rejected server-side, not hidden client-side.
- Anything whose asset fails to load warns naming the item and falls back to a
  default. Nothing ever renders as untextured grey.

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

### Rarity tiers

Six tiers on the scarcity ladder, plus two that are categorical rather than
rarer. That distinction matters mechanically: a tier on the ladder needs a
probability, and a categorical tier needs an *availability rule* instead.

**The ladder** — these appear in crates and carry odds:

| Tier | Colour | Crate odds (baseline) |
|---|---|---|
| Common | pale blush | 40% |
| Uncommon | mint | 27% |
| Rare | periwinkle | 17% |
| Super Rare | lavender | 10% |
| Legendary | hot pink — the brand colour sits at the top | 5% |
| Exotic | gold, iridescent | 1% |

**Outside the ladder** — these never roll from a standard crate:

| Tier | Colour | How you get it |
|---|---|---|
| Special | teal, holographic | Achievement, challenge, event reward. Earned, never bought. |
| Limited | animated rainbow foil | Time-gated. Available in a window, then gone for good. |

Odds are per-crate-line and configurable; the table above is the default.
Published in the UI, always.

**Presentation scales with tier**, and per Leah rares are loud: card frame,
glow intensity, particle density, unlock sound and reveal length all escalate.
Exotic, Special and Limited get bespoke treatment — an Exotic pull should stop
the room. Limited items keep a visible "no longer obtainable" marker forever,
because that is most of what makes them worth having.

### Currencies and crates — Leah's call

Two currencies and a crate as the primary cosmetic sink:

- **Coins** — earned by playing. Buy crates, buy some items directly.
- **Gems** — premium, bought with Robux. Buy crates and premium-only items.

**Crates** are the main way cosmetics are acquired. Themed lines per category
(gun camos, outfits, charms, effects). Non-negotiables:

- **Published odds, always visible in the UI.** This is both the honest thing
  and what keeps us compliant with Roblox's paid-random-item disclosure rules
  once gems can buy crates.
- **Duplicates auto-refund.** Never a dead pull.
- **Server-authoritative everything** — RNG, grant, dedupe, refund. The client
  is told the result and animates it. It never rolls anything.
- **The opening IS the product.** Spinning reel, slowing ticks, rarity glow, a
  cute sound per tier. This gets real animation time, not a message box.

Nothing that affects gameplay is ever purchasable. Crates contain cosmetics
only — no guns, no attachments, no perks. Weapons and attachments unlock through
play, per §6. That line does not move.

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

## 9.1 Match length

**5–10 minutes**, per Leah. That sets the tuning targets:

| Mode | Score limit | Time limit |
|---|---|---|
| TDM | 75 | 10 min |
| FFA | 30 | 10 min |
| Domination | 200 | 10 min |
| Kill Confirmed | 65 tags | 10 min |
| Hardpoint | 250 | 8 min |
| Search & Destroy | 6 rounds | 1:45 per round |

Every number lives in `Config/Modes` and gets tuned against real matches. A
match that regularly hits the time limit instead of the score limit means the
score limit is too high.

---

## 9.2 Spawning

Per Leah: **no spawning on the enemy, and spawns can switch.** Those are the
same system, and getting it right is most of the difference between a shooter
that feels fair and one people quit.

The naive approach — pick a random spawn from your team's list — produces
exactly the two failures she named: you materialize in front of someone, or you
get spawn-trapped because your side never changes.

### Scored spawn selection

Every spawn point is scored at the moment of each request. Highest score wins,
with a little randomization among the top few so it is not deterministic.

| Factor | Effect on score |
|---|---|
| Nearest enemy closer than `dangerRadius` | heavy negative, scaling with closeness |
| An enemy currently **looking at** the spawn (dot product + clear line) | disqualifying |
| Enemy could reach it within ~2s | strong negative |
| Teammate nearby | positive — spawn with your team, not alone |
| Someone died here in the last few seconds | negative, decaying |
| Distance to the live objective | mode-dependent, usually mild positive |
| Enemy spawn-side pressure | negative |

If every spawn scores below a floor, we pick the least-bad and grant a slightly
longer spawn protection rather than dumping the player into a firefight.

### Spawn zones that flip

Spawns are grouped into **zones** (tagged `SpawnGroup` in the map). A zone is
owned by whichever team currently has presence there. When map control shifts —
a team pushes across — ownership flips and both teams start spawning from
different ends. That is the "spawns can switch" she asked for, and it is what
prevents a spawn trap from being permanent.

Zone ownership recomputes on a timer, with hysteresis so it does not thrash
back and forth while a fight is contested on a boundary.

### Timing and protection

- **Respawn delay: 5s default**, per mode in `Config/Modes`. Search & Destroy
  has none — you are out for the round.
- **Spawn protection:** brief invulnerability that **breaks the moment you fire
  or aim**, so it can never be used offensively.
- Wave respawns for objective modes are a per-mode option, not a global.

### Debugging it

A spawn debug overlay (Studio only) draws every spawn point coloured by its
current score and prints the winning factors for the last selection. Spawn bugs
are otherwise almost impossible to reproduce and diagnose from a report.

---

## 10. Maps (Titus builds, I provide the framework)

**Leah's six**, in build order — the first is the one everything else is
validated against:

1. **Pink Mall** — atriums and shopfronts. The natural three-lane, so it goes
   first and becomes the reference layout.
2. **Candy Factory** — conveyors and catwalks, verticality.
3. **Dream Bedroom** — oversized furniture, close quarters, the cosiest one.
4. **Princess Castle** — courtyards and towers, long sightlines plus tight interiors.
5. **Toy Store** — dense aisles, chaotic, best for smaller modes.
6. **Luxury Mansion** — symmetrical wings, the most competitive layout.

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

### The art direction is not a skin on a military shooter

This is the thing that makes it *Pink Panic* and not "CoD clone #4000". The
systems are CoD; the surface is unapologetically cute. Leah's original
intention, kept:

- **The minimap is a heart.** Not a circle, not a rounded square — a heart,
  masked, with the compass ticks running around its outline. It is the single
  most-looked-at element on screen and it should announce what game this is
  within one second of a screenshot.
- Blush and hot pink over grey and tan. Rounded everything. Chunky friendly
  type. Hearts, bows and glitter where CoD would use chevrons and stencils.
  Hello Kitty, coquette, Y2K pink.
- **Hitmarkers stay crisp and readable** — Leah's call. Competitive clarity
  matters more than cuteness on the thing you read mid-fight.
- **Kill effects are where the hearts and sparkles go.** That is the
  celebration moment and it should be genuinely over the top.
- Killfeed reads soft, not aggressive.
- **Rares are loud** — Leah's call. A Legendary camo should be obvious from
  across the map: glow, particles, an animated card frame in the menus, its own
  sound on unlock. If someone has something rare, everyone should know.
- Scorestreaks keep CoD mechanics and lose the military dress entirely: the
  UAV is a heart-shaped drone, the airstrike drops glitter.
- **Everything is nice to touch.** Cutesy click effects, sparkle particles on
  hover and press, a cute sound on every meaningful interaction. Damage
  numbers, XP popups, unlock cards and crate openings get real animation time.
  Juice is most of what "expensive" feels like, and Leah asked for it directly.

Cute is the point, not a coat of paint. Any surface that could pass for a
military shooter with a hue shift has missed it.

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
| M3 | **Gun models, batch 1** (8 ARs) to the §3.4 spec, **shared UV layout** | Cowork |
| M4 | Attachment models to the §4 socket spec | Cowork |
| M4 | **Camo textures** — as many as you like, to the shared UV layout | you / generation |
| M6 | Outfit sets for the standard R15 rig | Cowork |
| M9 | First map, three-lane, tagged per §10 | Studio |
| M11 | Moon Animator clips against my spec | Moon Animator |
| M12 | Visual direction per surface | Claude Design |
| M13 | Weapon audio | wherever you like |

Cowork prompts get written as part of the M3 and M4 issues, not now — they need
the final socket names, and those get proven on the placeholder first.
