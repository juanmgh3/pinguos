# PinguOS — JARVIS (agent core) — v3 (wrap native client)

- **Status:** Approved (design agreed in chat 2026-07-01); mechanism verified from mod source.
- **Date:** 2026-07-01 (v3 supersedes v2's "build a thin Lua client")
- **Slug:** `jarvis-core`
- **Owner:** Juan
- **Depends on:** ClaudeCraft 1.2.2 (`github.com/west3436/claudecraft`), its rom `claude`
  program, `fleet.lua`, the app/`ctx` model.

> Durable record per the SDD flow. If it isn't written here, it isn't agreed.

---

## 0. Revision notes

- **v2 (pivot):** Task 0 proved ClaudeCraft is NOT chat-only — the brain is a full Claude
  Code agent. Dropped v1's Lua tool-loop; planned a "thin Lua client" over `_G.claude`.
- **v3 (wrap):** in-game testing + reading the mod source revealed that **in channel mode the
  Lua CLIENT must execute the brain's tool calls** (`claude_tool_exec` → run → `sendToolResult`),
  not just relay text. A "thin relay" is insufficient (tools time out). ClaudeCraft already
  ships a complete, correct client — its rom `claude` program (chat UI + the tool-exec loop +
  a ~150-line tools module). **Decision (owner): wrap the native client instead of
  reimplementing it.** JARVIS = a PinguOS launcher for `claude` + base knowledge + programs.

## 1. Summary & vision

**JARVIS** is the operating agent for Juan's base: talk in natural language, it perceives and
acts (turtles, peripherals, Create, ME). The agent is **ClaudeCraft's embedded Claude Code
brain + its native `claude` client**, which already does the full loop (chat + tool
execution). JARVIS's PinguOS-side contribution:

1. **A body** — the `jarvis` app: a desktop launcher that hands the terminal to `claude` and
   returns to the desktop on exit.
2. **Knowledge** — `/data/jarvis/world.md`: base facts the brain can `read_file`.
3. **Programs** — CLI helpers the brain runs via `run_command` (Inc 0: `fleet_status`).

Inc 0 = a working JARVIS launch + the fleet helper, so *"lee world.md; ¿cómo va la flota?"*
yields real turtle data via the brain's own tool loop.

## 2. Goals / Non-goals

**Goals (Inc 0)**
- A `jarvis` app that launches ClaudeCraft's native `claude` client (`_G.shell.run("claude")`)
  and degrades cleanly if `_G.claude`/`shell` is absent.
- `WORLD.md` base knowledge on the CC FS (brain reads it).
- `fleet_status` program (reuses `fleet.lua`) the brain runs.

**Non-goals (Inc 0)**
- Reimplementing the client / tool-exec loop in Lua → **rejected** (wrap the native one).
- Injecting `world.md` as the brain's system prompt → the native client uses the mod's
  personality config; base knowledge is delivered by the brain reading the file (later: set
  the ClaudeCraft personality for auto-context).
- Custom PinguOS-native tools, memory, proactivity → later increments.

## 3. Confirmed mechanism (verified from mod source `west3436/claudecraft`)

- Each computer runs its own **Claude Code brain**, bridged by a per-computer Bun MCP server
  (`~/.claudecraft/channel/`, cwd `~/.claudecraft/computers/<id>/`).
- **`_G.claude` Lua API** (`ClaudeAPI.java`): `startChannel(isTurtle,label,w,h)->success,port`;
  **`sendMessage(messages, tools, system)->reqId`** where `messages` is a Lua ARRAY
  `{{role="user",content="..."}}` (a map → empty content — the v2 bug); `sendToolResult(reqId,
  callId,resultJson)`; `isChannelReady`, `cancelRequest`, `stopChannel`, getters.
- **Channel-mode events** (`os.pullEvent`→ev,p1,p2,p3,p4): `claude_text`(reqId,text=p2),
  `claude_done`(reqId,...), **`claude_tool_exec`(reqId,callId,toolName,inputJson)**,
  `claude_error`(reqId,msg).
- **The client executes tools.** On `claude_tool_exec` it runs the tool (rom `claude.lua`
  `tools._exec`: run_command via `shell.run`, get_info, peripheral_call, file ops, redstone,
  turtle_*) and replies `sendToolResult`. This is why we wrap the rom client rather than
  rebuild it.

## 4. Architecture

```
  desktop --launch--> app jarvis  (thin launcher)
                          |  _G.shell.run("claude")
                          v
                   rom `claude` client  (chat UI + agentic loop + tool execution)
                          |  sendMessage / claude_tool_exec + sendToolResult
                          v
                   ClaudeCraft brain (Claude Code)  --run_command/peripheral_call--> the base

  /data/jarvis/world.md   : base facts the brain read_files
  /os/jarvis/fleet_status : CLI the brain run_commands (reuses fleet.lua)
```

On `claude` exit (type `exit`/`quit`), the app returns and the kernel redraws the desktop.

## 5. Components

- **`dist/os/apps/jarvis.lua`**: the launcher. Checks `_G.claude` + `_G.shell`; clears the
  term; `shell.run("claude")`; returns. ~30 lines.
- **`dist/data/jarvis/world.md`**: base knowledge (ASCII; the `pingufleet` protocol; "to check
  the fleet run /os/jarvis/fleet_status.lua"; PinguOS layout).
- **`dist/os/jarvis/fleet_status.lua`**: headless CLI, reuses `fleet.lua`, prints the fleet.
- **Removed** (vs v2): `claudecc.lua` (the native client replaces it).

## 6. Increments (roadmap; this spec = Inc 0)

| Inc | Name | Adds |
|---|---|---|
| **0** | **Núcleo** (this spec) | launcher + WORLD.md + `fleet_status` |
| 1 | Conocimiento | set ClaudeCraft personality = base knowledge (auto-context, no read needed) |
| 2 | Programas | more base CLIs the brain runs; safety conventions |
| 3 | Memoria | brain persists base facts to the CC FS (it has write_file) |
| 4+ | Proactivo/HD | event-driven triggers; HD monitor JARVIS surface |

## 7. Verification

- **App + `fleet_status`:** `luac -p`; PinguOS suite stays **90**; validated in-game.
- **First miracle:** open **JARVIS** → native client → *"lee /data/jarvis/world.md y dime cómo
  va la flota"* → brain `read_file`s world.md, `run_command`s `fleet_status`, answers with real
  turtle states (its tool loop executes correctly — the whole point of the wrap).

## 8. Confirmed decisions

1. **Brain = ClaudeCraft native** (full Claude Code agent) — confirmed by Task 0.
2. **Channel mode = the client executes tools** (`claude_tool_exec`/`sendToolResult`),
   verified from `ClaudeAPI.java`.
3. **Wrap the native `claude` client** rather than reimplement it — owner's call: it works, is
   proven, and won't drift on mod updates. JARVIS adds the launcher + knowledge + programs.
4. **Base knowledge via `world.md` the brain reads** (Inc 0); ClaudeCraft personality is the
   later auto-context path.
5. **Fleet is the first capability**, a read-only CLI the brain runs (reuses `fleet.lua`).
