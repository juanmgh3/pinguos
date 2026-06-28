# PinguOS

A small desktop OS for a CC: Tweaked Advanced Computer, plus a Node bridge that
serves it and relays a Claude chat app.

## Run

1. **Allow `127.0.0.1`** in the world's `serverconfig/computercraft-server.toml`
   (see `specs/pinguos/plan.md`, Task 14). Add, above the `$private` deny:
   ```toml
   [[http.rules]]
       host = "127.0.0.1"
       action = "allow"
   ```
2. **PC:** start the bridge from this folder:
   ```
   DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js
   ```
3. **In-game** (Advanced Computer):
   ```
   wget run http://127.0.0.1:8080/install
   ```
   It downloads PinguOS and reboots into the desktop.
4. **Update** later (after editing files on the PC): run the **Update** app, or
   `wget run http://127.0.0.1:8080/install` again.

## Tests

- Bridge (Node, local): `node --test`
- OS pure modules (Lua): `lua dist/tests/run.lua` (or in CraftOS-PC)

## Layout

- `dist/` — the in-game OS (source of truth; served by the bridge)
  - `startup.lua`, `os/kernel.lua`, `os/ui.lua`, `os/config.lua`, `os/log.lua`,
    `os/text.lua`, `os/appreg.lua`, `os/apps/*.lua`
- `bridge/` — bridge logic: `ascii.js`, `manifest.js`, `install.js`, `fspath.js`
- `claude-bridge.js` — the HTTP server (chat + install/update routes)
- `specs/pinguos/` — design spec and implementation plan

## Notes

- The chat POST endpoint requires `Content-Type: application/json` and rejects
  cross-origin requests (anti-CSRF), since it drives a tool-capable Claude.
- Adding an app: drop a file in `dist/os/apps/` returning `{ id, name, icon,
  color, run = function(ctx) ... end }`. Copy `about.lua` as a template.
