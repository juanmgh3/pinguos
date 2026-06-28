# PinguOS — GPS app + visual decoration pass

- **Status:** Approved, building
- **Date:** 2026-06-28
- **Depends on:** PinguOS v1 (kernel, ui, config, apps contract)

## Part A — Visual language (applies to the whole OS)

PinguOS v1 worked but looked plain. Add a cohesive, font-safe visual language
driven by **color blocks** (not exotic glyphs, which depend on the font).

New `ui.lua` helpers (inherited by every app):
- `ui.shadow(x, y, w, h)` — drop shadow (gray cells) offset bottom-right.
- `ui.panel(x, y, w, h, opts)` — framed/two-tone panel; optional title; optional shadow.
- `ui.statusBar(text)` — bottom accent bar with hint text.
- `ui.splash(version)` — brief boot splash: PinguOS wordmark + a block-art penguin.
- Restyle `ui.titleBar` (left accent block + styled close) and `ui.button`
  (filled, with a pressed highlight via `ui.buttonDown`).
- `ui.iconTile(x, y, glyph, color, label, selected)` — the shadowed desktop tile.

Retrofit: the kernel desktop (shadowed tiles, accent top bar, bottom status bar,
splash at boot) and the four existing apps (About, Settings, Terminal, Update)
adopt panels/accents. Taste over volume — a few strong touches, not clutter.

## Part B — GPS / map app (pocket computer)

**Prerequisites (set up once in creative; guide the owner):**
- **GPS constellation:** 4 computers, each with an **ender modem**, at known fixed
  coords, running `gps host`. Needed for `gps.locate()` to return a position.
- **Pocket:** an **Advanced Pocket Computer** with an **ender modem**, PinguOS
  installed via `wget run http://127.0.0.1:8080/install`.

**App `dist/os/apps/gps.lua`:**
- Header: live `X / Y / Z` + heading (N/NE/E/...). Heading derives from the delta
  between successive `gps.locate()` reads (so it only knows heading while moving).
- Minimap: top-down, centered on the player (`@`), with the breadcrumb trail
  (`.`) and waypoints (letters), inside a framed `ui.panel`.
- Actions (click/key): **Mark** waypoint here (named), **Waypoints** list with
  distance + compass direction to each (the orientation feature), **Clear** trail.
- Persistence: waypoints saved in config (namespace `gps`). Trail kept in memory
  (last ~200 points).
- No signal: if `gps.locate()` returns nil (no constellation / out of range),
  show "Sin senal GPS" instead of crashing.

**Out of scope:** block/ore scanning — not possible on this setup (Fabric + MC
26.2; Advanced Peripherals is Forge/NeoForge, and the Fabric scanner addons
Finer Peripherals / Plethora only support 1.20.1). Revisit if those reach 26.2.

## Pure, testable module

`dist/os/geo.lua` — CC-API-free math, unit-tested locally with the Lua runner:
- `geo.distance(a, b)` — 3D distance between `{x,y,z}` points.
- `geo.compass(from, to)` — 8-point compass direction ("N", "NE", ...).
- `geo.heading(prev, cur)` — compass direction of travel between two points.
- `geo.toMinimap(player, point, w, h, scale)` — project a world point to minimap
  cell coords centered on the player, or nil if off-map.

CC-bound modules (ui decoration, kernel desktop, gps app) are syntax-checked
with `luac -p` and verified in-game (the live loop).

## Constellation setup (recorded for the owner)

1. Place 4 Advanced Computers, spread out and not all on the same plane (e.g.
   high up, in a rough cross). Note each one's exact X/Y/Z (F3).
2. On each: attach an ender modem (right side), then run:
   `edit startup` -> `shell.run("gps","host",<x>,<y>,<z>)` (its real coords) -> save.
   Reboot. (Or just run `gps host <x> <y> <z>` and keep it open.)
3. The pocket (with ender modem) can now call `gps.locate()` anywhere.
