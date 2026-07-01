# PinguOS — JARVIS (agent core) — v2 (pivot)

- **Status:** Approved pivot (design agreed in chat 2026-07-01); mechanism verified from source.
- **Date:** 2026-07-01 (v2 supersedes the v1 "chat-only" premise)
- **Slug:** `jarvis-core`
- **Owner:** Juan
- **Depends on:** ClaudeCraft 1.2.2 (the embedded Claude Code brain), `fleet.lua`, the app/`ctx` model.

> Durable record per the SDD flow. If it isn't written here, it isn't agreed.

---

## 0. Revision note — why v2

v1 assumed **ClaudeCraft is chat-only**, so it planned to build the whole agent (tool
catalogue + tool-call loop + protocol) in Lua. **Task 0 (in-game smoke test) proved that
false.** ClaudeCraft in Channel mode embeds a **full Claude Code CLI** per computer, with
native MCP tools that already perceive and act on the world (`peripheral_call`,
`run_command`, `redstone`, `turtle_*`, file I/O on the CC FS, inter-computer `send_message`).
The v1 Lua loop reimplemented — worse — what the brain already does. v2 pivots: **JARVIS is a
body + knowledge + programs for that brain, not a home-grown loop.** (v1 code —
`protocol/agent/tools` — is removed; `claudecc`, the app, and `world.md` are repurposed.)

## 1. Summary & vision

**JARVIS** is the operating agent for Juan's base: talk in natural language, it perceives and
acts on the base (turtles, peripherals, Create, ME). The brain is the **ClaudeCraft-embedded
Claude Code agent** — it already has a tool loop and native world tools. JARVIS gives that
brain three things PinguOS-side:

1. **A body** — a `jarvis` app: a chat UI in the PinguOS desktop over `_G.claude`.
2. **Knowledge** — a `WORLD.md` describing Juan's base (the fleet, protocols, layout,
   conventions), delivered to the brain so it acts as *Juan's* operator, not generic Claude.
3. **Programs** — base-specific CLI tools the brain runs via `run_command` (Inc 0 ships one:
   `fleet_status`, reusing `fleet.lua`).

Inc 0 = the thin core that proves the round-trip and the "first miracle": ask about the fleet,
the brain runs `fleet_status`, and answers with real turtle states.

## 2. Goals / Non-goals

**Goals (Inc 0)**
- A `jarvis` app: NL in → brain reply out, over `_G.claude` (thin; the loop is the brain's).
- **`claudecc.lua`** — the ONLY file touching `_G.claude`: `available/open/send/close`.
  Reply is received via a CC event, matched **adaptively** (any `claude*` event).
- **`WORLD.md`** base knowledge, prepended to the brain on session start.
- **`fleet_status`** program (reuses `fleet.lua`) the brain runs to read the fleet.
- Clean degradation if `_G.claude` is absent (like any app needing a missing peripheral).

**Non-goals (Inc 0)**
- Rebuilding a Lua tool loop / `@tool` text protocol → **removed** (the brain has one).
- Custom Lua-serviced native tools via `sendToolResult` → later (a real option, not Inc 0).
- Persistent memory, self-extension, proactivity → later incs (and mostly *near-free* now:
  the brain has `write_file`/`run_command` on the CC FS).

## 3. Confirmed mechanism (verified from the channel server source, 2026-07-01)

Replaces v1's "TBD by smoke test" — this is now **known**:

- Each in-game computer runs its own **Claude Code brain**, bridged by a Bun MCP server
  (`~/.claudecraft/channel/claudecraft-channel.ts`, port 8789+, cwd
  `~/.claudecraft/computers/<id>/`).
- **One turn:** `_G.claude.sendMessage({userMessage=...})` → mod `POST /message` → brain (MCP
  notification) → brain calls native tools (the mod executes them in-game, returns results) →
  brain calls the **`reply`** tool → SSE `reply`→`done` → surfaced in-game as a CC event.
- **Brain native tools:** `peripheral_call` (any peripheral method — universal), `run_command`,
  read/write/edit/list/find/search_file (on the **CC virtual FS** — it can read/modify PinguOS
  itself), `redstone`, `get_info`, `send_message` (inter-computer), `reply`; turtles add
  `turtle_move/dig/place/inspect/inventory`.
- **`_G.claude` Lua API:** `startChannel(bool)->true`, `isChannelReady()`, `sendMessage(table)`
  (a TABLE, `{userMessage=...}`), `sendToolResult`, `cancelRequest`, `stopChannel`,
  `getModel()`(=`claude-sonnet-4-6`), `getPersonality()`(empty), `isApiKeyConfigured()`(false
  — Channel mode uses the CC subscription). The **reply event name** is the one detail pinned
  empirically on the first app run (claudecc matches `claude*` adaptively until then).

## 4. Architecture

```
  app jarvis  (chat UI: NL in, brain reply out)
      |  sendMessage({userMessage=...})           ^  reply (CC event, adaptive match)
      v                                            |
  claudecc  (the ONLY file that knows _G.claude: available/open/send/close)
      |
      v
  ClaudeCraft brain  (Claude Code + native world tools + its own loop)
      |  run_command / peripheral_call
      v
  the base (turtles via fleet_status, peripherals, ...)

  /data/jarvis/world.md : base knowledge, prepended to the brain on session start
  fleet_status (program): headless CLI the brain runs to read the fleet (reuses fleet.lua)
```

The agent loop is **the brain's**; claudecc just sends the message and returns the reply.

## 5. Components

- **`dist/os/jarvis/claudecc.lua`** (rewrite, CC-bound, isolates the mod dep):
  `available()`; `open()` → session (starts the channel, waits ready); `send(session, text)` →
  reply text (posts `{userMessage=text}`, waits for the `claude*` reply event, returns text);
  `close(session)`.
- **`dist/os/apps/jarvis.lua`** (rewrite): thin chat UI (reuses the `claude.lua` pattern).
  Prepends `world.md` to the first message of a session. Shows the reply. On the first reply,
  prints the raw event name once (pins it; then we hardcode/keep adaptive).
- **`dist/data/jarvis/world.md`** (expand): who JARVIS is + base facts (the `pingufleet`
  rednet protocol, how to check the fleet via `fleet_status`, PinguOS layout, ASCII-only, be
  concise — the brain already knows CC:Tweaked).
- **`dist/os/jarvis/fleet_status.lua`** (new): a headless CLI that discovers the fleet
  (reuses `fleet.discover()` / `fleet.PROTOCOL`) and prints one line per turtle. The brain runs
  it with `run_command`. (This is where v1's `tools.lua` fleet logic is repurposed.)
- **Removed:** `dist/os/jarvis/{protocol,agent,tools}.lua`,
  `dist/tests/test_jarvis_protocol.lua`, and its line in `run.lua` (redundant with the brain).

## 6. Increments (revised roadmap; this spec = Inc 0)

| Inc | Name | Adds (note: most capability is now native + knowledge, not hand-built Lua) |
|---|---|---|
| **0** | **Núcleo** (this spec) | chat app + claudecc + WORLD.md + `fleet_status` program |
| 1 | Sentidos | teach the brain (via WORLD.md/programs) to use `peripheral_call`/`scan` on your base |
| 2 | Manos | action recipes + safety conventions (the brain has `turtle_*`/`redstone` already) |
| 3 | Memoria | the brain persists base facts to the CC FS (`write_file`) — near-free |
| 4 | Auto-extensión | the brain writes & installs new PinguOS programs (`write_file`+`run_command`) |
| 5 | Proactivo | event-driven triggers that call `sendMessage` on their own |

## 7. Verification

- **`claudecc` + app + `fleet_status`:** `luac -p`-checked; validated in-game by the owner.
- **`fleet_status`** discovery logic can be smoke-run locally where pure (rednet is CC-bound).
- **First miracle (revised):** in-game, open **JARVIS**, type *"¿cómo va la flota?"* → the
  brain runs `fleet_status` (or `peripheral_call`) → answers in NL with the real turtle
  count/states; with none, says the fleet is empty (never invents).
- No pure unit suite for JARVIS anymore (v1's `protocol.lua` removed). The 90-test PinguOS
  suite must still pass after removing the `test_jarvis_protocol` line.

## 8. Confirmed decisions

1. **Brain = ClaudeCraft native** — CONFIRMED to be a full Claude Code agent with native world
   tools, not chat-only. The v1 premise was corrected empirically by Task 0 (its whole point).
2. **JARVIS = body + knowledge + programs**, not a Lua tool loop.
3. **`claudecc.lua` isolates `_G.claude`**; the reply event is matched adaptively, pinned on
   first run.
4. **Fleet is the first capability**, delivered as a CLI program the brain runs (reuses
   `fleet.lua`), read-only ⇒ safe first slice.
5. **`sendToolResult` (custom Lua tools the brain calls natively)** is a noted future upgrade,
   out of Inc 0 scope.
