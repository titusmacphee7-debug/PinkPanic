# Test coverage — where we actually stand

125 Luau files. 26,339 lines. Zero tests.

That number is less damning than it looks, and more damning than it looks, and
this document is about which parts are which.

## The short version

There is no test suite, no test framework, and no CI. What there *is* instead is
a genuinely good **runtime self-verification layer** — eleven `validate()` and
`audit()` functions wired into a boot manifest that refuses to let a dead system
look like a live one. That layer is real work and it catches real bugs. It is
also, without exception, answering one question:

> **Is the data self-consistent right now?**

Nothing in the codebase answers the other one:

> **Does the machine produce the right sequence of outputs when you drive it?**

Every gun's cone is checked against every other gun's cone. Nobody checks that
pressing the trigger twice on a semi-auto fires twice.

## What verification exists today

Worth listing properly, because the instinct on reading "zero tests" is to
assume nothing is checked, and that is wrong.

| Mechanism | What it proves | Runs |
|---|---|---|
| `Diagnostics` boot manifest | 27 server / 18 client systems are loaded *and* reported; a syntax error is one DEAD line, not a dead server | every boot |
| `Remotes.assertHandlers` / `assertListeners` | every declared remote has something on the other end | every boot |
| `ContentAudit.run` | config id ↔ asset folder, **both directions** | every boot |
| `CombatStats.validate` | every attachment/perk modifier names a real stat | every boot |
| `Movement.validate` | state graph reachable from Idle, slide curve monotonically decays, no direction faster than forward, no Sprint-without-TacSprint trap | every boot |
| `Recoil.validate` | no bloom (three separate ways), no downward kick, no permanent offset after 10s | every boot |
| `Handling.validate` | derived handling timings land where the config says | every boot |
| `Balance.validate` | TTK spread, falloff engages, class charter, no limb one-shots, no secondary competing up close, every gun has a `why` | every boot |
| `Attachments.validate` | no attachment is a strict upgrade | every boot |
| `Rarity.validate` | the eight tiers | every boot |
| `CameraRig` drift audit | nothing outside the render chain is writing the camera — catches the *symptom*, so it works for code nobody has written yet | every frame |
| `MoveAudit` | server-side speed sampling against `Movement.speedFor` | runtime |
| `tools/validate_assets.sh` | `.obj` geometry, naming, tri budgets, muzzle down −Z | manual |
| `scripts/check-tokens.sh` | no raw `Color3` in client chrome | manual |

Two of these deserve special mention because they are the pattern worth
extending: `ContentAudit` checks both directions (a config with no asset *and*
an asset with no config), and the `CameraRig` audit checks the symptom rather
than the syntax. Both are checks that keep working when the thing they guard
gets rewritten.

## The seams are already cut

This is the part that makes the case. The codebase was deliberately built to be
testable and then never tested. Not paraphrased — these are comments already in
the source:

- `Systems/Weapon.luau:28` — *"Time is an accumulated clock advanced by `step`,
  never os.clock(). It makes the whole machine testable without waiting real
  seconds."*
- `Systems/Weapon.luau:589` — *"Public and driven by the caller, for the same
  reason Ballistics.step and Health.step are: a machine only reachable through
  Heartbeat can only be tested by waiting real seconds and hoping the frame rate
  cooperates."*
- `Systems/Recoil.luau:18` — *"The RNG is injectable. That is what makes 'fire 30
  rounds twice and get the same shape' a thing a test can assert rather than a
  thing someone eyeballs."*
- `Systems/Recoil.luau:257` — *"Deterministic when handed a seeded Random, which
  is what makes 'same gun, same 30 shots, twice — identical grouping' an
  assertion rather than a squint at two screenshots."*
- `Systems/CombatStats.luau:440` — *"`clearCache` exists for tests and for
  hot-reloading balance in Studio."*

Injectable RNG. Accumulated clocks instead of `os.clock()`. Public `step()`
functions on every simulation. A cache-clear entry point that says "for tests"
in its own comment. The hard part of making this codebase testable is **done**.
What is missing is the twenty lines that call it.

## The gaps, worst first

### 1. `Weapon.luau` — 625 lines, the highest-consequence module in the game, zero verification

No `validate()`. No `Diagnostics` reporting of any kind. **It is not in the boot
manifest on either side** — `Diagnostics.expect` on the server names Handling,
Recoil, CombatStats, Movement, Balance and Attachments, and does not name
Weapon. The client's list does not either.

This is the module both sides run to answer "may this player fire right now".
Its own header says why that matters: *"the alternative is a client that decides
it can fire and a server that decides it cannot, and the symptom is not an
error: it is a gun that occasionally does nothing, at a rate nobody can
reproduce, which every player will describe as lag."*

It is a pure state machine with an injected clock. It is the single easiest
thing in this repository to test, and the most expensive thing to get wrong.

Behaviours that are documented as deliberate and guarded by nothing:

- **A swap is not a free reload.** `equip()` carries `ammo` across. Getting this
  wrong makes weapon-swapping strictly better than reloading — the exact exploit
  the comment at line 226 calls out.
- **A trigger held through a swap must not fire the new gun.** `state.triggerConsumed
  = state.triggerHeld` at line 250, with a comment saying clearing it there "is
  how a swap becomes a free shot".
- **Semi-auto is one shot per press**, so a macro is no faster than a finger.
- **A burst gun cannot be made to fire like an auto by holding the button** —
  `burstRpm` inside the burst, `shotInterval` between them, and `minInterval()`
  is what the server's ballistics gate uses because for a burst gun the fire
  rate is the wrong number.
- **Reload cancel keeps rounds that already landed** and loses ones that
  haven't — `reloadAmmoAt` is described as "the single most important number in
  how a reload feels".
- **Shell reloads: the first shell is the payout**, and pulling the trigger cuts
  the reload short and fires what is in the tube.
- **A press on an empty gun is spent; a press while sprinting or drawing is
  buffered.** Lines 564–572 describe consuming on "sprinting" as the first
  version and the wrong one, because it "feels precisely like the gun failing to
  fire".

And one that is not hypothetical. Lines 614–619 document a bug that already
happened and was already fixed:

> *"The first version recomputed it, and once the magazine was full the while
> loop stopped running and left `shellNextAt` a whole shell past the last one —
> so the reload loaded every shell correctly and then never ended, which
> presents as a gun that will not fire again."*

There is a comment preventing that regression. There is no test preventing it.
The comment survives exactly as long as the next person reads it.

**Proposed tests** (~15, all pure, no DataModel needed beyond a resolved stats
table): the seven bullets above, plus the shell-reload termination case by name.

### 2. `Recoil` — the harness is written, the assertion is missing

`Recoil.validate()` is the best check in the codebase: it measures
`Handling.spread` before and after a full magazine and after ten seconds of
stepping, bit-for-bit, and calls the no-bloom rule a failure if the number
moves. That is checking a *guarantee*, not a value.

Two problems.

**The determinism claim is never asserted.** `Recoil.simulate` exists, per its
own comment, so that "same gun, same 30 shots, twice — identical grouping" can
be an assertion. Nothing asserts it. Two calls with the same seeded `Random`
should produce identical point lists; that is four lines and it is not there.

**`validate()` shares one `Recoil.State` across all 45 guns.** `local burst =
Recoil.create()` sits outside the `for id in GunCatalog.guns` loop, so each gun
starts from whatever residue the previous gun left. It happens to work, because
the ten-second settle drives it to exactly zero — but the check that the settle
*reaches* zero is one of the assertions being made with that same state. The
check is holding itself up. Move `create()` inside the loop and the guns become
independent; if anything then fails, it was a real failure being masked.

**It also runs on every live server boot.** 45 guns × ~645 `exp()`-driven steps
each is roughly 29,000 iterations of pure balance math, paid by every player-
facing server, to check something that can only change when someone edits a
config file. This belongs in CI, not in the boot path.

### 3. Server authority and the exploit surface — asserted in prose, tested nowhere

The non-negotiables in `CLAUDE.md` read like a test plan:

> Gun trials must never grant ownership. No glitch path to a free gun.
> Loadout changes are lobby-only.
> All purchases and ownership are server-derived from the profile.

The enforcement is real and structural — a trial is a key in
`WeaponService.trials`, never a profile write, and `GunShopService.buyIntoList`
does the ownership check *inside* `PlayerDataService.update` specifically so a
double-buy has no window. That design is right. Nothing asserts it stays right.

**Proposed tests:**

- `startTrial` → advance past `expiresAt` → `endTrial`: the profile's
  `ownedGuns` is byte-identical to before. Also across `endTrial` called twice,
  and across an `EquipLoadout` mid-trial (which calls `endTrial` at
  `GunShopService.luau:166`).
- Two `BuyGun` calls for the same gun in the same tick debit the price once.
- `buyIntoList` with `coins` exactly equal to `price` succeeds and leaves 0;
  with `price - 1` fails and debits nothing.

Also worth a look while writing these: `onAimState` honours the client's ADS
claim, and `WeaponService.spreadFor` only overrides it when
`MoveAudit.lastSpeed(player)` returns a number. For a player who has just
spawned and has no samples yet, `measured` is `nil` and the claim is honoured
unconditionally. That may be fine — it is a narrow window and the payoff is a
tighter cone for a moment — but it is currently an accident rather than a
decision, and a test is how it becomes a decision.

### 4. `Guard` — 72 lines, standalone, zero requires, completely untested

The only file in `shared/` with no dependencies at all. It could be unit-tested
today with no shim, no harness, no DataModel. It is the front door for every
remote in the game.

`checkRate` has a real edge worth pinning: the window resets on the first call
after expiry and returns with `count = 1`, so a client that times its calls to
straddle a boundary gets `maxCalls` at the end of one window plus a fresh
`maxCalls` immediately. That is normal fixed-window behaviour and probably fine
at these limits — but "probably fine" is what a test turns into "fine".

`isUnitVector` accepts magnitudes within 0.01 of 1. `isFiniteNumber` rejects
NaN via `value == value` and both infinities. `isString` defaults to 100 chars.
All four are one-liners to test and all four are load-bearing.

### 5. `PlayerDataSchema.migrate` — 521 lines, VERSION 3, nothing checks it

The only code in the repository that can **permanently destroy player data**. A
bad migration is not a bug you fix forward; the profile is already written.

`migrate` runs `while version < VERSION` over a `Migrations[n]` table, then
`reconcile` fills missing keys from the default profile. Nothing checks that:

- a v1 profile survives to v3 with its purchases intact
- migrations are idempotent (running `migrate` on an already-v3 profile is a
  no-op)
- `reconcile` does not overwrite a legitimately-empty list with a default one
- a profile with a garbage `version` (string, nil, 99) lands somewhere sane

This is the highest blast radius per line in the codebase and it has the least
coverage. It also uses relative `script.Parent.Parent` requires rather than
`game:GetService`, which makes it one of the two easiest files to get under a
headless harness.

### 6. Three of the five structural rules are honour-system, and two have already drifted

`CLAUDE.md` lists five structural rules. Two are enforced by boot assertions and
three are not:

| Rule | Enforced by | Status |
|---|---|---|
| 1. `shared/Config` is data — a config containing an `if` is wrong | nothing | **drifted** |
| 2. `shared/Systems` owns every shared answer | nothing | unmeasured |
| 3. Dependency direction is Service → Systems → Config | nothing | **violated** |
| 4. An asset folder name IS its config id | `ContentAudit` | holding |
| 5. Every remote is declared by the system that handles it | `assertHandlers` / `assertListeners` | holding |

Rule 3 is violated once, concretely: `Config/Rarity.luau:15` requires
`Systems/Diagnostics`. A Config is supposed to require nothing but Config.

Rule 1 has drifted further. `Rarity` (6 functions incl. `validate()`),
`GunCatalog` (4, including a `pcall(require)` assembly loop), `GunSkinCatalog`
(2) and `CatalogConfig` (real branching at lines 109 and 113) all contain
behaviour. Several other configs expose a bare `get(id)` accessor, which is
probably an intended exception — but nothing writes that exception down, and an
unwritten exception is how a rule stops meaning anything.

Both rules are checkable statically in about twenty lines of shell, in the exact
style of `check-tokens.sh`, which already proves the pattern works: it is the
only thing standing between the client UI and 95 scattered `Color3.fromRGB`
calls.

### 7. Nothing runs headless, and the most expensive outage on record would have been caught by a parser

There is no `.github/` directory. `rokit.toml` pins `selene 0.28.0` and there is
no `selene.toml`, so the linter is installed and never run. `stylua.toml` exists
and nothing enforces it.

From `CLAUDE.md`:

> On 2026-08-10 a single parse error in `LobbyService` (`(Vector3, Vector3)?`,
> which Luau does not allow) had kept the **entire server dead** since commit
> `a09307c`: no round loop, no combat, no lobby camera, no cursor release, no
> pads. Every "separate bug" reported for days was that one dead server.

That is a **parse error**. Any headless Luau parse step — `luau-lsp analyze`
against a `rojo sourcemap`, or `selene`, which is already pinned — rejects it in
seconds. Days of debugging, on a class of failure a CI job catches before the
push lands. `Diagnostics.load` was built afterwards to contain the blast radius,
and it does its job well; a CI gate stops the commit existing.

This is the cheapest item on this list by a wide margin and it should go first.

### 8. Client controllers — 9,398 lines, largely unverified

`LoadoutController` is 1,587 lines with zero `Diagnostics` calls.
`EffectsController` (485), `SettingsController` (348), `ShopController` (316),
`StatBlock` (419), `GunPreview` (278) — same. They are inside the manifest via
`Diagnostics.start`, so a throw during `init` is contained and named, which is
the important half. But "init did not throw" is a long way from "the loadout
screen works".

This is the lowest-priority item here, deliberately: UI is where automated tests
cost the most and catch the least, and Titus playtesting is a better instrument
than anything we would write. The exception is `LoadoutController` — at 1,587
lines it is the largest file in the project and it owns loadout state, which is
server-authoritative and therefore has a testable seam that the rest of the UI
does not.

## What to build, in what order

**Stage 1 — CI gate. Days, not weeks, and it pays for itself immediately.**

A GitHub Actions workflow on push that runs:

- `rojo sourcemap --output sourcemap.json` then `luau-lsp analyze` — catches
  parse errors and `--!strict` violations before they reach Studio
- `selene src` — already pinned, needs a `selene.toml`
- `stylua --check src`
- `bash scripts/check-tokens.sh` — exists, currently manual
- `bash tools/validate_assets.sh assets/stage1` — exists, currently manual

Nothing new to write except the workflow file and a selene config. This is the
step that would have prevented the worst outage in the project's history.

**Stage 2 — a headless harness for the pure modules.**

The obstacle is that fourteen of the `shared/` modules open with
`game:GetService("ReplicatedStorage")` and then `require` by instance, which
pins them to a live DataModel. Two do not: **`Net/Guard.luau` requires nothing
at all**, and **`Data/PlayerDataSchema.luau` uses relative `script.Parent`
requires**. Those two can be tested with Lune today, as a proof that the
approach works, before anything is refactored.

For the rest, a Lune shim of maybe 60 lines — a fake `game` whose
`GetService("ReplicatedStorage").Shared.Systems.X` resolves to a real
filesystem `require`, built off `rojo sourcemap` — unlocks `Weapon`,
`CombatStats`, `Movement`, `Recoil`, `Handling` and `Attachments` without
touching a single line of game code. That is the highest-value order:

1. `Guard` and `PlayerDataSchema` (no shim needed)
2. `Weapon` — the fifteen tests in §1
3. `Recoil` determinism, plus the `create()`-inside-the-loop fix
4. `CombatStats` — order-independence of adds vs muls, clamp behaviour, and
   that the cache key really does treat `{Grip, Comp}` and `{Comp, Grip}` as one
   entry
5. Trial and purchase invariants from §3

**Stage 3 — move the expensive validators out of boot.**

Once CI can run them, `Recoil.validate` and `Balance.validate` should run there
and fail the build, rather than running on every live server and emitting a
`Diagnostics.warn` that ships anyway. Boot keeps the cheap structural checks —
`assertHandlers`, `ContentAudit`, `Movement`'s graph walk — which are the ones
that depend on the actual place file and genuinely cannot run headless.

That is the real division: **checks that need the place file stay at boot;
checks that only need the config belong in CI.** Right now everything is at boot
because boot is the only place that exists.

## What not to test

Worth writing down, so the list above does not grow by default.

- **Anything measured on a live Humanoid.** The numbers in `CLAUDE.md` — `mass×90`
  → 0.60 studs, `math.huge` → 24.30, the mantle landing within 0.05 studs — came
  from driving a real character in a real session. No harness reproduces the
  Roblox solver, and a mock of it would assert our belief about the engine
  rather than the engine.
- **Camera feel.** The `CameraRig` drift audit already catches the failure that
  matters (something writing outside the chain) by symptom. Whether recoil
  *feels* right is Titus's call and always will be.
- **Most UI.** See §8.
- **`AssetTree` / `AssetRegistry` / `GunModelLoader`.** They exist to read the
  place file, which is not in git. `ContentAudit` covers the part that can be
  covered from config.

## The one-line summary

The infrastructure that proves the game *booted* is genuinely strong. The
infrastructure that proves the game *works* does not exist — and every seam it
would need was already cut, deliberately, months ago.
