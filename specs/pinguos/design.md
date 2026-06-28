# PinguOS — Design Spec

- **Status:** Draft for review
- **Date:** 2026-06-28
- **Working name:** PinguOS (provisional, rename freely)
- **Owner:** Juan
- **Slug:** `pinguos`

> Durable record for this feature, per the project's SDD flow. This is the
> contract the implementation builds against. If it isn't written here, it
> isn't agreed.

---

## 1. Summary & vision

A small, clean desktop-style operating system for a Minecraft **CC: Tweaked**
Advanced Computer. It boots to a clickable desktop with a taskbar and app
icons; apps run full-screen and return to the desktop on exit. It is a
**platform**: dropping a file into `/os/apps/` adds an app, with no other
wiring. The first flagship app is the existing Claude chat client.

Two goals pull equally:

1. **Daily-use desktop** — "Linux-like" feel: boot → desktop → taskbar →
   icons → apps. Customizable (themes, settings).
2. **Learning sandbox** — clean module boundaries, readable code, documented so
   the owner understands it and we extend it together. *Clarity > cleverness*
   is design principle #1.

## 2. Goals / Non-goals

**Goals (v1)**
- Boot to a clickable desktop on an Advanced Computer (color + mouse).
- Auto-discovering app framework with a single, well-defined app contract.
- Crash isolation: a faulty app never brings the OS down.
- Persistent settings (theme, bridge URL) with atomic saves.
- One-line install + one-command update loop from the PC bridge.
- Ship 5 starter apps that prove the platform end to end.

**Non-goals (v1, explicitly deferred)**
- Overlapping windows / window manager (Approach A). Full-screen apps only.
- Background services / multitasking (Approach C). Designed-for, not built.
- Gold/ore mapper (needs Advanced Peripherals — not installed; see §4).
- GPS app, farm automation, monitors as primary surface — future app specs.

## 3. Environment & constraints

| Fact | Source | Consequence |
|---|---|---|
| CC: Tweaked **[26.2] 1.120.0** (Jun 2026) | confirmed | Modern APIs: HTTP timeouts, `cc.strings`, `http.request` table form, `utf8` lib all available. |
| **Advanced Computer** (color + mouse) | confirmed | Clickable desktop is viable; `mouse_click` events exist. Degrade gracefully if ever run on a normal computer. |
| **Wireless modem** present | confirmed | Future GPS / rednet apps feasible. |
| **Creative mode**, "all hardware available" | confirmed | Can spawn turtles, monitors, extra computers as future apps need. Creative gives *items*, not *mods*. |
| **No Advanced Peripherals**; it is Forge/NeoForge only (no Fabric), supports MC 1.20.1 / 1.21.1 | confirmed | No block scanning → no radar-style ore mapper in vanilla. Revisit only if the mod is installed (needs Forge/NeoForge). |
| Terminal is **8-bit, ASCII-only** (no unicode/emoji) | confirmed | All rendered text must be ASCII. Accents/emoji must be transliterated/stripped (done bridge-side; UI also sanitizes as a net). |
| CC:T blocks `127.0.0.1` by default (`$private` deny) | confirmed | Install/update/chat all require editing `serverconfig/computercraft-server.toml` to allow local IPs. Prerequisite step. |
| No local Lua interpreter on dev machine | confirmed | Cannot unit-test CC code locally. Mitigations in §10. |

## 4. Architecture

Layered, each layer one responsibility, talking through narrow interfaces.

```
  ┌─────────────────────────────────────────────┐
  │  APPS   /os/apps/*.lua   (claude, settings…) │  ← extensible surface
  ├─────────────────────────────────────────────┤
  │  KERNEL   boot · discover apps · desktop+bar │
  │           · launch/close apps · event loop   │
  ├──────────────┬──────────────┬────────────────┤
  │  UI toolkit  │ CONFIG (json)│  LOG  · (svcs*) │  ← support modules
  ├──────────────┴──────────────┴────────────────┤
  │  CraftOS  (term, http, fs, parallel, os…)     │  ← provided by CC
  └─────────────────────────────────────────────┘
  * services layer = future Approach C, designed-for, not built in v1.
```

**Boot flow**
1. `startup.lua` (auto-run by CC on power-on) requires and starts the kernel.
2. Kernel initializes `config`, `log`, `ui`; **discovers** apps by scanning
   `/os/apps/`.
3. Kernel draws the desktop: taskbar (clock + menu) and a grid of clickable
   icons.
4. Click an icon → kernel launches that app full-screen → on return, redraws
   the desktop.

**On-disk layout (in-game computer)**
```
startup.lua            -> boots the kernel
/os/kernel.lua         -> core
/os/ui.lua             -> drawing toolkit (immediate-mode)
/os/config.lua         -> settings load/save
/os/log.lua            -> timestamped logging to /logs/
/os/apps/claude.lua    -> Claude chat app
/os/apps/settings.lua  -> settings app
/os/apps/update.lua    -> pull latest from bridge + reboot
/os/apps/terminal.lua  -> drop to CraftOS shell
/os/apps/about.lua     -> version/help; doubles as "hello world" template
/cfg/system.json       -> persisted settings (theme, bridge URL…)
/data/<app>/           -> bulk per-app data (maps, logs) — NOT settings
/logs/                 -> system + per-app logs
```

## 5. App contract (extensibility core)

An app is a file in `/os/apps/` that **returns a table**: metadata + a `run`
function. Nothing else is required.

```lua
-- /os/apps/claude.lua
return {
  id    = "claude",            -- unique; equals the filename
  name  = "Claude",            -- label under the icon
  icon  = "C",                 -- single glyph in v1
  color = colors.cyan,         -- icon tile color
  desc  = "Chat con Claude",   -- about/tooltip
  run   = function(ctx) ... end, -- full-screen entry; returning = exit
}
```

**`ctx` is the only boundary** an app may use — it never reaches into kernel
internals:

| `ctx` field | Provides |
|---|---|
| `ctx.ui` | drawing toolkit: `titleBar`, `button`, `hit`, `wrap`, `text`, theme colors |
| `ctx.config` | settings **namespaced to `app.id`**: `get(key, default)` / `set(key, v)` (auto-persisted) |
| `ctx.term` | the draw surface (computer term; redirectable to a monitor) |
| `ctx.width` / `ctx.height` | current screen size (auto-fit) |
| `ctx.log(msg)` | append to `/logs/<app>.log` |
| `ctx.sys` | OS API: `sys.openApp(id)`, `sys.theme`, `sys.version` |

**Lifecycle (Approach B, full-screen, synchronous)**
1. Click icon → kernel clears screen, builds `ctx`, calls `app.run(ctx)` under
   `pcall`.
2. App owns the screen and its own `os.pullEvent` loop until it returns
   (click the title-bar `[x]`, or a reserved key).
3. `run` returns → kernel redraws the desktop. If `run` errored, kernel shows
   the error and redraws anyway.

**Discovery** — kernel scans `/os/apps/`, loads each file, validates it returns
a table with `id`, `name`, `run`. Invalid files are **skipped and logged**;
boot never fails because of one bad app. System apps (Settings, etc.) follow
the same contract — the OS dogfoods it.

**Growth to Approach C (free):** because an app only talks through `ctx` and
blocks in `os.pullEvent`, the kernel can later wrap `app.run` in a coroutine and
multiplex with `parallel`. CC coroutines yield exactly at `os.pullEvent`, so
**app code does not change**. Choosing B costs nothing future-wise.

## 6. Support subsystems

### 6.1 UI toolkit (`/os/ui.lua`) — immediate mode
Decision: **immediate-mode**, not a retained widget tree (that is Approach A,
with hidden state and bugs). Pattern: draw → each widget returns its rectangle →
the app's loop hit-tests clicks against those rectangles.

```lua
local r = ui.button(2, 5, "Enviar")          -- draws, returns {x,y,w,h}
local _, btn, mx, my = os.pullEvent("mouse_click")
if ui.hit(r, mx, my) then ... end
```

Helpers: `clear/fill/text/center`, `wrap` (via `cc.strings.wrap`),
`titleBar(title)` (top bar with clickable `[x]`), `button`, `hit`, `toast`.
Surface-agnostic (operates on the current `term`, so apps redirect to a monitor
unchanged). Respects the configurable **theme** (the customization hook).

### 6.2 Config (`/os/config.lua`) — one JSON, namespaced
Decision: a single `/cfg/system.json` with per-app sections (not one file per
app). API: `config.get(ns, key, default)`, `config.set(ns, key, value)`,
`config.save()`. `ctx.config` binds `ns = app.id` automatically.

- **Atomic save:** write `system.json.tmp`, then `fs.move` over the real file.
  A power-off mid-write never corrupts settings.
- **Tolerant load:** corrupt JSON → back up the bad file, start from defaults,
  never crash.
- **Settings vs data:** small settings live in `config`; bulk app data lives in
  `/data/<app>/`, managed by the app.

### 6.3 Logging (`/os/log.lua`)
Timestamped lines to `/logs/system.log` and `/logs/<app>.log`. This is how we
debug without a monitor — first-class, not an afterthought. `ctx.log` feeds it.

### 6.4 Error handling — 4 layers
| Layer | Behavior |
|---|---|
| **App** | `app.run` under `pcall`; on error log it, show "La app X falló: <msg>", return to desktop. OS survives. |
| **Boot/discovery** | bad app file skipped + logged; boot continues. |
| **Kernel** | main loop under `pcall`; kernel-level failure shows a recoverable "panic" screen (reboot / drop to shell), not a cryptic dump. |
| **Logs** | every error written with timestamp + app id. |

**Ctrl+T:** left as a real escape to the CraftOS shell during development (an
emergency exit for both of us). May later be trapped with a confirm prompt.

## 7. Distribution & dev loop

The existing PC **bridge** (`claude-bridge.js`) gains a static-serving role
alongside the chat endpoint. New routes:

- `GET /manifest` → `{ version, files: [{ path }] }`
- `GET /fs/<path>` → that file's contents
- `GET /install` → a tiny Lua bootstrap script

**Install (typed once in-game):**
```
wget run http://127.0.0.1:8080/install
```
The bootstrap reads the manifest, downloads each file to its path (creating
dirs), then reboots.

**Update:** an `update` app/command re-fetches the latest and reboots.
Dev loop: *edit files here → click **Update** in-game → computer pulls latest +
reboots → change visible.* No copy/paste, no manual file editing.

- Source of truth: a `dist/` folder on the PC mirroring the in-game layout; the
  bridge serves it; the installer replicates it.
- **Robust update:** download to temp paths, then move into place — never
  half-overwrite the running kernel; abort cleanly on a failed download.

**Prerequisite:** CC:T must allow `127.0.0.1`. In the world's
`serverconfig/computercraft-server.toml`, change the `$private` rule from `deny`
to `allow` (or remove it). Exact TOML provided at install time.

**Chat backend (deferred decision):** v1 reuses the existing bridge path
(`claude -p`, drawing on the subscription; `--bare` removed, stdin closed,
terminal system prompt + ASCII transliteration already implemented). Whether to
later swap the Claude app's backend to a direct API call (faster/cheaper, needs
an API key) is an app-level decision deferred to the Claude app's own iteration.

## 8. v1 app set

| App | Proves | Effort |
|---|---|---|
| **Claude** | the polished chat (wrap, spinner, ASCII, `titleBar`, configurable URL) | medium — ~90% exists |
| **Settings** | config persistence + customization (theme, bridge URL) | low |
| **Update** | the update loop | low |
| **Terminal** | escape to CraftOS shell | trivial |
| **About** | version/help; serves as the "hello world" app template | trivial |

Bulk of the work is **kernel + ui + config + log + Claude app**; the rest is
light. v1 demonstrates: boot → desktop → clickable icons → run apps → settings
persist → update.

## 9. Testing strategy

No local Lua → no local unit tests of CC code. Mitigations:
1. **Isolate pure logic** (text wrap math, manifest parsing, config
   (de)serialization, app-discovery filtering) into CC-API-free functions that
   are reviewable and, if a Lua runtime is added, testable.
2. **Optional: CraftOS-PC** (desktop CC:Tweaked emulator) for a faster loop and
   possible automated smoke tests — owner's choice, not required.
3. **Live loop**: owner runs `update`, reports behavior / shares `/logs`.

v1 relies on (1) + (3). (2) is an optional accelerator.

## 10. Out of scope / future (each its own spec)

- **Gold/ore mapper** — needs Advanced Peripherals Geo Scanner (Forge/NeoForge),
  or a mining-turtle inspect-logger as a vanilla alternative.
- **GPS app** — build a 4-computer GPS constellation, then `gps.locate()`.
- **Farm automation** — turtles and/or redstone control.
- **Background services (Approach C)** — keep the Claude session warm, rednet
  listener, live clock.
- **Window manager (Approach A)** — only really worthwhile on a large monitor.
- **Chat Box synergy** (needs Advanced Peripherals) — talk to Claude from normal
  Minecraft chat, not just the computer terminal.

## 11. Confirmed decisions

1. **Name:** PinguOS (confirmed).
2. **v1 surface:** computer terminal only; monitors deferred (confirmed).
3. **v1 app set:** Claude, Settings, Update, Terminal, About — as listed
   (confirmed).
