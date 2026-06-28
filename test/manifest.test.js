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
