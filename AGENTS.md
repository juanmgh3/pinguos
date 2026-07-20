# PinguOS

A desktop-style OS for a Minecraft **CC: Tweaked** Advanced Computer, plus a Node
bridge that serves it and relays a Claude chat app. The in-game OS lives in `dist/`;
the bridge serves it over HTTP for one-line install/update.

## Commands

- Run the bridge (serves `dist/` + Claude chat, keep it open):
  `DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`
- Bridge tests (Node): `node --test`
- OS pure-module tests (Lua): `"$LUA" dist/tests/run.lua`
- Syntax-check a CC-bound Lua file (can't be unit-tested locally): `"$LUAC" -p <file.lua>`
- In-game install/update: `wget run http://127.0.0.1:8080/install` (or the **Update** app).

Local Lua 5.4 is at `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`
(`luac.exe` alongside it). `$LUA` / `$LUAC` above = those paths.

## Architecture

- `dist/` — the in-game OS, **source of truth**. Edit a file here + run the in-game
  **Update** app → it pulls the change and reboots. That is the dev loop.
- `dist/os/kernel.lua` — boot, desktop, app launch (every app runs under `pcall`).
- `dist/os/ui.lua` — immediate-mode draw toolkit (the visual language).
- `dist/os/{config,log,text,appreg,geo}.lua` — support modules.
- `dist/os/apps/*.lua` — auto-discovered apps; each returns
  `{ id, name, icon, color, run = function(ctx) ... end }`.
- `bridge/{ascii,manifest,install,fspath}.js` — bridge logic (unit-tested).
- `specs/pinguos/` — design specs + implementation plan (durable record).

## Conventions

- **Apps depend ONLY on `ctx`.** Everything an app needs is there (`ui`, `geo`,
  `config`, `sys`, `term`, `log`). See `makeCtx` in `dist/os/kernel.lua`.
- **UI is immediate-mode**: a widget draws and returns a region; the app's event
  loop hit-tests clicks with `ui.hit`. No retained widget tree.
- **Rendered text must be ASCII** — the CC terminal is 8-bit (no unicode/emoji).
- Config saves atomically (tmp + `fs.move`); small settings via `config`, bulk data
  in `/data/<app>/`. Commits: Conventional Commits, English. Run tests/`luac -p` before "done".

## Gotchas (real ones, each caused a crash)

- **`require`, `shell`, `gps` are NOT globals inside an app.** Apps load via
  `loadfile` (sees only `_G`); these are injected elsewhere. Get them from `ctx`
  (kernel) or stash in `_G` at boot (`startup.lua` does this for `shell`). Never
  `require` in an app.
- **A crashing app must never crash the OS** — keep app launch under `pcall` and
  surface the error (`runApp` in the kernel).
- **`DIST_DIR` may be relative** — `path.resolve` before any containment check
  (see `bridge/fspath.js`); a relative base broke `/fs/` serving once.
- The chat `POST /` requires `Content-Type: application/json` and rejects
  cross-origin (anti-CSRF) — it drives a tool-capable Claude.
- Lua must run on **CC's Lua 5.1** and local **5.4**: use `math.atan2 or math.atan`,
  and `math.floor` before `string.format("%d", n)` (5.3+ rejects float `%d`).

## Environment

Target instance: **NeoForge 1.21.1**, **CC: Tweaked 1.120.0**, Advanced Computer
(color + mouse), wireless/ender modems, creative mode. This instance has the
peripheral mods the old Fabric 26.2 setup lacked: **Advanced Peripherals** 0.7.62b
(geo/ore scanner, player/environment detectors, ME bridge, chat box), **Tom's
Peripherals** 1.3.1 (HD monitors + GPU `tm_gpu`, physical keyboard), **CC:C Bridge**
(read/control Create machines), **ClaudeCraft** 1.2.2 (native Claude in CC). So
block/ore scanning, HD displays, etc. ARE now possible — see
`specs/pinguos/hd-command-center.md`. The base computer terminal is still 8-bit
ASCII; only Tom's HD monitors break out of that.

## Writing style

Applies to commits, pull request titles and bodies, review comments, docs and
code comments.

Comments here earn their place by naming the failure that motivated them:

    -- ...the rednet broadcast is THROTTLED to ~2/s. Jobs call this every block;
    -- several working turtles broadcasting every step floods the fleet computer's
    -- event queue (a real limit inside CC) and freezes a pocket.

Don't:

- Emoji, anywhere
- "This PR introduces..." — say what it does
- Restating the diff as bullets; the diff already says that
- "Note that", "It's worth noting", "Importantly"
- Opening with praise: "Great catch!", "Nice work!"
- "comprehensive", "robust", "seamless", "leverage"
- Bold scattered through prose, or a closing summary repeating the opening

Do:

- PR body: what changed, why, how it was verified. Three lines is a valid body.
- Name the failure that motivated the change, if there was one.
- Review comments: point at the line, state the problem, say what breaks if it
  stays. No praise sandwich.
- Link the spec or the gotcha when one applies.

Comment only what the code cannot say for itself. A comment restating the line
below it is worse than no comment.

## Verification

| Layer | Verified by | Needs a human in-game |
| --- | --- | --- |
| Pure modules (`geo`, `text`, `focus`, `gpu`, `nav`, ...) | unit tests + CI | no |
| Bridge | `node --test` + CI | no |
| CC-bound Lua (`kernel`, apps, `turtle/lib/api.lua`) | `luac -p` only | **yes** |

The third row is a property of the platform: every call hits a Minecraft API
that does not exist outside the game.

Every task states which is true:

- **No in-game check needed** — covered by tests, say so and move on.
- **In-game check needed** — name the exact steps. "Open the Fleet app, confirm
  the scrollbar pages" beats "test it".

State anything you could not verify. Never assume it works.
