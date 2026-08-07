# Pink Panic — Art Direction Lock (NOD-35)

The spec all M5+ assets obey. Derived from the approved lobby/UI concept art.

## Palette

| Role | Hex | Usage |
| --- | --- | --- |
| Hot pink | `#FF5CA8` | Primary accent: buttons, strokes, highlights, your row |
| Deep pink | `#D6428F` | Headings, emphasized text |
| Bubblegum | `#FF82BE` | Weapon grips, secondary accents |
| Blush | `#FFE3F0` | Panel backgrounds |
| Pink white | `#FFF5FA` | Rows, cards, weapon bodies |
| Text plum | `#60384E` | Body text on light panels |
| Plum dark | `#5C4858` | Weapon hardware (barrels, guards) |
| Princess gold | `#FFC458` | Coins, Legendary rarity, 1st place |
| Error red | `#DC3C50` | Errors, low health, kill emphasis |

Rules: backgrounds stay in the blush/white range; hot pink is an accent, never
a fill for large areas; gold is reserved for money, winners, and Legendary.

## UI

- Font: **Fredoka One** (bubbly, rounded) everywhere; no mixed fonts.
- Corners: 10–18px radius. Nothing sharp.
- Panels: blush background, 2px hot-pink `UIStroke` at ~35% transparency.
- Iconography: hearts 💗, bows 🎀, crowns 👑, sparkles. Max one emoji per label.
- Rarity colors: Common `#96828F` · Rare `#5A8CEB` · Epic `#AA5ADC` · Legendary `#EBA032`.

## 3D asset budgets

| Asset type | Max triangles | Notes |
| --- | --- | --- |
| Weapon (world/viewmodel) | 3,000 | One mesh + up to 4 attachments |
| Charm | 500 | Single mesh |
| Lobby prop (small) | 1,500 | Benches, lamps, gifts |
| Lobby centerpiece | 8,000 | Fountain, arch — one per scene |
| Map structural piece | 2,000 | Walls, floors modular kit |

## Textures

- Weapon skins: one 512×512 albedo per skin, shared UV layout across all
  weapons of a class (a skin is ONE texture applied to any weapon mesh).
- Props: 256×256, atlas shared per prop family.
- No normal/roughness maps for MVP — SmoothPlastic + color does the work.
- Style: flat pastel fills, soft gradients, minimal decals (hearts/bows only).

## Sound (NOD-40 guidance)

Cute > realistic: pops, chimes, sparkles. Gunshots are soft "pops," never
harsh. Lobby music: soft, dreamy, ~90 BPM. Victory: bright chime melody.

## Placeholder → final swap

Code-built part models (WeaponModels.luau) define the silhouette and part
names (`Slide`, `Grip`, `Charm` are skin-recolorable). Final meshes must keep
those named parts (or equivalent attachment points) so the skin/charm systems
keep working unchanged.
