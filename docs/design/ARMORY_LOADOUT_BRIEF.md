# Brief — Armory, Loadout, and the Gun Detail screen

Hand this file to Claude Design. It pairs with `docs/design/DESIGN_SYSTEM.md` (tokens, components, patterns) — read that first.

## What exists today

One screen, `src/client/Controllers/LoadoutController.luau`: a grid of all 32 guns where **clicking a gun equips it immediately**, with a camo strip along the bottom. That's wrong. It does too much in one place, buries the stats, and puts camos where they don't belong.

## What to build instead — two full-screen surfaces

**Both are FULL-SCREEN, not floating panels.** The current 760×560 centred card is too small for any of this. These should fill the viewport edge to edge, the way a console shooter's loadout menu does. Only small confirmations (buy, trial) stay as dialogs on top.

### 1. Loadout screen — "my kit"

Everything about the gear you already have. Full-screen, three regions:

**Your character.** A live 3D view of the player's avatar. *There is no outfit system yet* — clone `Players.LocalPlayer.Character` into a `ViewportFrame` and show the real Roblox avatar. Leave obvious room beside it for outfit/skin slots to land later; do not invent controls that don't exist yet.

**Your two weapon slots.** Primary and Secondary, each showing the equipped gun's 3D preview, name, class and current camo. Tapping a slot swaps to a picker of **owned guns for that slot only** — no prices, no locked guns.

**Stats and camos for the selected gun.** Selecting either slot fills a panel with that gun's full stat block (below) and its camos and colour skins, **buyable inline**. This is the difference from the old design: the loadout is where you tune the guns you own, not just pick them.

### 2. Armory screen — "the store"

The full roster, browsable. Full-screen. This is the shopping surface, and eventually the UI layer over the physical Candy Armory interior.

- All 32 guns, grouped or filterable by **class** (8 classes, listed below)
- Locked guns visible with price behind the standard `lockedScrim` — aspirational, never hidden
- **Clicking a gun opens the Detail view. It must NOT equip.** That is the single biggest change from today.
- Owned/price sort so the next affordable thing is obvious
- Coin balance always visible

### 3. Gun Detail — one gun, everything

Reached from the Armory. Can be a full-screen state or a large region of the Armory — designer's call, as long as it isn't a small popup.

- Large 3D preview, rotatable — the hero of the view
- Full stat block
- Price + **Buy** if unowned; **Equip to Primary/Secondary** if owned
- **Try it** (60s trial) if the range exists — see NOD-97
- Camos and colour skins for this gun
- Back to Armory

### Where things live

| | Loadout | Armory |
|---|---|---|
| Character + outfit | ✅ | — |
| Equipped slots | ✅ | — |
| Pick from owned guns | ✅ | — |
| Browse all 32 | — | ✅ |
| Buy guns | — | ✅ |
| Gun stats | ✅ | ✅ |
| Camos / skins | ✅ (owned guns) | ✅ (on Detail) |

---

## The stat block

These are the COD-style stats already implemented. Everything below is real and resolvable — nothing needs inventing. Get them with `CombatStats.resolve(gunId)`.

**Damage**
| Field | Notes |
|---|---|
| `damageNear` / `damageFar` | Two-point falloff. Show as a curve or a two-stop bar, not two numbers — this is the signature stat. |
| `rangeNear` / `rangeFar` | The studs those two damage values apply at |
| `headshotMult` | ×1.4 … ×1.7 |
| `pellets` | Shotguns only (5 guns, 8–10 pellets). Hide when 1. |

**Fire**
| Field | Notes |
|---|---|
| `fireRate` | Shots/sec. **Display as RPM** — multiply by 60. |
| `auto` | "Automatic" vs "Semi-Auto" |
| `magSize` | |
| `reloadSeconds` | |

**Accuracy & Recoil**
| Field | Notes |
|---|---|
| `spreadDeg` | Hip-fire cone. **Fixed — never grows. There is no bloom in this game.** |
| `adsSpreadDeg` | Aimed cone, always ≤ hip |
| `recoilVert` / `recoilHoriz` | Degrees of camera climb per shot |
| `recoilRecovery` | How fast it settles |

**Handling**
| Field | Notes |
|---|---|
| `adsTime` | Time to aim |
| `equipTime` | Time to draw |
| `sprintToFire` | Sprint → able to shoot |
| `moveSpeedMult` | Weapon weight. Show as ±% (0.98 → −2% speed). |

**Ballistics** — these are real; bullets are server-simulated projectiles, not hitscan
| Field | Notes |
|---|---|
| `velocity` | Studs/sec (800 – 2590) |
| `drop` | Gravity on the bullet |
| `travelMax` | Where the bullet dies (`rangeFar × 1.6`) |

### Two derived numbers worth showing

More useful to a player than any raw stat, and both computable client-side:

- **Shots to kill** = `ceil(100 / damageNear)` — health is always 100
- **TTK** = `(shotsToKill - 1) / fireRate` seconds

Show both at near range, and ideally at far range too.

### Presentation

Bars beat numbers for a new-player audience, but **don't hide the numbers** — this roster's identity is in the details, and players who care will look. Bars with the value printed alongside.

Normalise bars **per class**, not across the whole roster. A pistol scored against a sniper's range reads as broken.

---

## Camos

Ten universal camos in `GunSkinCatalog.universal`, and each gun has exactly **3** colour skins in `GunSkinCatalog.perGun[gunId]` (96 total, globally unique ids).

**All 10 camos currently have `textureId = ""`** — the PNGs in `assets/textures/` were never uploaded to Roblox, and the server refuses to sell them. Design the "coming soon" empty state; the section lights up automatically once the asset ids are pasted in.

Camos and skins both belong on the **Detail screen**, scoped to the gun being viewed.

---

## The 32 guns

23 Primary, 9 Secondary. 8 classes. Prices are final (already through the multiplier).

### Primary

| Class | Gun | Rarity | Price |
|---|---|---|---|
| SMG | Chatterbox | Common | 700 |
| SMG | Bubbler | Rare | 1,500 |
| SMG | Zoomie | Rare | 2,200 |
| SMG | Jitterbug | Epic | 5,200 |
| Shotgun | Big Boop | Common | 900 |
| Shotgun | Scrunchie | Rare | 1,400 |
| Shotgun | Shortcake | Rare | 1,800 |
| Shotgun | Double Trouble | Epic | 4,000 |
| Shotgun | Homemaker | Epic | 6,000 |
| Rifle | Gumdrop | Rare | 2,000 |
| Rifle | Cherry Bomb | Epic | 5,000 |
| Rifle | Picnic Punch | Epic | 6,000 |
| Rifle | Grump | Epic | 6,800 |
| Carbine | Sprinkler | Rare | 2,800 |
| Carbine | Sweet Talker | Epic | 5,500 |
| Carbine | Chunky | Legendary | 9,000 |
| Bullpup | Marshmallow | Rare | 2,500 |
| Bullpup | Toastie | Epic | 4,800 |
| Sniper | Whisper | Rare | 3,000 |
| Sniper | Scout's Honor | Epic | 5,800 |
| Sniper | Long Kiss | Epic | 6,500 |
| Sniper | Star Crossed | Legendary | 10,000 |
| Sniper | Heartstopper | Legendary | 12,000 |

### Secondary

| Class | Gun | Rarity | Price |
|---|---|---|---|
| Pistol | **Pip** | Common | **Free** (starter) |
| Pistol | Dolly | Common | 500 |
| Pistol | Stiletto | Rare | 1,200 |
| Pistol | Pixie | Epic | 4,000 |
| Pistol | Jawbreaker | Epic | 4,500 |
| Revolver | Smooch | Common | 400 |
| Revolver | Heartbreaker | Rare | 1,600 |
| Revolver | Drama Queen | Epic | 4,200 |
| Revolver | Longing | Epic | 4,400 |

Plus a **Knife**, always carried, slot 3. Not purchasable, not in the catalog.

Classes: `Pistol` `Revolver` `SMG` `Shotgun` `Rifle` `Carbine` `Bullpup` `Sniper`
Rarities: `Common` `Rare` `Epic` `Legendary` — colours in `Theme.rarity`

---

## Wiring — don't break this

The server validates everything; the UI only ever *asks*.

**Reading state** — `ClientData`:
```lua
ClientData.ownsGun(gunId)         -- boolean
ClientData.ownsCamo(camoId)
ClientData.ownsGunSkin(skinId)
ClientData.loadout()              -- returns (primary: string?, secondary: string)
ClientData.gunCosmeticsFor(gunId) -- returns (skinId: string?, camoId: string?)
ClientData.snapshot.coins
ClientData.changed                -- fires on every profile update
```

**Actions** — all `RemoteFunction:InvokeServer`, all return `{ ok = true }` or `{ ok = false, error = "..." }`:
```lua
Remotes.func("BuyGun"):InvokeServer(gunId)
Remotes.func("BuyCamo"):InvokeServer(camoId)
Remotes.func("BuyGunSkin"):InvokeServer(gunId, skinId)
Remotes.func("EquipLoadout"):InvokeServer(primary, secondary)   -- send BOTH slots
Remotes.func("EquipGunCosmetics"):InvokeServer(gunId, skinId, camoId)
Remotes.func("TryGun"):InvokeServer(gunId)                      -- 60s trial, lobby only
```

Show `error` inline in `Theme.color.danger`, clear after ~3s. Never a modal alert.

**3D previews:** `GunModelLoader.build(gunId, { skinId = skinId, camoId = camoId })` returns a ready model for a `ViewportFrame`. Set every `BasePart.Anchored = true` on the clone. There are **no thumbnails to upload** — previews are the real meshes and wear the real camo.

Rotate about the **bounding-box centre**, not the pivot: `PivotTo` positions the PrimaryPart, which is a different point, so feeding it the bbox CFrame shifts the model off-centre. See the existing `LoadoutController` spin loop for the correct form.

**Panels must** use `Components.modalBlocker` (full-screen, releases the mouse lock), set their `ClientData.*Open` flag, and call `ClientData.updateMouseUnlock()`. The old 1×1 offscreen modal button used by ShopController is broken — clicks pass straight through it into the game.

**Performance:** `ClientData.changed` fires on every coin gain. Do **not** rebuild a grid of `ViewportFrame`s on it — diff first. `LoadoutController.signature()` shows the pattern.

## Hard constraints

- `--!strict` everywhere
- All chrome from `Theme` / `Components` — no raw `Color3` in a controller
- Loadout changes are **lobby-only**; the server rejects them mid-round
- Gun trials must never grant ownership
- Target audience is new players: readable beats clever, every time
