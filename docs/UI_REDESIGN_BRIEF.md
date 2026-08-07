# Pink Panic — UI Redesign Brief (NOD-36 Core UI Kit)

You are redesigning the entire in-game UI of Pink Panic, a cute pink Roblox
FFA shooter. The logic works; the visuals are programmer-art. Your job is to
make every screen look like the approved concept art without breaking any
behavior.

## References (read first)

1. `docs/ART_DIRECTION.md` — the locked palette (exact hex values), font,
   corner radii, rarity colors, iconography rules. This is law.
2. The lobby/UI concept mockup (ask Titus for the image): soft pink panels,
   white rounded cards, hearts/bows, glow accents, gold for currency —
   specifically its PLAYERS list, shop cards with rarity + price footers, and
   chunky rounded menu buttons.

## Hard constraints

- **Do not change any logic.** Every remote call, event subscription,
  `init()` signature, and data flow stays exactly as-is. You are restyling
  and restructuring visuals only.
- All UI is **built in code** (Instance.new) inside the controller files
  listed below. Keep it that way — no StarterGui assets, no external images
  (uploaded ImageLabels are fine ONLY if Titus uploads them and gives you
  asset ids; otherwise use UICorner/UIStroke/UIGradient shapes).
- Font: `Enum.Font.FredokaOne` everywhere.
- Must stay readable on small screens: prefer Scale + AnchorPoint layouts
  over fixed offsets where practical; test at 1280×720.
- The mouse-unlock system (`ClientData.updateMouseUnlock`) and the
  `ClientData.shopOpen` / `settingsOpen` flags must keep working — call them
  exactly where the current code does.
- Keep every existing keybind hookup (B shop, Tab scoreboard, ⚙️ settings).

## Step 1 — Build the UI kit (new file)

Create `src/client/UIKit.luau`: one module every controller imports. It owns
the palette constants (single source of truth — delete the per-file copies)
and returns styled component builders:

- `UIKit.panel(props)` — blush panel, 14–18px corners, hot-pink stroke,
  optional drop-shadow effect and open/close tween (scale + fade, ~0.15s).
- `UIKit.button(props)` — chunky rounded button, hot-pink fill, white
  Fredoka text, hover brighten + press shrink tweens.
- `UIKit.card(props)` — white rounded card for grids (shop items, rows) with
  optional rarity-colored stroke/glow.
- `UIKit.label(props)` — Fredoka text with size/color presets
  (title / heading / body / caption).
- `UIKit.bar(props)` — rounded progress bar (XP, health) with tweened fill.
- `UIKit.slider(props)` — the draggable slider (lift the working logic from
  `SettingsController.mkSlider`, restyle it).
- `UIKit.closeButton(parent, onClose)` — the ✕.
- Nice-to-have: `UIKit.sparkle(parent)` — subtle floating ✨/💗 particles for
  panel corners; keep it cheap (few TextLabels + tweens, no per-frame loops).

## Step 2 — Restyle every surface using the kit

| File (src/client/Controllers/) | Surfaces to redo |
| --- | --- |
| `EconomyController.luau` | Top-left coins + level + XP bar panel; "+n 🪙" gain pop |
| `RoundController.luau` | Top-center status pill; top-right PLAYERS panel (crown/rank/name/💗kills, self-row highlight); hold-Tab K/D board; round-end results overlay |
| `HudController.luau` | Bottom-center health bar + ammo/weapon panel; right-side killfeed rows |
| `HitFeedbackController.luau` | Crosshair, hitmarker ✕, floating damage numbers |
| `ShopController.luau` | 🛍️ Shop button; shop modal: header, scrolling card grid (preview swatch, name, rarity, price/Equip/Equipped ✓ footer), message line |
| `SettingsController.luau` | ⚙️ button; settings modal: sliders, starting-weapon picker, controls hint |

Specific upgrades wanted while you're in there:
- Shop cards: rarity-colored stroke + soft glow per `ART_DIRECTION.md` rarity
  colors; "Equipped ✓" state styled like the mockup's owned items; price row
  uses 💗 + gold text like the mockup.
- Panels animate open/closed instead of popping.
- Results overlay: bigger moment — winner name large, confetti-ish sparkles,
  your stats beneath.
- Health bar: hearts motif; smooth tween on damage; keep the low-health red.
- Killfeed rows: slide in from the right, fade out.
- Buttons: consistent hover/press feedback everywhere.

## Step 3 — Verify (2-player test in Studio)

Rojo-sync, run a Clients-and-Servers 2-player test, and confirm: shop buy +
equip flows work with readable insufficient-funds errors; settings sliders
persist; Tab board and PLAYERS panel update on kills; mouse unlocks in shop
and settings and relocks after; nothing overlaps at 1280×720; no errors in
the client console.

## Definition of done (NOD-36 acceptance)

- [ ] Reusable buttons, panels, modals, rounded corners in one kit module
- [ ] Cute font + icon accents (hearts, bows) consistently applied
- [ ] Every listed surface uses the kit; zero behavior changes
