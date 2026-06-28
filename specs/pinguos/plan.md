# PinguOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean, extensible desktop-style OS for a CC: Tweaked Advanced Computer, plus the PC-side bridge that serves and updates it.

**Architecture:** Layered (CraftOS → support modules → kernel → apps), Approach B (full-screen apps + taskbar, no window manager), designed to grow into background services later. Apps are auto-discovered files implementing a single `ctx`-based contract. A Node bridge serves the OS files over HTTP for one-line install/update.

**Tech Stack:** Lua 5.1+ (CC: Tweaked 1.120.0 runtime, with `utf8`/`cc.strings` backports) for the OS; Node.js (built-in modules only, `node --test` for tests) for the bridge.

## Global Constraints

Every task's requirements implicitly include these. Exact values from the spec:

- **Target runtime:** CC: Tweaked **1.120.0** on an **Advanced Computer** (color + mouse). No third-party mods (no Advanced Peripherals).
- **ASCII only:** every rendered string must be ASCII (terminal is 8-bit, no unicode/emoji). Transliterate/strip on the bridge; sanitize again in the UI.
- **No external Lua deps:** OS uses only CC built-ins. Bridge uses only Node built-in modules (no npm installs).
- **Repo language:** code, identifiers, commits, and repo docs in **English**. Commits follow Conventional Commits.
- **Source of truth:** the in-game OS files live under `dist/` on the PC, mirroring the in-game paths. The bridge serves `dist/`; the in-game installer mirrors it.
- **Two test lanes:**
  - **Node lane (local, real):** all bridge logic is unit-tested with `node --test`. These tasks have runnable fail→pass cycles.
  - **Lua lane (emulator/in-game):** pure Lua modules ship with a plain-Lua test file runnable in **CraftOS-PC** or a local `lua` (`lua dist/tests/run.lua`). CC-API-bound modules (ui, kernel, apps) are verified by an **in-game smoke checklist** (the "live loop": owner runs `update`, observes, shares `/logs`). Each such task states the exact smoke steps and expected on-screen result.
- **Crash isolation:** apps run under `pcall`; a faulty app must never crash the OS.
- **Prerequisite:** CC:T must allow `127.0.0.1` (edit world `serverconfig/computercraft-server.toml`, `$private` → `allow`). Covered in the final task.

## File Structure

**PC / bridge (Node):**
- `claude-bridge.js` — HTTP server wiring only (chat endpoint + static routes). Modified.
- `bridge/ascii.js` — `toTerminalAscii(s)` pure transliteration. New.
- `bridge/manifest.js` — build the file manifest from `dist/`. New.
- `bridge/install.js` — generate the in-game Lua bootstrap script. New.
- `test/ascii.test.js`, `test/manifest.test.js`, `test/server.test.js` — Node tests. New.

**OS source (`dist/`, shipped in-game):**
- `dist/startup.lua` — boot entry; requires and runs the kernel.
- `dist/os/text.lua` — pure text helpers (`wrap`, `truncate`, `ljust`). Testable.
- `dist/os/appreg.lua` — app validation + discovery. Pure `validate` is testable.
- `dist/os/log.lua` — timestamped logging to `/logs/`.
- `dist/os/config.lua` — JSON settings: load/get/set/save (atomic, namespaced).
- `dist/os/ui.lua` — immediate-mode draw toolkit.
- `dist/os/kernel.lua` — boot, desktop, taskbar, app launch/loop.
- `dist/os/apps/about.lua` — version/help; the "hello world" template.
- `dist/os/apps/terminal.lua` — drop to CraftOS shell.
- `dist/os/apps/settings.lua` — theme + bridge URL.
- `dist/os/apps/update.lua` — pull latest from bridge + reboot.
- `dist/os/apps/claude.lua` — Claude chat (ported from `claude.lua`).

**Lua tests (PC-side, not shipped):**
- `dist/tests/run.lua` — tiny assert-based runner.
- `dist/tests/test_text.lua`, `dist/tests/test_appreg.lua`.

---

## Tasks

### Task 1: Bridge — ASCII transliteration module

**Files:**
- Create: `bridge/ascii.js`
- Create: `test/ascii.test.js`
- Create: `.gitignore`
- Modify: `claude-bridge.js` (replace inline `toTerminalAscii` with a `require`)

**Interfaces:**
- Produces: `toTerminalAscii(s: string) -> string` (CommonJS export). Maps common
  unicode punctuation to ASCII, decomposes+strips accents, drops any remaining
  non-ASCII. Non-strings returned unchanged.

- [ ] **Step 1: Write the failing test**

```js
// test/ascii.test.js
const { test } = require("node:test");
const assert = require("node:assert");
const { toTerminalAscii } = require("../bridge/ascii");

test("passes plain ASCII through unchanged", () => {
  assert.equal(toTerminalAscii("pong"), "pong");
  assert.equal(toTerminalAscii("line1\nline2\ttab"), "line1\nline2\ttab");
});

test("strips accents to base letters", () => {
  assert.equal(toTerminalAscii("café"), "cafe");
  assert.equal(toTerminalAscii("ñoño"), "nono");
  assert.equal(toTerminalAscii("ÁÉÍÓÚ"), "AEIOU");
});

test("maps spanish punctuation", () => {
  assert.equal(toTerminalAscii("¿qué?"), "?que?");
  assert.equal(toTerminalAscii("¡hola!"), "!hola!");
});

test("maps dashes and smart quotes", () => {
  assert.equal(toTerminalAscii("a—b–c"), "a-b-c");
  assert.equal(toTerminalAscii("“x”‘y’"), '"x"\'y\'');
});

test("drops emoji and leftover non-ascii", () => {
  assert.equal(toTerminalAscii("hola 👋 mundo"), "hola  mundo");
});

test("returns non-strings unchanged", () => {
  assert.equal(toTerminalAscii(42), 42);
  assert.equal(toTerminalAscii(null), null);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test test/ascii.test.js`
Expected: FAIL — `Cannot find module '../bridge/ascii'`.

- [ ] **Step 3: Write the module**

```js
// bridge/ascii.js
// CC: Tweaked terminals are 8-bit, ASCII-only. Make any string renderable.
const PUNCT = {
  "¿": "?", "¡": "!",          // ¿ ¡
  "—": "-", "–": "-",          // — –
  "…": "...", "•": "*",        // … •
  "“": '"', "”": '"', "„": '"', // “ ” „
  "‘": "'", "’": "'",          // ‘ ’
  "→": "->", "←": "<-",        // → ←
  " ": " ",                          // non-breaking space
};
function toTerminalAscii(s) {
  if (typeof s !== "string") return s;
  s = s.replace(
    /[¿¡—–…•“”„‘’→← ]/g,
    (c) => PUNCT[c] || c
  );
  s = s.normalize("NFKD").replace(/[̀-ͯ]/g, ""); // strip accents
  s = s.replace(/[^\x09\x0a\x0d\x20-\x7e]/g, "");          // drop the rest
  return s;
}
module.exports = { toTerminalAscii };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test test/ascii.test.js`
Expected: PASS (6 tests).

- [ ] **Step 5: Wire it into the bridge and add `.gitignore`**

In `claude-bridge.js`, delete the inline `PUNCT` object and `toTerminalAscii`
function, and add near the other requires:

```js
const { toTerminalAscii } = require("./bridge/ascii");
```

Create `.gitignore`:

```
node_modules/
*.log
/logs/
*.tmp
.DS_Store
```

- [ ] **Step 6: Verify the bridge still starts**

Run: `node -e "require('./claude-bridge.js')" & sleep 1; curl -s -X POST http://127.0.0.1:8080/ -H 'Content-Type: application/json' -d '{\"reset\":true}'; kill %1`
Expected: `{"text":"(memoria borrada)"}` (proves the require resolves and the server runs).

- [ ] **Step 7: Commit**

```bash
git add bridge/ascii.js test/ascii.test.js .gitignore claude-bridge.js
git commit -m "refactor(bridge): extract tested toTerminalAscii module"
```

---

### Task 2: Bridge — manifest builder

**Files:**
- Create: `bridge/manifest.js`
- Create: `test/manifest.test.js`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `buildManifest(distDir: string, version: string) -> { version, files: Array<{path}> }`.
  Walks `distDir` recursively, **excluding** any `tests/` directory. Each `path`
  is the in-game absolute path: `/` + the POSIX-style path relative to `distDir`.
  `files` is sorted by `path` ascending (stable manifests).

- [ ] **Step 1: Write the failing test**

```js
// test/manifest.test.js
const { test } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { buildManifest } = require("../bridge/manifest");

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pinguos-"));
  fs.mkdirSync(path.join(dir, "os", "apps"), { recursive: true });
  fs.mkdirSync(path.join(dir, "tests"), { recursive: true });
  fs.writeFileSync(path.join(dir, "startup.lua"), "x");
  fs.writeFileSync(path.join(dir, "os", "kernel.lua"), "x");
  fs.writeFileSync(path.join(dir, "os", "apps", "about.lua"), "x");
  fs.writeFileSync(path.join(dir, "tests", "run.lua"), "x"); // must be excluded
  return dir;
}

test("lists shipped files as in-game paths, sorted, tests excluded", () => {
  const dir = fixture();
  const m = buildManifest(dir, "1.0.0");
  assert.equal(m.version, "1.0.0");
  assert.deepEqual(
    m.files.map((f) => f.path),
    ["/os/apps/about.lua", "/os/kernel.lua", "/startup.lua"]
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test test/manifest.test.js`
Expected: FAIL — `Cannot find module '../bridge/manifest'`.

- [ ] **Step 3: Write the module**

```js
// bridge/manifest.js
const fs = require("node:fs");
const path = require("node:path");

function walk(dir, base, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (entry.name === "tests") continue; // never ship tests
      walk(path.join(dir, entry.name), base, out);
    } else if (entry.isFile()) {
      const rel = path.relative(base, path.join(dir, entry.name));
      out.push({ path: "/" + rel.split(path.sep).join("/") });
    }
  }
}

function buildManifest(distDir, version) {
  const files = [];
  walk(distDir, distDir, files);
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return { version, files };
}
module.exports = { buildManifest };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test test/manifest.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bridge/manifest.js test/manifest.test.js
git commit -m "feat(bridge): add dist manifest builder"
```

---

### Task 3: Bridge — install script + static routes

**Files:**
- Create: `bridge/install.js`
- Create: `test/server.test.js`
- Modify: `claude-bridge.js` (add `DIST_DIR`, routes `/manifest`, `/fs/<path>`, `/install`, version)

**Interfaces:**
- Consumes: `buildManifest` (Task 2).
- Produces:
  - `installScript(baseUrl: string) -> string` — a Lua bootstrap that GETs
    `/manifest`, downloads each `/fs<path>` to `<path>`, and reboots.
  - Bridge env `DIST_DIR` (default `./dist`) and `OS_VERSION` (default `"dev"`).
  - Routes: `GET /manifest` → manifest JSON; `GET /fs/<path>` → file bytes
    (path-traversal-safe, must resolve inside `DIST_DIR`); `GET /install` →
    `installScript`.

- [ ] **Step 1: Write the failing test**

```js
// test/server.test.js
const { test, before, after } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const http = require("node:http");

const dist = fs.mkdtempSync(path.join(os.tmpdir(), "pinguos-dist-"));
fs.mkdirSync(path.join(dist, "os"), { recursive: true });
fs.writeFileSync(path.join(dist, "startup.lua"), "print('hi')");
fs.writeFileSync(path.join(dist, "os", "kernel.lua"), "return {}");

process.env.DIST_DIR = dist;
process.env.OS_VERSION = "9.9.9";
process.env.PORT = "8099";
const { server } = require("../claude-bridge.js");

function get(p) {
  return new Promise((res) => {
    http.get(`http://127.0.0.1:8099${p}`, (r) => {
      let b = "";
      r.on("data", (c) => (b += c));
      r.on("end", () => res({ code: r.statusCode, body: b }));
    });
  });
}

before(() => new Promise((r) => (server.listening ? r() : server.once("listening", r))));
after(() => server.close());

test("GET /manifest returns version + files", async () => {
  const r = await get("/manifest");
  assert.equal(r.code, 200);
  const m = JSON.parse(r.body);
  assert.equal(m.version, "9.9.9");
  assert.ok(m.files.some((f) => f.path === "/os/kernel.lua"));
});

test("GET /fs/<path> returns file contents", async () => {
  const r = await get("/fs/os/kernel.lua");
  assert.equal(r.code, 200);
  assert.equal(r.body, "return {}");
});

test("GET /fs blocks path traversal", async () => {
  const r = await get("/fs/../claude-bridge.js");
  assert.equal(r.code, 404);
});

test("GET /install returns a lua bootstrap", async () => {
  const r = await get("/install");
  assert.equal(r.code, 200);
  assert.match(r.body, /\/manifest/);
  assert.match(r.body, /os\.reboot\(\)/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test test/server.test.js`
Expected: FAIL — `claude-bridge.js` does not export `server`, and routes 404.

- [ ] **Step 3: Write the install-script module**

```js
// bridge/install.js
function installScript(baseUrl) {
  return `-- PinguOS installer (auto-generated)
local BASE = "${baseUrl}"
local function getJSON(url)
  local h = http.get(url); if not h then error("no manifest: "..url) end
  local s = h.readAll(); h.close(); return textutils.unserialiseJSON(s)
end
local function dirOf(p) return p:match("^(.*)/[^/]+$") end
print("PinguOS: fetching manifest...")
local m = getJSON(BASE.."/manifest")
for _, f in ipairs(m.files) do
  local url = BASE.."/fs"..f.path
  local h = http.get(url); if not h then error("download failed: "..f.path) end
  local data = h.readAll(); h.close()
  local d = dirOf(f.path); if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
  local out = fs.open(f.path, "w"); out.write(data); out.close()
  print("  "..f.path)
end
print("PinguOS "..(m.version or "?").." installed. Rebooting...")
sleep(1)
os.reboot()
`;
}
module.exports = { installScript };
```

- [ ] **Step 4: Add routes + export `server` in `claude-bridge.js`**

Add requires and config near the top:

```js
const { buildManifest } = require("./bridge/manifest");
const { installScript } = require("./bridge/install");
const DIST_DIR = process.env.DIST_DIR || path.join(__dirname, "dist");
const OS_VERSION = process.env.OS_VERSION || "dev";
```

Inside the request handler, **before** the `/claude.lua` handler, add:

```js
if (req.method === "GET" && req.url === "/manifest") {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify(buildManifest(DIST_DIR, OS_VERSION)));
  return;
}
if (req.method === "GET" && req.url === "/install") {
  const base = `http://127.0.0.1:${PORT}`;
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(installScript(base));
  return;
}
if (req.method === "GET" && req.url.startsWith("/fs/")) {
  const rel = decodeURIComponent(req.url.slice("/fs/".length));
  const abs = path.resolve(DIST_DIR, rel);
  if (abs !== DIST_DIR && !abs.startsWith(DIST_DIR + path.sep)) {
    res.writeHead(404).end("nope");
    return;
  }
  fs.readFile(abs, (e, data) => {
    if (e) { res.writeHead(404).end("not found"); return; }
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(data);
  });
  return;
}
```

Change the bottom of the file so the server is exported and only auto-listens
when run directly:

```js
if (require.main === module) {
  server.listen(PORT, "127.0.0.1", () => { /* existing startup logs */ });
}
module.exports = { server };
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `node --test test/server.test.js`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the whole Node suite**

Run: `node --test`
Expected: PASS (all of ascii + manifest + server).

- [ ] **Step 7: Commit**

```bash
git add bridge/install.js test/server.test.js claude-bridge.js
git commit -m "feat(bridge): serve manifest, files, and installer for in-game wget"
```

---

### Task 4: OS — pure text helpers + Lua test runner

**Files:**
- Create: `dist/os/text.lua`
- Create: `dist/tests/run.lua`
- Create: `dist/tests/test_text.lua`

**Interfaces:**
- Produces:
  - `text.wrap(s: string, width: number) -> string[]` — word-wrap to lines
    `<= width`; hard-split words longer than `width`; explicit `\n` becomes a
    paragraph break (blank lines preserved); empty input → `{}`.
  - `text.truncate(s, width) -> string` — `s` if `#s <= width`, else first
    `width` bytes.
  - `text.ljust(s, width) -> string` — pad right with spaces to `width`.
  - `text.center(s, width) -> string` — center within `width` (extra space on
    the right).
  - `dist/tests/run.lua` exposes global `T.eq(got, want, msg)` / `T.ok(cond, msg)`
    and `dofile`s every `test_*.lua`.

- [ ] **Step 1: Ensure a Lua interpreter (best-effort)**

Run: `lua -v` (or `lua5.4 -v`). If present, the Lua lane runs locally.
If missing on Windows, try `winget install -e --id DEVCOM.Lua` once. If it still
can't be installed, that's acceptable: these modules are pure and reviewed, and
are exercised again in-game in Task 14. Record which path applied in the commit
body.

- [ ] **Step 2: Write the runner and the failing test**

```lua
-- dist/tests/run.lua  (run from repo root: lua dist/tests/run.lua)
package.path = "dist/os/?.lua;./os/?.lua;" .. package.path
local pass, fail = 0, 0
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local p = {}; for i = 1, #v do p[i] = dump(v[i]) end
  return "{" .. table.concat(p, ", ") .. "}"
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if not same(a[i], b[i]) then return false end end
  return true
end
_G.T = {
  eq = function(got, want, msg)
    if same(got, want) then pass = pass + 1
    else fail = fail + 1
      print("FAIL: " .. (msg or ""))
      print("  want: " .. dump(want)); print("  got:  " .. dump(got))
    end
  end,
  ok = function(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. (msg or "")) end
  end,
}
dofile("dist/tests/test_text.lua")
if fs and false then end -- (appreg test added in Task 5)
print(("PinguOS tests: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
```

```lua
-- dist/tests/test_text.lua
local text = require("text")
T.eq(text.wrap("hello world", 20), {"hello world"}, "wrap fits")
T.eq(text.wrap("hello world", 5), {"hello", "world"}, "wrap splits")
T.eq(text.wrap("aaaaaa", 3), {"aaa", "aaa"}, "wrap hard-split long word")
T.eq(text.wrap("a\n\nb", 10), {"a", "", "b"}, "wrap preserves blank line")
T.eq(text.wrap("the quick brown fox", 9), {"the quick", "brown fox"}, "wrap words")
T.eq(text.wrap("", 10), {}, "wrap empty")
T.eq(text.truncate("hello", 3), "hel", "truncate long")
T.eq(text.truncate("hi", 5), "hi", "truncate short")
T.eq(text.ljust("hi", 5), "hi   ", "ljust")
T.eq(text.center("hi", 6), "  hi  ", "center")
```

- [ ] **Step 3: Run to verify it fails**

Run: `lua dist/tests/run.lua`
Expected: error — module `text` not found (or all wrap tests FAIL).
(If no Lua interpreter is available, skip to Step 4 and verify by review.)

- [ ] **Step 4: Write the module**

```lua
-- dist/os/text.lua
local text = {}

local function wrapParagraph(s, width, out)
  local line = ""
  for word in s:gmatch("%S+") do
    while #word > width do
      if line ~= "" then out[#out + 1] = line; line = "" end
      out[#out + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
end

function text.wrap(s, width)
  if width < 1 then width = 1 end
  local out = {}
  if s == "" then return out end
  for line in (s .. "\n"):gmatch("(.-)\n") do
    if line == "" then out[#out + 1] = "" else wrapParagraph(line, width, out) end
  end
  return out
end

function text.truncate(s, width)
  if #s <= width then return s end
  return s:sub(1, width)
end

function text.ljust(s, width)
  if #s >= width then return s end
  return s .. string.rep(" ", width - #s)
end

function text.center(s, width)
  if #s >= width then return s end
  local pad = width - #s
  local left = math.floor(pad / 2)
  return string.rep(" ", left) .. s .. string.rep(" ", pad - left)
end

return text
```

- [ ] **Step 5: Run to verify it passes**

Run: `lua dist/tests/run.lua`
Expected: `PinguOS tests: 10 passed, 0 failed`.
(No interpreter: confirm by review that each assertion matches the code.)

- [ ] **Step 6: Commit**

```bash
git add dist/os/text.lua dist/tests/run.lua dist/tests/test_text.lua
git commit -m "feat(os): pure text wrap/format helpers with lua test runner"
```

---

### Task 5: OS — app registry (validate + collect)

**Files:**
- Create: `dist/os/appreg.lua`
- Create: `dist/tests/test_appreg.lua`
- Modify: `dist/tests/run.lua` (load the new test file)

**Interfaces:**
- Produces:
  - `appreg.validate(app) -> ok: boolean, err: string|nil` — requires a table
    with non-empty string `id`, non-empty string `name`, and function `run`.
  - `appreg.collect(files, load) -> apps: table[], errs: table[]` — `files` is a
    list of `{ id, path }`; `load(path) -> ok, appOrErr`. Returns valid apps
    sorted by `name`, and a list of `{ id, err }` for the rest. Pure (no `fs`),
    so the kernel injects the real loader in Task 9.

- [ ] **Step 1: Write the failing test**

```lua
-- dist/tests/test_appreg.lua
local appreg = require("appreg")
T.ok(appreg.validate({ id = "x", name = "X", run = function() end }), "valid app")
T.ok(not appreg.validate({}), "missing id invalid")
T.ok(not appreg.validate("nope"), "non-table invalid")
T.ok(not appreg.validate({ id = "x", name = "X" }), "missing run invalid")

local files = {
  { id = "good", path = "good" },
  { id = "boom", path = "boom" },
  { id = "bad",  path = "bad" },
}
local function load(path)
  if path == "good" then return true, { id = "good", name = "Good", run = function() end } end
  if path == "boom" then return false, "syntax error" end
  return true, { name = "NoRun" } -- invalid: no run()
end
local apps, errs = appreg.collect(files, load)
T.eq(#apps, 1, "one valid app")
T.eq(apps[1].name, "Good", "valid app kept")
T.eq(#errs, 2, "two rejected")
```

In `dist/tests/run.lua`, replace the placeholder line
`if fs and false then end -- (appreg test added in Task 5)` with:

```lua
dofile("dist/tests/test_appreg.lua")
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua dist/tests/run.lua`
Expected: error — module `appreg` not found.

- [ ] **Step 3: Write the module**

```lua
-- dist/os/appreg.lua
local appreg = {}

function appreg.validate(app)
  if type(app) ~= "table" then return false, "not a table" end
  if type(app.id) ~= "string" or app.id == "" then return false, "missing id" end
  if type(app.name) ~= "string" or app.name == "" then return false, "missing name" end
  if type(app.run) ~= "function" then return false, "missing run()" end
  return true
end

function appreg.collect(files, load)
  local apps, errs = {}, {}
  for _, f in ipairs(files) do
    local ok, res = load(f.path)
    if not ok then
      errs[#errs + 1] = { id = f.id, err = tostring(res) }
    else
      local valid, why = appreg.validate(res)
      if valid then
        res.id = res.id or f.id
        apps[#apps + 1] = res
      else
        errs[#errs + 1] = { id = f.id, err = why }
      end
    end
  end
  table.sort(apps, function(a, b) return a.name < b.name end)
  return apps, errs
end

return appreg
```

- [ ] **Step 4: Run to verify it passes**

Run: `lua dist/tests/run.lua`
Expected: `PinguOS tests: 17 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add dist/os/appreg.lua dist/tests/test_appreg.lua dist/tests/run.lua
git commit -m "feat(os): app registry validate/collect with tests"
```

> **Verification note for Tasks 6-13:** these modules call CC APIs (`term`,
> `fs`, `colors`, `http`) that don't exist in plain `lua`, so they are not
> unit-tested locally. Verify by **review** while building, then by the
> **in-game smoke checklist in Task 14** (or incrementally in CraftOS-PC if
> installed: mount `dist/` as the computer root and `update`/reboot). In-game
> steps are **OWNER ACTIONS** (the agent cannot drive Minecraft).

---

### Task 6: OS — logging

**Files:**
- Create: `dist/os/log.lua`

**Interfaces:**
- Produces: `log.system(msg)`, `log.app(id, msg)`, `log.write(name, msg)` —
  append a timestamped line to `/logs/<name>.log`, creating `/logs` if needed.

- [ ] **Step 1: Write the module**

```lua
-- dist/os/log.lua
local log = {}
local DIR = "/logs"

local function stamp()
  local ok, s = pcall(os.date, "[%H:%M:%S] ")
  if ok and s then return s end
  return "[" .. tostring(os.clock()) .. "] "
end

function log.write(name, msg)
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  local h = fs.open(DIR .. "/" .. name .. ".log", "a")
  if h then h.writeLine(stamp() .. tostring(msg)); h.close() end
end

function log.system(msg) log.write("system", msg) end
function log.app(id, msg) log.write(id, msg) end

return log
```

- [ ] **Step 2: Commit**

```bash
git add dist/os/log.lua
git commit -m "feat(os): timestamped logging to /logs"
```

---

### Task 7: OS — config store (atomic, namespaced)

**Files:**
- Create: `dist/os/config.lua`

**Interfaces:**
- Produces:
  - `config.init()` — lazy-load `/cfg/system.json` (tolerant: corrupt JSON is
    backed up to `.bad` and replaced by `{}`).
  - `config.get(ns, key, default) -> value`
  - `config.set(ns, key, value)` — sets and persists (atomic).
  - `config.save()` — write `/cfg/system.json.tmp` then `fs.move` over the real
    file (never corrupts on power-off).

- [ ] **Step 1: Write the module**

```lua
-- dist/os/config.lua
local config = {}
local PATH = "/cfg/system.json"
local data = nil

local function load()
  data = {}
  if fs.exists(PATH) then
    local h = fs.open(PATH, "r"); local raw = h.readAll(); h.close()
    local ok, parsed = pcall(textutils.unserialiseJSON, raw)
    if ok and type(parsed) == "table" then
      data = parsed
    else
      pcall(fs.delete, PATH .. ".bad")
      pcall(fs.move, PATH, PATH .. ".bad") -- keep the corrupt file for inspection
    end
  end
end

function config.init() if not data then load() end end

function config.get(ns, key, default)
  config.init()
  local sect = data[ns]
  if type(sect) == "table" and sect[key] ~= nil then return sect[key] end
  return default
end

function config.save()
  config.init()
  if not fs.exists("/cfg") then fs.makeDir("/cfg") end
  local tmp = PATH .. ".tmp"
  local h = fs.open(tmp, "w"); h.write(textutils.serialiseJSON(data)); h.close()
  if fs.exists(PATH) then fs.delete(PATH) end
  fs.move(tmp, PATH)
end

function config.set(ns, key, value)
  config.init()
  if type(data[ns]) ~= "table" then data[ns] = {} end
  data[ns][key] = value
  config.save()
end

return config
```

- [ ] **Step 2: Smoke (CraftOS-PC or in-game — OWNER ACTION, can defer to Task 14)**

In a Lua prompt: `local c=require("config"); c.set("t","x",5); print(c.get("t","x"))`
→ prints `5`; reboot; `print(require("config").get("t","x",0))` → still `5`.

- [ ] **Step 3: Commit**

```bash
git add dist/os/config.lua
git commit -m "feat(os): atomic namespaced JSON config store"
```

---

### Task 8: OS — immediate-mode UI toolkit

**Files:**
- Create: `dist/os/ui.lua`

**Interfaces:**
- Consumes: `text.wrap` (Task 4).
- Produces (all draw on the current `term`):
  - `ui.theme` table: `bg, fg, bar, barFg, accent, error`.
  - `ui.setTheme(t)`, `ui.clear(bg?)`, `ui.fill(x,y,w,h,bg)`,
    `ui.text(x,y,s,fg?,bg?)`, `ui.center(y,s,fg?,bg?)`.
  - `ui.button(x,y,label) -> region {x,y,w,h}` and `ui.hit(region,mx,my) -> bool`.
  - `ui.titleBar(title) -> region` (the clickable close `[x]`, top-right).
  - `ui.wrap(s,width?) -> string[]`.

- [ ] **Step 1: Write the module**

```lua
-- dist/os/ui.lua
local text = require("text")
local ui = {}

ui.theme = {
  bg = colors.black, fg = colors.white,
  bar = colors.gray, barFg = colors.white,
  accent = colors.cyan, error = colors.red,
}

local function safe(c) -- degrade gracefully on non-advanced computers
  if term.isColour() then return c end
  if c == colors.black then return colors.black end
  if c == colors.gray or c == colors.lightGray then return colors.lightGray end
  return colors.white
end

function ui.setTheme(t) for k, v in pairs(t) do ui.theme[k] = v end end

function ui.clear(bg)
  term.setBackgroundColor(safe(bg or ui.theme.bg))
  term.setTextColor(safe(ui.theme.fg))
  term.clear(); term.setCursorPos(1, 1)
end

function ui.fill(x, y, w, h, bg)
  term.setBackgroundColor(safe(bg))
  local row = string.rep(" ", w)
  for i = 0, h - 1 do term.setCursorPos(x, y + i); term.write(row) end
end

function ui.text(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  if fg then term.setTextColor(safe(fg)) end
  if bg then term.setBackgroundColor(safe(bg)) end
  term.write(s)
end

function ui.center(y, s, fg, bg)
  local w = term.getSize()
  ui.text(math.max(1, math.floor((w - #s) / 2) + 1), y, s, fg, bg)
end

function ui.button(x, y, label)
  local s = " " .. label .. " "
  ui.text(x, y, s, ui.theme.barFg, ui.theme.accent)
  return { x = x, y = y, w = #s, h = 1 }
end

function ui.hit(r, mx, my)
  return r ~= nil and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function ui.titleBar(title)
  local w = term.getSize()
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.text(2, 1, title, ui.theme.barFg, ui.theme.bar)
  local close = " x "
  ui.text(w - #close + 1, 1, close, ui.theme.barFg, ui.theme.error)
  return { x = w - #close + 1, y = 1, w = #close, h = 1 }
end

function ui.wrap(s, width)
  return text.wrap(s, width or (select(1, term.getSize())))
end

return ui
```

- [ ] **Step 2: Commit**

```bash
git add dist/os/ui.lua
git commit -m "feat(os): immediate-mode UI toolkit"
```

---

### Task 9: OS — kernel + boot

**Files:**
- Create: `dist/os/kernel.lua`
- Create: `dist/startup.lua`

**Interfaces:**
- Consumes: `ui`, `log`, `config`, `appreg`, `text`.
- Produces: `kernel.run()` (never returns under normal use); `kernel.version`
  string; `ctx` shape for apps: `{ ui, term, width, height, log(msg),
  config.get(k,d)/set(k,v), sys.version/theme/openApp(id) }`.

- [ ] **Step 1: Write the kernel**

```lua
-- dist/os/kernel.lua
package.path = "/os/?.lua;" .. package.path
local ui = require("ui")
local log = require("log")
local config = require("config")
local appreg = require("appreg")
local text = require("text")

local kernel = { version = "0.1.0", pending = nil }
local APP_DIR = "/os/apps"

local function loadApp(path)
  local fn, err = loadfile(path)
  if not fn then return false, err end
  local ok, res = pcall(fn)
  if not ok then return false, res end
  return true, res
end

local function discover()
  local files = {}
  if fs.exists(APP_DIR) then
    for _, name in ipairs(fs.list(APP_DIR)) do
      if name:match("%.lua$") then
        files[#files + 1] = { id = name:gsub("%.lua$", ""), path = APP_DIR .. "/" .. name }
      end
    end
  end
  local apps, errs = appreg.collect(files, loadApp)
  for _, e in ipairs(errs) do log.system("app '" .. e.id .. "' skipped: " .. e.err) end
  return apps
end

local function makeCtx(app)
  local w, h = term.getSize()
  return {
    ui = ui, term = term, width = w, height = h,
    log = function(msg) log.app(app.id, msg) end,
    config = {
      get = function(k, d) return config.get(app.id, k, d) end,
      set = function(k, v) return config.set(app.id, k, v) end,
    },
    sys = {
      version = kernel.version, theme = ui.theme,
      openApp = function(id) kernel.pending = id end,
      getSetting = function(k, d) return config.get("system", k, d) end,
      setSetting = function(k, v) return config.set("system", k, v) end,
    },
  }
end

local function runApp(app)
  ui.clear()
  local ok, err = pcall(app.run, makeCtx(app))
  if not ok then
    log.app(app.id, "CRASH: " .. tostring(err))
    ui.clear()
    local _, h = term.getSize()
    ui.center(math.floor(h / 2), "App '" .. app.name .. "' fallo", ui.theme.error)
    ui.center(math.floor(h / 2) + 1, "Pulsa una tecla para volver", ui.theme.fg)
    os.pullEvent("key")
  end
end

local function drawClock()
  local w = term.getSize()
  local clk = textutils.formatTime(os.time(), true)
  ui.text(w - #clk, 1, clk, ui.theme.barFg, ui.theme.bar)
end

local function drawDesktop(apps)
  ui.clear()
  local w = term.getSize()
  ui.fill(1, 1, w, 1, ui.theme.bar)
  ui.text(2, 1, "PinguOS", ui.theme.accent, ui.theme.bar)
  drawClock()
  local regions, cols = {}, math.max(1, math.floor(w / 12))
  for i, app in ipairs(apps) do
    local n = i - 1
    local cx = 2 + (n % cols) * 12
    local cy = 3 + math.floor(n / cols) * 5
    ui.fill(cx, cy, 9, 3, app.color or ui.theme.accent)
    ui.text(cx + 4, cy + 1, app.icon or "?", ui.theme.bg, app.color or ui.theme.accent)
    ui.text(cx, cy + 3, text.truncate(app.name, 11), ui.theme.fg, ui.theme.bg)
    regions[#regions + 1] = { r = { x = cx, y = cy, w = 9, h = 3 }, app = app }
  end
  return regions
end

function kernel.run()
  config.init()
  local accent = config.get("system", "accent")
  if accent then ui.setTheme({ accent = accent }) end
  log.system("PinguOS " .. kernel.version .. " booting")
  local apps = discover()
  while true do
    local regions = drawDesktop(apps)
    local timer = os.startTimer(1)
    local redraw = false
    while not redraw do
      local ev = { os.pullEvent() }
      if ev[1] == "timer" and ev[2] == timer then
        drawClock(); timer = os.startTimer(1)
      elseif ev[1] == "mouse_click" then
        for _, item in ipairs(regions) do
          if ui.hit(item.r, ev[3], ev[4]) then runApp(item.app); redraw = true; break end
        end
      elseif ev[1] == "term_resize" then
        redraw = true
      end
      if kernel.pending then
        for _, app in ipairs(apps) do
          if app.id == kernel.pending then runApp(app); break end
        end
        kernel.pending = nil; redraw = true
      end
    end
  end
end

return kernel
```

- [ ] **Step 2: Write the boot entry**

```lua
-- dist/startup.lua
package.path = "/os/?.lua;" .. package.path
local ok, err = pcall(function()
  require("kernel").run()
end)
if not ok then
  term.setBackgroundColor(colors.blue); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  print("PinguOS panic:")
  print(tostring(err))
  print("")
  print("Press T for the shell.")
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.t then
      term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1); return
    end
  end
end
```

- [ ] **Step 3: Smoke (OWNER ACTION, full check in Task 14)**

After Task 14 install: power on → top bar shows "PinguOS" + clock; desktop shows
app tiles; clicking a tile opens it; the panic screen never appears on boot.

- [ ] **Step 4: Commit**

```bash
git add dist/os/kernel.lua dist/startup.lua
git commit -m "feat(os): kernel boot, desktop, taskbar, app launch under pcall"
```

---

### Task 10: Apps — About (template) + Terminal

**Files:**
- Create: `dist/os/apps/about.lua`
- Create: `dist/os/apps/terminal.lua`

**Interfaces:**
- Consumes: the `ctx` contract (Task 9). Each file returns an app table.
- Produces: two discoverable apps. `about.lua` doubles as the copy-me template.

- [ ] **Step 1: Write About**

```lua
-- dist/os/apps/about.lua  (also: the "hello world" template — copy to start an app)
return {
  id = "about", name = "Acerca de", icon = "i", color = colors.lightBlue,
  desc = "Info de PinguOS",
  run = function(ctx)
    local close = ctx.ui.titleBar("Acerca de")
    ctx.ui.text(2, 3, "PinguOS " .. ctx.sys.version, colors.white, colors.black)
    local body = "Escritorio para CC: Tweaked. Las apps viven en /os/apps/. " ..
                 "Clic en [x] (o tecla Q) para volver al escritorio."
    local y = 5
    for _, line in ipairs(ctx.ui.wrap(body, ctx.width - 2)) do
      ctx.ui.text(2, y, line, colors.white, colors.black); y = y + 1
    end
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" and ctx.ui.hit(close, ev[3], ev[4]) then return end
      if ev[1] == "key" and ev[2] == keys.q then return end
    end
  end,
}
```

- [ ] **Step 2: Write Terminal**

```lua
-- dist/os/apps/terminal.lua
return {
  id = "terminal", name = "Terminal", icon = ">", color = colors.gray,
  desc = "Shell de CraftOS",
  run = function(ctx)
    ctx.ui.clear()
    term.setTextColor(colors.white)
    print("CraftOS shell. Escribe 'exit' para volver a PinguOS.")
    shell.run("shell")
  end,
}
```

- [ ] **Step 3: Commit**

```bash
git add dist/os/apps/about.lua dist/os/apps/terminal.lua
git commit -m "feat(apps): about (template) and terminal escape hatch"
```

---

### Task 11: App — Settings (theme + bridge URL)

**Files:**
- Create: `dist/os/apps/settings.lua`

**Interfaces:**
- Consumes: `ctx.ui`, `ctx.sys.getSetting/setSetting` (system-scoped settings;
  defined in Task 9's `makeCtx`). The accent is stored as a `colors.*` number.

- [ ] **Step 1: Write the app**

```lua
-- dist/os/apps/settings.lua
return {
  id = "settings", name = "Ajustes", icon = "*", color = colors.orange,
  desc = "Tema y conexion",
  run = function(ctx)
    local ui = ctx.ui
    local accents = { colors.cyan, colors.lime, colors.orange, colors.magenta, colors.red }
    local names   = { "cyan", "lime", "orange", "magenta", "red" }
    while true do
      ui.clear()
      local close = ui.titleBar("Ajustes")
      ui.text(2, 3, "Color de acento:", colors.white, colors.black)
      local btns = {}
      for i = 1, #accents do
        local x = 2 + (i - 1) * 9
        ui.fill(x, 5, 8, 1, accents[i])
        ui.text(x, 5, " " .. names[i], colors.black, accents[i])
        btns[i] = { x = x, y = 5, w = 8, h = 1 }
      end
      ui.text(2, 8, "Bridge URL:", colors.white, colors.black)
      ui.text(2, 9, ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080"),
              colors.lightGray, colors.black)
      local editBtn = ui.button(2, 11, "Editar URL")
      local ev = { os.pullEvent() }
      if ev[1] == "mouse_click" then
        if ui.hit(close, ev[3], ev[4]) then return end
        for i = 1, #btns do
          if ui.hit(btns[i], ev[3], ev[4]) then
            ui.setTheme({ accent = accents[i] })
            ctx.sys.setSetting("accent", accents[i])
          end
        end
        if ui.hit(editBtn, ev[3], ev[4]) then
          ui.clear(); ui.titleBar("Bridge URL")
          ui.text(2, 3, "Nueva URL (Enter para guardar):", colors.white, colors.black)
          term.setCursorPos(2, 5); term.setTextColor(colors.white)
          local input = read(nil, nil, nil, ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080"))
          if input and #input > 0 then ctx.sys.setSetting("bridgeUrl", input) end
        end
      end
    end
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add dist/os/apps/settings.lua
git commit -m "feat(apps): settings for accent theme and bridge URL"
```

---

### Task 12: App — Update (pull latest + reboot)

**Files:**
- Create: `dist/os/apps/update.lua`

**Interfaces:**
- Consumes: bridge routes `/manifest` and `/fs/<path>` (Task 3);
  `ctx.sys.getSetting("bridgeUrl", ...)`.

- [ ] **Step 1: Write the app**

```lua
-- dist/os/apps/update.lua
return {
  id = "update", name = "Update", icon = "@", color = colors.green,
  desc = "Actualizar desde el bridge",
  run = function(ctx)
    ctx.ui.clear(); ctx.ui.titleBar("Update")
    local base = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    ctx.ui.text(2, 3, "Bajando de " .. base, colors.white, colors.black)
    local h = http.get(base .. "/manifest")
    if not h then
      ctx.ui.text(2, 5, "No hay bridge. Esta corriendo?", colors.red, colors.black)
      ctx.ui.text(2, 7, "Pulsa una tecla", colors.white, colors.black)
      os.pullEvent("key"); return
    end
    local m = textutils.unserialiseJSON(h.readAll()); h.close()
    for _, f in ipairs(m.files) do
      local fh = http.get(base .. "/fs" .. f.path)
      if fh then
        local data = fh.readAll(); fh.close()
        local d = f.path:match("^(.*)/[^/]+$")
        if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
        local tmp = f.path .. ".tmp"
        local out = fs.open(tmp, "w"); out.write(data); out.close()
        if fs.exists(f.path) then fs.delete(f.path) end
        fs.move(tmp, f.path)
        ctx.log("updated " .. f.path)
      end
    end
    ctx.ui.text(2, 5, "Actualizado a " .. (m.version or "?") .. ". Reiniciando...",
                colors.lime, colors.black)
    sleep(1); os.reboot()
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add dist/os/apps/update.lua
git commit -m "feat(apps): in-place update from the bridge"
```

---

### Task 13: App — Claude chat (port of `claude.lua`)

**Files:**
- Create: `dist/os/apps/claude.lua`

**Interfaces:**
- Consumes: `ctx.ui.wrap/titleBar/clear`, `ctx.sys.getSetting("bridgeUrl", ...)`,
  bridge `POST /` returning `{ text }` or `{ error }`.
- Behavior: async request + spinner (so it never looks frozen), word-wrap to
  screen width, ASCII sanitize, `exit`/`reset` commands, `[x]` title bar.

- [ ] **Step 1: Write the app**

```lua
-- dist/os/apps/claude.lua
return {
  id = "claude", name = "Claude", icon = "C", color = colors.cyan,
  desc = "Chat con Claude",
  run = function(ctx)
    local ui = ctx.ui
    local url = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    local w = term.getSize()
    ui.clear(); ui.titleBar("Claude")
    term.setCursorPos(1, 3)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)

    local function colour(c) if term.isColour() then term.setTextColor(c) end end
    local function sanitize(s) return (s:gsub("\r", ""):gsub("[^\n\t -~]", "")) end

    local function say(body)
      body = sanitize(body)
      colour(colors.cyan); term.write("claude > "); colour(colors.white)
      local lines = ui.wrap(body, w)
      if #lines <= 1 and (9 + #(lines[1] or "")) <= w then
        print(lines[1] or "")
      else
        print()
        for _, ln in ipairs(lines) do print(ln) end
      end
    end

    local function request(bodyTable)
      http.request({
        url = url, body = textutils.serialiseJSON(bodyTable),
        headers = { ["Content-Type"] = "application/json" }, timeout = 120,
      })
      local frames, fi = "|/-\\", 1
      term.write("claude esta pensando... ")
      local hx, hy = term.getCursorPos()
      local tid = os.startTimer(0.15)
      while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "timer" and a == tid then
          term.setCursorPos(hx, hy); term.write(frames:sub(fi, fi))
          fi = fi % #frames + 1; tid = os.startTimer(0.15)
        elseif ev == "http_success" then        -- a=url, b=handle
          local raw = b.readAll(); b.close()
          term.setCursorPos(1, hy); term.clearLine()
          return raw, nil
        elseif ev == "http_failure" then         -- a=url, b=errmsg, c=handle?
          local raw = nil; if c then raw = c.readAll(); c.close() end
          term.setCursorPos(1, hy); term.clearLine()
          return raw, (b or "request failed")
        end
      end
    end

    local function handle(raw, err)
      if err and not raw then
        printError("error: " .. tostring(err))
        printError("(bridge encendido en " .. url .. " ?)")
        return
      end
      local ok, data = pcall(textutils.unserialiseJSON, raw)
      if ok and data and data.text then say(data.text)
      elseif ok and data and data.error then printError("bridge: " .. tostring(data.error))
      else say(raw or "(sin respuesta)") end
    end

    print("Claude listo. 'exit' vuelve al escritorio, 'reset' olvida la charla.")
    while true do
      print()
      colour(colors.yellow); term.write("you > "); colour(colors.white)
      local msg = read()
      if msg == nil then return end
      msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
      if msg == "exit" or msg == "quit" then return
      elseif msg == "reset" then handle(request({ reset = true }))
      elseif #msg > 0 then handle(request({ prompt = msg })) end
    end
  end,
}
```

- [ ] **Step 2: Commit**

```bash
git add dist/os/apps/claude.lua
git commit -m "feat(apps): Claude chat client as a PinguOS app"
```

---

### Task 14: Bring-up — allow localhost, install, full in-game smoke

This is where everything meets the game. Most steps are **OWNER ACTIONS**.

**Files:**
- Modify: world `serverconfig/computercraft-server.toml` (owner's machine, not in repo)
- Modify: `README.md` (Create) — quick-start for future sessions

**Interfaces:**
- Consumes: the bridge (Tasks 1-3) serving `DIST_DIR=dist`; all OS files (Tasks 4-13).

- [ ] **Step 1: Allow `127.0.0.1` in CC:T (OWNER ACTION, once per world)**

Quit to the title screen (so the world is unloaded). Open the world's config:
`…/saves/<WorldName>/serverconfig/computercraft-server.toml`
(modded launchers: under that instance's saves folder). Add this as the **first**
`[[http.rules]]` block, above the `$private` deny:

```toml
[[http.rules]]
	host = "127.0.0.1"
	action = "allow"
```

Save, then load the world again.

- [ ] **Step 2: Start the bridge serving `dist/` (PC)**

Run: `OS_VERSION=0.1.0 DIST_DIR=./dist node claude-bridge.js`
Expected: `claude-bridge listening on http://127.0.0.1:8080`.
Sanity (PC): `curl -s http://127.0.0.1:8080/manifest` lists the OS files.

- [ ] **Step 3: Install in-game (OWNER ACTION)**

On the Advanced Computer:
```
wget run http://127.0.0.1:8080/install
```
Expected: it prints each `/…` path, then `PinguOS 0.1.0 installed. Rebooting...`,
then boots into the desktop.

- [ ] **Step 4: Smoke checklist (OWNER ACTION) — report results / share `/logs`**

- [ ] Boots to desktop: top bar `PinguOS` + clock; 5 tiles (About, Ajustes,
      Claude, Terminal, Update). No panic screen.
- [ ] Click **About** → shows version; `[x]` or `Q` returns to desktop.
- [ ] Click **Terminal** → CraftOS shell; `exit` returns.
- [ ] Click **Ajustes** → click an accent color → click **Update** later and
      confirm the accent persists across reboot (proves config + atomic save).
- [ ] Click **Claude** → type "hola"; spinner shows; reply word-wraps and is
      ASCII-clean; `reset` then `exit` work. (Bridge must be running.)
- [ ] Click **Update** → re-pulls and reboots cleanly.
- [ ] Crash isolation: temporarily add a bad app
      (`echo 'return {id="x"}' > dist/os/apps/x.lua` on PC, run Update) → it is
      skipped, logged in `/logs/system.log`, desktop still works. Remove it after.

- [ ] **Step 5: Write README quick-start and commit**

```markdown
# PinguOS

A small desktop OS for a CC: Tweaked Advanced Computer, plus a Node bridge that
serves it and relays a Claude chat app.

## Run
1. Allow `127.0.0.1` in the world's `serverconfig/computercraft-server.toml`
   (see `specs/pinguos/plan.md`, Task 14).
2. PC: `DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`
3. In-game (Advanced Computer): `wget run http://127.0.0.1:8080/install`
4. After install it reboots into the desktop. To update later: the **Update** app.

## Tests
- Bridge (local): `node --test`
- OS pure modules: `lua dist/tests/run.lua` (or in CraftOS-PC)

## Layout
- `dist/` — the in-game OS (source of truth; served by the bridge)
- `bridge/` — bridge logic (ascii, manifest, install)
- `specs/pinguos/` — design + plan
```

```bash
git add README.md
git commit -m "docs: add PinguOS quick-start readme"
```

---

## Done criteria

v1 is complete when: the desktop boots with all 5 app tiles; each app runs and
returns cleanly; settings persist across reboot; the Claude app chats through the
bridge with wrapped ASCII output; `Update` re-pulls and reboots; a broken app is
skipped without crashing the OS; `node --test` is green; the Lua pure-module
tests pass (where a runtime is available).
