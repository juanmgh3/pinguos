// test/server.test.js
const { test, before, after } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const http = require("node:http");
const net = require("node:net");

const dist = fs.mkdtempSync(path.join(os.tmpdir(), "pinguos-dist-"));
fs.mkdirSync(path.join(dist, "os"), { recursive: true });
fs.writeFileSync(path.join(dist, "startup.lua"), "print('hi')");
fs.writeFileSync(path.join(dist, "os", "kernel.lua"), "return {}");

process.env.DIST_DIR = dist;
process.env.OS_VERSION = "9.9.9";
process.env.PORT = "8099";
const { server, start } = require("../claude-bridge.js");

// setHost:false stops Node's client from substituting a real loopback Host.
// The empty-Host test needs it: without it, headers: { Host: "" } is silently
// replaced with the real one and the test asserts nothing.
function get(p, headers, opts = {}) {
  // options form (not a URL string) so the path is sent verbatim — a URL
  // string would normalize "/fs/%2e%2e/x" to "/x" before it reaches the server.
  return new Promise((res) => {
    http
      .request({ host: "127.0.0.1", port: 8099, path: p, method: "GET", headers, ...opts }, (r) => {
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

test("GET /gpshost returns a GPS host setup script", async () => {
  const r = await get("/gpshost");
  assert.equal(r.code, 200);
  assert.match(r.body, /gps/);
  assert.match(r.body, /startup\.lua/);
});

test("GET /turtle returns the turtle firmware installer", async () => {
  const r = await get("/turtle");
  assert.equal(r.code, 200);
  assert.match(r.body, /turtle-manifest/); // it pulls the firmware manifest...
  assert.match(r.body, /\/pingu/);         // ...and installs under /pingu
});

test("GET /turtle-manifest lists the turtle firmware files", async () => {
  const r = await get("/turtle-manifest");
  assert.equal(r.code, 200);
  const m = JSON.parse(r.body);
  assert.ok(Array.isArray(m.files));
  assert.ok(m.files.some((f) => f.path === "/agent.lua"));
  assert.ok(!m.files.some((f) => f.path.includes("/tests/"))); // tests never shipped
});

test("GET /turtle-fs serves a turtle file", async () => {
  const r = await get("/turtle-fs/agent.lua");
  assert.equal(r.code, 200);
  assert.match(r.body, /pingufleet/);
});

test("GET /turtle-fs blocks path traversal", async () => {
  const r = await get("/turtle-fs/%2e%2e/claude-bridge.js");
  assert.equal(r.code, 404);
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

test("rejects a Host that is not loopback (DNS rebinding)", async () => {
  const r = await get("/manifest", { Host: "evil.example" });
  assert.equal(r.code, 403);
});

test("accepts loopback Host with a port", async () => {
  const r = await get("/manifest", { Host: "localhost:8099" });
  assert.equal(r.code, 200);
});

// The carve-out covers HTTP/1.0 clients that send no Host; whether CC: Tweaked
// needs it is unverified. Driven over a raw socket because Node's own server
// 400s an HTTP/1.1 request with no Host before the handler runs — only HTTP/1.0
// reaches hostAllowed with Host absent.
test("permits an absent Host (HTTP/1.0 client)", async () => {
  const line = await new Promise((res) => {
    const s = net.connect(8099, "127.0.0.1", () => s.write("GET /manifest HTTP/1.0\r\n\r\n"));
    let b = "";
    s.on("data", (c) => (b += c));
    s.on("end", () => res(b.split("\r\n")[0]));
  });
  assert.match(line, /^HTTP\/1\.[01] 200 /);
});

test("rejects an empty Host", async () => {
  const r = await get("/manifest", { Host: "" }, { setHost: false });
  assert.equal(r.code, 403);
});

test("rejects a bracketed Host with no closing bracket", async () => {
  const r = await get("/manifest", { Host: "[127.0.0.1x" });
  assert.equal(r.code, 403);
});

test("accepts an uppercase loopback Host (Host is case-insensitive)", async () => {
  const r = await get("/manifest", { Host: "LOCALHOST:8099" });
  assert.equal(r.code, 200);
});

test("POST rejects a body over the size cap", async () => {
  const r = await post("/", JSON.stringify({ prompt: "x".repeat(70 * 1024) }), {
    "Content-Type": "application/json",
  });
  assert.equal(r.code, 413);
});
