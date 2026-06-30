# JARVIS Core — Implementation Plan (Increment 0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or
> subagent-driven-development) to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax. **This plan is written for a fresh session with no
> prior context** — read the spec `specs/pinguos/jarvis-core.md` first.

**Goal:** Ship the JARVIS agent core: a `jarvis` app where you type a natural-language
order, JARVIS runs the `fleet_status` tool through a home-grown tool loop over
ClaudeCraft, and answers with real fleet data. ("First miracle": *"JARVIS, ¿cómo va
la flota?"* → real turtle states.)

**Architecture:** `protocol.lua` (pure: prompt build + tool-call parse) →
`agent.lua` (the loop) → `claudecc.lua` (the only file that knows ClaudeCraft's API)
and `tools.lua` (the catalogue, one tool: `fleet_status`). The `jarvis` app loads
these with `loadfile` and wires them. WORLD.md in `/data/jarvis/` is the base system
prompt. See `specs/pinguos/jarvis-core.md` for the full design and the loop diagram.

**Tech Stack:** Lua (CC:Tweaked 5.1 in-game, Lua 5.4 locally), ClaudeCraft 1.2.2
(`_G.claude`), reuses `fleet.lua` for the fleet tool.

## Global Constraints

- **The ClaudeCraft Lua API is undocumented — Task 0 (in-game smoke test) is the
  source of truth.** Tasks 2/4 are written against the *reference* API
  (`startChannel`/`sendMessage`/`claude_text`/`claude_done`); after Task 0, **adjust
  `claudecc.lua` to whatever the smoke test reveals**. The dependency is isolated
  there on purpose.
- **`require` is NOT available inside apps or files loaded by an app.** Apps load via
  `loadfile` and see only `_G`; `require` lives only in the kernel's load context
  (project gotcha). Therefore: the `jarvis` app loads its modules with `loadfile`,
  and `agent.lua` receives its dependencies via `agent.init(...)` — **no `require` in
  any `dist/os/jarvis/*.lua` file.** (`loadfile`, `fs`, `term`, `os`, `peripheral`,
  `rednet`, `textutils`, `window`, `colors`, `keys` ARE in `_G`.)
- **The test comparator `same()` in `run.lua` only handles array tables** (`#`-keyed).
  For tables with string keys (e.g. `{name=..,argsRaw=..}`), assert each field with a
  separate `T.eq` on the string field — do NOT `T.eq` the whole table.
- **Lua must run on CC 5.1 AND local 5.4** (pure modules): no `//`, no bit-ops;
  `math.floor` before `string.format("%d", n)`.
- **Rendered text is ASCII only.** WORLD.md and tool output are ASCII too (CC reads
  files as byte strings on 5.1).
- **Test model:** pure logic via `"$LUA" dist/tests/run.lua`
  (`$LUA` = `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`,
  `$LUAC` = `luac.exe` beside it); CC-bound code `luac -p`-checked + validated
  in-game by the owner via the Update app.
- **Inc 0 is read-only** (only `fleet_status`) — no destructive actions, so no safety
  confirmations needed yet (those are Inc 2).

---

### Task 0: In-game smoke test — confirm the ClaudeCraft API

**This task needs the owner in-game. It can run in parallel with Task 1.** Its output
is the real shape of `_G.claude`, which Task 2 is adjusted against.

**Files:**
- Create: `dist/tests/claude_smoke.lua`

- [ ] **Step 1: Write the probe**

```lua
-- dist/tests/claude_smoke.lua  -- run in-game: wget run http://127.0.0.1:8080/fs/tests/claude_smoke.lua
-- Confirms ClaudeCraft's Lua API: is _G.claude present, what functions/events exist,
-- and can we do one round-trip? Mirrors kb_smoke.lua. NOT a unit test.
print("=== ClaudeCraft smoke ===")
print("_G.claude type: " .. type(_G.claude))
if type(_G.claude) ~= "table" then
  print("NOT FOUND. Is ClaudeCraft installed + a key/channel set? (/claudecraft ...)")
  return
end
print("keys on _G.claude:")
for k, v in pairs(_G.claude) do print("  ." .. tostring(k) .. " = " .. type(v)) end

print("Sending a test message (watch for events for 20s)...")
-- Try the reference call shapes; adjust if your build differs:
local ok, err = pcall(function()
  if _G.claude.ask then
    print("ask() returned: " .. tostring(_G.claude.ask("Say OK in 3 words.")))
  elseif _G.claude.startChannel then
    local ch = _G.claude.startChannel("You are a test. Reply briefly.")
    print("startChannel -> " .. type(ch))
    if ch and ch.sendMessage then ch.sendMessage("Say OK in 3 words.")
    elseif _G.claude.sendMessage then _G.claude.sendMessage("Say OK in 3 words.") end
  elseif _G.claude.sendMessage then
    _G.claude.sendMessage("Say OK in 3 words.")
  end
end)
if not ok then print("call error: " .. tostring(err)) end

local t = os.startTimer(20)
while true do
  local ev = { os.pullEventRaw() }
  if ev[1] == "timer" and ev[2] == t then break end
  if tostring(ev[1]):find("claude") then
    print("EVENT " .. ev[1] .. " | " .. tostring(ev[2]):sub(1, 60))
  end
  if ev[1] == "terminate" then break end
end
print("=== done ===")
```

- [ ] **Step 2: Syntax-check + commit**

```bash
"$LUAC" -p dist/tests/claude_smoke.lua
git add dist/tests/claude_smoke.lua
git commit -m "test(jarvis): in-game ClaudeCraft API smoke probe"
```

- [ ] **Step 3: Owner runs it in-game and reports**

Owner: `wget run http://127.0.0.1:8080/fs/tests/claude_smoke.lua`. Record: the exact
function names on `_G.claude`, whether `startChannel` returns a handle with
`sendMessage`, and the exact event name(s) carrying the reply (and which `ev[n]` holds
the text). **These answers parametrise Task 2.**

---

### Task 1: `protocol.lua` — pure prompt + tool-call parsing (TDD)

**Files:**
- Create: `dist/os/jarvis/protocol.lua`
- Create: `dist/tests/test_jarvis_protocol.lua`
- Modify: `dist/tests/run.lua` (register the test)

**Interfaces:**
- Produces: `protocol.parseCall(text) -> {name,argsRaw} | nil`;
  `protocol.renderTools(catalog) -> string`;
  `protocol.buildPrompt(worldMd, catalog) -> string`. `catalog` is an array of
  `{name=string, description=string, params={string,...}}`.

- [ ] **Step 1: Write the failing tests**

Create `dist/tests/test_jarvis_protocol.lua`:

```lua
-- dist/tests/test_jarvis_protocol.lua -- pure agent-protocol parsing.
local protocol = require("jarvis.protocol")

-- parseCall: tool-call sentinel -> {name, argsRaw}; assert fields (comparator is array-only)
local c = protocol.parseCall("@tool fleet_status {}")
T.eq(c and c.name, "fleet_status", "parse name")
T.eq(c and c.argsRaw, "{}", "parse argsRaw")

local c2 = protocol.parseCall("bla bla\n@tool scan {\"r\":8}\nmas texto")
T.eq(c2 and c2.name, "scan", "first sentinel name")
T.eq(c2 and c2.argsRaw, "{\"r\":8}", "first sentinel args")

T.ok(protocol.parseCall("La flota va bien, 3 turtles.") == nil, "final answer -> nil")
T.ok(protocol.parseCall(nil) == nil, "nil input -> nil")
local c3 = protocol.parseCall("   @tool ping   ")
T.eq(c3 and c3.name, "ping", "trims + empty args")
T.eq(c3 and c3.argsRaw, "", "empty argsRaw")

-- renderTools: deterministic ASCII line
local cat = { { name = "fleet_status", params = {}, description = "estado de la flota" } }
T.eq(protocol.renderTools(cat), "- fleet_status() -- estado de la flota", "render one tool")

-- buildPrompt: contains world text, the protocol sentinel, and the tool name
local p = protocol.buildPrompt("BASE FACTS", cat)
T.ok(p:find("BASE FACTS", 1, true) ~= nil, "prompt has world md")
T.ok(p:find("@tool", 1, true) ~= nil, "prompt explains @tool")
T.ok(p:find("fleet_status", 1, true) ~= nil, "prompt lists the tool")
```

- [ ] **Step 2: Register the test** — add to `dist/tests/run.lua` after the
  `test_focus` line:

```lua
dofile("dist/tests/test_jarvis_protocol.lua")
```

- [ ] **Step 3: Run to verify it fails**

Run: `"$LUA" dist/tests/run.lua`
Expected: FAIL — `module 'jarvis.protocol' not found` (or nil-field errors).

- [ ] **Step 4: Implement `protocol.lua`**

Create `dist/os/jarvis/protocol.lua`:

```lua
-- dist/os/jarvis/protocol.lua -- pure agent-protocol helpers (no CC globals).
-- Loaded by require() in tests (local 5.4) and by loadfile() in-game; uses neither
-- require nor any CC API, so it works under both. Unit-tested in test_jarvis_protocol.
local protocol = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Parse a Claude reply. The FIRST line that (trimmed) matches `@tool <name> <args>`
-- is a tool-call -> {name, argsRaw}. No such line -> nil (the reply is the final
-- answer). JSON of argsRaw is decoded by the caller (CC textutils), keeping this pure.
function protocol.parseCall(text)
  if type(text) ~= "string" then return nil end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local name, argsRaw = trim(line):match("^@tool%s+(%S+)%s*(.-)$")
    if name then return { name = name, argsRaw = trim(argsRaw) } end
  end
  return nil
end

-- Render the catalogue as deterministic ASCII lines for the system prompt.
function protocol.renderTools(catalog)
  local out = {}
  for _, t in ipairs(catalog or {}) do
    out[#out + 1] = "- " .. t.name .. "(" .. table.concat(t.params or {}, ", ")
                 .. ") -- " .. (t.description or "")
  end
  return table.concat(out, "\n")
end

-- Full system prompt: WORLD.md + tools + the fixed protocol instructions.
function protocol.buildPrompt(worldMd, catalog)
  return table.concat({
    worldMd or "",
    "",
    "## Tools",
    "To use a tool, reply with EXACTLY one line and nothing else:",
    "@tool <name> <json-args>   (example: @tool fleet_status {})",
    "The system then replies with: @result <json>. Continue from there.",
    "When you have the final answer, reply in plain natural language (no @tool line).",
    "",
    "Available tools:",
    protocol.renderTools(catalog),
  }, "\n")
end

return protocol
```

- [ ] **Step 5: Run to verify pass**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 101 passed, 0 failed` (90 prior + 11 new).

- [ ] **Step 6: Commit**

```bash
git add dist/os/jarvis/protocol.lua dist/tests/test_jarvis_protocol.lua dist/tests/run.lua
git commit -m "feat(jarvis): pure agent protocol (parseCall/renderTools/buildPrompt)"
```

---

### Task 2: `claudecc.lua` — the ClaudeCraft wrapper (CC-bound)

**Files:**
- Create: `dist/os/jarvis/claudecc.lua`

**Interfaces:**
- Produces: `claudecc.available() -> bool`; `claudecc.open(systemPrompt) -> session`;
  `claudecc.send(session, text) -> replyText`; `claudecc.close(session)`.
- **Adjust the body to Task 0's findings** before trusting it.

- [ ] **Step 1: Write it (against the reference API)**

Create `dist/os/jarvis/claudecc.lua`:

```lua
-- dist/os/jarvis/claudecc.lua -- the ONLY file that knows ClaudeCraft's API.
-- Reference API (CONFIRM/CORRECT via dist/tests/claude_smoke.lua, Plan Task 0):
--   _G.claude.startChannel(systemPrompt) -> channel ; channel.sendMessage(text)
--   events: "claude_text"(partial chunk) / "claude_done"(full text).
-- If Task 0 shows a different shape (e.g. _G.claude.ask(text) -> string), implement
-- send() with that instead -- nothing else in JARVIS needs to change.
local claudecc = {}

function claudecc.available()
  return type(_G.claude) == "table"
end

function claudecc.open(systemPrompt)
  local ch = _G.claude.startChannel and _G.claude.startChannel(systemPrompt) or _G.claude
  return { ch = ch, system = systemPrompt }
end

-- Send a message; block until the reply is complete; return the full text.
function claudecc.send(session, text)
  local ch = session.ch
  if ch.sendMessage then ch.sendMessage(text)
  elseif _G.claude.sendMessage then _G.claude.sendMessage(text) end
  local buf = {}
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "claude_text" then buf[#buf + 1] = tostring(ev[2] or "")
    elseif ev[1] == "claude_done" then
      return (ev[2] ~= nil and ev[2] ~= "") and tostring(ev[2]) or table.concat(buf)
    end
  end
end

function claudecc.close(session)
  if session.ch and session.ch.close then session.ch.close() end
end

return claudecc
```

- [ ] **Step 2: Syntax-check + commit**

```bash
"$LUAC" -p dist/os/jarvis/claudecc.lua
git add dist/os/jarvis/claudecc.lua
git commit -m "feat(jarvis): ClaudeCraft wrapper (isolated mod dependency)"
```

---

### Task 3: `tools.lua` — the catalogue + `fleet_status` (CC-bound)

**Files:**
- Create: `dist/os/jarvis/tools.lua`

**Interfaces:**
- Consumes: `ctx.fleet` (the `fleet` module: `fleet.discover()`, `fleet.PROTOCOL`).
- Produces: a table `{ list = {tool,...}, byName = { name = tool } }` where each
  `tool = { name, description, params, run = function(args, ctx) -> table }`.

- [ ] **Step 1: Write it**

Create `dist/os/jarvis/tools.lua`. `fleet_status` mirrors `fleet.lua`'s discovery
(broadcast `discover()`, collect `rednet_message` on `fleet.PROTOCOL` for 2s):

```lua
-- dist/os/jarvis/tools.lua -- JARVIS tool catalogue. Each tool: {name, description,
-- params, run(args, ctx) -> table}. Inc 0 ships one read-only tool: fleet_status.
local tools = { list = {}, byName = {} }

local function register(t) tools.list[#tools.list + 1] = t; tools.byName[t.name] = t end

register({
  name = "fleet_status",
  description = "estado actual de la flota de turtles (id, nombre, rol, estado, fuel)",
  params = {},
  run = function(_, ctx)
    local fleet = ctx.fleet
    local side
    for _, s in ipairs(peripheral.getNames()) do
      if peripheral.getType(s) == "modem" then side = s; break end
    end
    if not side then return { error = "no hay modem en el computer" } end
    rednet.open(side)
    rednet.broadcast(fleet.discover(), fleet.PROTOCOL)
    local seen, deadline = {}, os.startTimer(2)
    while true do
      local ev, a, b, c = os.pullEvent()
      if ev == "timer" and a == deadline then break
      elseif ev == "rednet_message" and c == fleet.PROTOCOL and type(b) == "table" and b.name then
        seen[a] = { id = a, name = b.name, role = b.role, status = b.status, fuel = b.fuel }
      end
    end
    rednet.close(side)
    local list = {}
    for _, t in pairs(seen) do list[#list + 1] = t end
    return { count = #list, turtles = list }
  end,
})

return tools
```

- [ ] **Step 2: Syntax-check + commit**

```bash
"$LUAC" -p dist/os/jarvis/tools.lua
git add dist/os/jarvis/tools.lua
git commit -m "feat(jarvis): tool catalogue + fleet_status (read-only)"
```

---

### Task 4: `agent.lua` — the tool loop (CC-bound)

**Files:**
- Create: `dist/os/jarvis/agent.lua`

**Interfaces:**
- Consumes (via `agent.init`): the `protocol`, `claudecc`, `tools` modules (injected,
  NOT required — see Global Constraints).
- Produces: `agent.init(protocol, claudecc, tools)`;
  `agent.run(ctx, worldMd, userMsg, emit)` where `emit(kind, text)`,
  `kind ∈ "tool"|"result"|"answer"|"error"`.

- [ ] **Step 1: Write it**

Create `dist/os/jarvis/agent.lua`:

```lua
-- dist/os/jarvis/agent.lua -- the agent loop: NL -> (tool-call)* -> final answer.
-- Dependencies are INJECTED via agent.init (no require inside app-loaded files).
local agent = {}
local MAX_TURNS = 6
local protocol, claudecc, tools

function agent.init(p, c, t) protocol, claudecc, tools = p, c, t end

function agent.run(ctx, worldMd, userMsg, emit)
  if not claudecc.available() then emit("error", "ClaudeCraft no detectado"); return end
  local session = claudecc.open(protocol.buildPrompt(worldMd, tools.list))
  local ok, err = pcall(function()
    local reply = claudecc.send(session, userMsg)
    for _ = 1, MAX_TURNS do
      local call = protocol.parseCall(reply)
      if not call then emit("answer", reply); return end
      emit("tool", call.name)
      local tool = tools.byName[call.name]
      local result
      if not tool then
        result = { error = "tool desconocida: " .. call.name }
      else
        local args = textutils.unserialiseJSON(call.argsRaw) or {}
        local rok, r = pcall(tool.run, args, ctx)
        result = rok and r or { error = tostring(r) }
      end
      local resJson = textutils.serialiseJSON(result)
      emit("result", resJson)
      reply = claudecc.send(session, "@result " .. resJson)
    end
    emit("answer", reply) -- turn cap hit: surface the last reply
  end)
  claudecc.close(session)
  if not ok then emit("error", tostring(err)) end
end

return agent
```

- [ ] **Step 2: Syntax-check + commit**

```bash
"$LUAC" -p dist/os/jarvis/agent.lua
git add dist/os/jarvis/agent.lua
git commit -m "feat(jarvis): agent loop (parse -> run tool -> feed result -> repeat)"
```

---

### Task 5: `jarvis` app + WORLD.md (CC-bound)

**Files:**
- Create: `dist/os/apps/jarvis.lua`
- Create: `dist/data/jarvis/world.md`

**Interfaces:**
- Consumes: `ctx` (`ui`, `fleet`, `sys`); loads `dist/os/jarvis/*.lua` via `loadfile`;
  calls `agent.run`.

- [ ] **Step 1: Write WORLD.md**

Create `dist/data/jarvis/world.md` (ASCII only):

```markdown
# JARVIS -- base operating agent

Eres JARVIS, el asistente operativo de la base de Juan (PinguOS, Minecraft).
Hablas espanol, claro y breve. Tienes herramientas para percibir y actuar sobre la
base. Usa una tool cuando necesites datos reales; nunca inventes cifras.
Cuando ya tengas la respuesta, contesta en lenguaje natural (sin lineas @tool).

Hechos de la base:
- (anade aqui lo que JARVIS deba saber siempre)
```

- [ ] **Step 2: Write the app**

Create `dist/os/apps/jarvis.lua` (input loop reuses the `claude.lua` pattern):

```lua
-- dist/os/apps/jarvis.lua -- chat UI for the JARVIS agent. Loads the jarvis modules
-- via loadfile (require is unavailable in apps) and drives agent.run.
return {
  id = "jarvis", name = "JARVIS", icon = "J", color = colors.cyan,
  desc = "Asistente de la base",
  run = function(ctx)
    local ui = ctx.ui
    local function load(n) return assert(loadfile("/os/jarvis/" .. n .. ".lua"))() end
    local protocol, claudecc, tools, agent = load("protocol"), load("claudecc"), load("tools"), load("agent")
    agent.init(protocol, claudecc, tools)

    local worldMd = ""
    if fs.exists("/data/jarvis/world.md") then
      local fh = fs.open("/data/jarvis/world.md", "r"); worldMd = fh.readAll(); fh.close()
    end

    local W, H = term.getSize()
    ui.clear()
    local close = ui.titleBar("JARVIS")
    local win = window.create(term.current(), 1, 2, W, H - 1)
    local old = term.redirect(win)
    local function restore() term.redirect(old) end
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)

    local function colour(c) if term.isColour() then term.setTextColor(c) end end
    local function sanitize(s) return (s:gsub("\r", ""):gsub("[^\n\t -~]", "")) end
    local function emit(kind, text)
      text = sanitize(tostring(text or ""))
      if kind == "tool" then colour(colors.lightGray); print("  [tool: " .. text .. "]")
      elseif kind == "result" then colour(colors.gray); print("  [result: " .. text:sub(1, 2 * W) .. "]")
      elseif kind == "answer" then colour(colors.cyan); term.write("jarvis > "); colour(colors.white); print(text)
      elseif kind == "error" then colour(colors.red); print("error: " .. text) end
    end

    -- input line: types text; returns nil if [x] is clicked (mirrors claude.lua)
    local function inputLine()
      print()
      colour(colors.yellow); term.write("you > "); colour(colors.white)
      local px, py = term.getCursorPos()
      local buf = ""
      term.setCursorBlink(true)
      while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "char" then buf = buf .. a; term.write(a)
        elseif ev == "key" then
          if a == keys.enter then term.setCursorBlink(false); print(); return buf
          elseif a == keys.backspace and #buf > 0 then
            buf = buf:sub(1, #buf - 1)
            term.setCursorPos(px, py); term.write(buf .. " "); term.setCursorPos(px + #buf, py)
          end
        elseif ev == "mouse_click" and ui.hit(close, b, c) then
          term.setCursorBlink(false); return nil
        end
      end
    end

    local ok, err = pcall(function()
      if not claudecc.available() then
        colour(colors.red); print("ClaudeCraft no detectado.")
        print("Configura /claudecraft y reabre. [x] para salir.")
        while true do
          local ev, a, b, c = os.pullEvent()
          if ev == "mouse_click" and ui.hit(close, b, c) then return end
          if ev == "key" and a == keys.q then return end
        end
      end
      print("JARVIS listo. Escribe una orden, o [x] para salir.")
      while true do
        local msg = inputLine()
        if msg == nil then return end
        msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "exit" or msg == "quit" then return
        elseif #msg > 0 then agent.run(ctx, worldMd, msg, emit) end
      end
    end)
    restore()
    if not ok then error(err, 0) end
  end,
}
```

- [ ] **Step 3: Syntax-check both, then run the suite (sanity)**

```bash
"$LUAC" -p dist/os/apps/jarvis.lua
"$LUA" dist/tests/run.lua    # expect: 101 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add dist/os/apps/jarvis.lua dist/data/jarvis/world.md
git commit -m "feat(jarvis): chat app + base WORLD.md system prompt"
```

---

### Task 6: In-game validation (owner) — the first miracle

**No code. The phase boundary. Hand off to the owner.**

- [ ] **Step 1: Ensure the bridge serves the new `dist/`** (so the in-game Update app
  pulls these commits): `DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`.

- [ ] **Step 2: Owner updates in-game and validates**

After **Update**, open the **JARVIS** app and check:
- It opens (or shows "ClaudeCraft no detectado" if the mod/key isn't set).
- Type: **"¿cómo va la flota?"** → the transcript shows `[tool: fleet_status]`, then
  `[result: ...]`, then a natural-language answer with the real turtle count/states.
- With turtles online, the count matches reality; with none, JARVIS says the fleet is
  empty (and does not invent turtles).
- `[x]` exits cleanly; relaunching works.

- [ ] **Step 3: If the loop misbehaves, the usual suspects (in order)**
  1. **API mismatch** → fix `claudecc.lua` per Task 0's smoke output (event names /
     `send` shape). This is the #1 expected issue.
  2. **Claude ignores the protocol** (prose around `@tool`, or never emits it) →
     tighten `world.md` / the protocol instructions in `protocol.buildPrompt`.
  3. **`require` error on open** → confirm the app loads modules via `loadfile` (it
     does) and that no `dist/os/jarvis/*.lua` file calls `require`.

- [ ] **Step 4: On green, finish the branch** — announce and use
  **superpowers:finishing-a-development-branch**.

---

## Self-Review

**Spec coverage (`jarvis-core.md`):** §4 loop → `agent.lua` (Task 4) + `protocol`
(Task 1); §4 protocol `@tool/@result` → `protocol.parseCall`/`buildPrompt` (Task 1) +
`agent` feeding `@result` (Task 4); §5 `claudecc` → Task 2; §5 `tools`/`fleet_status`
→ Task 3; §5 app + WORLD.md → Task 5; §3 API uncertainty → Task 0 + the adjust note on
Task 2; §3 `require` gotcha → Global Constraints + `agent.init` injection + `loadfile`
in the app; §7 first-miracle acceptance → Task 6 Step 2.

**Placeholder scan:** none. Task 0 and Task 6 are deliberately code-light (a smoke
probe and the in-game gate); every other task ships complete code.

**Type consistency:** `parseCall` returns `{name, argsRaw}` (Task 1) and `agent`
reads `call.name`/`call.argsRaw` and decodes `argsRaw` with `textutils.unserialiseJSON`
(Task 4) — consistent. `tools` exposes `.list` and `.byName` (Task 3), consumed as
`tools.list` in `buildPrompt` and `tools.byName[call.name]` in `agent` (Task 4).
`claudecc.{available,open,send,close}` defined in Task 2, called in Task 4 and the app
(Task 5). `emit(kind,text)` kinds match between `agent` (Task 4) and the app's `emit`
(Task 5).

**Fresh-session note:** Task 0 (in-game, owner) and Task 1 (pure, local) are
independent — start Task 1 immediately and have the owner run Task 0 in parallel;
fold Task 0's findings into Task 2 before Task 6.
