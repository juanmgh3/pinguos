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
