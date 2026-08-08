# Handoff: Pink Panic — Full UI (lobby-first)

## Overview

Complete UI for **Pink Panic**, a cute pink Roblox FFA shooter. This covers the
walkable plaza lobby, the combat HUD, and every panel in between: shop, settings
/ armory, PLAYERS, scoreboard, news, killfeed, hitmarkers, nameplates.

The target codebase is **Roblox Luau**, synced with Rojo. Repo:
`titusmacphee7-debug/PinkPanic`, branch `claude/pink-panic-roblox-5g2w56`.
The authoritative spec is `docs/UI_REDESIGN_BRIEF.md` in that repo, with locked
values in `docs/ART_DIRECTION.md`. **Read both before starting — where this
document and the brief disagree, the brief wins.**

## About the Design Files

`Pink Panic UI.dc.html` in this bundle is a **design reference built in HTML** —
a prototype showing intended look and behavior. It is not production code and
none of it should be copied.

Your job is to **rebuild these designs in Roblox Luau** as code-built
`Instance.new` UI inside the existing Controllers, following the codebase's
established patterns. Every HTML construct here has a Roblox equivalent:

| HTML in the prototype | Roblox equivalent |
| --- | --- |
| `<div>` with background | `Frame` |
| `border-radius` | `UICorner` |
| `border` | `UIStroke` |
| `linear-gradient` background | `Frame` + `UIGradient` |
| `<span>` text | `TextLabel` (`Font = Enum.Font.FredokaOne`) |
| `onClick` | `TextButton` / `ImageButton` + `.Activated` |
| `display:flex; gap` | `UIListLayout` with `Padding` |
| `display:grid` | `UIGridLayout` |
| CSS `@keyframes` / `animation` | `TweenService` |
| `position:absolute; left/top` | `Position` + `AnchorPoint` in scale/offset |
| Dashed placeholder swatch | real render, or a `Frame` placeholder |

The prototype runs at a fixed 1920×1080 design canvas. Convert positions to
`UDim2` with anchor points rather than raw offsets so it holds at 1280×720,
which the brief requires as the readable floor.

## Fidelity

**High-fidelity.** Colors, typography, spacing, radii, and interaction states
are final and come from `docs/ART_DIRECTION.md`. Match them exactly. The one
deliberate exception is iconography: the prototype draws icons as simple
primitive shapes (see Assets below) — those are *specifications for shapes you
build in Luau*, not final art.

---

## Hard rules (from the brief, non-negotiable)

1. **Zero game-logic changes.** Remote calls, event subscriptions, `init()`
   signatures, keybinds (`B` shop, `Tab` scoreboard) stay exactly as wired.
2. `ShopController.setOpen(open)` and `SettingsController.setOpen(open)` are
   **public API** — the lobby calls them when the player walks into a building.
   Keep the names, signatures, and their internal `ClientData` flag +
   `ClientData.updateMouseUnlock()` calls intact.
3. Any new full-screen surface must set a `ClientData` flag and call
   `updateMouseUnlock()` so the cursor frees correctly.
4. Preserve every `ClientData.inLobby()` check. Combat HUD and crosshair are
   combat-only; the cursor is free in the lobby.
5. `default.project.json` must NOT reintroduce `CameraMode: LockFirstPerson`.
6. **All UI is code-built.** No uploaded images. Allowed: emoji, `UICorner` /
   `UIStroke` / `UIGradient` shapes, and player avatars via
   `Players:GetUserThumbnailAsync`.
7. `Enum.Font.FredokaOne` everywhere.
8. **Feature honesty.** Never ship a button that looks functional but does
   nothing. Designed-but-unwired features get muted "Coming soon 💗" states.

### DO NOT BUILD — no shells, no placeholders

Main-menu overlay (the plaza replaced it) · play-menu / mode-select · Battle
Pass · inventory grid · daily-rewards claim · spin wheel · emotes wheel · codes
redemption · ranked · gems purchasing.

The prototype previously contained a main menu and play menu; both were deleted.
Do not reintroduce them.

---

## Design Tokens

From `docs/ART_DIRECTION.md`. **All of these live in `src/client/UIKit.luau` and
nowhere else** — delete per-file color constants.

### Colors

| Token | Hex | Use |
| --- | --- | --- |
| Hot pink | `#FF5CA8` | primary accent, buttons, crosshair, bar fills |
| Deep pink | `#D6428F` | headings, key text on light |
| Bubble pink | `#FF82BE` | gradient top stop, secondary fill |
| Blush | `#FFE3F0` | panel body background |
| White pink | `#FFF5FA` | cards, rows, inner surfaces |
| Plum | `#60384E` | body text |
| Gold | `#FFC458` | coins, crits, price pills, rank 1 |
| Error | `#DC3C50` | low health, insufficient funds, your death |

### Rarity

| Rarity | Hex |
| --- | --- |
| Common | `#96828F` |
| Rare | `#5A8CEB` |
| Epic | `#AA5ADC` |
| Legendary | `#EBA032` |

Card treatment: 3px stroke in the rarity color, plus a 4px outer glow of the
same color at 20% alpha. Rarity label letterspacing `0.12em`.

### Derived surface values used throughout

- Panel stroke: `#FF5CA8` at 45–70% alpha, 2–3px
- Panel shadow: `0 12px 30px rgba(148,52,102,.28)`
- Chunky button shadow: `0 6px 0 rgba(198,52,124,.55)` (press → `0 3px 0` and
  translate down 3px)
- Dark HUD chip: `rgba(60,32,48,.82)` → `rgba(44,24,38,.82)` vertical gradient,
  2px `rgba(255,255,255,.28)` stroke

### Radii

6 · 9 · 11 · 14 · 16 · 18 · 20 · 24 · 26 · 28 px. Small chips 9–14, panels
18–20, modals 24–28.

### Typography — `Enum.Font.FredokaOne`, all of it

| Role | Size (at 1920×1080) |
| --- | --- |
| Modal title | 27 |
| Panel header | 20–25 |
| Section heading | 21 |
| Menu / large button | 28 |
| Body | 17–19 |
| Row name | 20–21 |
| Numeric readout | 23–30 |
| Caption | 13–15 |
| Rarity label | 15 |

Floor: nothing below 24px equivalent on a 1920 slide-scale surface; must stay
readable at 1280×720.

### Spacing

4 · 6 · 8 · 9 · 11 · 12 · 14 · 16 · 18 · 20 · 22 · 26 · 34 px. Panel padding
16–26. Row gap 8–12. Screen margin 36 (desktop), 18 (phone).

---

## Phase A — `src/client/UIKit.luau`

Single source of truth for palette + components. Delete per-file color
constants. Components required by the brief:

| Component | Spec |
| --- | --- |
| `panel` | blush `#FFE3F0` body, 14–18px corners, pink stroke, open/close scale+fade tween |
| `button` | chunky rounded, hover brighten 1.08, press shrink + shadow collapse |
| `iconButton` | square, 64×64 desktop / 52×52 phone, 20px radius |
| `menuButton` | icon + label row (kept for in-panel rows; NOT for a main menu) |
| `card` | white `#FFF5FA` rounded, optional rarity stroke + glow |
| `label` | presets: title / heading / body / caption |
| `bar` | tweened progress fill, gradient support |
| `slider` | lift logic from `SettingsController` |
| `closeButton` | 34×34, 11px radius, `rgba(255,255,255,.28)` on header |
| `tab` | pill tabs, active = pink gradient + white stroke, inactive = white + pink stroke, disabled = dashed + muted |
| `sparkle` | tweened 💗/✨ label accent, **no per-frame loops** |

---

## Screens / Views

### 1. Plaza lobby (`LobbyController.luau`)

**Purpose:** the lobby IS the menu. Free cursor, Animal Crossing-style camera.
Walking into a building auto-opens its panel; leaving closes it.

**Layout:** sky gradient top (`#FFE9F5` → `#FFD6EB` 34% → `#FFC4E0` 56% →
`#F7B0D3`), ground plane from y≈600 with a lighter plaza ellipse and a radial
paving pattern. Three buildings across the upper-middle band; players stand on
the plaza below.

**Buildings** (each: sign → pointer triangle → striped awning → façade with
door):

| Building | Sign colors | Prototype position (1920×1080) | Action |
| --- | --- | --- | --- |
| 🎀 The Bow-tique | `#FF7FBC`→`#FF5CA8`, awning stripes pink/white | x 150, y 286, w 376 | opens shop |
| 🍭 Candy Armory | `#FFB765`→`#FF9A3C`, stripes orange/white | x 672, y 322, w 376 | opens settings/armory |
| 💘 Heartbreaker Range | `#D97CE0`→`#BE55CC` | x 1108, y 352, w 330 | balloon target practice |

Sign text 26px white, 3px `#FFF5FA` stroke, `0 6px 0` colored shadow.
Caption under each ("walk in to shop") 17px in a darkened building color.

**Balloons at the Range:** three, 54×66, `border-radius: 50% 50% 46% 46%`,
colors `#FF5CA8` / `#FFC458` / `#AA5ADC`, 3px white stroke, 2px string below.
Idle: gentle bob — **animate transform only, never opacity**. Popped: animation
stops, fill goes flat `rgba(214,66,143,.16)`, opacity 0.35, and a "POP!" marker
+ `+5 coins` fires at the balloon's own center.

**Do not** hardcode marker coordinates. Derive the point from the balloon
instance's actual position so it can't drift when layout changes.

### 2. Zone banner ribbon (`LobbyController.luau`) — Phase C.3

Shown on zone entry, top-center (y≈104). A ribbon: two triangular tails in the
zone's dark tone flanking a center bar with a vertical gradient of the zone's
light→base tone, 3px white top and bottom borders.

- Text 34px white, `0 3px 0 rgba(0,0,0,.18)` shadow, e.g. `🎀 The Bow-tique 🎀`
- ✨ sparkle labels either side, tweened opacity/scale, offset phase (the second
  starts 0.8s later)
- Zone tones: Bow-tique `#FF82BE`/`#FF5CA8`/`#B03A78` · Armory
  `#FFB765`/`#FF9A3C`/`#C4741F` · Range `#D97CE0`/`#BE55CC`/`#8C32A0`
- Below it, a "← walk out" pill (18px deep pink on white, 14px radius)
- Slides/fades in on entry

### 3. News panel (`NewsConfig.luau` + lobby UI) — Phase C.4

Create `src/shared/Config/NewsConfig.luau` returning a static table so content
is editable without touching UI:

```lua
return {
    title = "NEW SUMMER UPDATE! 🌴",
    bullets = { "2 New Maps!", "New Weapon Skins!", "Limited Time Event!" },
}
```

Panel: right side, **below the PLAYERS panel** (prototype: right 36, top 680,
w 392). Blush body, 3px pink stroke, 24px radius. Pink gradient header with a
newspaper glyph + `NEWS` (21px, `0.12em`) and a ✕. Body is a white card
(`#FFF5FA`, 2px pink stroke, 18px radius) with a 23px deep-pink title and
bullets — 8px pink dot + 17px plum text.

Dismissible. When dismissed, leave a small `NEWS` pill in the same spot to
reopen. **Must not overlap the PLAYERS panel** (which occupies y 132–655).

### 4. Overhead nameplates (`NameplateController.luau`, new) — Phase C.5

Client-only `BillboardGui` per character, built from `Players` events. **No
server changes.**

White-pink pill (`rgba(255,245,250,.95)`), 2px pink stroke at 60% alpha, 16px
radius, `0 6px 16px rgba(148,52,102,.25)` shadow, containing the display name in
deep pink + a 💗 glyph: `cutiegracie 💗`. A small pink triangle points down at
the character.

Local player 23px; others scale down with distance (19px, 17px in the
prototype) with progressively lighter strokes.

### 5. Combat HUD (`HudController.luau`)

Gated on `not ClientData.inLobby()` — hidden entirely in the lobby.

**Health/ammo panel**, bottom-left (36, 34), w 330, 20px radius,
`rgba(255,245,250,.94)`, 2px pink stroke:
- `HEALTH` caption 16px `0.1em` + big value, deep pink normally,
  **`#DC3C50` at ≤30**
- Bar 20px tall, 10px radius, track `rgba(214,66,143,.16)`, fill
  `#FF82BE`→`#FF5CA8` gradient, flips solid `#DC3C50` at ≤30. Tween 0.35s.
- Divider, then weapon icon chip (44×36) + weapon name 19px, and ammo
  `24` at 30px deep pink `/ 30` at 18px muted

**Status pill**, top-center (y 30): `FREE FOR ALL` 21px deep pink · divider ·
clock 23px · `💗 7 kills` 19px hot pink. White-pink pill, 18px radius.

**Killfeed**, top-left column, rows slide in from −26px over 0.6s ease-out, hold
4.0s, fade 1.0s, max 5 rows. Row: killer name · 30×30 weapon chip (9px radius,
`rgba(255,92,168,.16)`) · victim name, in a white-pink pill with 2px pink
stroke.
- Your kill → killer name in deep pink
- Your death → victim name and the row stroke in `#DC3C50`

### 6. Crosshair, hitmarkers, damage numbers (`HitFeedbackController.luau`)

Combat-only. Full 1:1 specs are on the **asset sheet** view of the prototype.

**Crosshair**, 4 states, arms 3×10px r2, center dot 5px, all with a 1px
`rgba(255,255,255,.70)` outline:
- idle 34px box · firing arms +9px (0.08s out, 0.16s back) · hit → ✕ overlay ·
  reload → 38px arc ring sweeping one full turn over the reload duration

**Hitmarker** ✕: hit 34px hot pink · crit 44px gold with glow · kill 40px
`#DC3C50` + a 58px ring. Scale 0.40 → 1.15 → 1.50, alpha 0 → 1 → 0, rotate
0 → 14°, 0.50s ease-out.

**Damage numbers:** body 32px hot pink · crit 44px gold with `84 ✦` · kill 30px
`#DC3C50` `KO`. Rise 64px, alpha 0 → 1 (0.15s) → 0 over 0.85s ease-out, random
x-jitter ±14px, spawned at the hit world point projected to screen.

### 7. Currency / level bar (`EconomyController.luau`)

Top-right (36, 26), two dark chips side by side.

**Coins chip:** 38px radial-gradient gold coin (`#FFE0A8` → `#FFC458` 55% →
`#E39F35`), 2px white stroke, `0 0 12px rgba(255,196,88,.55)` glow, then the
amount at 26px white.

**Level chip:** `Level 27` 20px white + `2,450 / 5,000 XP` 14px at 70% white;
below, a 252×14 bar, 8px radius, track `rgba(0,0,0,.35)`, fill gradient
`#FF82BE` → `#FF5CA8` 60% → `#FFC458` with a pink glow, tween 0.5s. To the
right, a 46px level badge.

Gain pop: `+25 coins · +40 XP` in gold, rises and fades over 1.2s.

**No gems.** The brief's DO NOT BUILD list includes gems purchasing; the
prototype's hidden gems slot was deleted. Leave no shell.

### 8. PLAYERS panel (`RoundController.luau`)

Right side (36, 132), w 396, 20px radius, blush body, 2px pink stroke at 65%.
Pink gradient header: `PLAYERS` 20px `0.1em` white + ✕.

Rows: 42px avatar (12px radius) via `Players:GetUserThumbnailAsync`, name 20px
truncating, right-aligned `💗 {kills}`, and an 11px green online dot
(`#6FCF7F` + glow). Self row: `rgba(255,92,168,.20)` fill, 75%-alpha pink
stroke, deep-pink name.

### 9. Scoreboard (Tab, `RoundController.luau`)

Full-screen dim `rgba(44,24,38,.5)` + blur. 820px panel, 24px radius. Columns
`56 / 1fr / 110 / 110 / 130` — `#` · PLAYER · KILLS · DEATHS · SCORE. Rank 1 in
gold. Score = `kills × 100 − deaths × 20`. Self row highlighted as above.

### 10. Shop (`ShopController.luau`) — Phase C.1

Opened by walking into The Bow-tique, or `B`. **Panel sits to the left**
(prototype: `padding-left: 64px`, w 1080) with a light `rgba(52,26,42,.3)`
scrim and **no blur**, so the player's character at the storefront stays
visible.

Header: `🎀 SHOP` 27px white on pink gradient · coin chip · ✕.

**Tabs:** `SKINS` · `CHARMS` live. `FEATURED` · `BUNDLES` · `DAILY` · `LIMITED`
render as disabled coming-soon pills — dashed stroke, muted text, `soon 💗`,
`cursor: not-allowed`, no handler.

**Cards**, 4-up grid, 20px gap: preview swatch (176px, 16px radius), name 21px
plum centered, rarity label 15px in its rarity color with `0.12em`, then the
action button:

| State | Treatment |
| --- | --- |
| Not owned | gold pill `#FFD98A`→`#FFC458`, `💗 1,299`, brown text `#7A4A12` |
| Owned | pink gradient, `Equip 🎀`, white text |
| Equipped | green tint `rgba(111,207,127,.22)`, `Equipped ✓`, `#3E8A50`, no handler |

Message line below the grid: purchase confirmations in deep pink, insufficient
funds in `#DC3C50` — `"Not enough coins — you need 240 more 💗"`.

Wire to existing `PurchaseItem` / `EquipItem`. Coins only.

### 11. Settings / Candy Armory (`SettingsController.luau`) — Phase C.2

Opened by walking into the Candy Armory. Same left-side placement, 720px wide.
Header `⚙️ SETTINGS` with a code-built gear.

- **Mouse sensitivity** and **Volume** sliders: 14px track, 8px radius, pink
  gradient fill, 28px white knob with a 3px `#FF5CA8` ring
- **Starting weapon** — weapon-card styling (it's the gun store): 4-up grid of
  cards, 16px radius, 76px preview swatch, name 18px, and a rarity-style tag
  line. Frame is 3px in the weapon's rarity color with a 3px glow; the equipped
  card switches to hot pink with `EQUIPPED ✓`. Prototype rarities: Pistol
  Common · Rifle Rare · Shotgun Epic · Knife Common.
- The panel gets a hot-pink 3px ring when opened via the Armory, to focus the
  weapon picker.

All changes fire the existing `UpdateSettings` remote (sensitivity, volume,
startingWeapon).

---

## Interactions & Behavior

| Trigger | Result |
| --- | --- |
| Walk into The Bow-tique | `ShopController.setOpen(true)`, zone banner shows |
| Walk into Candy Armory | `SettingsController.setOpen(true)`, banner shows, weapon picker focused |
| Walk out of either | corresponding `setOpen(false)`, banner hides |
| Click a Range balloon | pop marker + `+5 coins`, balloon goes flat and stops animating |
| `B` | toggle shop |
| `Tab` hold | scoreboard while held |
| `Esc` | close panel / leave zone |
| Round starts | combat HUD + crosshair appear, cursor locks |
| Round ends | everyone returns to the plaza, cursor frees |

Every panel open/close: scale + fade tween, ~0.2s ease-out.

Hover on chunky buttons: brightness 1.08. Press: translate down 3px and collapse
the drop shadow from `0 6px 0` to `0 3px 0`.

## State Management

Client-side only; all of it already exists in `ClientData` except where noted.

- `inLobby()` — gates combat HUD, crosshair, cursor lock
- `shopOpen` / `settingsOpen` — set by the `setOpen` APIs, each followed by
  `updateMouseUnlock()`
- Current zone (lobby-local) — drives the banner and which panel is open
- Popped-balloon set (lobby-local, cosmetic, resets on a timer)
- News panel dismissed flag (lobby-local, session only)
- Snapshots from `DataChanged`: coins, XP, level, owned, equipped
- `RoundStateChanged` / `ScoreUpdated`: round state, timer, per-player K/D

## Assets

**None external.** Everything is code-built. Three allowed sources: emoji,
shape primitives, and `Players:GetUserThumbnailAsync` for avatars.

The prototype's **asset sheet** view (third button in its harness bar) is the
icon spec: 20 icons at 1:1 on 72px tiles, each 2–8 solid shapes with corner
radii and a single accent color, so each maps to a handful of `Frame`s with
`UICorner`. Covered: PLAY, SHOP, LOADOUT, SETTINGS, INVENTORY, BATTLE PASS,
DAILY, RANKED, CODES, NEWS, Pistol, Rifle, Shotgun, Knife, coin, gem, heart,
level flower, crown, star.

Note that several of those icons belong to DO NOT BUILD features — they exist on
the sheet for completeness only. Build the icon when you build the feature, not
before.

💗 and ✨ stay real emoji.

## Files

- `Pink Panic UI.dc.html` — the full prototype. Open it in a browser. The bar
  along the bottom switches lobby / combat, desktop / phone, and the asset
  sheet.
- Repo: `docs/UI_REDESIGN_BRIEF.md` — the authoritative spec, phases A–D
- Repo: `docs/ART_DIRECTION.md` — locked palette, font, radii, rarity colors

## Phase D — verification checklist

Rojo-sync, then a **Clients-and-Servers 2-player test** in Studio:

- [ ] Walk into The Bow-tique — shop auto-opens, cursor stays free, banner shows
- [ ] Walk out — shop closes
- [ ] Walk into Candy Armory — settings auto-open, weapon picker focused
- [ ] Pop a balloon at the Heartbreaker Range
- [ ] Shop buy + equip works, insufficient-funds message is readable
- [ ] Shop tabs switch; coming-soon tabs are visibly dead
- [ ] Settings persist across a round
- [ ] PLAYERS panel shows real avatars and live kills for both clients
- [ ] Play a full round — first-person HUD returns, crosshair appears
- [ ] Round ends — everyone returns to the plaza, cursor frees
- [ ] Nameplates render over both characters
- [ ] Nothing overlaps at 1280×720
- [ ] Zero client errors in the Output window
