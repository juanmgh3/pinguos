# JARVIS Inc 1 — ME stock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or
> subagent-driven-development) to implement this plan task-by-task. Steps use checkbox
> (`- [ ]`) syntax. **Read the spec `specs/pinguos/jarvis-me-stock.md` first.**

**Goal:** Ship JARVIS's first sense: a `me_stock` program the ClaudeCraft brain runs via
`run_command` to answer *"¿cuánto hierro tengo?"* / *"¿qué hay en el ME?"* with real ME-system
data.

**Architecture:** Pure formatting/filtering in `me_format.lua` (unit-tested on local Lua);
CC-bound I/O in `me_stock.lua` (finds the `me_bridge`, calls `listItems`/energy, delegates to
`me_format`, prints ASCII). `world.md` tells the brain the program exists. Same pattern as
`fleet_status`.

**Tech Stack:** Lua (CC 5.1 in-game, 5.4 local), Advanced Peripherals `me_bridge`, PinguOS
`/os/jarvis/` program pattern.

## Global Constraints

- **`require` is unavailable in files loaded via `loadfile`.** `me_format.lua` uses neither
  `require` nor CC globals, so it loads via `require("jarvis.me_format")` in tests (local 5.4)
  AND `loadfile("/os/jarvis/me_format.lua")` in-game — exactly like `protocol.lua` did.
- **The test comparator `same()` in `run.lua` is array-only** (`#`-keyed). Assert scalar
  fields (`#m`, `m[1].name`, a rendered string) with separate `T.eq`/`T.ok`; never `T.eq` a
  whole string-keyed table.
- **Lua runs on CC 5.1 AND local 5.4:** no `//`, no bit-ops; **`math.floor` before
  `string.format("%d", n)`** (5.3+ rejects float `%d`).
- **Rendered text is ASCII** (`me_stock` output and `world.md`).
- **The `me_bridge` method names vary by Advanced Peripherals version** — Task 0's in-game
  probe is the source of truth; adjust `me_stock.lua` (only) after it.
- **Physical prereq (owner):** the ME Bridge must be on JARVIS's computer / wired-modem network
  for `peripheral.find("me_bridge")` to reach it.
- **Test model:** pure logic via `"$LUA" dist/tests/run.lua`
  (`$LUA` = `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`, `$LUAC` = `luac.exe`
  beside it); CC-bound code `luac -p` + validated in-game.

---

### Task 0: ME Bridge API smoke probe

**Runs in parallel with Task 1; owner runs it in-game. Its output confirms the real
`me_bridge` methods, which Task 2 is adjusted against.**

**Files:** Create `dist/tests/me_bridge_smoke.lua`.

- [ ] **Step 1: Write the probe**

```lua
-- dist/tests/me_bridge_smoke.lua -- run in-game: wget run http://127.0.0.1:8080/fs/tests/me_bridge_smoke.lua
-- Confirms the Advanced Peripherals me_bridge API before me_stock trusts it. NOT a unit test.
print("=== me_bridge smoke ===")
local me = peripheral.find("me_bridge")
if not me then print("no me_bridge found -- wire it to this computer or its modem net"); return end
print("methods on me_bridge:")
for k, v in pairs(me) do if type(v) == "function" then print("  ." .. k) end end
print("listItems() sample:")
local ok, items = pcall(me.listItems)
if ok and type(items) == "table" then
  print("  item types: " .. #items)
  for i = 1, math.min(3, #items) do
    local it = items[i] or {}
    print(("  [%d] name=%s count=%s disp=%s"):format(
      i, tostring(it.name), tostring(it.count), tostring(it.displayName)))
  end
else
  print("  listItems failed: " .. tostring(items))
end
for _, fn in ipairs({ "getEnergyStorage", "getMaxEnergyStorage", "getStoredEnergy", "getEnergyUsage" }) do
  if type(me[fn]) == "function" then
    local eok, val = pcall(me[fn])
    print(fn .. " -> " .. (eok and tostring(val) or ("ERR " .. tostring(val))))
  else
    print(fn .. ": (absent)")
  end
end
print("=== done ===")
```

- [ ] **Step 2: Syntax-check + commit**

```bash
"$LUAC" -p dist/tests/me_bridge_smoke.lua
git add dist/tests/me_bridge_smoke.lua
git commit -m "test(jarvis): me_bridge API smoke probe"
```

- [ ] **Step 3: Owner runs it in-game and reports** the exact method names (esp. the item-list
  method and the energy getters) + a `listItems` sample row. **These parametrise Task 2.**

---

### Task 1: `me_format.lua` — pure filter/format (TDD)

**Files:** Create `dist/os/jarvis/me_format.lua`, `dist/tests/test_me_format.lua`; modify
`dist/tests/run.lua`.

**Interfaces (Produces):**
- `me_format.match(items, term) -> filtered array` (items whose `name`/`displayName` contain
  `term`, case-insensitive, sorted by `count` desc).
- `me_format.top(items, n) -> array` (top `n` by `count` desc).
- `me_format.line(item) -> string` (`"label: count"`, `displayName` preferred, count floored).
- `me_format.renderQuery(items, term, cap) -> string`.
- `me_format.renderOverview(items, energy, n) -> string`.
- `item = {name=string, count=number, displayName=string?}`; `energy = {stored=number, max=number}`.

- [ ] **Step 1: Write the failing test** — create `dist/tests/test_me_format.lua`:

```lua
-- dist/tests/test_me_format.lua -- pure ME stock filter/format.
local mf = require("jarvis.me_format")

local items = {
  { name = "minecraft:iron_ingot", displayName = "Iron Ingot",   count = 1200 },
  { name = "minecraft:iron_block", displayName = "Block of Iron", count = 34 },
  { name = "minecraft:gold_ingot", displayName = "Gold Ingot",   count = 500 },
  { name = "minecraft:diamond",    displayName = "Diamond",      count = 64 },
}

-- match: by name substring, case-insensitive, sorted by count desc
local m = mf.match(items, "IRON")
T.eq(#m, 2, "match count for iron")
T.eq(m[1].name, "minecraft:iron_ingot", "match sorted desc (ingot first)")
T.eq(m[2].name, "minecraft:iron_block", "match second")
T.ok(#mf.match(items, "netherite") == 0, "no match -> empty")
T.eq(#mf.match(items, "block of iron"), 1, "match by displayName")

-- top: sorted desc, capped
local t = mf.top(items, 2)
T.eq(#t, 2, "top capped at 2")
T.eq(t[1].name, "minecraft:iron_ingot", "top1 = iron ingot (1200)")
T.eq(t[2].name, "minecraft:gold_ingot", "top2 = gold (500)")

-- line: displayName preferred, count floored, name fallback
T.eq(mf.line({ name = "x", displayName = "Iron Ingot", count = 1200 }), "Iron Ingot: 1200", "line format")
T.eq(mf.line({ name = "minecraft:raw_iron", count = 7.0 }), "minecraft:raw_iron: 7", "line fallback + floor")

-- renderQuery: match lines + no-match message
T.ok(mf.renderQuery(items, "iron", 20):find("Iron Ingot: 1200", 1, true) ~= nil, "renderQuery has iron")
T.eq(mf.renderQuery(items, "netherite", 20), "sin stock que coincida con 'netherite'", "renderQuery no match")

-- renderOverview: type count + energy
local ov = mf.renderOverview(items, { stored = 5000, max = 10000 }, 3)
T.ok(ov:find("tipos de item: 4", 1, true) ~= nil, "overview type count")
T.ok(ov:find("energia ME: 5000 / 10000", 1, true) ~= nil, "overview energy")
```

- [ ] **Step 2: Register the test** — in `dist/tests/run.lua`, add after the `test_focus` line:

```lua
dofile("dist/tests/test_me_format.lua")
```

- [ ] **Step 3: Run to verify it fails**

Run: `"$LUA" dist/tests/run.lua`
Expected: FAIL — `module 'jarvis.me_format' not found`.

- [ ] **Step 4: Implement `me_format.lua`** — create `dist/os/jarvis/me_format.lua`:

```lua
-- dist/os/jarvis/me_format.lua -- pure ME stock filter/format (no CC globals, no require).
-- Loaded by require() in tests (5.4) and loadfile() in-game; unit-tested in test_me_format.
local M = {}

-- Items whose name/displayName contains `term` (case-insensitive), sorted by count desc.
function M.match(items, term)
  local t = tostring(term or ""):lower()
  local out = {}
  for _, it in ipairs(items or {}) do
    local name = tostring(it.name or ""):lower()
    local disp = tostring(it.displayName or ""):lower()
    if name:find(t, 1, true) or disp:find(t, 1, true) then out[#out + 1] = it end
  end
  table.sort(out, function(a, b) return (a.count or 0) > (b.count or 0) end)
  return out
end

-- Top `n` items by count desc.
function M.top(items, n)
  local sorted = {}
  for _, it in ipairs(items or {}) do sorted[#sorted + 1] = it end
  table.sort(sorted, function(a, b) return (a.count or 0) > (b.count or 0) end)
  local out = {}
  for i = 1, math.min(n or 10, #sorted) do out[i] = sorted[i] end
  return out
end

-- "label: count" (displayName preferred, count floored for 5.1/5.4 %d safety).
function M.line(it)
  local label = (it.displayName and it.displayName ~= "" and it.displayName) or it.name or "?"
  return string.format("%s: %d", label, math.floor(it.count or 0))
end

-- Matches for `term`, capped at `cap` lines (default 20), or a no-match message.
function M.renderQuery(items, term, cap)
  cap = cap or 20
  local m = M.match(items, term)
  if #m == 0 then return "sin stock que coincida con '" .. tostring(term) .. "'" end
  local lines = {}
  for i = 1, math.min(cap, #m) do lines[#lines + 1] = M.line(m[i]) end
  if #m > cap then lines[#lines + 1] = "... (" .. (#m - cap) .. " mas)" end
  return table.concat(lines, "\n")
end

-- Overview: type count + top `n` + energy (if provided).
function M.renderOverview(items, energy, n)
  local lines = { ("tipos de item: %d"):format(#(items or {})) }
  for _, it in ipairs(M.top(items, n or 10)) do lines[#lines + 1] = "  " .. M.line(it) end
  if energy then
    lines[#lines + 1] = ("energia ME: %d / %d"):format(
      math.floor(energy.stored or 0), math.floor(energy.max or 0))
  end
  return table.concat(lines, "\n")
end

return M
```

- [ ] **Step 5: Run to verify pass**

Run: `"$LUA" dist/tests/run.lua`
Expected: PASS — `PinguOS tests: 104 passed, 0 failed` (90 prior + 14 new).

- [ ] **Step 6: Commit**

```bash
git add dist/os/jarvis/me_format.lua dist/tests/test_me_format.lua dist/tests/run.lua
git commit -m "feat(jarvis): pure ME stock filter/format (match/top/render)"
```

---

### Task 2: `me_stock.lua` + `world.md` (CC-bound)

**Files:** Create `dist/os/jarvis/me_stock.lua`; modify `dist/data/jarvis/world.md`.

**Interfaces (Consumes):** `me_format.{renderQuery,renderOverview}` (Task 1);
`peripheral.find`, `me_bridge.listItems()` + energy getters (Task 0 confirms names).

- [ ] **Step 1: Write `me_stock.lua`** — create `dist/os/jarvis/me_stock.lua`:

```lua
-- dist/os/jarvis/me_stock.lua -- read the ME system on demand. The JARVIS brain runs this via
-- run_command: "me_stock <item>" -> that item's stock; "me_stock" -> overview. Formatting is in
-- the pure me_format module. ASCII. CONFIRM me_bridge method names via me_bridge_smoke.lua (Task 0).
local mf = assert(loadfile("/os/jarvis/me_format.lua"))()

local me = peripheral.find("me_bridge")
if not me then print("me_stock: no ME Bridge on JARVIS's network"); return end

local ok, items = pcall(me.listItems)  -- reference method; adjust per Task 0 if different
if not ok or type(items) ~= "table" then
  print("me_stock: ME Bridge query failed (" .. tostring(items) .. ")"); return
end

local arg = ...
if arg and tostring(arg) ~= "" then
  print(mf.renderQuery(items, tostring(arg), 20))
else
  local energy
  local eok, stored = pcall(function() return me.getEnergyStorage and me.getEnergyStorage() end)
  local mok, max = pcall(function() return me.getMaxEnergyStorage and me.getMaxEnergyStorage() end)
  if eok and stored then energy = { stored = stored, max = (mok and max) or 0 } end
  print(mf.renderOverview(items, energy, 10))
end
```

- [ ] **Step 2: Add the ME section to `world.md`** — in `dist/data/jarvis/world.md`, under
  `## La base`, add this bullet after the fleet line:

```markdown
- Almacen ME (Applied Energistics, via ME Bridge): para consultar stock ejecuta
  /os/jarvis/me_stock.lua [item]  -- con item = cantidad de ese item (match difuso, ej. "iron"),
  sin item = resumen (top items + energia). Ej: "cuanto hierro tengo" -> me_stock.lua iron.
```

- [ ] **Step 3: Syntax-check + run the suite (sanity)**

```bash
"$LUAC" -p dist/os/jarvis/me_stock.lua
"$LUA" dist/tests/run.lua    # expect: 104 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add dist/os/jarvis/me_stock.lua dist/data/jarvis/world.md
git commit -m "feat(jarvis): me_stock CLI + WORLD.md (first sense: ME stock)"
```

---

### Task 3: In-game validation (owner) — the first sense

**No code. Phase boundary — hand off to the owner.**

- [ ] **Step 1:** Wire the ME Bridge to JARVIS's computer (#3) or its wired-modem network.
  Bridge serves `dist/`; **Update** in-game.

- [ ] **Step 2: Run Task 0's probe** (`wget run .../fs/tests/me_bridge_smoke.lua`) and report the
  real method names. If `listItems`/energy getters differ from the reference, **adjust
  `me_stock.lua` only** (per the isolation decision) and re-commit.

- [ ] **Step 3: Acceptance** — open **JARVIS** (native client), then:
  - *"¿cuánto hierro tengo?"* -> brain runs `me_stock iron` -> the **real** count.
  - *"¿qué tengo en el ME?"* -> overview (top items + energy).
  - With no ME Bridge wired -> the graceful "no ME Bridge" message (brain reports it, doesn't invent).

- [ ] **Step 4: On green** -> announce and use **superpowers:finishing-a-development-branch**.

---

## Self-Review

**Spec coverage (`jarvis-me-stock.md`):** §5 `me_stock` -> Task 2; §5 pure filter/format ->
Task 1 (extracted to `me_format` for testability, per the project's protocol.lua precedent);
§5 `world.md` -> Task 2 Step 2; §5 probe / §3 API-varies -> Task 0 + Task 3 Step 2; §6
acceptance -> Task 3 Step 3. **Placeholder scan:** none — every task ships complete code
(Task 0/3 are deliberately probe/gate). **Type consistency:** `me_format.{match,top,line,
renderQuery,renderOverview}` are defined in Task 1 and consumed in Task 2 with matching
signatures; `item`/`energy` shapes match between the test fixtures, `me_format`, and
`me_stock`'s `listItems`/energy calls. **Fresh-session note:** Task 0 (in-game, owner) and
Task 1 (pure, local) are independent — start Task 1 immediately; fold Task 0's findings into
Task 2 before Task 3.
