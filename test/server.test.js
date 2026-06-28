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
const { server, start } = require("../claude-bridge.js");

function get(p) {
  // options form (not a URL string) so the path is sent verbatim — a URL
  // string would normalize "/fs/%2e%2e/x" to "/x" before it reaches the server.
  return new Promise((res) => {
    http
      .request({ host: "127.0.0.1", port: 8099, path: p, method: "GET" }, (r) => {
        let b = "";
        r.on("data", (c) => (b += c));
        r.on("end", () => res({ code: r.statusCode, body: b }));
      })
      .end();
  });
}

function post(p, body, headers) {
  return new Promise((res) => {
    const r = http.request(
      { host: "127.0.0.1", port: 8099, path: p, method: "POST", headers },
      (resp) => {
        let b = "";
        resp.on("data", (c) => (b += c));
        resp.on("end", () => res({ code: resp.statusCode, body: b }));
      }
    );
    r.end(body);
  });
}

before(async () => { await start(); });
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
  const r = await get("/fs/%2e%2e/claude-bridge.js");
  assert.equal(r.code, 404);
});

test("GET /install returns a lua bootstrap", async () => {
  const r = await get("/install");
  assert.equal(r.code, 200);
  assert.match(r.body, /\/manifest/);
  assert.match(r.body, /os\.reboot\(\)/);
});

test("POST chat requires application/json (anti-CSRF)", async () => {
  const r = await post("/", "hola", { "Content-Type": "text/plain" });
  assert.equal(r.code, 415);
});

test("POST chat rejects a cross-origin Origin (anti-CSRF)", async () => {
  const r = await post("/", JSON.stringify({ reset: true }), {
    "Content-Type": "application/json",
    Origin: "http://evil.example",
  });
  assert.equal(r.code, 403);
});

test("POST reset works with application/json from a non-browser client", async () => {
  const r = await post("/", JSON.stringify({ reset: true }), {
    "Content-Type": "application/json",
  });
  assert.equal(r.code, 200);
  assert.match(r.body, /borrada/);
});
