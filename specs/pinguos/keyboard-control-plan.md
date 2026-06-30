# Keyboard Control — Implementation Plan (Phase 1: desktop)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the PinguOS desktop fully operable by keyboard — move an icon
highlight with the arrows and launch the focused app with Enter — on the HD
station, without breaking mouse/touch.

**Architecture:** A new pure module `focus.lua` does the spatial math (nearest
focusable in a direction). The kernel's `desktopLoop` keeps a `focusIdx` over the
page's icon tiles, moves it with `focus.spatial` on arrow keys (reusing the
existing `iconTile` `selected` highlight), and launches the focused app on Enter.
Self-contained in the kernel — no parallel daemon, no app changes. App-internal
focus (the parallel focus manager + synthesised clicks) is **Phase 2**, a separate
plan written after this ships and validates the pattern in-game.

**Tech Stack:** Lua (CC: Tweaked 5.1 in-game, Lua 5.4 locally), Tom's `tm_keyboard`
already wired in `kernel.run` (`setFireNativeEvents(true)`).

## Global Constraints

- **Lua must run on CC 5.1 AND local 5.4.** Use only constructs valid in both
  (no `//`, no bit-ops; `math.floor` before any `string.format("%d", n)`).
- **Rendered text is ASCII only** — the CC terminal is 8-bit.
- **Test model:** pure logic is unit-tested on local Lua 5.4 via
  `"$LUA" dist/tests/run.lua`; CC-bound code is `luac -p`-checked and validated
  **in-game** by the owner via the Update app. `$LUA` = `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`, `$LUAC` = `luac.exe` beside it.
- **Arrow key ids (CC `keys`):** up=265, down=264, left=263, right=262, enter=257.
- **Esc is reserved** (closes Tom's capture GUI); never bind `Ctrl+T/R/S`.

---

### Task 1: `focus.lua` — pure spatial-navigation helper

**Files:**
- Create: `dist/os/focus.lua`
- Test: `dist/tests/test_focus.lua`
- Modify: `dist/tests/run.lua` (register the new test)

**Interfaces:**
- Consumes: nothing (pure; no CC globals).
- Produces:
  - `focus.center(r) -> cx, cy` — integer centre cell of a region `{x,y,w,h}`.
  - `focus.spatial(rects, current, dir) -> index` — `rects` is a list of
    `{x,y,w,h}`; `current` is a 1-based index; `dir` is `"up"|"down"|"left"|"right"`.
    Returns the index of the nearest focusable in that direction, or `current` if
    none, `0` for an empty list, `1` for an out-of-range `current`.

- [ ] **Step 1: Write the failing test**

Create `dist/tests/test_focus.lua`:

```lua
-- dist/tests/test_focus.lua  -- pure spatial focus navigation (desktop grid).
local focus = require("focus")

-- center: integer centre cell of a region
T.eq({ focus.center({ x = 2, y = 3, w = 9, h = 3 }) }, { 6, 4 }, "center of 9x3 tile")
T.eq({ focus.center({ x = 1, y = 1, w = 1, h = 1 }) }, { 1, 1 }, "center of 1x1")

-- a 2x2 grid of tiles, like the desktop: 1,2 top row; 3,4 bottom row
local grid = {
  { x = 2,  y = 3, w = 9, h = 3 },  -- 1 top-left
  { x = 14, y = 3, w = 9, h = 3 },  -- 2 top-right
  { x = 2,  y = 9, w = 9, h = 3 },  -- 3 bottom-left
  { x = 14, y = 9, w = 9, h = 3 },  -- 4 bottom-right
}
T.eq(focus.spatial(grid, 1, "right"), 2, "right from 1 -> 2")
T.eq(focus.spatial(grid, 1, "down"),  3, "down from 1 -> 3")
T.eq(focus.spatial(grid, 2, "left"),  1, "left from 2 -> 1")
T.eq(focus.spatial(grid, 4, "up"),    2, "up from 4 -> 2")
T.eq(focus.spatial(grid, 1, "left"),  1, "no tile left of 1 -> stays")
T.eq(focus.spatial(grid, 1, "up"),    1, "no tile above 1 -> stays")

-- guards
T.eq(focus.spatial({}, 1, "right"),   0, "empty list -> 0")
T.eq(focus.spatial(grid, 0, "right"), 1, "bad index -> first")
```

- [ ] **Step 2: Register the test in the runner**

In `dist/tests/run.lua`, add this line immediately after the existing
`dofile("dist/tests/test_hdterm.lua")` line (currently line 33):

```lua
dofile("dist/tests/test_focus.lua")
```

- [ ] **Step 3: Run the suite to verify it fails**

Run: `"$LUA" dist/tests/run.lua`
Expected: error / FAIL — `module 'focus' not found` (the module does not exist yet).

- [ ] **Step 4: Write the implementation**

Create `dist/os/focus.lua`:

```lua
-- dist/os/focus.lua  -- pure keyboard-focus navigation math (no CC globals).
-- Phase 1 uses center + spatial for the desktop icon grid. Unit-tested on Lua 5.4
-- (dist/tests/test_focus.lua); loads clean in both CC 5.1 and local 5.4.
local focus = {}

-- Integer centre cell of a region {x,y,w,h}.
function focus.center(r)
  return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2)
end

-- Nearest focusable in a spatial direction.
--   rects   : list of {x,y,w,h}
--   current : 1-based index of the focused rect
--   dir     : "up" | "down" | "left" | "right"
-- Returns the new index (current if nothing lies that way; 0 if empty;
-- 1 if current is out of range). A candidate counts as "in dir" when its centre
-- is on that side AND the move is more along that axis than across it; ties break
-- on squared centre-distance (closest wins).
function focus.spatial(rects, current, dir)
  if #rects == 0 then return 0 end
  if current < 1 or current > #rects then return 1 end
  local cx, cy = focus.center(rects[current])
  local best, bestScore = current, nil
  for i, r in ipairs(rects) do
    if i ~= current then
      local ix, iy = focus.center(r)
      local dx, dy = ix - cx, iy - cy
      local aligned =
           (dir == "right" and dx > 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "left"  and dx < 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "down"  and dy > 0 and math.abs(dy) >= math.abs(dx))
        or (dir == "up"    and dy < 0 and math.abs(dy) >= math.abs(dx))
      if aligned then
        local score = dx * dx + dy * dy
        if not bestScore or score < bestScore then best, bestScore = i, score end
      end
    end
  end
  return best
end

return focus
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: N passed, 0 failed` (N = previous count + 8).

- [ ] **Step 6: Syntax-check for CC 5.1 compatibility**

Run: `"$LUAC" -p dist/os/focus.lua`
Expected: no output (success).

- [ ] **Step 7: Commit**

```bash
git add dist/os/focus.lua dist/tests/test_focus.lua dist/tests/run.lua
git commit -m "feat(os): add focus.lua spatial navigation helper (pure, tested)"
```

---

### Task 2: Desktop keyboard navigation (arrows + Enter)

**Files:**
- Modify: `dist/os/kernel.lua` (require `focus`; `drawDesktop` signature + icon
  highlight; `desktopLoop` focus state + key handling)

**Interfaces:**
- Consumes: `focus.spatial`, `focus.center` (Task 1); the existing
  `ui.iconTile(x,y,glyph,color,label,selected,labelBg)` `selected` parameter; CC
  `keys` constants and `os.pullEvent`.
- Produces: no new exports; behaviour change only.

- [ ] **Step 1: Require the focus module**

In `dist/os/kernel.lua`, add after the existing `local hdterm = require("hdterm")`
line (currently line 12):

```lua
local focus = require("focus")
```

- [ ] **Step 2: Thread a focus index into `drawDesktop`**

Change the `drawDesktop` signature (currently `local function drawDesktop(apps, page)`)
to take a focused index:

```lua
local function drawDesktop(apps, page, focusIdx)
```

Then, in the tile loop, change the `iconTile` call so the focused tile draws
selected. Replace the current call:

```lua
      ui.iconTile(cx, cy, app.icon or "?", app.color or ui.theme.accent,
                  text.truncate(app.name, 11), false, wbg)
```

with (the tile about to be appended will be at index `#tiles + 1`):

```lua
      ui.iconTile(cx, cy, app.icon or "?", app.color or ui.theme.accent,
                  text.truncate(app.name, 11), (#tiles + 1 == focusIdx), wbg)
```

- [ ] **Step 3: Keep a `focusIdx` in `desktopLoop` and pass it to `drawDesktop`**

In `desktopLoop`, change the loop state line (currently `local page = 1`) to:

```lua
  local page, focusIdx = 1, 1
```

Change the draw call (currently `local tiles, dots, pages, cur = drawDesktop(apps, page)`) to:

```lua
    local tiles, dots, pages, cur = drawDesktop(apps, page, focusIdx)
```

Immediately after `page = cur` (the next line), clamp the focus into range:

```lua
    if focusIdx > #tiles then focusIdx = #tiles end
    if focusIdx < 1 then focusIdx = 1 end
```

- [ ] **Step 4: Handle arrows + Enter in the key branch**

In `desktopLoop`, replace the existing `elseif name == "key" then` branch
(currently):

```lua
      elseif name == "key" then
        if ev[2] == keys.right and page < pages then page = page + 1; redraw = true
        elseif ev[2] == keys.left and page > 1 then page = page - 1; redraw = true end
```

with a focus-aware handler (Enter launches the focused app; arrows move the
highlight, and left/right at a grid edge flip the page, preserving today's paging):

```lua
      elseif name == "key" then
        local k = ev[2]
        if k == keys.enter then
          if tiles[focusIdx] then runApp(tiles[focusIdx].app); redraw = true end
        elseif k == keys.up or k == keys.down or k == keys.left or k == keys.right then
          local dir = (k == keys.up and "up") or (k == keys.down and "down")
                   or (k == keys.left and "left") or "right"
          local rects = {}
          for i, t in ipairs(tiles) do rects[i] = t.r end
          local ni = focus.spatial(rects, focusIdx, dir)
          if ni ~= focusIdx then
            focusIdx = ni; redraw = true
          elseif dir == "right" and page < pages then
            page = page + 1; focusIdx = 1; redraw = true
          elseif dir == "left" and page > 1 then
            page = page - 1; focusIdx = 1; redraw = true
          end
        end
```

- [ ] **Step 5: Syntax-check the kernel**

Run: `"$LUAC" -p dist/os/kernel.lua`
Expected: no output (success).

- [ ] **Step 6: Run the full suite (no regressions)**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: N passed, 0 failed` (unchanged count from Task 1).

- [ ] **Step 7: Validate in-game (owner)**

1. Ensure the bridge is running (`DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`).
2. On the HD station, open the **Update** app and reboot.
3. On the desktop, open the keyboard capture GUI and:
   - Press **arrows** → the highlighted icon (accent strip on top of a tile) moves
     across the grid; at a left/right edge, the page flips.
   - Press **Enter** → the focused app opens.
   - Confirm the **mouse/touch** still opens apps as before (no regression).

- [ ] **Step 8: Commit**

```bash
git add dist/os/kernel.lua
git commit -m "feat(os): keyboard navigation on the desktop (arrows + Enter)"
```

---

## Self-Review

**Spec coverage (Phase 1 slice of `keyboard-control.md`):**
- §4 key map — arrows move focus, Enter activates: Task 2. (Tab, Ctrl+B/Ctrl+Q are
  Phase 2 — app-level focus.)
- §5 reuse `iconTile`'s existing `selected` highlight: Task 2, Step 2.
- §6 `focus.lua` pure + unit-tested: Task 1.
- §7 Increment 0 (desktop keyboard-navigable): this plan. Increments 1–2 (apps,
  back/quit) are the Phase 2 plan, deliberately deferred until the pattern is
  validated in-game here.
- §8 verification (pure tests + luac -p + in-game): Tasks 1 & 2.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `focus.center`/`focus.spatial` signatures used in Task 2
match Task 1's `Produces`. `drawDesktop(apps, page, focusIdx)` and the `tiles[i].r`
shape (`{x,y,w,h}`) are consistent across steps.

**Out of scope (Phase 2, separate plan):** `ui.lua` focusable registry,
the parallel focus manager, Enter→synthesised-click for apps, `Ctrl+B`/`Ctrl+Q`,
migrating hand-drawn app controls. Reason: their fine design depends on CC runtime
behaviour (coroutine resume order under `parallel`, highlight redraw) best
confirmed once desktop nav is live.
