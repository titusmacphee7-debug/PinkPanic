# Handoff prompt — local Claude Code session with Studio MCP

Paste everything below the line into a local Claude Code session running in
`C:\Users\slaye\Documents\PinkPanic`, with Roblox Studio open and the MCP
server enabled.

---

Read `CLAUDE.md` first — it has the architecture, the combat model, the render-step
ordering, the attribute conventions, and the gotchas. Don't re-derive any of it.

You have the Roblox Studio MCP connected, which no previous session has had. That
changes the job: you can read and modify the place file directly instead of handing
me Command Bar scripts. Use it.

**The goal is one thing: make Pink Panic playable end to end.** A player spawns in
the lobby, sees the town, presses START GAME, fights in the arena, dies, respawns,
and comes back to the lobby. No new features until that works. Linear NOD-117 is the
roll-up.

## Step 1 — Find out what is actually running. Do this before touching any code.

This is not optional and it is not a formality. Three of the bugs I'm about to list
were fixed and pushed days ago. If those fixes aren't running, every minute spent
re-fixing them is wasted, and that has already happened on this project — I lost days
testing stale scripts while reporting that fixes didn't work.

Do not ask me to read the Output window. You can check this yourself now:

1. `git log --oneline -5` and `git status` — confirm the checkout is at or past
   `0cc0a62` on branch `claude/pink-panic-roblox-5g2w56`.
2. Via MCP, read the actual source of `ServerScriptService/Server/init.server` in the
   live place and compare it to `src/server/init.server.luau` on disk. If they differ,
   Rojo is not syncing and nothing else matters until that's fixed.
3. Check `ServerScriptService` for a **second** copy of the script tree. A duplicate
   runs everything twice and re-creates content the live copy just deleted.
4. Check `StarterPlayer/StarterPlayerScripts/Client` the same way.
5. Confirm `BUILD_TAG` in the running source reads `2026-08-10-C`.

Tell me plainly what you found before moving on. If the answer is "stale scripts,"
say so — that's a good outcome, it means the fixes are fine and the pipeline is broken.

## Step 2 — The lobby

Reported: **no camera at all**, cursor locked, pads don't respond, and **no START GAME
button**, so the game can't be started.

My diagnosis, which you should verify rather than trust:

- The lobby camera, free cursor, and pads are all gated on `ClientData.inLobby()`,
  which is false whenever `roundState == "Active"`. If the round auto-starts, all
  three symptoms appear at once and none of them are actually camera/cursor/pad bugs.
  `RoundService.soloHold()` was changed so solo Studio always waits — verify it's the
  version running.
- **A real bug I found and did not fix**, in `LobbyController.customPads()`: it caches
  the tagged-pad list on first call and never invalidates it. The client's first
  Heartbeat very likely runs before `workspace.Lobby` finishes replicating, so it
  caches an **empty list permanently** and pads never work for the whole session. Fix
  this regardless of what else you find.
- `LobbyService.ensureCameraAnchor()` should be creating a `CameraAnchor` part inside
  `workspace.Lobby` if none exists. Check via MCP whether it's there. If it exists but
  the camera still doesn't engage, the problem is round state, not the anchor.

While you're in there: the auto-placed `CameraAnchor` is a bounding-box guess. Once
the camera works, position and rotate it to actually frame the storefronts, and set
`MaxYawDeg` / `MaxPitchDeg` so it can't pivot far enough to show unbuilt space.

## Step 3 — Respawn and the arena (NOD-118)

I have an arena built with spawn points. The death/respawn loop has never been tested
against it. Check in Studio:

- Is the folder named **exactly** `Arena`, directly under Workspace?
- Are the spawns real `SpawnLocation` instances, and is `Neutral` true on them?
- Are the lobby spawns inside `workspace.Lobby`?
- Did `Players.RespawnTime = 3` from `default.project.json` actually apply?

Then verify the whole loop: round starts → arena spawns enable and lobby spawns
disable → die → respawn in the arena → round ends → back to the lobby.

## Step 4 — Guns (NOD-114)

The 32 new split gun models are sitting in a folder called `Unsorted 📦`. They need
to be in `ReplicatedStorage/GunModels`, replacing the old solid ones. Do this via MCP.

They're split into moving parts named `Slide`, `Bolt`, `Pump`, `Cylinder`, `Mag` —
`ViewmodelController` already drives all of those, so once they're in the right place
the cycling animations should just appear.

One pistol points backwards, at the camera. Find out whether it's one model or all of
them and fix the orientation in the place. Report which, so it can go back to Cowork.

Then verify **one** gun completely: equip, fire, recoil, shell ejects from the real
port, reload with the mag drop, ADS. One gun working beats 32 half-working.

## Step 5 — Recoil (NOD-112) and ADS (NOD-106)

Both are reported still broken. Both have been "fixed" before, so establish ground
truth from Step 1 before changing numbers.

**Recoil is too strong — third report.** `WeaponController.RECOIL_SCALE` is the master
volume, currently `0.5`. Per-gun ceilings come from `recoilCeilings()` and derive from
each gun's own stats, so guns should already feel different from each other; if they
don't, that code isn't running. Target audience is new players. Err far too weak —
recoil I can barely feel is a much better failure than recoil that fights me.

**ADS jitter.** Root cause was `adsAlpha` oscillating every frame at full ADS because
the blend stepped past its target and then corrected, forever. Fixed by clamping to
the target in both directions. If it still jitters *with the fix confirmed running*,
it's a genuinely new bug — check the render-step chain in `CLAUDE.md`, since several
systems write the camera each frame and the order is load-bearing.

## Rules

- **Never generate lobbies or maps.** All that code was deleted on purpose. It kept
  getting baked into saved place files and reappearing after I built my own town.
- Absolute server authority. The client predicts; the server decides damage.
- `--!strict` everywhere. Every remote declared only in `Remotes.luau`, validated
  through `Guard`, rate-limited.
- Push to `claude/pink-panic-roblox-5g2w56` only. No pull request unless I ask.
- Bump `BUILD_TAG` in `src/server/init.server.luau` on any behavior change.

## How to talk to me

Lead with the fix and what it changes in-game. Skip the play-by-play. I'm new to
Roblox and git, and I'm better at telling you how something *feels* than at reading
code — so when you need something from me, make it a concrete action, not a question
about internals.
