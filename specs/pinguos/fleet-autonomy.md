# PinguOS — Autonomous turtle fleet

- **Status:** Building
- **Date:** 2026-06-29
- **Supersedes the manual-control layer of** `fleet.md` (the base protocol stays).

## Goal

Turtles stop being remote-controlled one step at a time. You **delegate a job**
("branch-mine 24 blocks", "fell these trees", "farm this field") and the turtle
runs it on its own — navigating, sensing with `inspect`/`detect`, auto-refueling,
handling obstacles, reporting progress — until it finishes or gets blocked.

## The core decision: intelligence lives on the turtle

The old agent was a slave: receive `forward`, take one step, reply. Every step was
a rednet round-trip — slow, and dead if the turtle drifts out of modem range.

Now the computer sends ONE `job` message; the turtle owns the loop. The computer
only dispatches and listens for progress. This is what "medianamente inteligente"
means: the turtle reacts to its local world instantly, with no radio in the loop.

## Architecture

### Turtle firmware as real modules (not a JS string)

The agent used to be one giant template literal inside `bridge/install.js` —
untestable, not even `luac -p`-checkable. It is now real Lua under `turtle/`:

```
turtle/
  agent.lua            -- boot: detect role, load jobs, main loop
  lib/
    roles.lua          -- tool-name -> role (PURE, unit-tested)
    nav.lua            -- GPS navigation math (PURE, unit-tested)
    api.lua            -- the helper handed to each job (wraps turtle.*)
  jobs/
    branch-mine.lua    -- each returns { id, label, roles, params, run }
    dig-down.lua
    fell-tree.lua
    tree-farm.lua
    crop-loop.lua
    goto.lua
  tests/               -- pure-logic tests (roles, nav), run on local Lua 5.4
```

A turtle installs them with a **mini-installer** that reuses the proven OS install
flow (`buildManifest` + `safeFsPath`): `wget run .../turtle` pulls a turtle-specific
manifest and writes each file under `/pingu/` on the turtle, then runs the agent.
Adding a job later = drop one `.lua` file in `turtle/jobs/`. That is the extensibility.

### Job registry pattern (mirrors the app registry)

Each job is a table:

```lua
return {
  id = "branch-mine", label = "Branch mine",
  roles = { mineria = true },                 -- which roles may run it
  params = { { name = "depth", label = "Largo", default = 24 } },
  run = function(api)  ...  return ok, info end,
}
```

The agent auto-discovers jobs (`fs.list("/pingu/jobs")` + `loadfile`), filters them
by the turtle's role, and sends that **catalog** to the computer so the Fleet app
builds its menu dynamically — no hardcoded per-role menus.

### Staying responsive mid-job (`parallel`)

A 5-minute mining job must still answer "cancel" and "status". The agent runs the
job and a listener concurrently with `parallel.waitForAny`:

- **worker** runs `job.run(api)`, storing the result.
- **listener** loops on `rednet.receive`; answers discover/status (so the turtle
  reads as *working*, not *lost*), and on `cancel` sets a shared flag and returns.

When either returns, `parallel` kills the other. The job polls `api.shouldCancel()`
between steps and exits cleanly.

### Role auto-detection

`getEquippedLeft()/getEquippedRight()` expose the equipped tool's detail. `roles.lua`
maps its name to a role (`pickaxe`→mineria, `axe`→tala, `sword`→ataque, `shovel`→
excavacion, `hoe`→granja). **Order matters: "pickaxe" contains "axe"** — pickaxe is
checked first. Falls back to a saved `/pingu-role` file, then a one-time prompt.

## Protocol (extends `pingufleet`)

Computer → turtle:
- `{t="discover"}` — find turtles (on open + every 2s).
- `{t="job", job=<id>, params={...}}` — delegate a job.
- `{t="cancel"}` — stop the running job.
- `{t="cmd", action=<a>, arg=<n>}` — single manual action (debug mode, kept).

Turtle → computer:
- `{t="hello", name, role, status, fuel, pos, job, catalog}` — on register/discover.
- `{t="status", name, role, status, fuel, pos, job}` — heartbeat / after an action.
- `{t="progress", name, job, pct, info, fuel, pos}` — emitted during a job.
- `{t="done", job|action, ok, info, name, fuel, pos}` — on finish.

`status` ∈ `idle | working | blocked | nofuel`. `pos` from `gps.locate` or nil.

## v1 job set

| Role | Jobs |
|---|---|
| **mineria** (pickaxe) | `branch-mine N` (tunnel + side branches), `dig-down N` |
| **tala** (axe) | `fell-tree` (chop up, climb down, replant), `tree-farm L` (patrol + fell + replant) |
| **granja** (hoe) | `crop-loop WxL` (harvest only ripe, replant, deposit) |
| **any** | `goto x y z` (GPS navigation), manual D-pad as a **debug** submenu |

## Fleet app: mission control

Live dashboard per turtle (role, current job, progress bar, fuel, inventory %).
Click a turtle → pick a role-appropriate job from *its own catalog* → simple param
prompts → dispatch. A **Cancel/Recall** button stops the running job. The old D-pad
survives as a "manual (debug)" submenu — useful for nudging a stuck turtle.

## Verification

- Pure libs (`roles`, `nav`) unit-tested on local Lua 5.4 (`turtle/tests/run.lua`).
- Everything CC-bound (`agent`, `api`, every job) is `luac -p` syntax-checked.
- Protocol builders covered in `dist/tests/test_fleet.lua`.
- Job run-loops (they call `turtle.*`) can only be tested **in-game** — shipped with
  a test script for the user.

## Out of scope (later)

Multi-turtle coordinated tasks, job queues per turtle, pathfinding around big
obstacles, persistent job resume across reboots, a blueprint/builder job.
