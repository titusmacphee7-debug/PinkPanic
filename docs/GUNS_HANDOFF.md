# Pink Panic — Guns, Skins & Camos Handoff (for Claude Code)

> **Paste-this prompt for Claude Code:**
> "Read `docs/GUNS_HANDOFF.md` fully, then implement it phase by phase starting
> with Phase A. Follow the module conventions in README.md (strict Luau,
> Services/Controllers, remotes only in `Remotes.luau`, Guard validation,
> server authority). Ask before changing anything marked OPEN QUESTION."

Everything in this doc was prepared in a Cowork session on 2026-08-09. Assets
are already committed to the repo; this doc is the spec for wiring them into
gameplay, the shop, and persistence.

---

## 1. What's already in the repo (do not regenerate)

| Path | What it is |
| --- | --- |
| `assets/meshes/guns/` | **Use these.** The 32 roster gun OBJs, already extracted: UV-mapped, palette-colored, split into parts named `Body`/`Panel`/`Grip`/`Hardware`/`Accent`. Muzzle faces **-Z**, up is **+Y**, scaled to studs (pistols ~3.2, snipers ~6.5 long). Shared `pink_guns.mtl`. The 8 dropped lookalikes are quarantined in `guns/dropped/`. |
| `assets/meshes/pink_guns_uv.zip` | Source archive of all 40 (same files). Keep as backup. |
| `assets/meshes/pink_guns.zip` | Older export, **no UVs** — textures render blank on these. Superseded; ignore. |
| `assets/meshes/pistol.obj` | Hand-built "marshmallow" hero pistol (2,640 tris, parts `Slide/Frame/Grip/Accent/Guard/Barrel/Tip/Charm`). Candidate replacement for the code-built Pistol viewmodel later; not part of the 40-gun roster. |
| `assets/textures/camo_*.png` | 10 seamless 512×512 universal camo textures (list in §5). |
| `assets/previews/*.png` | Contact sheets: all 40 recolored guns, 8×3 skin variants, camo swatches. Show these to Leah. |
| `src/shared/Config/GunSkinCatalog.luau` | Generated, `--!strict`. 120 per-gun color skins (3 per gun, Common 100 / Rare 150 / Epic 300), 10 universal camo defs (`textureId = ""` TODOs), plus `applyColorSkin()` and `applyUniversalCamo()`. Inert until required. |

License: all 40 meshes are CC0 (Quaternius Ultimate Gun Pack) — no credit or
payment required, safe for commercial Roblox use.

## 2. Human-only Studio tasks (Titus does these; Claude Code cannot)

1. The 32 roster OBJs are already extracted in `assets/meshes/guns/`. For
   each one: **Avatar → 3D Importer** → pick the OBJ → import as one Model.
   Scale unit: Studs. Each import yields MeshParts named
   `Body/Panel/Grip/Hardware/Accent` (some guns lack `Panel`/`Accent` — fine).
2. If .mtl colors don't survive import, recolor parts manually:
   Body `255,245,250` · Panel `255,227,240` · Grip `255,130,190` ·
   Hardware `92,72,88` · Accent `255,92,168`. Material: SmoothPlastic.
3. Group imports under `ReplicatedStorage/Shared/Assets/GunModels/<GunId>`
   (e.g. `GunModels/Pistol_1`). Keep the exact GunIds from §3.
4. **Asset Manager → Bulk Import** the 10 `assets/textures/camo_*.png`, then
   paste each `rbxassetid://...` into the matching TODO line in
   `GunSkinCatalog.luau`.
5. Per gun: set `Body` as PrimaryPart, add an Attachment named `Muzzle` on
   `Body` at the barrel tip (muzzle faces -Z, so roughly
   `(0, <barrel height>, -<halfLength>)`). WeldConstraint other parts to Body.
   — Claude Code: write a Studio MCP script or a one-shot setup module to
   automate step 5 across all imported models instead of doing it by hand.

## 3. Gun roster — 32 guns (8 near-duplicates dropped)

**Dropped** (lookalikes, per Titus): `Pistol_2`, `Revolver_2`, `SubmachineGun_5`,
`Shotgun_2`, `AssaultRifle_5`, `AssaultRifle2_2`, `Bullpup_3`, `SniperRifle_6`.
Their GunSkinCatalog entries can stay (harmless) or be pruned — pruning
preferred for tidiness.

Every gun is **hitscan** (matches existing WeaponService). Stats below are
**starting points for playtests**, tuned so nothing is strictly better —
higher price buys a different *feel*, not a straight upgrade. `HS` =
headshot multiplier. Shotgun dmg = per-pellet × pellet count. Prices assume
~75–200 coins per round (EconomyConfig); top gun ≈ 60–80 good rounds.

### Secondaries — Pistols
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pistol_1 | **Pip** | Common | Free | 25 | 380 | 12 | 1.6 | 1.5 | Starter. Honest, snappy. |
| Pistol_3 | **Stiletto** | Rare | 1,200 | 30 | 300 | 10 | 1.7 | 1.6 | Long slide, more reach. |
| Pistol_5 | **Pixie** | Epic | 4,000 | 18 | 560 | 18 | 1.8 | 1.4 | Fast little machine pistol. |
| Pistol_6 | **Dolly** | Common | 500 | 24 | 400 | 14 | 1.6 | 1.5 | Pip sidegrade, bigger mag. |
| Pistol_4 | **Jawbreaker** | Epic | 4,500 | 50 | 150 | 7 | 2.2 | 1.8 | The deagle. Wham. |

### Secondaries — Revolvers
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Revolver_4 | **Smooch** | Common | 400 | 40 | 190 | 5 | 2.2 | 1.8 | Snub. Cheap heartache. |
| Revolver_1 | **Heartbreaker** | Rare | 1,600 | 45 | 180 | 6 | 2.4 | 2.0 | The classic. |
| Revolver_3 | **Longing** | Epic | 4,400 | 48 | 160 | 6 | 2.5 | 2.0 | Long barrel, tighter spread. |
| Revolver_5 | **Drama Queen** | Epic | 4,200 | 55 | 130 | 5 | 2.7 | 2.0 | Heavy frame, huge hits. |

### Primaries — SMGs
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SubmachineGun_1 | **Chatterbox** | Common | 700 | 15 | 850 | 32 | 1.9 | 1.3 | Spray, giggle, repeat. |
| SubmachineGun_3 | **Zoomie** | Rare | 2,200 | 14 | 950 | 25 | 1.7 | 1.3 | Fastest fire rate in game. |
| SubmachineGun_2 | **Bubbler** | Rare | 1,500 | 18 | 720 | 30 | 2.0 | 1.35 | Controllable all-rounder. |
| SubmachineGun_4 | **Jitterbug** | Epic | 5,200 | 16 | 880 | 40 | 2.2 | 1.3 | Big mag, big feelings. |

### Primaries — Shotguns
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shotgun_1 | **Big Boop** | Common | 900 | 8×9 | 70 | 6 | shell 0.6 | 1.3 | Standard pump. |
| Shotgun_ShortStock | **Scrunchie** | Rare | 1,400 | 8×8 | 80 | 5 | shell 0.55 | 1.3 | Snappier handling. |
| Shotgun_SawedOff | **Shortcake** | Rare | 1,800 | 9×10 | 90 | 2 | 2.3 | 1.2 | Two shots, huge spread, run. |
| Shotgun_4 | **Double Trouble** | Epic | 4,000 | 9×9 | 110 | 2 | 2.5 | 1.3 | Full-length double. Duelist. |
| Shotgun_3 | **Homemaker** | Epic | 6,000 | 8×10 | 65 | 7 | shell 0.6 | 1.35 | Stocked pump, tight pattern. |

### Primaries — Rifles (AK family)
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AssaultRifle_2 | **Gumdrop** | Rare | 2,000 | 24 | 570 | 30 | 2.3 | 1.4 | The AK. Thumpy. |
| AssaultRifle_3 | **Cherry Bomb** | Epic | 5,000 | 26 | 540 | 30 | 2.4 | 1.45 | Harder hits, more kick. |
| AssaultRifle_4 | **Picnic Punch** | Epic | 6,000 | 24 | 590 | 30 | 2.2 | 1.4 | Folding stock, quicker swap. |
| AssaultRifle_1 | **Grump** | Epic | 6,800 | 28 | 500 | 25 | 2.5 | 1.5 | The dark one. Moody DMR-ish AK. |

### Primaries — Carbines (M4 family) + Bullpups
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AssaultRifle2_1 | **Sweet Talker** | Epic | 5,500 | 21 | 680 | 30 | 2.1 | 1.4 | The M4. Smooth + accurate. |
| AssaultRifle2_3 | **Sprinkler** | Rare | 2,800 | 19 | 720 | 30 | 2.1 | 1.35 | Spray-friendly carbine. |
| AssaultRifle2_4 | **Chunky** | Legendary | 9,000 | 23 | 650 | 35 | 2.3 | 1.45 | CQB brick. Best all-rounder. |
| Bullpup_1 | **Marshmallow** | Rare | 2,500 | 20 | 660 | 36 | 2.4 | 1.4 | Squishy-looking, laser-accurate. |
| Bullpup_2 | **Toastie** | Epic | 4,800 | 22 | 620 | 36 | 2.5 | 1.45 | Marshmallow's spicy sibling. |

### Primaries — Snipers
| GunId | Name | Rarity | Price | Dmg | RPM | Mag | Reload | HS | Identity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SniperRifle_1 | **Whisper** | Rare | 3,000 | 70 | 55 | 5 | 2.8 | 2.0 | Entry bolt. Two-tap body. |
| SniperRifle_3 | **Scout's Honor** | Epic | 5,800 | 60 | 75 | 6 | 2.6 | 2.0 | Fast scout, mobile. |
| SniperRifle_2 | **Long Kiss** | Epic | 6,500 | 90 | 45 | 5 | 3.0 | 2.0 | The classic. HS deletes. |
| SniperRifle_4 | **Star Crossed** | Legendary | 10,000 | 100 | 38 | 4 | 3.2 | 2.0 | Heavy glass. One-tap body ≥100? No: 100 = exactly lethal — keep 95 if too strong. |
| SniperRifle_5 | **Heartstopper** | Legendary | 12,000 | 85 | 55 | 6 | 2.9 | 2.1 | Flagship tactical. |

**OPEN QUESTION (economy):** the ladder tops at 12,000 coins. If rounds pay
75–200, that's ~60–160 rounds to max out. If that feels grindy in playtests,
scale all prices by one multiplier in one place — don't hand-tune 32 numbers.

## 4. Data & systems spec

### 4.1 GunCatalog (new: `src/shared/Config/GunCatalog.luau`)
One entry per roster gun: `{ name, class ("Pistol"|"Revolver"|"SMG"|"Shotgun"|
"Rifle"|"Carbine"|"Bullpup"|"Sniper"), slot ("Primary"|"Secondary"), rarity,
price, stats { damage, rpm, magSize, reloadSeconds, headshotMult, pellets?,
shellReload?, spreadDeg, rangeStuds } }` — populate from §3 tables. `--!strict`,
same shape conventions as `CatalogConfig`.

### 4.2 Player data (`PlayerDataSchema.luau`)
Add: `ownedGuns: {string}` (GunIds; seed with `Pistol_1`),
`ownedGunSkins: {string}` (skin ids from GunSkinCatalog.perGun),
`ownedCamos: {string}` (camo ids), `loadout: { primary: string?, secondary:
string }`, `gunCosmetics: { [gunId]: { skinId: string?, camoId: string? } }`.
Migrate existing saves with sensible defaults (everything empty, secondary =
`Pistol_1`).

### 4.3 Purchase + equip flow (server-authoritative, per README rules)
- Remotes declared **only** in `Remotes.luau`: `BuyGun`, `BuyGunSkin`,
  `BuyCamo`, `EquipLoadout`, `EquipGunCosmetics`.
- Every handler: `Guard` type/range checks → `Guard.checkRate` → re-derive
  price/ownership **server-side** from GunCatalog/GunSkinCatalog. Never trust
  a client-sent price. Reject buying skins for guns the player doesn't own.
  Reject equipping unowned anything. All coin math through
  `PlayerDataService.update`.
- `WeaponService` builds the equipped gun's model from
  `ReplicatedStorage/Shared/Assets/GunModels/<GunId>`, clones it, applies
  cosmetics via `GunSkinCatalog.applyColorSkin` / `applyUniversalCamo`.
  Layering rule (per Titus/Leah pending): **camo overrides color skin**.
  `WeaponModels.build()` stays as fallback when a model is missing.

### 4.4 Shop UI (`ShopController`)
Three tabs: **Guns** (grid like the reference screenshot: silhouette, name,
price, rarity chip), **Skins** (per owned gun, 3 schemes), **Camos** (10
universal swatches — render the texture in an ImageLabel). Rarity colors from
`docs/ART_DIRECTION.md`: Common `#96828F`, Rare `#5A8CEB`, Epic `#AA5ADC`,
Legendary `#EBA032`. Blush panels, Fredoka One, 10–18px corners, max one
emoji per label. Locked items show price; owned show "Equip".

### 4.5 Viewmodel
`ViewmodelController` currently assumes the 4 code-built weapons. It must
accept any GunCatalog model; grip offset per class (constant table is fine
for MVP). Muzzle flash / tracer origin = the `Muzzle` attachment.

## 5. Universal camos (already in GunSkinCatalog.universal)
Gingham Picnic + Candy Stripe (Rare 250) · Sweetheart, Sprinkles, Leopard
Luxe, Pink Camo, Hex Tech, Cow Cutie (Epic 400) · Starlight, Galaxy Berry
(Legendary 600). TextureIds are blank until Titus finishes §2 step 4 — code
should treat blank textureId as "not yet purchasable" (hide or gray out).

## 6. Implementation order (suggest one Linear issue each)
- **Phase A — Catalog + data**: GunCatalog.luau, schema migration, prune
  dropped guns from GunSkinCatalog. No behavior change.
- **Phase B — Purchases**: remotes + ShopService handlers + validation. Test
  with mock UI or command bar before real UI.
- **Phase C — Equipping + combat**: WeaponService consumes GunCatalog stats;
  loadout selection; viewmodel handles arbitrary models; cosmetics applied on
  spawn.
- **Phase D — Shop UI**: the three tabs, buy/equip states.
- **Phase E — Balance pass**: playtest, tune §3 numbers, price multiplier.

## 7. Test checklist
- Buy each rarity tier once; coins deduct exactly; double-buy rejected.
- Buy attempt with insufficient coins rejected server-side (test by firing
  the remote directly, not through UI).
- Equip unowned gun/skin/camo rejected; loadout persists through rejoin.
- Skin applies to world gun AND viewmodel identically; camo overrides skin;
  clearing camo restores color skin.
- Gun with no `Panel`/`Accent` parts skins without erroring.
- A missing GunModel falls back to `WeaponModels.build` without breaking spawn.
- DataStore migration: old save loads, gets `Pistol_1` + empty tables.

## 8. Open questions for Titus & Leah
1. Camo-overrides-skin layering — confirmed, or should camo tint with skin colors?
2. Loadout = Primary + Secondary + Knife? (doc assumes yes)
3. Star Crossed at 100 dmg = one-shot body. Intended power fantasy or nerf to 95?
4. Prune dropped-gun skins from GunSkinCatalog now, or leave until Phase A?
