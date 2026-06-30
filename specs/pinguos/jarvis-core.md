# PinguOS — JARVIS (agent core)

- **Status:** Approved (design agreed in chat 2026-07-01)
- **Date:** 2026-07-01
- **Slug:** `jarvis-core`
- **Owner:** Juan
- **Depends on:** ClaudeCraft 1.2.2 (`_G.claude`), `fleet.lua`, the app/`ctx` model.
- **Verified API:** **TBD by smoke test (Plan Task 0).** ClaudeCraft's exact Lua API
  is not published; the smoke test is the source of truth, and the dependency is
  isolated in one wrapper file so a different API touches only that file.

> Durable record per the SDD flow. If it isn't written here, it isn't agreed.

---

## 1. Summary & vision

**JARVIS** is an operating agent for your world: you talk to it in natural language
and it **perceives and acts** on the base (turtles, peripherals, Create, ME) through
**tools**. The brain is **ClaudeCraft native** (in-game chat, text↔text, no lag — the
owner verified it beats the Node bridge). Because ClaudeCraft gives only *chat*, the
**agent scaffolding** — a `CLAUDE.md`-style system prompt, a tool catalogue, a
tool-call loop, and memory — is built by PinguOS in Lua. We are **replicating the
machinery that makes Claude Code powerful**, but the tools touch your world instead
of your disk.

This spec covers **Increment 0: the agent core** — the skeleton that proves the
home-grown tool loop is *reliable*, wired to a single real tool (`fleet_status`).
Everything else (more tools, memory, self-extension, proactivity) builds on this.

## 2. Goals / Non-goals

**Goals (Inc 0)**
- A multi-turn **agent loop** over ClaudeCraft: `NL → (tool-call)* → final answer`.
- An extensible **tool catalogue** (`{ name, description, params, run }`),
  auto-registered (the project's "earn it once" pattern).
- One real tool: **`fleet_status`** — reads the turtle fleet state (rednet, reuses
  `fleet.lua`).
- A **`WORLD.md`** base system prompt loaded from `/data/jarvis/`.
- A **`jarvis` app** with a chat UI (reuses the `claude.lua` app pattern).
- The **tool-call protocol parser** unit-tested on local Lua 5.4.

**Non-goals (Inc 0 — each is a later increment)**
- More perception/action tools → Inc 1 (Sentidos) / Inc 2 (Manos).
- Accumulated persistent memory → Inc 3.
- JARVIS writing new programs → Inc 4.
- Proactive/event-driven behaviour → Inc 5.
- Safety confirmations for destructive actions → Inc 2 (Inc 0 only **reads**, so it
  is safe by construction).

## 3. Environment & constraints

| Fact | Consequence |
|---|---|
| ClaudeCraft 1.2.2 brings Claude into CC; connection modes **API key / Channel**; advertised features **streaming + tool use**; in-game `/claudecraft setkey`, `/claudecraft model`. | The brain exists and the owner has it working. We drive it from Lua. |
| **The exact Lua API is undocumented.** The project's `hd-command-center.md` observed `startChannel`→`sendMessage`→ events `claude_text`/`claude_done`. | **Plan Task 0 (in-game smoke test) is the source of truth.** Treat the above as a *reference* to confirm/correct, exactly like `kb_smoke.lua` did for the keyboard. |
| **Open question (Task 0 resolves):** does ClaudeCraft expose **native tool-use** to Lua (register Lua tools Claude can call), or only chat? | If native → prefer it (more reliable). If chat-only → the text protocol in §4 (this spec's assumption). The design works on chat-only and treats native tools as a future upgrade. |
| **Globals are not visible inside `loadfile`-loaded apps** (the kernel gotcha: `require`/`gps`/… ). | Task 0 must confirm `_G.claude` is visible inside an app. If not, inject it via `ctx` (kernel) or stash in `_G` at boot — resolved in the plan. |
| Pure modules must run on **CC Lua 5.1 and local 5.4**; rendered text is **ASCII**; tools touch rednet/peripherals (CC-bound). | Only `protocol.lua` is unit-tested locally; the rest is `luac -p` + in-game. |
| Apps depend **only on `ctx`**. | The agent reaches `fleet`, `term`, `log` etc. through `ctx`; the ClaudeCraft global is the one exception, handled in Task 0. |

## 4. Architecture

```
  app jarvis  (chat UI: NL in, transcript + tool trace out)
      |  user message
      v
  agent.run(ctx, msg, emit)        <- the loop, bounded by a max-turns cap
      |                 ^
      |  send(text)     |  reply (text)
      v                 |
  claudecc  (wrapper over _G.claude: open(systemPrompt) / send / close)
      |
      v
  ClaudeCraft  (native Claude chat, in-game)

  protocol.lua (PURE): buildPrompt(worldmd, catalog), renderTools(catalog),
                       parseCall(text) -> toolcall | nil(final answer)
  tools.lua    (CC):   catalogue + fleet_status.run(args, ctx)
  /data/jarvis/world.md : the base system prompt (CLAUDE.md of your base)
```

**The loop (`agent.run`):**
1. `prompt = protocol.buildPrompt(worldMd, catalog)` — WORLD.md + rendered tool
   signatures + the strict protocol instructions.
2. `claudecc.open(prompt)` — start the channel seeded with the system prompt.
3. `claudecc.send(userMsg)` → `reply`.
4. `call = protocol.parseCall(reply)`:
   - **tool-call** → `result = catalog[call.name].run(call.args, ctx)`;
     `reply = claudecc.send("@result " .. json(result))`; **go to 4**.
   - **nil** (no `@tool` line) → `reply` is the **final answer**; show it; **done**.
5. A **max-turns cap** (e.g. 6) prevents infinite tool loops; on overflow, return
   what we have with a note.

**Tool-call protocol (text, robust to a chat model):**
- To call a tool, JARVIS replies with **exactly one line, no prose**:
  `@tool <name> <json-args>`  (e.g. `@tool fleet_status {}`).
- We feed the result back as: `@result <json>`.
- A **final answer** is any reply with no `@tool` line — plain natural language.
- The system prompt states this strictly and lists every tool with its params.
  (Chosen over "JSON embedded in prose" because a single sentinel line is far
  easier to parse reliably in Lua and to instruct a chat model to emit.)

**Degradation:** if `_G.claude` is absent, the `jarvis` app shows "ClaudeCraft no
detectado" and exits cleanly — like any app that needs a missing peripheral.

## 5. Components (interfaces the plan builds to)

- **`dist/os/jarvis/protocol.lua`** (PURE):
  - `protocol.parseCall(text) -> { name=string, argsRaw=string } | nil` — returns
    the tool-call on the first line matching `^@tool%s+(%S+)%s*(.*)$` (trimmed), or
    `nil` when there is no such line (⇒ final answer). JSON of `argsRaw` is decoded
    by the caller (CC `textutils`), not here, so this stays pure.
  - `protocol.renderTools(catalog) -> string` — a deterministic, ASCII list of
    `name(params) — description` lines.
  - `protocol.buildPrompt(worldMd, catalog) -> string` — WORLD.md + tool list +
    the fixed protocol instructions.
- **`dist/os/jarvis/claudecc.lua`** (CC-bound, the ONLY file that knows the mod API):
  - `claudecc.available() -> bool`
  - `claudecc.open(systemPrompt) -> session` ; `session.send(text) -> replyText` ;
    `session.close()`. Internally wraps whatever Task 0 confirms.
- **`dist/os/jarvis/tools.lua`** (CC-bound): returns `{ list = {...}, byName = {...} }`;
  each tool `{ name, description, params, run = function(args, ctx) -> table }`.
  Inc 0 ships exactly one: `fleet_status`.
- **`dist/os/jarvis/agent.lua`** (CC-bound): `agent.run(ctx, userMsg, emit)` where
  `emit(kind, text)` feeds the UI (`kind` ∈ `"tool"|"result"|"answer"|"error"`).
- **`dist/os/apps/jarvis.lua`**: the chat app; builds `emit` from its window and
  calls `agent.run`.
- **`dist/data/jarvis/world.md`**: the base system prompt (who JARVIS is, the
  protocol reminder, base facts).

## 6. Increments (global JARVIS roadmap; this spec = Inc 0)

| Inc | Name | Adds |
|---|---|---|
| **0** | **Núcleo** (this spec) | agent loop + protocol + `fleet_status` + app + WORLD.md |
| 1 | Sentidos | read tools: geo `scan`, environment, ME stock |
| 2 | Manos | action tools (turtle orders, redstone, ME craft) + safety confirm |
| 3 | Memoria | persistent world facts + JARVIS edits its own WORLD.md |
| 4 | Auto-extensión | a tool that writes & installs new Lua programs |
| 5 | Proactivo | event-driven watching/acting without being asked |

## 7. Verification

- **Pure** (`protocol.lua`: `parseCall`, `renderTools`, `buildPrompt`) unit-tested on
  local Lua 5.4 in `dist/tests/`, registered in `run.lua`.
- **CC-bound** (`claudecc`, `tools`, `agent`, app) `luac -p`-checked and validated
  **in-game** by the owner via the Update app.
- **Task 0 first:** `claude_smoke.lua` confirms `_G.claude`'s real shape before any
  wrapper code is trusted. Keep it for regressions, like `kb_smoke.lua`.
- **The "first miracle" acceptance:** in-game, `"JARVIS, ¿cómo va la flota?"` →
  JARVIS emits `@tool fleet_status {}` → the OS runs it → JARVIS answers in natural
  language with the real turtle count/states.

## 8. Confirmed decisions

1. **Brain = ClaudeCraft native (option B)** — chosen on the owner's *empirical*
   evidence that the Node bridge lagged and ClaudeCraft does not.
2. **First tool = `fleet_status`** — turtle-related (owner's ask), reuses `fleet.lua`,
   read-only ⇒ low risk for a first slice.
3. **Scaffolding built in Lua** — ClaudeCraft is chat-only, so the CLAUDE.md/tools/
   loop are ours (and that *is* the feature the owner asked for).
4. **Text tool-call protocol (`@tool` / `@result` sentinel lines)** — picked for
   parse reliability over JSON-in-prose. Revisit if Task 0 finds native tool-use.
5. **The mod dependency is isolated in `claudecc.lua`** — so the undocumented API can
   be corrected in one place after the smoke test.
