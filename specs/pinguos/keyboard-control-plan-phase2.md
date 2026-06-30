# Keyboard Control — Implementation Plan (Phase 2: in-app)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every PinguOS **app** operable by keyboard on the HD station — move a
focus highlight over the app's controls with arrows/Tab, activate with Enter, and
quit with Ctrl+Q — without rewriting the apps.

**Architecture:** Earn it once in the shared layer. `ui.lua` keeps a per-frame
`_focusables` registry that `ui.button`, the new `ui.swatch`, and `ui.titleBar`'s
close box populate as they draw; the *focused* widget self-highlights by reading
`ui._focusIndex` (the "inverse" trick — robust because the highlight rides along
inside the app's own redraw, so it survives back-buffers and tick-coalesced
redraws). A `focusManager` parallel task (sibling of `hdDaemon`, gated on
`kernel.inApp`) owns navigation: arrows → `focus.spatial`, Tab → `focus.cycle`,
Enter → a synthesised `mouse_click` at the focused region's centre, Ctrl+Q → a
synthesised click on the stashed close box. Apps stay 100% click-driven; they
resolve the synthesised clicks with their existing `ui.hit`. Zero per-app code
beyond migrating Ajustes' hand-drawn swatches to the registering helper.

**Tech Stack:** Lua (CC: Tweaked 5.1 in-game, Lua 5.4 locally). Builds on Phase 1
(`focus.lua`, desktop nav) and the already-wired `tm_keyboard`
(`setFireNativeEvents(true)` + `kernel.kb` in `kernel.run`).

## Global Constraints

- **Lua must run on CC 5.1 AND local 5.4.** No `//`, no bit-ops; `math.floor`
  before any `string.format("%d", n)`.
- **Rendered text is ASCII only** — the CC terminal is 8-bit.
- **Test model:** pure logic is unit-tested on local Lua 5.4 via
  `"$LUA" dist/tests/run.lua`; CC-bound code is `luac -p`-checked and validated
  **in-game** by the owner via the Update app. `$LUA` =
  `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`, `$LUAC` = `luac.exe`
  beside it.
- **Key map (validated in-game, spec §4):** arrows = move focus, Tab = next
  control, Enter = activate, **Ctrl+Q = quit**. Ctrl arrives as `key`
  `keys.leftCtrl`(341)/`keys.rightCtrl`(345) then `key` `keys.q` with **no `char`**.
  Esc is reserved (closes the capture GUI); never bind `Ctrl+T/R/S`.
- **HD + keyboard only.** The focus manager is spawned only when `kernel.hd` AND
  `kernel.kb`. On the pocket / non-HD / no-keyboard, nothing changes — the mouse/
  touch path and the visuals must be byte-for-byte as today (no stray highlight).
- **Apps depend ONLY on `ctx`.** No app may reference the kernel or the registry
  directly; the registry lives inside `ui` and is populated by `ui` helpers.

## Scope (this plan = spec §7 increment 1 + the Ctrl+Q exit from increment 2)

In: registry + self-highlight, focus manager (arrows/Tab/Enter), Ctrl+Q quit,
migrate Ajustes swatches. **Out** (deferred to a Phase 3 plan): Ctrl+B "back" (no
uniform per-app back semantics yet), Shift+Tab, polished highlight styling, and
per-app polish. Ctrl+Q is pulled forward because without a keyboard exit the
capture GUI (which grabs the mouse) traps the user inside an app.

---

### Task 1: `focus.cycle` — Tab-order wrap-around (pure)

**Files:**
- Modify: `dist/os/focus.lua` (add `focus.cycle`)
- Modify: `dist/tests/test_focus.lua` (add cases)

**Interfaces:**
- Consumes: nothing (pure).
- Produces: `focus.cycle(n, current, step) -> index` — given `n` focusables, the
  1-based `current` index, and `step` (`+1` next / `-1` prev), return the new
  1-based index, wrapping at the ends. `n == 0` → `0`; `current` out of `[1,n]` → `1`.

- [ ] **Step 1: Write the failing tests**

Append to `dist/tests/test_focus.lua`:

```lua
-- cycle: Tab-order wrap-around
T.eq(focus.cycle(3, 1, 1),  2, "cycle next 1 -> 2")
T.eq(focus.cycle(3, 3, 1),  1, "cycle next wraps 3 -> 1")
T.eq(focus.cycle(3, 1, -1), 3, "cycle prev wraps 1 -> 3")
T.eq(focus.cycle(3, 2, -1), 1, "cycle prev 2 -> 1")
T.eq(focus.cycle(0, 1, 1),  0, "cycle empty -> 0")
T.eq(focus.cycle(3, 9, 1),  1, "cycle bad index -> first")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `"$LUA" dist/tests/run.lua`
Expected: FAIL — `attempt to call a nil value (field 'cycle')` (or 6 failures).

- [ ] **Step 3: Implement `focus.cycle`**

Add to `dist/os/focus.lua`, before the final `return focus`:

```lua
-- Wrap-around Tab order. n focusables, 1-based current, step +1 (next) / -1 (prev).
-- n==0 -> 0; current out of [1,n] -> 1.
function focus.cycle(n, current, step)
  if n == 0 then return 0 end
  if current < 1 or current > n then return 1 end
  local i = current + step
  if i > n then i = 1 end
  if i < 1 then i = n end
  return i
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 90 passed, 0 failed` (84 prior + 6 new).

- [ ] **Step 5: Commit**

```bash
git add dist/os/focus.lua dist/tests/test_focus.lua
git commit -m "feat(focus): add cycle() for Tab-order wrap-around"
```

---

### Task 2: `ui.lua` — focusable registry + self-highlight + `ui.swatch`

**Files:**
- Modify: `dist/os/ui.lua`

**Interfaces:**
- Consumes: `focus.cycle`/`focus.spatial` are not used here (the manager uses them);
  this task only exposes state the manager reads.
- Produces (new `ui` fields/functions, read by `kernel.lua` Task 3 and apps Task 4):
  - `ui._focusables` — array of `{x,y,w,h}` regions, in draw order, rebuilt each
    frame (reset by `ui.clear`).
  - `ui._focusIndex` — 1-based index of the focused region (the manager mutates it).
  - `ui._closeRegion` — the current frame's titleBar close box `{x,y,w,h}` or `nil`
    (the manager synthesises Ctrl+Q clicks here). NOT added to `_focusables`.
  - `ui.focusEnabled` — boolean; when false, no widget renders a highlight (so
    non-HD / no-keyboard looks exactly as today). Set true by the kernel only when
    spawning the focus manager.
  - `ui.swatch(x, y, w, label, color) -> {x,y,w,h}` — a labelled colour swatch that
    draws, registers as focusable, and self-highlights. Returns its region.
  - Behaviour change: `ui.button` and the `ui.titleBar` close box now register;
    `ui.button` self-highlights when focused.

- [ ] **Step 1: Add registry state at the top of the module**

In `dist/os/ui.lua`, immediately after `local ui = {}` (line ~3), insert:

```lua
-- Keyboard-focus registry (Phase 2). Rebuilt each frame by ui.clear; populated by
-- the focusable helpers below. The focus manager (kernel) reads these; nothing here
-- depends on CC keyboard APIs, so non-HD just leaves focusEnabled = false.
ui._focusables = {}
ui._focusIndex = 1
ui._closeRegion = nil
ui.focusEnabled = false
```

- [ ] **Step 2: Reset the registry at frame start in `ui.clear`**

In `ui.clear` (currently lines ~21-25), add the two resets so each frame starts
clean:

```lua
function ui.clear(bg)
  ui._focusables = {}
  ui._closeRegion = nil
  term.setBackgroundColor(safe(bg or ui.theme.bg))
  term.setTextColor(safe(ui.theme.fg))
  term.clear(); term.setCursorPos(1, 1)
end
```

- [ ] **Step 3: Make `ui.button` register + self-highlight**

Replace `ui.button` (currently lines ~45-49) with:

```lua
function ui.button(x, y, label)
  local s = " " .. label .. " "
  ui._focusables[#ui._focusables + 1] = { x = x, y = y, w = #s, h = 1 }
  local fg, bg = ui.theme.barFg, ui.theme.accent
  if ui.focusEnabled and #ui._focusables == ui._focusIndex then
    fg, bg = ui.theme.accent, ui.theme.barFg   -- inverse = focus highlight
  end
  ui.text(x, y, s, fg, bg)
  return { x = x, y = y, w = #s, h = 1 }
end
```

- [ ] **Step 4: Stash the close box in `ui.titleBar` (do NOT register it for nav)**

Replace the close-box lines at the end of `ui.titleBar` (currently lines ~60-62)
with:

```lua
  local close = " x "
  ui.text(w - #close + 1, 1, close, ui.theme.barFg, ui.theme.error)
  ui._closeRegion = { x = w - #close + 1, y = 1, w = #close, h = 1 }
  return { x = w - #close + 1, y = 1, w = #close, h = 1 }
```

Rationale: keeping `[x]` out of `_focusables` avoids the footgun of opening an app
with the close box focused (Enter would quit immediately). Keyboard close is Ctrl+Q,
which uses `ui._closeRegion`.

- [ ] **Step 5: Add `ui.swatch`**

Add after `ui.button` (so it sits with the other widgets):

```lua
-- A labelled colour swatch (e.g. the Ajustes accent picker): w cells of `color`
-- with " label" over it. Registers as focusable; when focused, prefixes ">" and
-- writes the label in white so the colour stays visible.
function ui.swatch(x, y, w, label, color)
  ui._focusables[#ui._focusables + 1] = { x = x, y = y, w = w, h = 1 }
  local focused = ui.focusEnabled and (#ui._focusables == ui._focusIndex)
  ui.fill(x, y, w, 1, color)
  ui.text(x, y, (focused and ">" or " ") .. label,
          focused and colors.white or colors.black, color)
  return { x = x, y = y, w = w, h = 1 }
end
```

- [ ] **Step 6: Syntax-check**

Run: `"$LUAC" -p dist/os/ui.lua`
Expected: no output (clean).

- [ ] **Step 7: Run the suite (must stay green — no pure logic changed)**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 90 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add dist/os/ui.lua
git commit -m "feat(ui): per-frame focusable registry, self-highlight, swatch helper"
```

---

### Task 3: `kernel.lua` — focus manager + `inApp` gating + parallel wiring

**Files:**
- Modify: `dist/os/kernel.lua`

**Interfaces:**
- Consumes: `focus.spatial`, `focus.cycle`, `focus.center` (from `focus.lua`);
  `ui._focusables`, `ui._focusIndex`, `ui._closeRegion`, `ui.focusEnabled`
  (from Task 2); `kernel.hd`, `kernel.kb` (already set in `kernel.run`).
- Produces: `kernel.inApp` (boolean, true while an app's `run` executes);
  `ui.focusEnabled` set true when the manager is spawned; the running focus manager.

- [ ] **Step 1: Track `inApp` and reset focus on app entry in `runApp`**

In `runApp` (currently lines ~59-75), wrap the `pcall` so focus state is set up on
entry and cleared on exit even if the app crashes. Replace:

```lua
local function runApp(app)
  sound.click()
  ui.clear()
  local ok, err = pcall(app.run, makeCtx(app))
```

with:

```lua
local function runApp(app)
  sound.click()
  ui.clear()
  ui._focusIndex = 1
  kernel.inApp = true
  local ok, err = pcall(app.run, makeCtx(app))
  kernel.inApp = false
```

(The existing `if not ok then ... end` block and the close of the function stay as
they are — `kernel.inApp` is already false before the crash screen's
`os.pullEvent("key")`, so the manager ignores keys on the error screen.)

- [ ] **Step 2: Add the focus manager, next to `hdDaemon`**

Add this function immediately after `hdDaemon` (after its `end`, ~line 201):

```lua
-- Focus manager: sibling of hdDaemon. Only acts inside an app (kernel.inApp); the
-- desktop drives its own focus (Phase 1). Mutates ui._focusIndex and synthesises
-- mouse_clicks the apps resolve with their existing ui.hit -- so apps need no code.
local function focusManager()
  local ctrlHeld = false
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "key" then
      local k = ev[2]
      if k == keys.leftCtrl or k == keys.rightCtrl then
        ctrlHeld = true
      elseif kernel.inApp then
        local foc = ui._focusables
        if ctrlHeld and k == keys.q then
          if ui._closeRegion then
            local cx, cy = focus.center(ui._closeRegion)
            os.queueEvent("mouse_click", 1, cx, cy)
          end
        elseif #foc > 0 then
          if ui._focusIndex < 1 then ui._focusIndex = 1 end
          if ui._focusIndex > #foc then ui._focusIndex = #foc end
          if k == keys.tab then
            ui._focusIndex = focus.cycle(#foc, ui._focusIndex, 1)
          elseif k == keys.up or k == keys.down or k == keys.left or k == keys.right then
            local dir = (k == keys.up and "up") or (k == keys.down and "down")
                     or (k == keys.left and "left") or "right"
            ui._focusIndex = focus.spatial(foc, ui._focusIndex, dir)
          elseif k == keys.enter then
            local r = foc[ui._focusIndex]
            if r then
              local cx, cy = focus.center(r)
              os.queueEvent("mouse_click", 1, cx, cy)
            end
          end
        end
      end
    elseif name == "key_up" then
      local k = ev[2]
      if k == keys.leftCtrl or k == keys.rightCtrl then ctrlHeld = false end
    end
  end
end
```

- [ ] **Step 3: Spawn the manager (HD + keyboard only) in `kernel.run`**

Replace the parallel block at the end of `kernel.run` (currently lines ~228-232):

```lua
  if kernel.hd then
    parallel.waitForAny(main, hdDaemon)
  else
    main()
  end
```

with:

```lua
  if kernel.hd and kernel.kb then
    ui.focusEnabled = true   -- widgets may now show a focus highlight
    parallel.waitForAny(focusManager, main, hdDaemon)
  elseif kernel.hd then
    parallel.waitForAny(main, hdDaemon)
  else
    main()
  end
```

`focusManager` is listed first so it updates `ui._focusIndex` before `main` (the
app) redraws on the same key event — the highlight then rides along inside that
redraw.

- [ ] **Step 4: Syntax-check**

Run: `"$LUAC" -p dist/os/kernel.lua`
Expected: no output (clean).

- [ ] **Step 5: Run the suite (kernel isn't unit-tested; suite must stay green)**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 90 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add dist/os/kernel.lua
git commit -m "feat(kernel): in-app focus manager (arrows/Tab/Enter/Ctrl+Q)"
```

---

### Task 4: Migrate Ajustes' hand-drawn swatches to `ui.swatch`

**Files:**
- Modify: `dist/os/apps/settings.lua`

**Interfaces:**
- Consumes: `ui.swatch` (Task 2). The wallpaper buttons (`ui.button`) and `editBtn`
  (`ui.button`) already auto-register; the close box is handled by Ctrl+Q.
- Produces: nothing new — `abtns[i]` regions keep the same shape, so the existing
  `ui.hit` handling below is unchanged.

- [ ] **Step 1: Replace the hand-drawn accent loop**

In `dist/os/apps/settings.lua`, replace the accent block (currently lines ~15-21):

```lua
      ui.text(2, 3, "Color de acento:", colors.white, colors.black)
      local abtns = {}
      for i = 1, #accents do
        local x = 2 + (i - 1) * 9
        ui.fill(x, 4, 8, 1, accents[i])
        ui.text(x, 4, " " .. anames[i], colors.black, accents[i])
        abtns[i] = { x = x, y = 4, w = 8, h = 1 }
      end
```

with:

```lua
      ui.text(2, 3, "Color de acento:", colors.white, colors.black)
      local abtns = {}
      for i = 1, #accents do
        local x = 2 + (i - 1) * 9
        abtns[i] = ui.swatch(x, 4, 8, anames[i], accents[i])
      end
```

- [ ] **Step 2: Syntax-check**

Run: `"$LUAC" -p dist/os/apps/settings.lua`
Expected: no output (clean).

- [ ] **Step 3: Run the suite (sanity)**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 90 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add dist/os/apps/settings.lua
git commit -m "refactor(settings): accent swatches via ui.swatch (keyboard-focusable)"
```

---

### Task 5: In-game validation (owner, via the Update app)

**This task has no code — it is the phase boundary. Stop and hand off to the owner.**

- [ ] **Step 1: Confirm the bridge is serving the new `dist/`**

The bridge must be running (`DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`)
so the in-game **Update** app pulls these commits.

- [ ] **Step 2: Owner runs Update in-game, then validates the checklist**

On the HD station with Tom's keyboard, open **Ajustes** and verify:

- A focus highlight is visible on the first control when the app opens.
- **Arrows** move the highlight spatially across accent swatches → wallpaper
  buttons → "Editar URL".
- **Tab** cycles through the controls in order (wrapping at the end).
- **Enter** on an accent swatch changes the accent; **Enter** on a wallpaper button
  sets the wallpaper; **Enter** on "Editar URL" opens the `read()` field (type +
  Enter saves).
- **Ctrl+Q** returns to the desktop (no need to touch the mouse).
- Desktop nav (Phase 1) still works unchanged.
- Sanity on a second app (e.g. **Acerca de**): Ctrl+Q exits it.

- [ ] **Step 3: On green, finish the branch**

Announce and use **superpowers:finishing-a-development-branch**. Known follow-ups
for a future Phase 3 plan (not blockers): Ctrl+B back, Shift+Tab, highlight polish,
and per-app focus latency on tick-redraw apps like `fleet` (highlight follows
within ~0.4s there — acceptable, documented).

---

## Self-Review

**Spec coverage (keyboard-control.md):** §4 key map → arrows/Tab/Enter (Task 3) +
Ctrl+Q (Task 3); Shift+Tab and Ctrl+B explicitly deferred (Scope section). §5
architecture → registry in `ui.lua` (Task 2), focus manager sibling of `hdDaemon`
(Task 3), synthesised click (Task 3), self-highlight reusing the inverse trick
(Task 2). §6 components → `ui.lua` (Task 2), `kernel.lua` (Task 3),
`focus.lua` pure additions (Task 1). §7 increment 1 + the increment-2 exit (Scope).
Degradation (§2/§5) → `ui.focusEnabled` + HD&&kb spawn gate (Tasks 2-3).

**Placeholder scan:** none — every code step shows full code; the only no-code task
(Task 5) is the deliberate in-game gate.

**Type consistency:** `_focusables` entries are `{x,y,w,h}` everywhere (Task 2
populates, Task 3 reads via `focus.center`/`focus.spatial`, which already take
`{x,y,w,h}` from Phase 1). `focus.cycle(n,current,step)` signature is identical in
Task 1's definition and Task 3's call. `ui.swatch(x,y,w,label,color)` signature
matches between Task 2 (def) and Task 4 (call). `kernel.inApp` set in Task 3 Step 1,
read in Task 3 Step 2. `ui.focusEnabled` set in Task 3 Step 3, read in Task 2.

**Decision flagged for owner OK:** pulling Ctrl+Q into this plan (spec had it in
increment 2) and deferring Ctrl+B/Shift+Tab — because the capture GUI grabs the
mouse, so a keyboard exit is required for the increment to be testable at all.
