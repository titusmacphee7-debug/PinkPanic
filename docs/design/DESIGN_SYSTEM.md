# Pink Panic — Design System

The brief for anyone (human or Claude Design) styling Pink Panic's UI.

Code lives in `src/client/UI/`:

| File | What it is |
|---|---|
| `Theme.luau` | Tokens only — colour, type, spacing, radius. No behaviour. |
| `Components.luau` | Builders — `text`, `panel`, `card`, `button`, `scroller`, `lockedScrim`, `modalBlocker`. |

**Rule zero: don't hardcode a colour or a pixel size in a controller.** Add a token to `Theme` and use it. `HOT_PINK` used to be declared in nine separate files and `TEXT_DARK` in five, which is why no two panels ever quite matched.

---

## The feel

A cute-pink FFA shooter. **Light, sweet, soft** — blush surfaces, plum text, hot pink for anything you can touch. Rounded everything; no hard corners anywhere in the UI.

**The audience is new players.** Readable beats clever, every time. If a choice trades clarity for style, take clarity.

Nothing in the UI should feel military, tactical, or grim — this is a candy shooter. Guns are treated like collectible toys, not weapons.

---

## Colour

All values are `Theme.color.*`.

### Brand
| Token | RGB | Use |
|---|---|---|
| `primary` | 255, 92, 168 | Buttons, selection, focus, anything interactive |
| `primaryDeep` | 214, 66, 143 | Headings, borders, pressed states |
| `primarySoft` | 255, 150, 200 | Glows, tracers, subtle accents |

### Surfaces — lightest to heaviest
| Token | RGB | Use |
|---|---|---|
| `surface` | 255, 227, 240 | Panel backgrounds (blush) |
| `surfaceRaised` | 255, 245, 250 | Cards and rows sitting on `surface` |
| `surfaceSunken` | 246, 208, 226 | Wells, tracks, empty slots, viewport backdrops |

### Text
| Token | RGB | Use |
|---|---|---|
| `text` | 96, 56, 78 | Body copy on light surfaces (plum) |
| `textMuted` | 150, 116, 134 | Secondary lines, stat rows, hints |
| `textOnPrimary` | 255, 245, 250 | Text sitting on hot pink |

### Semantic
| Token | RGB | Use |
|---|---|---|
| `coin` | 255, 196, 88 | Currency, prices |
| `danger` | 235, 90, 90 | Low health, errors |
| `kill` | 255, 64, 96 | Killfeed, elimination |
| `success` | 120, 200, 150 | Confirmations |
| `scrim` | 52, 28, 44 | Locked overlays, modal dimming |

### Rarity
Drives card borders and the rarity line. `Theme.rarityColor(name)`.

| Rarity | RGB |
|---|---|
| Common | 168, 150, 162 |
| Rare | 96, 168, 236 |
| Epic | 186, 108, 240 |
| Legendary | 240, 172, 60 |

**Dark values are for scrims and viewport backdrops only.** If a panel is coming out dark, it's wrong.

---

## Type

`FredokaOne` everywhere. It *is* the brand — don't introduce a second face.

| Token | px | Use |
|---|---|---|
| `display` | 34 | Round results, big moments |
| `title` | 26 | Panel titles |
| `heading` | 19 | Section headers |
| `body` | 15 | Default |
| `label` | 13 | Buttons, chips |
| `caption` | 11 | Stat lines, hints |

---

## Spacing & shape

4pt scale — `Theme.space.*`: `xs 4`, `sm 8`, `md 12`, `lg 20`, `xl 32`.

Radii — `Theme.radius.*`: `chip 10`, `card 14`, `panel 20`, `pill 999`.

Panels are padded `lg`. Grids gap `sm`.

---

## Components

```lua
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
```

| Builder | Notes |
|---|---|
| `text(parent, opts)` | `{ text, size, color, align, area, position, truncate, zIndex }` |
| `panel(parent, opts)` | Blush surface, rounded, soft pink border. `centered = true` to middle it. |
| `card(parent, opts)` | A `TextButton` so the whole tile is clickable. `accent` sets the border (pass a rarity colour); `selected` gives it the 3px pink border. |
| `button(parent, opts)` | `selected = true` → filled hot pink with `textOnPrimary`. |
| `lockedScrim(card, label)` | The locked pattern. See below. |
| `modalBlocker(parent)` | Invisible `Modal` button — the sanctioned way to free the first-person mouse lock. |
| `scroller`, `gridLayout`, `listLayout`, `corner`, `stroke`, `padding` | Plumbing. |

---

## Patterns

### Locked content
One implementation, `Components.lockedScrim`, so an unowned gun, skin, and camo all read identically: `scrim` at 45% over the whole card, centred 🔒, price in `coin` beneath.

**Locked should read as aspirational, not disabled.** The player should want it, not think it's broken. Keep the item's art visible through the scrim — never hide or grey it into mush.

### Panels and the cursor
Any full-screen panel needs a `modalBlocker`, and must set its `ClientData.*Open` flag and call `ClientData.updateMouseUnlock()`. Skip this and the cursor stays locked to the crosshair and the panel is unusable.

### Feedback
Errors come back from the server as `{ ok = false, error = "..." }`. Show the message inline near the title in `danger` and clear it after ~3s. Never a modal alert.

---

## Screens

| Screen | File | State |
|---|---|---|
| **Loadout** | `LoadoutController` | ✅ On the system. Reference implementation. |
| HUD | `HudController` | Own constants — migrate |
| Round / results | `RoundController` | Own constants — migrate |
| Settings | `SettingsController` | Own constants; its weapon picker is dead (NOD-119) |
| Armory | `ArmoryController` | Own constants; dormant until the interior is built |
| Shop | `ShopController` | Legacy — slated for deletion (NOD-119) |
| Economy / coins | `EconomyController` | Own constants — migrate |

Migration is safe to do one file at a time: `Theme` deliberately carries the same values those files already use, so swapping a constant for a token is a no-op visually.

**Don't restyle `ShopController`** — it's being deleted.

---

## The loadout screen (reference)

760×560 centred panel.

- Title, close button
- `Primary` / `Secondary` tabs
- 4-wide scrolling grid of 168×176 gun cards
- Horizontal camo chip row at the bottom

Each card: `ViewportFrame` with the **real 3D gun model** (top 78px, spinning, already wearing its equipped camo), name, `Class · Rarity`, a `26 dmg · 380 rpm` stat line, footer.

Five states that must stay unmistakable:

1. Owned, not equipped → footer "Tap to equip"
2. Owned + equipped → 3px pink border, "✓ EQUIPPED"
3. Unowned → locked scrim, 🔒, price
4. Camo chip owned / equipped
5. Camo chip unowned (price) vs unreleased ("coming soon")

The 3D preview is the hero of the card. Give it room.

---

## Hard constraints

- **Behaviour lives in the controllers.** Keep Instance names, `.Activated` handlers, `refresh()`, and `setOpen()` intact — the server validates every equip and purchase, and the wiring is load-bearing.
- `--!strict` in every file.
- No external image assets for gun art — previews are live `ViewportFrame` renders of the real models. Nothing to upload, and camos apply automatically.
- Camo textures are **not uploaded yet**: all 10 have `textureId = ""` in `GunSkinCatalog`. Design the "coming soon" state; it resolves itself once the IDs are pasted in.
