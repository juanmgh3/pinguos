# PinguOS — Keyboard Control (HD station)

- **Status:** Draft for review
- **Date:** 2026-06-30
- **Slug:** `keyboard-control`
- **Owner:** Juan
- **Depends on:** `hd-command-center.md` (HD surface) and the in-kernel
  `tm_keyboard` detection already landed (`setFireNativeEvents(true)` in `kernel.run`).
- **Verified API:** `toms-peripherals-reference.md` §Keyboard (read before coding).

> Durable record for this feature, per the SDD flow. If it isn't written here,
> it isn't agreed.

---

## 1. Summary & vision

On the HD station, Tom's physical keyboard is the way you type — but its capture
GUI **grabs the mouse** (`grabMouse()`), so while you type you **cannot click**.
Today every PinguOS control is click/touch only (`ui.hit` over `mouse_click`).
This feature makes the **whole OS keyboard-operable**: move a focus highlight with
the arrows/Tab, activate with Enter, go back/quit with dedicated keys — on the
desktop and in **every app, existing and future, without rewriting the apps**.

Guiding principle (the project's recurring leverage move): like the HD render
backend gave every app HD "for free" and `setFireNativeEvents(true)` gave physical
typing "for free", keyboard navigation should be **earned once in the shared layer**
(`ui.lua` + a focus manager) and inherited by every app that draws with the toolkit.

## 2. Goals / Non-goals

**Goals**
- Keyboard navigation + activation of **every control that today responds to a
  click**, on the desktop and in apps.
- A **focus model**: the active control is highlighted; **arrows/Tab** move focus,
  **Enter** activates (= synthesised click).
- **Back / Quit** on dedicated keys that never collide with typing: **Ctrl+B** /
  **Ctrl+Q**.
- **Free for new apps:** the focusable registry lives in `ui.lua`; using the
  toolkit helpers is enough — apps declare nothing.
- **Graceful degradation:** on the pocket (no `tm_keyboard`) or with a mouse/touch,
  everything works exactly as today. The native click path is never broken.

**Non-goals**
- **Multi-line paste (Ctrl+V).** Not possible with Tom's keyboard — see §3. The
  long-text path (e.g. the Claude chat) stays on the bridge. Documented so it is
  not re-attempted.
- Rewriting any app's UX beyond migrating hand-drawn controls to a registering
  helper.
- A free-moving "virtual cursor" (considered and rejected in favour of focus).
- Mouse/touch removal — touch (`tm_monitor_touch`) stays as a parallel input.

## 3. Environment & constraints (verified in-game, 2026-06-30)

| Fact | Consequence |
|---|---|
| **Esc closes Tom's capture GUI** (standard MC screen close); it does not reach the OS. | Esc is unusable as an in-OS key. Back/Quit must be other keys. |
| **Tab (258)** is explicitly forwarded by Tom's GUI; **arrows (262–265)**, **Enter (257)**, **Backspace (259)** all arrive as native `key` events. | Navigation keys are viable. Verified via `kb_smoke.lua`. |
| **Ctrl combos arrive clean:** holding Ctrl gives `key 341` (repeating `held=true`), then `key <letter>` with **no `char`**. | `Ctrl+B` / `Ctrl+Q` are usable as actions that never type text. Detect "Ctrl held" = a `341` with no matching `key_up` yet. |
| **CraftOS reserves `Ctrl+T` (terminate), `Ctrl+R` held (reboot), `Ctrl+S` (shutdown).** | Never bind those — they'd kill the computer. Use B/Q/etc. |
| **Multi-line paste is stripped in the mod's client** (`KeyboardWidget.java`): `clipboard.substring(0, min(idx("\r"), idx("\n")))` + `StringUtil.filterText` + 512-char cap, **before** it is sent to the computer. | The multi-line text never reaches the OS. Multi-line paste is impossible here (§2 non-goal). |
| `read()` (native CC line input) already works with the physical keyboard. | Single-line text entry is already solved; this feature is about **navigation/activation**, not text entry. |

## 4. Key map (CLOSED — validated in-game)

| Key | Action |
|---|---|
| **Arrows** | move focus (spatially; on the desktop, across the icon grid) |
| **Tab / Shift+Tab** | next / previous control (registration order) |
| **Enter** | activate the focused control (= synthesised `mouse_click`) |
| **Ctrl+B** | back one level (cancel sub-screen; at an app's root, behaves like Quit) |
| **Ctrl+Q** | quit the app to the desktop |
| *(Backspace, letters, …)* | reserved for typing into text fields |

## 5. Architecture (focus manager as a sibling of `hdDaemon`)

```
  APPS  (unchanged: draw widgets -> ui.hit over mouse_click)
    |  draw                                   ^ mouse_click (synthesised)
    v                                          |
  ui.lua  --- per-frame focusable registry ----+
    |  (button / titleBar / iconTile / new list helper self-register)
    v
  focus manager  (parallel task, HD only; sibling of hdDaemon)
    - tracks Ctrl-held + focus index over the current frame's focusables
    - arrows/Tab -> move focus + repaint highlight
    - Enter      -> os.queueEvent("mouse_click", 1, cx, cy) at focused control
    - Ctrl+Q     -> close app  (synthesised click on the titleBar [x])
    - Ctrl+B     -> back        (cancel current level; root -> quit)
```

- **Why this shape:** the `hdDaemon` already runs in `parallel` and turns the
  monitor's `tm_monitor_touch` into a `mouse_click`. The focus manager is the same
  pattern for a different input — so apps stay click-driven and **need no changes**.
- **`ui.lua` registry:** a `ui._focusables` list, reset at frame start (when an app
  calls `ui.clear`/`ui.wallpaper`), to which `ui.button`, the `titleBar` close box,
  `ui.iconTile`, and a new `ui.listItem`/row helper append their region as they
  draw. Apps that already use these helpers get focus for free.
- **Synthesised click:** Enter computes the focused region's centre and queues a
  `mouse_click` — the app resolves it with its existing `ui.hit`. Zero new app code.
- **Highlight:** reuse `iconTile`'s existing `selected` strip for the desktop; for
  buttons/rows, a themed inverse/accent border drawn by `ui` after the app's frame.
- **Modal nav vs edit:** while a text field is active (`read`), printable keys +
  Backspace go to the text; arrows/Tab/Ctrl actions still apply. The `read`
  integration detail (cancelling a blocking `read` on Ctrl+B/Q) is resolved in the
  plan.
- **Degradation:** no `tm_keyboard` → no focus manager spawned; mouse/touch path
  untouched. One codebase.

## 6. Components

- **`ui.lua`** — add `ui._focusables` + a frame reset; make `button`/`titleBar`/
  `iconTile`/new row helper self-register; add `ui.focusHighlight(region)`.
- **`kernel.lua`** — spawn the focus manager under `parallel` alongside `hdDaemon`
  in HD mode; track Ctrl-held; reuse the existing event loop.
- **`focus.lua` (new, pure)** — focus ordering, spatial arrow navigation (nearest
  control in a direction), Ctrl-combo detection, focused-cell-centre math. CC-API
  free, unit-tested on local Lua 5.4 like `geo`/`nav`.

## 7. Increments

0. **Infra + desktop.** `ui.lua` registry + reset; focus manager scaffolding;
   desktop becomes keyboard-navigable (arrows move icon selection — the `selected`
   visual already exists — Enter opens). Ships green + in-game.
1. **Apps activatable.** Enter→synthesised click wired; migrate hand-drawn controls
   (e.g. Ajustes accent swatches) to a registering helper. Existing apps now usable
   by keyboard.
2. **Back / Quit.** Ctrl+B / Ctrl+Q wired (quit = synthesised click on `[x]`);
   polished focus highlight.
3. **Per-app polish** (roadmap, each its own slice).

## 8. Verification

- **Pure logic** (`focus.lua`: ordering, spatial nav, ctrl-combo detection, cell
  centre) unit-tested on local Lua 5.4 in `dist/tests/`, as with `geo`/`nav`.
- **CC-bound** (event injection, highlight drawing, kernel wiring) `luac -p`-checked
  and validated **in-game** by the owner via the Update app, per increment.
- `kb_smoke.lua` already validates which keys reach the OS; keep it for regressions.

## 9. Confirmed decisions

1. **Focus model**, not a virtual cursor (confirmed by owner).
2. **Key map** in §4 validated in-game (confirmed).
3. **Automatic registration in `ui.lua`** so apps inherit keyboard nav for free
   (confirmed — "cada app que hagamos").
4. **Multi-line paste is out of scope** — hard limit in Tom's client; long text
   goes through the bridge (confirmed by source read).
