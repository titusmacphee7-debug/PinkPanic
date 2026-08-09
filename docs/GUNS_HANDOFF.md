# Pink Panic — Guns, Skins & Camos Handoff (for Claude Code)

> Prepared in a Cowork session on 2026-08-09. Assets live in `assets/` (meshes,
> textures, previews) — NOTE: as of Phase A implementation the assets were not
> yet pushed to the repo; Titus pushes them from the Cowork machine. This doc
> is the spec for wiring them into gameplay, the shop, and persistence.

## 1. Asset inventory (from the Cowork session)

| Path | What it is |
| --- | --- |
| `assets/meshes/guns/` | The 32 roster gun OBJs: UV-mapped, palette-colored, parts named `Body`/`Panel`/`Grip`/`Hardware`/`Accent`. Muzzle faces **-Z**, up **+Y**, scaled to studs (pistols ~3.2, snipers ~6.5). Shared `pink_guns.mtl`. Dropped lookalikes quarantined in `guns/dropped/`. |
| `assets/meshes/pink_guns_uv.zip` | Source archive of all 40 (backup). |
| `assets/meshes/pink_guns.zip` | Older export, no UVs — superseded; ignore. |
| `assets/meshes/pistol.obj` | Hand-built "marshmallow" hero pistol (2,640 tris). Candidate hero viewmodel; not in the roster. |
| `assets/textures/camo_*.png` | 10 seamless 512x512 universal camo textures. |
| `assets/previews/*.png` | Contact sheets for review. |

License: all 40 meshes are CC0 (Quaternius Ultimate Gun Pack) — safe for commercial use.

## 2. Human-only Studio tasks (Titus)

1. Avatar → 3D Importer per roster OBJ → import as one Model, scale Studs.
2. If .mtl colors don't survive: Body `255,245,250` · Panel `255,227,240` ·
   Grip `255,130,190` · Hardware `92,72,88` · Accent `255,92,168`, SmoothPlastic.
3. Group under `ReplicatedStorage/Shared/Assets/GunModels/<GunId>`.
4. Bulk Import the 10 camo PNGs; paste each `rbxassetid://` into
   `GunSkinCatalog.luau`.
5. Per gun: `Body` = PrimaryPart, `Muzzle` Attachment at barrel tip (-Z),
   WeldConstraint parts to Body. (Claude Code: provide a one-shot setup module
   to automate this across imports.)

## 3. Gun roster — 32 guns

Dropped lookalikes: Pistol_2, Revolver_2, SubmachineGun_5, Shotgun_2,
AssaultRifle_5, AssaultRifle2_2, Bullpup_3, SniperRifle_6.

All hitscan. Stats are playtest starting points; higher price buys a
different feel, not a straight upgrade. Full tables live in
`src/shared/Config/GunCatalog.luau` (source of truth from Phase A onward):
Pistols (Pip free starter, Dolly, Stiletto, Pixie, Jawbreaker) · Revolvers
(Smooch, Heartbreaker, Longing, Drama Queen) · SMGs (Chatterbox, Bubbler,
Zoomie, Jitterbug) · Shotguns (Big Boop, Scrunchie, Shortcake, Double
Trouble, Homemaker) · Rifles (Gumdrop, Cherry Bomb, Picnic Punch, Grump) ·
Carbines/Bullpups (Sweet Talker, Sprinkler, Chunky, Marshmallow, Toastie) ·
Snipers (Whisper, Scout's Honor, Long Kiss, Star Crossed, Heartstopper).

OPEN QUESTION (economy): ladder tops at 12,000 coins (~60–160 rounds). If
grindy, scale all prices by one multiplier — never hand-tune 32 numbers.

## 4. Systems spec

- **GunCatalog.luau**: one entry per gun `{ name, class, slot, rarity, price,
  stats { damage, rpm, magSize, reloadSeconds, headshotMult, pellets?,
  shellReload?, spreadDeg, rangeStuds } }`.
- **PlayerDataSchema**: `ownedGuns` (seed Pistol_1), `ownedGunSkins`,
  `ownedCamos`, `loadout { primary?, secondary }`, `gunCosmetics { [gunId]:
  { skinId?, camoId? } }`. Migrate old saves.
- **Remotes** (Remotes.luau only): `BuyGun`, `BuyGunSkin`, `BuyCamo`,
  `EquipLoadout`, `EquipGunCosmetics`. Guard checks + rate limits; server
  re-derives price/ownership; reject skins for unowned guns; all coin math
  via PlayerDataService.update.
- **WeaponService**: clone `GunModels/<GunId>`, apply cosmetics
  (camo overrides color skin — pending confirmation), fall back to
  `WeaponModels.build()` when a model is missing.
- **Shop UI**: tabs Guns / Skins / Camos; rarity colors per ART_DIRECTION;
  blank camo textureId = not yet purchasable (hidden/grayed).
- **Viewmodel**: accept arbitrary GunCatalog models; per-class grip offsets;
  Muzzle attachment = tracer origin.

## 5. Universal camos

Gingham Picnic, Candy Stripe (Rare 250) · Sweetheart, Sprinkles, Leopard
Luxe, Pink Camo, Hex Tech, Cow Cutie (Epic 400) · Starlight, Galaxy Berry
(Legendary 600). Blank textureId until Studio upload.

## 6. Implementation phases (one Linear issue each)

A catalog+data · B purchases · C equipping+combat · D shop UI · E balance.

## 7. Test checklist

Buy each rarity once (exact deduction, double-buy rejected) · insufficient
funds rejected server-side via direct remote fire · unowned equip rejected ·
loadout persists rejoin · skin applies world+viewmodel identically · camo
overrides skin, clearing restores · missing Panel/Accent doesn't error ·
missing GunModel falls back cleanly · old save migrates (Pistol_1 + empties).

## 8. Open questions (Titus & Leah)

1. Camo-overrides-skin layering — confirmed, or camo tints with skin colors?
2. Loadout = Primary + Secondary + Knife? (assumed yes)
3. Star Crossed 100 dmg = one-shot body: intended, or nerf to 95?
4. Prune dropped-gun skins now (done in Phase A) — confirm.
