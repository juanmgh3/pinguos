# Going Public Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repo safe and verifiable enough to open to the public: close four bridge vulnerabilities, prove every change with CI, and write down the conventions that keep the repo readable.

**Architecture:** The bridge gains four independent request guards, each landed test-first against the existing `node --test` suite. CI runs the three suites that already exist plus a parse check against both Lua versions this code has to satisfy. Conventions move into `AGENTS.md` so any agentic CLI reads the same rules.

**Tech Stack:** Node 24 (zero dependencies, `node:test`), Lua 5.1 and 5.4, GitHub Actions, `gh` CLI.

## Global Constraints

- **No npm dependencies.** There is no `package.json` and none is added. `node --test` and `node:` builtins only.
- **Rendered text must be ASCII.** The CC terminal is 8-bit: no unicode, no emoji.
- **Lua must parse under 5.1 and 5.4.** Use `math.atan2 or math.atan`; `math.floor` before `string.format("%d", n)`.
- **Lua test runners run from the repo root.** They use relative `dofile` paths.
- **Apps depend only on `ctx`.** Never `require` inside an app.
- **Commits:** Conventional Commits, English, no emoji.
- **Writing style:** no emoji, no "This PR introduces", no restating the diff, no "Note that", no praise openers, no "comprehensive/robust/seamless/leverage".
- Local Lua 5.4: `C:\Users\juanm\AppData\Local\Programs\Lua\bin\lua.exe`, `luac.exe` alongside it.

**Baseline before any change:** 161 tests pass (23 bridge, 90 OS, 48 turtle).

## Branch workflow

This spec and plan live on `chore/public-infra`. **Every task gets its own
branch off `main`**, its own PR, and a squash merge. Nothing is stacked, so a
rejected task never blocks its neighbours.

Before starting task N:

```bash
git checkout main && git pull
git checkout -b <branch-for-task-N>
```

After the task's commits, open the PR and wait for checks:

```bash
git push -u origin <branch-for-task-N>
gh pr create --fill
gh pr checks --watch
```

Merge only on green:

```bash
gh pr merge --squash --delete-branch
```

Task 2 is the exception in one respect: it creates the checks that every later
PR waits on, so it merges before any other task starts.

Branch names, in order:

| Task | Branch |
| --- | --- |
| 1 | `chore/line-endings` |
| 2 | `ci/verify-every-change` |
| 3 | `fix/bridge-host-check` |
| 4 | `fix/bridge-body-cap` |
| 5 | `fix/bridge-symlink-escape` |
| 6 | `feat/bridge-token` |
| 7 | `feat/bridge-token-clients` |
| 8 | `docs/security-policy` |
| 9 | `chore/github-templates` |
| 10 | `docs/agents-md` |
| 11 | `chore/repo-settings` |
| 12 | `docs/review-stat` |

---

### Task 1: Normalize line endings

Committing from Windows produces `LF will be replaced by CRLF` warnings. Once the repo is public, contributors on other platforms will generate whole-file diffs that bury the real change. Fix before writing any code, so no later task carries the noise.

**Files:**
- Create: `.gitattributes`

- [ ] **Step 1: Create `.gitattributes`**

```gitattributes
* text=auto eol=lf

*.png binary
*.jpg binary
*.gif binary
```

- [ ] **Step 2: Renormalize the working tree**

Run: `git add --renormalize .`
Then: `git status --short`

Expected: either no output, or a list of files whose stored line endings changed. Both are fine.

- [ ] **Step 3: Confirm tests still pass**

Run: `node --test`
Expected: `pass 23`, `fail 0`

- [ ] **Step 4: Commit**

```bash
git add .gitattributes
git commit -m "chore: normalize line endings via .gitattributes"
```

---

### Task 2: CI workflow

CI lands before any code change so every later task merges against a green check. It runs the suites that already exist — nothing here should fail on first run.

The `syntax` job checks with **both** Lua versions on purpose. CC: Tweaked runs 5.1 and the dev machine runs 5.4; checking only 5.4 would let 5.3+ syntax through to a crash in-game. A grep for `//`, `goto` and bitwise operators found no 5.3+ syntax currently in the tree, so 5.1 should pass — the first CI run is what actually proves it.

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: three required check names — `bridge`, `lua`, `syntax` — referenced by branch protection in phase 2.

- [ ] **Step 1: Create the workflow**

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  bridge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
      - uses: actions/setup-node@a0853c24544627f65ddf259abe73b1d18a591444 # v5
        with:
          node-version: '24'
      - run: node --test

  lua:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
      - run: sudo apt-get update && sudo apt-get install -y lua5.4
      - run: lua5.4 dist/tests/run.lua
      - run: lua5.4 turtle/tests/run.lua

  syntax:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
      - run: sudo apt-get update && sudo apt-get install -y lua5.1 lua5.4
      - name: Tools are present
        run: which luac5.1 luac5.4
      - name: Parse under 5.1, the version CC runs
        run: find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -r -n1 luac5.1 -p
      - name: Parse under 5.4, the version the dev machine runs
        run: find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -r -n1 luac5.4 -p
```

- [ ] **Step 2: Verify locally what can be verified locally**

Run the three suites from the repo root:

```bash
node --test
"C:/Users/juanm/AppData/Local/Programs/Lua/bin/lua.exe" dist/tests/run.lua
"C:/Users/juanm/AppData/Local/Programs/Lua/bin/lua.exe" turtle/tests/run.lua
```

Expected: `pass 23 / fail 0`, `90 passed, 0 failed`, `48 passed, 0 failed`.

The apt install and `luac5.1` availability cannot be checked from Windows. The first CI run is the check. If `which luac5.1` fails, the Debian package name is wrong and the fix is to add `liblua5.1-0-dev` to that install line.

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run bridge, lua and parse checks on every pull request"
git push -u origin ci/verify-every-change
```

- [ ] **Step 4: Open the PR and watch the checks**

```bash
gh pr create --title "ci: verify every change" \
  --body "Runs the three existing suites on every PR, plus a luac parse check under both 5.1 (what CC runs) and 5.4 (what the dev machine runs).

Verified: 161 tests pass locally. The apt install and luac5.1 availability can only be proved by this run."
gh pr checks --watch
```

Expected: three checks pass. If `syntax` fails on a 5.1 parse error, that is a real bug in the file it names — fix it in this PR.

If `which luac5.1` fails, the Debian package does not ship it under that name. Check what landed with `dpkg -L lua5.1 | grep bin` in a scratch step and adjust.

- [ ] **Step 5: Merge, so later PRs get checks**

```bash
gh pr merge --squash --delete-branch
```

---

### Task 3: Reject non-loopback Host headers

DNS rebinding is the standard attack on a loopback service: a hostile page points its own domain at `127.0.0.1` and its requests arrive same-origin. Origin/Referer checks cover the chat route only; pinning `Host` closes every route at once.

**Files:**
- Modify: `claude-bridge.js`
- Test: `test/server.test.js`

**Interfaces:**
- Produces: `hostAllowed(hostHeader) -> boolean`, module-local in `claude-bridge.js`.

- [ ] **Step 1: Let the test helper send headers**

In `test/server.test.js`, replace the `get` helper:

```js
function get(p, headers) {
  // options form (not a URL string) so the path is sent verbatim — a URL
  // string would normalize "/fs/%2e%2e/x" to "/x" before it reaches the server.
  return new Promise((res) => {
    http
      .request({ host: "127.0.0.1", port: 8099, path: p, method: "GET", headers }, (r) => {
        let b = "";
        r.on("data", (c) => (b += c));
        r.on("end", () => res({ code: r.statusCode, body: b }));
      })
      .end();
  });
}
```

- [ ] **Step 2: Write the failing test**

Append to `test/server.test.js`:

```js
test("rejects a Host that is not loopback (DNS rebinding)", async () => {
  const r = await get("/manifest", { Host: "evil.example" });
  assert.equal(r.code, 403);
});

test("accepts loopback Host with a port", async () => {
  const r = await get("/manifest", { Host: "localhost:8099" });
  assert.equal(r.code, 200);
});
```

- [ ] **Step 3: Run it and watch it fail**

Run: `node --test`
Expected: FAIL on "rejects a Host that is not loopback" — got 200, expected 403.

- [ ] **Step 4: Implement**

In `claude-bridge.js`, add above `const server = http.createServer(...)`:

```js
// DNS rebinding: a hostile page can point its own domain at 127.0.0.1, so its
// requests reach this server looking same-origin. Pinning Host shuts that down
// for every route at once. The CC: Tweaked client sends no Host, hence the
// permissive nil case.
function hostAllowed(h) {
  if (!h) return true;
  const name = h.startsWith("[") ? h.slice(1, h.indexOf("]")) : h.split(":")[0];
  return name === "127.0.0.1" || name === "localhost" || name === "::1";
}
```

Then make it the first thing the handler does:

```js
const server = http.createServer((req, res) => {
  if (!hostAllowed(req.headers.host)) {
    res.writeHead(403).end("bad host");
    return;
  }

  // --- OS install/update static routes ---
```

- [ ] **Step 5: Run the tests**

Run: `node --test`
Expected: `pass 25`, `fail 0`

- [ ] **Step 6: Commit**

```bash
git add claude-bridge.js test/server.test.js
git commit -m "fix(bridge): reject non-loopback Host headers

Origin and Referer checks only guarded the chat route. A page that resolves its
own domain to 127.0.0.1 reaches every other route unchallenged."
```

---

### Task 4: Cap the request body

`body += c` with no ceiling lets any local client grow the process until it dies.

**Files:**
- Modify: `claude-bridge.js`
- Test: `test/server.test.js`

- [ ] **Step 1: Write the failing test**

Append to `test/server.test.js`:

```js
test("POST rejects a body over the size cap", async () => {
  const r = await post("/", JSON.stringify({ prompt: "x".repeat(70 * 1024) }), {
    "Content-Type": "application/json",
  });
  assert.equal(r.code, 413);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test`
Expected: FAIL — got 200 or 500, expected 413.

- [ ] **Step 3: Implement**

In `claude-bridge.js`, add near the other constants at the top:

```js
const MAX_BODY = 64 * 1024;
```

Replace the body accumulation block:

```js
  let body = "";
  let tooBig = false;
  req.on("data", (c) => {
    if (tooBig) return;
    body += c;
    if (body.length > MAX_BODY) {
      // Answer immediately and stop accumulating, but let the socket drain on
      // its own: destroying it here races the response and the client sees
      // ECONNRESET instead of the 413.
      tooBig = true;
      body = "";
      res.writeHead(413).end("body too large");
    }
  });
  req.on("end", async () => {
    if (tooBig) return;
    let prompt = "";
```

The rest of the `end` handler is unchanged.

- [ ] **Step 4: Run the tests**

Run: `node --test`
Expected: `pass 26`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add claude-bridge.js test/server.test.js
git commit -m "fix(bridge): cap request bodies at 64 KB

An unbounded body let any local client grow the process until it died."
```

---

### Task 5: Resolve symlinks in `safeFsPath`

`path.resolve` normalizes `..` but does not follow links, so a symlink planted inside `dist/` still points wherever it likes.

**Files:**
- Modify: `bridge/fspath.js`
- Test: `test/fspath.test.js`, `test/server.test.js`

**Interfaces:**
- Consumes: `safeFsPath(distDir, urlPath) -> string | null`, unchanged signature.

- [ ] **Step 1: Write the failing test**

Append to `test/server.test.js`:

```js
test("GET /fs blocks a symlink that escapes the dist dir", {
  skip: process.platform === "win32" ? "symlinks need admin rights on Windows" : false,
}, async () => {
  const outside = path.join(os.tmpdir(), "pinguos-outside.txt");
  fs.writeFileSync(outside, "not yours");
  fs.symlinkSync(outside, path.join(dist, "escape.lua"));
  const r = await get("/fs/escape.lua");
  assert.equal(r.code, 404);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test`
Expected on Linux/CI: FAIL — got 200 with body `not yours`, expected 404.
Expected on Windows: the test reports as skipped. That is why this one is proved by CI, not locally.

- [ ] **Step 3: Implement**

Replace `bridge/fspath.js` entirely:

```js
// bridge/fspath.js
const path = require("node:path");
const fs = require("node:fs");

// Resolve an in-game /fs/<urlPath> request to an absolute file path inside
// distDir, or null if it escapes. distDir may be relative or absolute; both the
// base and the resolved path are normalized to absolute so the containment
// check is reliable regardless of how DIST_DIR was passed.
function safeFsPath(distDir, urlPath) {
  const base = path.resolve(distDir);
  let rel;
  try {
    rel = decodeURIComponent(urlPath);
  } catch {
    return null;
  }
  const abs = path.resolve(base, rel);
  if (abs !== base && !abs.startsWith(base + path.sep)) return null;

  // resolve() flattens ".." but does not follow links, so a symlink planted
  // inside distDir still points wherever it likes. Re-check the real path.
  // A missing file throws here and returns null, which the caller 404s anyway.
  try {
    const realBase = fs.realpathSync(base);
    const real = fs.realpathSync(abs);
    if (real !== realBase && !real.startsWith(realBase + path.sep)) return null;
  } catch {
    return null;
  }
  return abs;
}
module.exports = { safeFsPath };
```

- [ ] **Step 4: Run the tests**

Run: `node --test`
Expected: `pass 27` on Linux, `pass 26` plus one skip on Windows. `fail 0` either way.

Check `test/fspath.test.js` still passes — its cases use paths that may not exist on disk, which now return null. If a case regressed, it was asserting on a non-existent path; point it at a real file in the temp dist dir rather than loosening the check.

- [ ] **Step 5: Commit**

```bash
git add bridge/fspath.js test/server.test.js test/fspath.test.js
git commit -m "fix(bridge): follow symlinks before the containment check

path.resolve flattens '..' but does not follow links, so a symlink inside
dist/ escaped the check and served any file the process could read."
```

---

### Task 6: Require a token on the chat route

`POST /` drives a tool-capable Claude with `cwd` set to the repo. Anything that reaches it runs arbitrary code as the user.

The custom header is a second CSRF layer for free: a cross-origin request carrying `X-Bridge-Token` triggers a CORS preflight that this server never answers, so the browser blocks it before it is sent.

**Files:**
- Modify: `claude-bridge.js`
- Test: `test/server.test.js`

**Interfaces:**
- Produces: `TOKEN` (string) exported from `claude-bridge.js`; `tokenOk(given) -> boolean`, module-local. Task 7 consumes `TOKEN`.
- Header name: `X-Bridge-Token`.

- [ ] **Step 1: Pin a token in the test environment**

In `test/server.test.js`, alongside the existing env setup near the top:

```js
process.env.DIST_DIR = dist;
process.env.OS_VERSION = "9.9.9";
process.env.PORT = "8099";
process.env.BRIDGE_TOKEN = "test-token";
const { server, start } = require("../claude-bridge.js");
```

- [ ] **Step 2: Write the failing tests**

Append to `test/server.test.js`:

```js
test("POST chat rejects a missing token", async () => {
  const r = await post("/", JSON.stringify({ reset: true }), {
    "Content-Type": "application/json",
  });
  assert.equal(r.code, 401);
});

test("POST chat rejects a wrong token", async () => {
  const r = await post("/", JSON.stringify({ reset: true }), {
    "Content-Type": "application/json",
    "X-Bridge-Token": "wrong-token",
  });
  assert.equal(r.code, 401);
});
```

Then update the two existing tests that expect a successful POST. `POST reset works with application/json from a non-browser client` becomes:

```js
test("POST reset works with application/json from a non-browser client", async () => {
  const r = await post("/", JSON.stringify({ reset: true }), {
    "Content-Type": "application/json",
    "X-Bridge-Token": "test-token",
  });
  assert.equal(r.code, 200);
  assert.match(r.body, /borrada/);
});
```

The 415 and 403 tests stay as they are: those guards run before the token check, so they still return 415 and 403 without a token.

- [ ] **Step 3: Run and watch them fail**

Run: `node --test`
Expected: FAIL on both new tests — got 200, expected 401.

- [ ] **Step 4: Implement**

In `claude-bridge.js`, add to the requires:

```js
const crypto = require("node:crypto");
```

Add below the other constants:

```js
// POST / drives a tool-capable Claude, so reaching it must take a secret. The
// installer bakes this into the generated client, which keeps the one-line
// in-game install working. Handing it out over an open GET is deliberate: a
// hostile page cannot read a cross-origin GET body without CORS, and that page
// is the attacker this defends against.
const TOKEN = process.env.BRIDGE_TOKEN || crypto.randomBytes(16).toString("hex");

// Constant-time compare so a wrong token leaks nothing through response timing.
function tokenOk(given) {
  const a = Buffer.from(String(given || ""));
  const b = Buffer.from(TOKEN);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

In the chat route, immediately after the cross-origin check and before `let body = ""`:

```js
  if (!tokenOk(req.headers["x-bridge-token"])) {
    res.writeHead(401).end("bad or missing token");
    return;
  }
```

Print it at startup, inside `start()` after the existing `console.log` lines:

```js
      console.log(`token: ${TOKEN}`);
```

Export it:

```js
module.exports = { server, start, TOKEN };
```

- [ ] **Step 5: Run the tests**

Run: `node --test`
Expected: `pass 29` on Linux, `fail 0`.

- [ ] **Step 6: Commit**

```bash
git add claude-bridge.js test/server.test.js
git commit -m "feat(bridge): require a token on the chat route

POST / spawns claude with cwd set to the repo, so anything that could reach it
ran arbitrary code as the user. Compared in constant time; GET routes stay open
so the one-line install keeps working."
```

---

### Task 7: Deliver the token to the in-game clients

Two clients POST to the bridge: the OS app `dist/os/apps/claude.lua`, and the standalone `claude.lua` served over `GET /claude.lua`. Both need the token without breaking the one-line install.

The OS app already reads `bridgeUrl` through `ctx.sys.getSetting`, which maps to the `system` namespace of `/cfg/system.json`. The token rides the same path: the generated installer merges it into that file.

**Files:**
- Modify: `bridge/install.js`, `claude-bridge.js`, `dist/os/apps/claude.lua`, `claude.lua`
- Test: `test/server.test.js`

**Interfaces:**
- Consumes: `TOKEN` from Task 6.
- Produces: `installScript(baseUrl, token) -> string` — the second parameter is new.
- Config key: `system.bridgeToken` in `/cfg/system.json`, read as `ctx.sys.getSetting("bridgeToken", "")`.

- [ ] **Step 1: Write the failing tests**

Append to `test/server.test.js`:

```js
test("GET /install bakes the token into the config it writes", async () => {
  const r = await get("/install");
  assert.equal(r.code, 200);
  assert.match(r.body, /test-token/);
  assert.match(r.body, /bridgeToken/);
  assert.match(r.body, /cfg\/system\.json/);
});

test("GET /claude.lua bakes the token into the standalone client", async () => {
  const r = await get("/claude.lua");
  assert.equal(r.code, 200);
  assert.match(r.body, /local TOKEN = "test-token"/);
});
```

- [ ] **Step 2: Run and watch them fail**

Run: `node --test`
Expected: FAIL on both — the token does not appear in either body.

- [ ] **Step 3: Take the token in `installScript` and write the config**

`installScript` returns one big JS template literal, so edit it in place rather than retyping it — three surgical changes to `bridge/install.js`.

**3a.** Change the signature on line 2:

```js
function installScript(baseUrl, token) {
```

**3b.** Add the token constant right after the `local BASE = ...` line inside the template:

```lua
local TOKEN = "${token}"
```

**3c.** Insert the config merge between the closing `end` of the download loop and the `print("PinguOS "..` line:

```lua
-- Merge the bridge token into the OS settings file. Read-modify-write, so an
-- update does not wipe accent, wallpaper or hdScale.
local CFG = "/cfg/system.json"
local cfg = {}
if fs.exists(CFG) then
  local ch = fs.open(CFG, "r"); local craw = ch.readAll(); ch.close()
  local cok, parsed = pcall(textutils.unserialiseJSON, craw)
  if cok and type(parsed) == "table" then cfg = parsed end
end
if type(cfg.system) ~= "table" then cfg.system = {} end
cfg.system.bridgeToken = TOKEN
if not fs.exists("/cfg") then fs.makeDir("/cfg") end
local cf = fs.open(CFG, "w"); cf.write(textutils.serialiseJSON(cfg)); cf.close()
```

The locals are named `ch`/`craw`/`cok` rather than `h`/`raw`/`ok` because the download loop above already uses those names in the same generated script.

- [ ] **Step 4: Pass the token at the call site and substitute in the standalone client**

In `claude-bridge.js`, update the `/install` route:

```js
  if (req.method === "GET" && req.url === "/install") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(installScript(`http://127.0.0.1:${PORT}`, TOKEN));
    return;
  }
```

And the `/claude.lua` route, so the served copy carries the live token while the file on disk stays a runnable template:

```js
  if (req.method === "GET" && req.url.startsWith("/claude.lua")) {
    fs.readFile(LUA_PATH, "utf8", (e, data) => {
      if (e) {
        console.error("Couldn't read claude.lua:", e.message);
        res.writeHead(404).end("claude.lua not found next to claude-bridge.js");
        return;
      }
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(data.replace('local TOKEN = ""', `local TOKEN = "${TOKEN}"`));
      console.log("served claude.lua");
    });
    return;
  }
```

- [ ] **Step 5: Send the header from the standalone client**

In `claude.lua`, add the placeholder below the URL:

```lua
local URL = "http://127.0.0.1:8080"
local TOKEN = ""
```

and send it:

```lua
    local res, errmsg = http.post(URL, body, {
      ["Content-Type"] = "application/json",
      ["X-Bridge-Token"] = TOKEN,
    })
```

- [ ] **Step 6: Send the header from the OS app**

In `dist/os/apps/claude.lua`, read the token next to the URL:

```lua
    local url = ctx.sys.getSetting("bridgeUrl", "http://127.0.0.1:8080")
    local token = ctx.sys.getSetting("bridgeToken", "")
```

and add it to the request headers:

```lua
      http.request({
        url = url, body = textutils.serialiseJSON(bodyTable),
        headers = {
          ["Content-Type"] = "application/json",
          ["X-Bridge-Token"] = token,
        },
        timeout = 120,
      })
```

- [ ] **Step 7: Run the tests and the parse check**

```bash
node --test
"C:/Users/juanm/AppData/Local/Programs/Lua/bin/luac.exe" -p claude.lua
"C:/Users/juanm/AppData/Local/Programs/Lua/bin/luac.exe" -p dist/os/apps/claude.lua
```

Expected: `pass 31`, `fail 0`, and no output from either `luac -p`.

- [ ] **Step 8: Commit**

```bash
git add bridge/install.js claude-bridge.js claude.lua dist/os/apps/claude.lua test/server.test.js
git commit -m "feat(bridge): deliver the token to the in-game clients

The installer merges it into /cfg/system.json and the served copy of claude.lua
has it substituted in, so 'wget run .../install' still works in one line."
```

- [ ] **Step 9: In-game check — the only one this phase needs**

This is the one thing tests cannot prove. Ask Juan to run it and report back:

1. Start the bridge: `DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js`, note the printed `token:` line.
2. In-game: `wget run http://127.0.0.1:8080/install`
3. After reboot, open the **Claude** app and send a message.

Expected: a reply, not a `bridge error: bad or missing token`.

If it fails, read `/cfg/system.json` in-game with `edit /cfg/system.json` and check `bridgeToken` matches the printed token.

---

### Task 8: Security policy and dependency updates

**Files:**
- Create: `SECURITY.md`, `.github/dependabot.yml`

- [ ] **Step 1: Write `SECURITY.md`**

```markdown
# Security

## Reporting

Open a private security advisory through the repository's Security tab. Please
do not open a public issue for a vulnerability.

## What the bridge is

`claude-bridge.js` is a local HTTP server that spawns `claude` with its working
directory set to this repo. Anything that can POST to it runs code as you. It is
built to be reachable only from your own machine and from a Minecraft world you
control.

It defends itself four ways:

- Binds `127.0.0.1` only, never `0.0.0.0`.
- Rejects any `Host` that is not loopback, which is what stops DNS rebinding.
- Rejects cross-origin `Origin`/`Referer`, and requires `Content-Type:
  application/json` so a browser form cannot reach it.
- Requires a token in `X-Bridge-Token` on the chat route. The token is generated
  at startup, or set with `BRIDGE_TOKEN`.

## What it does not defend against

Another process running as you on the same machine. That process already has
your privileges and does not need the bridge.

## Do not expose it

Do not port-forward it, and do not put it behind a tunnel. It is a local tool.
```

- [ ] **Step 2: Write `.github/dependabot.yml`**

With no `package.json`, the workflow files are the whole supply-chain surface.

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

- [ ] **Step 3: Commit**

```bash
git add SECURITY.md .github/dependabot.yml
git commit -m "docs: security policy and dependabot for actions"
```

---

### Task 9: Pull request and issue templates

The template is short on purpose. A form with three small prompts produces short PRs; a long one invites an essay.

**Files:**
- Create: `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/bug.md`, `.github/ISSUE_TEMPLATE/feature.md`, `.github/CODEOWNERS`

- [ ] **Step 1: Write `.github/pull_request_template.md`**

```markdown
## What changed


## Why


## How it was verified

<!-- Which suites ran, and whether an in-game check was needed. -->
```

- [ ] **Step 2: Write `.github/ISSUE_TEMPLATE/bug.md`**

```markdown
---
name: Bug
about: Something behaves differently than it should
labels: 'type:bug'
---

## What happened


## What should have happened


## How to reproduce


## Environment

- Minecraft / mod loader:
- CC: Tweaked version:
- Computer type (Advanced, turtle, pocket):
```

- [ ] **Step 3: Write `.github/ISSUE_TEMPLATE/feature.md`**

```markdown
---
name: Feature
about: Suggest something PinguOS should do
labels: 'type:feat'
---

## What it should do


## Why it is worth building


## What it would touch

<!-- OS, bridge, turtle fleet, JARVIS -->
```

- [ ] **Step 4: Write `.github/CODEOWNERS`**

```
* @juanmgh3
```

- [ ] **Step 5: Commit**

```bash
git add .github/pull_request_template.md .github/ISSUE_TEMPLATE .github/CODEOWNERS
git commit -m "chore: pull request and issue templates"
```

---

### Task 10: AGENTS.md

`AGENTS.md` becomes the single source of truth so any agentic CLI reads the same rules. `CLAUDE.md` keeps only what is Claude-specific and points at it.

**Files:**
- Create: `AGENTS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write `AGENTS.md`**

Move the contents of the current `CLAUDE.md` in, then add the two new sections. The Commands, Architecture, Conventions, Gotchas and Environment sections carry over unchanged — they are already tool-neutral. Add:

```markdown
## Writing style

Applies to commits, pull request titles and bodies, review comments, docs and
code comments.

Comments here earn their place by naming the failure that motivated them:

    -- ...the rednet broadcast is THROTTLED to ~2/s. Jobs call this every block;
    -- several working turtles broadcasting every step floods the fleet computer's
    -- event queue (a real limit inside CC) and freezes a pocket.

Don't:

- Emoji, anywhere
- "This PR introduces..." — say what it does
- Restating the diff as bullets; the diff already says that
- "Note that", "It's worth noting", "Importantly"
- Opening with praise: "Great catch!", "Nice work!"
- "comprehensive", "robust", "seamless", "leverage"
- Bold scattered through prose, or a closing summary repeating the opening

Do:

- PR body: what changed, why, how it was verified. Three lines is a valid body.
- Name the failure that motivated the change, if there was one.
- Review comments: point at the line, state the problem, say what breaks if it
  stays. No praise sandwich.
- Link the spec or the gotcha when one applies.

Comment only what the code cannot say for itself. A comment restating the line
below it is worse than no comment.

## Verification

| Layer | Verified by | Needs a human in-game |
| --- | --- | --- |
| Pure modules (`geo`, `text`, `focus`, `gpu`, `nav`, ...) | unit tests + CI | no |
| Bridge | `node --test` + CI | no |
| CC-bound Lua (`kernel`, apps, `turtle/lib/api.lua`) | `luac -p` only | **yes** |

The third row is a property of the platform: every call hits a Minecraft API
that does not exist outside the game.

Every task states which is true:

- **No in-game check needed** — covered by tests, say so and move on.
- **In-game check needed** — name the exact steps. "Open the Fleet app, confirm
  the scrollbar pages" beats "test it".

State anything you could not verify. Never assume it works.
```

- [ ] **Step 2: Replace `CLAUDE.md` with a pointer**

```markdown
# PinguOS

Conventions, commands, architecture and gotchas live in [AGENTS.md](AGENTS.md).
Read that first; it applies here in full.

## Claude Code specifics

- The durable record of each feature is its `specs/<slug>/` folder.
- `/spec` → `/plan` → `/tasks` → `/build` for anything touching more than two files.
```

- [ ] **Step 3: Check nothing referenced the old file layout**

Run: `git grep -n "CLAUDE.md" -- ':!CLAUDE.md'`
Expected: no hits, or only in `specs/`. Update any that point at moved content.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "docs: move conventions to AGENTS.md so any agent reads them

Adds the writing style and the verification contract, which were only ever
spoken."
```

---

### Task 11: Repo settings, labels, rename

Branch protection and CodeQL are **not** in this task. Both are free only on public repos, so they land in phase 2 at the flip.

**Files:** none — all `gh` CLI.

- [ ] **Step 1: Create labels**

```bash
gh label create "area:os"      --color 1D76DB --description "In-game OS (dist/)" --force
gh label create "area:bridge"  --color 0E8A16 --description "Node bridge" --force
gh label create "area:turtle"  --color FBCA04 --description "Turtle fleet" --force
gh label create "area:jarvis"  --color 5319E7 --description "JARVIS agent" --force
gh label create "type:bug"     --color D73A4A --description "Something is broken" --force
gh label create "type:feat"    --color A2EEEF --description "New capability" --force
gh label create "type:docs"    --color 0075CA --description "Docs and specs" --force
```

- [ ] **Step 2: Set merge behaviour**

```bash
gh repo edit --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge
```

- [ ] **Step 3: Add a description**

```bash
gh repo edit --description "A desktop OS for a Minecraft CC: Tweaked computer, with an autonomous turtle fleet and a Claude-powered agent"
```

- [ ] **Step 4: Rename and repoint the remote**

```bash
gh repo rename pinguos --yes
git remote set-url origin https://github.com/juanmgh3/pinguos.git
git remote -v
```

Expected: both lines show `.../pinguos.git`.

- [ ] **Step 5: Confirm the push path still works**

Run: `git fetch origin && git status -sb`
Expected: the branch still tracks `origin/chore/public-infra`, no error.

---

### Task 12: Measure whether a self-review counts

Whether a self-review registers as a contribution is undocumented. Measure it instead of guessing.

**Files:**
- Modify: `specs/going-public/design.md`

- [ ] **Step 1: Record the count before reviewing anything**

```bash
gh api graphql -f query='
{
  viewer {
    contributionsCollection {
      totalPullRequestReviewContributions
      totalPullRequestContributions
    }
  }
}'
```

Write down `totalPullRequestReviewContributions`. Without a before-value the experiment proves nothing.

- [ ] **Step 2: Leave a comment review on an open PR**

GitHub blocks approving your own PR, so use a comment review. Pick an open one:

```bash
gh pr list --state open
gh pr review <number> --comment --body "Token comparison is constant-time, and the GET routes stay open so the one-line install still works."
```

If every PR is already merged, reopen the task-12 PR for this and merge it after.

- [ ] **Step 3: Re-run the query the next day**

Run the same GraphQL query. The contribution graph settles within a day.

If `totalPullRequestReviewContributions` went up, self-reviews count. If it did not, they do not, and the only path to that stat is other people reviewing — which is phase 2 onward.

- [ ] **Step 4: Write the answer into the spec**

Replace the "Review-stat experiment" section's closing paragraph in
`specs/going-public/design.md` with the measured result, dated. One sentence.

- [ ] **Step 5: Commit**

```bash
git add specs/going-public/design.md
git commit -m "docs: record whether self-reviews count as contributions"
```

---

## Done when

- [ ] Four bridge findings each have a test that failed before the fix and passes after
- [ ] CI green on a pull request: `bridge`, `lua`, `syntax`
- [ ] `AGENTS.md` carries the writing style and the verification contract; `CLAUDE.md` points at it
- [ ] Repo is named `pinguos`, has a description, squash-only, deletes merged branches
- [ ] The one-line in-game install works against a token-protected bridge (Juan confirms)
- [ ] The review-stat answer is recorded in the spec

## Not in this plan

Phase 2 opens the repo: UI strings and the JARVIS prompt to English, LICENSE,
README rewrite with real screenshots, untrack `screenshots/`, flip to public,
then CodeQL and branch protection. Phase 3 is agent teams and looping.
