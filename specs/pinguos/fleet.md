# PinguOS — Turtle fleet base

- **Status:** Built (base/foundation)
- **Date:** 2026-06-29

Foundation for turtle ("robotsito") automation: turtles connect to the computer
over rednet and obey commands. Specific automations (mining, farming) are built
ON TOP of this later, as composed commands.

## Pieces

- `dist/os/fleet.lua` — rednet protocol (pure, tested). Protocol id `pingufleet`.
  Message builders: `discover`, `hello`, `status`, `cmd`, `done`; `fleet.is(msg,t)`;
  `fleet.ACTIONS` + `fleet.isAction`. Exposed to apps as `ctx.fleet`.
- `dist/os/apps/fleet.lua` — the command center (runs on the computer). Opens
  rednet, broadcasts `discover`, lists connected turtles (id, name, fuel), select
  with arrows, ENTER opens a command menu (forward/back/up/down/turn/dig/refuel).
- **Turtle agent** — served by the bridge at `GET /turtle`. On a turtle:
  `wget run http://127.0.0.1:8080/turtle`. Opens rednet, registers (`hello`),
  writes a startup that reconnects on boot, then loops obeying `cmd` messages via
  the `turtle` API and replying `done`. Heartbeats `status` when idle.

## Protocol flow

1. Computer broadcasts `{t="discover"}` (on open + every 2s).
2. Turtles reply `{t="hello", name, fuel, pos}`; the app registers them.
3. Computer sends `{t="cmd", action}` to a turtle id; turtle runs it and replies
   `{t="done", action, ok, fuel, pos}`.

## Requirements

Turtles + wireless/ender modems; the computer needs a modem too. `pos` comes from
`gps.locate` (needs the constellation) — optional; turtles report without it.

## Out of scope (build on top later)

Mining routines, farm loops, multi-turtle tasks/queues, pathing. These become
"composed commands" sent through this same protocol.
