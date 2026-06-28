// test/fspath.test.js
const { test } = require("node:test");
const assert = require("node:assert");
const path = require("node:path");
const { safeFsPath } = require("../bridge/fspath");

test("resolves a normal path inside a relative dist dir", () => {
  assert.equal(safeFsPath("./dist", "startup.lua"), path.resolve("dist/startup.lua"));
});

test("resolves a nested path", () => {
  assert.equal(safeFsPath("./dist", "os/kernel.lua"), path.resolve("dist/os/kernel.lua"));
});

test("decodes percent-encoding", () => {
  assert.equal(safeFsPath("./dist", "os%2Fkernel.lua"), path.resolve("dist/os/kernel.lua"));
});

test("blocks traversal (relative and encoded)", () => {
  assert.equal(safeFsPath("./dist", "../claude-bridge.js"), null);
  assert.equal(safeFsPath("./dist", "%2e%2e/claude-bridge.js"), null);
});
