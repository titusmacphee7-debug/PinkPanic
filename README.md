# Pink Panic 🎀

A cute pink Roblox FFA shooter. One mode, four hitscan weapons, an earn/buy/equip
economy loop, and an aesthetic slice. Full plan lives in Linear:
[Pink Panic — MVP](https://linear.app/nodewelll/project/pink-panic-mvp-b6276c1b2a4a).

## Getting started

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then from the repo root:
   ```sh
   rokit install
   ```
2. Install the [Rojo plugin](https://create.roblox.com/store/asset/13916111004) in Roblox Studio.
3. Start the sync server and connect from the Studio plugin (default `localhost:34872`):
   ```sh
   rojo serve
   ```
4. Or build a place file from source:
   ```sh
   rojo build -o PinkPanic.rbxl
   ```

Studio settings to enable by hand (not synced by Rojo):
- **Game Settings → Security → Enable Studio Access to API Services** (required for DataStores).
- First-person camera comes later (M1); no Studio changes needed yet.

## Claude Code ↔ Studio (MCP)

Studio ships a built-in MCP server (see the [official docs](https://create.roblox.com/docs/studio/mcp)),
which lets Claude Code read the data model, insert instances, and run code in
the open place. Repo config lives in `.mcp.json` (Windows: launches Studio's
`%LOCALAPPDATA%\Roblox\mcp.bat` over stdio), so setup is:

1. In Studio: **File → Studio Settings → Beta Features → enable MCP Server**, then restart Studio.
2. Run `claude` from this folder and approve the `Roblox_Studio` server it picks up
   from `.mcp.json`. (Equivalent manual registration:
   `claude mcp add --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"`)
3. Verify with `/mcp`, then ask Claude to list the children of `Workspace`.

## Controls

Left-click fire (hold for automatics) · **R** reload · **1–4** switch weapon ·
**Tab** scoreboard · **B** shop · **⚙️** settings (sensitivity, volume, starting weapon)

## Project structure

```
src/
  server/   -> ServerScriptService/Server      (server-only: services, game rules)
    init.server.luau                            boot script; initializes remotes + services
    Services/                                   one module per system (PascalCase ...Service)
  client/   -> StarterPlayer/StarterPlayerScripts/Client   (client-only: input, camera, UI)
    init.client.luau                            boot script; requires controllers
  shared/   -> ReplicatedStorage/Shared        (both sides: configs, schema, remote registry)
    Data/                                       PlayerDataSchema and (later) catalogs/configs
    Net/                                        Remotes registry + Guard validation helpers
```

## Module conventions

- **Language:** Luau with `--!strict` at the top of every file. Format with StyLua, lint with Selene.
- **Naming:** PascalCase module files and public APIs; camelCase locals and functions kept private to a module. Server systems are `<Name>Service`, client systems are `<Name>Controller`.
- **Template:** a module returns a table; long-lived systems expose `init()` which the bootstrap calls exactly once. No work at require-time beyond building the table.
- **Remotes:** every RemoteEvent/RemoteFunction is declared in `src/shared/Net/Remotes.luau` and created by the server at boot. Never `Instance.new` a remote elsewhere.
- **Player data:** the profile shape is defined only in `src/shared/Data/PlayerDataSchema.luau`; all reads/writes go through `PlayerDataService.get/update`. Nothing else touches DataStores.

## Server authority (the rule everything obeys)

The server decides everything that matters: health, damage, kills, coins, XP,
purchases, ownership, equips. The client *requests* and *displays* — it never
sets a value the server then trusts.

Concretely, every server-side remote handler must:
1. Validate argument types/ranges with `Guard` (`src/shared/Net/Guard.luau`) before any logic runs.
2. Rate-limit with `Guard.checkRate` where spam is possible.
3. Re-derive anything security-relevant server-side (positions, line of sight,
   prices, balances) instead of trusting client-supplied values.

## Roadmap (Linear milestones)

| Milestone | What it proves |
| --- | --- |
| **M0 — Foundation & Architecture** | Repo, Rojo, schema, persistence, networking baseline *(this scaffold)* |
| M1 — Core Combat | One pistol that feels great; server-authoritative damage |
| M2 — Round Loop (FFA) | A full round happens: states, spawns, scoring, results |
| M3 — Weapons & Loadout | Rifle, shotgun, knife, loadout selection |
| M4 — Economy & Progression | Coins, XP, shop with validated purchases |
| M5 — Cosmetics & Aesthetic Slice | Pink UI kit, HUD, skins, charms, audio — **only after M1–M2 is fun** |
| M6 — Lobby & First-Time Experience | Lobby, practice range, onboarding, settings |
| M7 — Anti-Exploit, Polish & Launch | Authority audit, rate limits, perf, analytics, soft launch |
