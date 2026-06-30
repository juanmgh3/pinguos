# PinguOS — HD Edition & Fleet Command Center

- **Status:** Draft for review
- **Date:** 2026-06-30
- **Slug:** `hd-command-center`
- **Owner:** Juan
- **Supersedes:** the "no Advanced Peripherals / terminal-only" constraints in
  `design.md` §3/§10 (those were true for the Fabric 26.2 setup; see §3 here).

> Durable record for this feature, per the SDD flow. This is the contract the
> implementation builds against. If it isn't written here, it isn't agreed.

---

## 1. Summary & vision

PinguOS moves to the new **NeoForge 1.21.1** instance, where mods unlock
capabilities the original Fabric 26.2 setup never had. This feature turns PinguOS
from a terminal-only pocket OS into a **two-surface OS with an HD edition**: the
same OS, when run on a stationary computer wired to a **Tom's Peripherals HD
monitor wall**, renders the *entire desktop and all apps* in true-color HD — not
just one app.

The flagship app on that surface is the **Fleet Command Center**: a live tactical
view of the autonomous turtle fleet (already built; see `fleet-autonomy.md`),
drawn on the HD canvas using telemetry that already flows over the `pingufleet`
rednet protocol.

The guiding principle (the reason this is worth building at all):

> **PinguOS does not compete with client mods; it shows what no mod can.**
> Xaero's already gives the player's world map. What no mod gives is the view of
> *your own system* — where your turtles are and what they're doing, your Create
> machines, your AE2 storage, an ore scan through the rock. PinguOS is the
> **command center of your base**. The Fleet panel is its first piece.

## 2. Goals / Non-goals

**Goals**
- A reusable **HD render layer** (`gpu.lua`) over Tom's `tm_gpu`, sibling to `ui.lua`.
- `ui.lua` gains an **HD backend**, so the desktop and all existing apps render in
  HD on the station *without per-app rewrites* (the high-leverage move).
- The desktop (wallpaper, icons, taskbar, clock) is **polished HD-native**.
- A **Fleet Command Center** app: live tactical map + status cards (read-only
  first), then on-screen control (dispatch/cancel) via touch + physical keyboard.
- **Graceful degradation:** with no monitor present (e.g. the pocket), the OS and
  every app fall back to the current terminal rendering. One codebase.

**Non-goals (this spec)**
- Rewriting every app's UX for HD beyond what the `ui.lua` backend gives for free.
  Per-app HD polish is roadmap (§10), one spec at a time.
- The ore radar / geoScanner mapper, Create dashboard, AE2 storage view — roadmap.
- Replacing the Claude app's backend with ClaudeCraft — independent quick-win,
  its own spec (§10).
- 3D rendering (Tom's `GPU3D`). The map is 2D.

## 3. Environment & constraints (verified, 2026-06-30)

Targets the user's NeoForge instance: MC 1.21.1, NeoForge, CC:Tweaked 1.120.0,
Advanced Peripherals 0.7.62b, Tom's Peripherals 1.3.1, ClaudeCraft 1.2.2.

| Fact | Consequence |
|---|---|
| **Tom's monitor is NOT a `term`.** The GPU block (`tm_gpu`) is a true-color **ARGB pixel** surface with its own draw API (`filledRectangle`, `drawText`, `line`, `sync`), double-buffered (draw → `sync()`). | `ui.lua` (immediate-mode over *character cells*) cannot paint there as-is. We need a new render layer (`gpu.lua`) and a cell→pixel backend for `ui.lua`. This is the central architectural fact. |
| GPU block is wrapped as `tm_gpu`; monitor blocks are passive. `getSize()` → `wpx, hpx, blocksX, blocksY, sizeMult`. Per-block resolution 16–64 px (`setSize`). 3×3 wall @64 = 192×192 px. | Wrap the GPU, not the monitor. Call `refreshSize()` at start, draw, `sync()`. |
| Color = ARGB int `0xAARRGGBB` (or R,G,B[,A]). **No power needed.** Physical keyboard `tm_keyboard` + touch `tm_monitor_touch` ({x,y,sneaking} in pixels). | Real colors, smooth bars, crisp fonts. Input model for HD control. |
| **No `setPixel`**; single pixels via `filledRectangle(x,y,1,1,c)`. PNG via `decodeImage`/`drawImage` (exact input type to confirm in-game). | Draw with rects/lines/text/images; pixel-pushing is rare. |
| Fleet telemetry **already flows** over `pingufleet` rednet: per turtle `role, status (idle/working/blocked/nofuel), fuel, pos (gps x/y/z), job, progress {pct,info}, inv%`. | The Fleet panel is a **new renderer over existing, proven data** — risk is isolated in `gpu.lua`, not in fleet logic. |
| The OS runs on a **pocket** today; the HD edition runs on a **stationary** Advanced Computer (monitor wall + modem). | Two surfaces, one codebase. Form factor is a deploy choice, not a fork. |
| Stale repo constraints (`CLAUDE.md` "No Advanced Peripherals"; `design.md` §3/§10; `turtle/lib/api.lua:106`, `turtle/jobs/lumber.lua:4` "no scanner") describe the OLD Fabric setup. | Increment 0 updates them so the repo stops lying about capabilities. |

## 4. Architecture (Approach B: one OS, two surfaces)

```
  ┌─────────────────────────────────────────────┐
  │  APPS  /os/apps/*.lua   (fleet, claude, …)   │  ← unchanged contract
  ├─────────────────────────────────────────────┤
  │  KERNEL  desktop · app launch · event loop   │
  ├──────────────┬──────────────────────────────┤
  │  ui.lua      │  term backend  (character grid)│  ← existing path (pocket)
  │  (immediate) ├──────────────────────────────┤
  │              │  HD backend → gpu.lua (pixels) │  ← NEW path (station)
  ├──────────────┴──────────────────────────────┤
  │  gpu.lua   wraps tm_gpu (ARGB, double-buffer) │  ← NEW render layer
  └─────────────────────────────────────────────┘
```

- **Surface detection at boot:** kernel looks for a `tm_gpu`. Found → HD mode
  (ui.lua routes draws through `gpu.lua`); absent → terminal mode (today's path).
- **`ctx.gpu`** is added to the app context, present only in HD mode. Apps stay
  `ctx`-only. Most apps never touch `ctx.gpu` — they use `ui.lua` and get HD for
  free. HD-*native* apps (the Fleet panel) use `ctx.gpu` directly for custom
  visuals (the tactical map).
- **One codebase, graceful degradation** — the pocket keeps working unchanged.

> **Increment 0 (housekeeping, no code risk):** update the stale repo constraints
> in §3 (`CLAUDE.md` "No Advanced Peripherals", `design.md` §3/§10, the
> `turtle/` "no scanner" comments) and confirm PinguOS boots on the station with a
> modem. Lands first; nothing else depends on it but it stops the repo from lying.

## 5. `gpu.lua` — the HD render layer (Increment 1)

Sibling to `ui.lua`. Wraps `tm_gpu`, hides the double-buffer, exposes clean,
testable primitives. Owns an **ARGB palette derived from the active PinguOS
theme**, so HD respects existing colors.

```lua
local gpu = require-free module returned table:
  gpu.attach()              -- find tm_gpu, refreshSize, setSize; nil if none
  gpu.size()                -- -> wpx, hpx
  gpu.clear(color?)         -- fill buffer (theme bg default)
  gpu.rect(x,y,w,h,color)           -- outline
  gpu.fillRect(x,y,w,h,color)
  gpu.line(x1,y1,x2,y2,color,smooth?)
  gpu.text(x,y,str,fg?,bg?,size?)
  gpu.bar(x,y,w,h,pct,fg,bg)        -- smooth progress/fuel bar (composed)
  gpu.image(x,y,ref)                -- blit a decoded image
  gpu.present()                     -- the sync() buffer push
  gpu.color(themeKey|argb)          -- theme-name -> ARGB resolver
```

- **Pure/testable split:** geometry (theme→ARGB mapping, bar fill math, text
  layout/measure, the cell→pixel transform used by §6) lives in CC-API-free
  functions, unit-tested on local Lua 5.4 like `geo`/`nav`. The `tm_gpu` calls are
  the thin I/O edge, `luac -p`-checked, validated in-game.
- **Double-buffer discipline:** apps draw a whole frame, then one `present()` —
  mirrors the coalesced-redraw pattern the Fleet app already uses for the terminal.

## 6. `ui.lua` HD backend — the OS looks better, for free (Increment 2)

`ui.lua` becomes **surface-agnostic**. Today every helper writes to `term`. We add
a backend selected at boot:

- **term backend** (default): exactly today's behavior.
- **HD backend**: each `ui.*` call renders the same semantics through `gpu.lua`.
  A character "cell" maps to an N×M pixel block; the 16-color CC palette maps to
  ARGB; `ui.text/fill/button/titleBar/panel/iconTile/bar` route to `gpu.*`.

Result: the **kernel desktop and all existing apps render in HD with no app
changes**. This is the high-leverage core of "make the OS look better."

- The app contract (`ctx.ui`, `ctx.term`, hit-testing with `ui.hit`) is unchanged.
  Hit-tests still work: the HD backend reports regions in the app's coordinate
  space; touch events (`tm_monitor_touch`, in pixels) are translated back to that
  space by the kernel before dispatch, so `ui.hit` logic is untouched.
- **Risk control:** if a widget looks wrong in HD, fix it in one place (the
  backend), not in eight apps.

## 7. Desktop HD polish (Increment 3)

With the backend live, hand-polish what carries the "Tony Stark" first impression,
HD-native via `ctx.gpu`/themed `ui.lua`:
- **Wallpaper:** real image/gradient (Tom's `drawImage`/`fillRect`), replacing the
  flat fill, reusing `ui.wallpapers` as theme keys.
- **Icon tiles:** depth (shadow/gradient), larger crisp glyphs, hover/selected
  states (touch).
- **Taskbar + clock:** refined bar, real font; optional live data later
  (environmentDetector time/biome) — kept minimal here.

## 8. Fleet Command Center (Increments 4–5)

HD-native app (`dist/os/apps/fleet.lua` gains an HD path; keeps its terminal path).
Data source unchanged: `pingufleet`.

**Increment 4 — live view (read-only):**
- **Tactical map** (left): turtles as blips placed by GPS coords, anchored to a
  base origin (configurable; default = the station's own GPS pos). Blip color by
  status (working/idle/blocked/nofuel), label = name + job, optional movement
  trail. Reuses `geo.toMinimap` projection math, retargeted to pixel space.
- **Status cards** (right): per turtle, smooth fuel/progress/inventory bars +
  status. What were ASCII blocks become real bars.
- **Header:** active count, clock.

**Increment 5 — on-screen control:**
- Tap a blip/card (touch) → select turtle → job menu from its self-reported
  **catalog** (the data already exists) → params via the **physical keyboard** →
  dispatch. Cancel/Recall button. **Reuses the dispatch/cancel logic the terminal
  Fleet app already has** — only the input/render surface is new.
- Until this ships, control stays on the pocket/terminal Fleet app.

## 9. Verification

- **Pure logic** (`gpu.lua` geometry, cell→pixel transform, bar math, map
  projection) unit-tested on local Lua 5.4 (`dist/tests/`), as with `geo`/`nav`.
- **CC-bound** code (`tm_gpu` I/O, kernel surface detection, touch translation)
  `luac -p`-checked; validated **in-game** by the owner via the Update app.
- Each increment ships green (tests + `luac -p`) and is visually confirmed in-game
  before the next starts.

## 10. Out of scope / roadmap (each its own spec)

- **Claude app via ClaudeCraft** — independent quick-win. ClaudeCraft exposes a
  global `claude.*` API (`startChannel`→`sendMessage`→`claude_text`/`claude_done`
  events) that a custom app can **wrap**, keeping PinguOS's UI and dropping the
  Node HTTP bridge + ASCII relay. (One in-game check first: confirm `_G.claude` is
  visible inside a `loadfile`-loaded app.)
- **Ore radar** — geoScanner `scan(8)` is free, returns 4,913 blocks in a 17³ cube
  with relative x/y/z + name, sees through rock, 1 scan / 2s. The `design.md` §10
  mapper, now possible.
- **Create dashboard** (CC:C Bridge), **AE2 storage view** (ME bridge),
  **chat-box notifications** (Advanced Peripherals chatBox).
- **Per-app HD polish** beyond the free backend; **3D** map (`GPU3D`).

## 11. Confirmed decisions

1. Flagship reoriented from "world map" to **command center** — Xaero's already
   covers the world map; PinguOS shows what no mod can (confirmed).
2. **Approach B**: one OS, HD backend behind surface detection, graceful
   degradation to terminal (confirmed).
3. Scope includes **whole-OS HD** via the `ui.lua` backend, not just the Fleet app
   (confirmed — "adapt the OS so it looks better").
4. First increment of the Fleet panel is **read-only live view**; HD control
   second (recommended; revise if desired).
