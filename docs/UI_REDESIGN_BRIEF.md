# Pink Panic — Full UI Design Brief (NOD-36 + mockup build-out)

You are building the complete UI of Pink Panic, a cute pink Roblox FFA
shooter, to match the approved concept mockup (attached image). The game
logic works; your job is visuals and screen structure — without breaking any
behavior.

## References (read first)

1. **The attached mockup image** — the target look. It shows: a lobby
   overview with a left menu stack, currency/level bar, PLAYERS and NEWS
   panels, a bottom dock; a main menu; a play menu with mode select + map
   carousel; and a shop with tabs and rarity-labeled item cards.
2. `docs/ART_DIRECTION.md` — locked palette hex values, font, radii, rarity
   colors, iconography rules. This is law.
3. The current code under `src/client/` — every existing surface is built in
   code (Instance.new) inside Controllers.

## Ground rules

- **Never change game logic.** Remote calls, event subscriptions, `init()`
  signatures, keybinds (B shop, Tab scoreboard), and the
  `ClientData.shopOpen` / `settingsOpen` / `updateMouseUnlock()` calls stay
  exactly where they are. Any new full-screen menu must set one of those
  flags + call `updateMouseUnlock()` so the cursor frees correctly.
- All UI is code-built. No uploaded images/assets unless Titus hands you
  asset ids. Allowed instead: emoji icons, UICorner/UIStroke/UIGradient
  shapes, and **player avatars via `Players:GetUserThumbnailAsync`** (use
  for the PLAYERS panel rows like the mockup).
- Font `Enum.Font.FredokaOne` everywhere. Readable at 1280×720.
- **Feature honesty:** the mockup shows features that don't exist yet. Build
  what's wired, show "Coming soon 💗" states for what's designed-but-unwired
  (the mockup itself does this for Infection/CTF), and skip what's listed as
  DO NOT BUILD. Never ship a button that looks functional but does nothing.

## What exists today (wire to these)

FFA rounds w/ state machine + timer · four weapons + starting-weapon choice ·
coins + XP/levels (`DataChanged` snapshots via `ClientData`) · shop
(skins/charms, coins only, `PurchaseItem`/`EquipItem`) · settings
(`UpdateSettings`: sensitivity/volume/startingWeapon) · players/scores
(`RoundStateChanged`/`ScoreUpdated`) · killfeed · health/ammo. Post-MVP
(Linear: gems, battle pass, daily rewards, inventory, ranked, emotes, TDM)
is NOT wired yet.

## Phase A — UIKit foundation

Create `src/client/UIKit.luau`, the single source of truth for palette +
components; delete the per-file color constants. Components: `panel` (blush,
14–18px corners, pink stroke, open/close scale+fade tween), `button` (chunky
rounded, hover brighten + press shrink), `iconButton` (square, like the
mockup's bottom dock), `menuButton` (left-stack style: icon + label, like
PLAY/SHOP/INVENTORY), `card` (white rounded, optional rarity stroke+glow),
`label` (title/heading/body/caption presets), `bar` (tweened progress),
`slider` (lift logic from SettingsController), `closeButton`, `tab` (pill
tabs like the shop's Featured/Weapons/…), and a cheap `sparkle` accent
(tweened 💗/✨ labels, no per-frame loops).

## Phase B — restyle every existing surface (kit only)

| File (src/client/Controllers/) | Surface | Mockup cues |
| --- | --- | --- |
| `EconomyController.luau` | Coins/level/XP → **top-right currency bar** | Gold coin pill + level bar w/ "2,450 / 5,000 XP" text and flower badge. Leave a hidden slot where gems will go. Keep "+n" gain pop |
| `RoundController.luau` | Status pill; PLAYERS panel; Tab K/D board; results overlay | PLAYERS panel exactly like mockup: header + ✕, white rows w/ avatar thumbnail, name, right-aligned detail (use 💗kills in-round where mockup shows Level), self-row highlighted |
| `HudController.luau` | Health/ammo panel; killfeed | Killfeed rows slide in / fade out |
| `HitFeedbackController.luau` | Crosshair, hitmarker, damage numbers | Keep pink; juice the kill flash |
| `ShopController.luau` | Shop modal | Rebuild per Phase C shop spec below |
| `SettingsController.luau` | Settings modal | Match mockup panel styling |

## Phase C — new screens from the mockup

1. **Main menu overlay** (`MenuController.luau`, new): opens with **M** or a
   🎀 button; PINK PANIC wordmark (styled TextLabels — bubbly, layered
   stroke), left menu stack: **PLAY** (closes menu) · **SHOP** (opens shop) ·
   **LOADOUT** (opens settings' weapon section or settings) · **SETTINGS** ·
   then INVENTORY / BATTLE PASS / DAILY / RANKED as "Coming soon 💗"
   (visibly muted). Sets a menu-open flag + `updateMouseUnlock()`.
2. **Play menu panel** (inside the main menu, like the mockup): mode list —
   **Free For All (active)**, Team Deathmatch / Infection / CTF as coming
   soon; right side shows mode blurb + "PINK MALL" map card (static text
   card; no carousel until more maps exist) + big PLAY button.
3. **Shop rebuild** (`ShopController.luau`): header + ✕; **tabs**: `Skins` ·
   `Charms` · (Featured/Bundles/Daily/Limited rendered as disabled coming-
   soon tabs); cards like the mockup: preview swatch, name, **rarity label
   in its rarity color**, price pill (💗 + amount, gold pill) / "Equip 🎀" /
   "Equipped ✓"; insufficient-funds message line stays.
4. **News panel** (part of main menu, right side): reads a static
   `src/shared/Config/NewsConfig.luau` table (title, bullets) you create —
   content editable without touching UI. "View update" button can close to
   a detail panel or be omitted if empty.
5. **Overhead nameplates** (`NameplateController.luau`, new): BillboardGui
   over each character — name + "💗 Level n" (level comes through
   `ScoreUpdated`/`RoundStateChanged` rows? If level isn't in the payload,
   show name only — do NOT touch server code to add it).

**DO NOT BUILD** (not designed for this pass, no shells): Battle Pass
screens, inventory grid, daily-rewards claim flow, spin wheel, emotes wheel,
codes redemption, ranked, gems purchasing. Their menu entries appear only as
muted coming-soon buttons.

## Phase D — verify (2-player test in Studio)

Rojo-sync, Clients-and-Servers 2-player test: menu opens/closes with cursor
freed/relocked · PLAY drops you back in game · shop buy/equip works with
readable errors · tabs switch · settings persist · PLAYERS panel shows
avatars + live kills · nothing overlaps at 1280×720 · zero client errors.

## Definition of done

- [ ] UIKit module is the only place colors/components are defined
- [ ] Every Phase B surface rebuilt on the kit; zero behavior changes
- [ ] Main menu, play menu, shop tabs, news, nameplates live per Phase C
- [ ] Coming-soon states clearly muted; no dead-looking-but-functional buttons
- [ ] Phase D checklist passes clean
