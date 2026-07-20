#!/usr/bin/env node
// claude-bridge.js
// Local HTTP bridge for Minecraft CC: Tweaked <-> Claude Code.
//
// Two jobs:
//   GET  /claude.lua  -> serves the Lua client so you can `wget` it in-game
//                        (no copy/paste pain). Reads ./claude.lua from this folder.
//   POST /            -> takes a prompt, runs it through your logged-in Claude Code
//                        session (claude -p), returns the text. No API key needed;
//                        it draws from your subscription.
//
// The CC: Tweaked terminal is an 8-bit, ASCII-only screen (no unicode/emoji), so the
// bridge (1) tells Claude to answer in short plain ASCII and (2) transliterates the
// reply to ASCII as a safety net before sending it in-game.
//
// Run on your PC, in the SAME folder where claude.lua sits:
//   node claude-bridge.js
// Keep the terminal open. Then in-game:
//   wget http://127.0.0.1:8080/claude.lua claude
//   claude

const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const crypto = require("node:crypto");
const { toTerminalAscii } = require("./bridge/ascii");
const { buildManifest } = require("./bridge/manifest");
const { installScript, gpsHostScript, turtleBootstrapScript } = require("./bridge/install");
const { safeFsPath } = require("./bridge/fspath");

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const WORKDIR = process.env.CLAUDE_WORKDIR || process.cwd();
const LUA_PATH = path.join(__dirname, "claude.lua");
const DIST_DIR = process.env.DIST_DIR || path.join(__dirname, "dist");
const TURTLE_DIR = process.env.TURTLE_DIR || path.join(__dirname, "turtle");
const OS_VERSION = process.env.OS_VERSION || "dev";
// Counted in UTF-16 code units, not wire bytes: a non-ASCII body can reach
// roughly 3x this in bytes before tripping. Bounded is the point here, not exact.
const MAX_BODY = 64 * 1024;

// POST / drives a tool-capable Claude, so reaching it must take a secret. The
// installer bakes this into the generated client, which keeps the one-line
// in-game install working. Handing it out over an open GET is deliberate: a
// hostile page cannot read a cross-origin GET body without CORS, and that page
// is the attacker this defends against.
// The value is spliced unescaped into generated Lua (the installer and the served
// claude.lua), so a token set via BRIDGE_TOKEN must stay quote-safe: hex or
// alphanumeric. The generated default already is.
const TOKEN = process.env.BRIDGE_TOKEN || crypto.randomBytes(16).toString("hex");

// Constant-time compare so a wrong token leaks nothing through response timing.
function tokenOk(given) {
  const a = Buffer.from(String(given || ""));
  const b = Buffer.from(TOKEN);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Keep replies renderable on the tiny CC terminal. Appended to Claude's normal
// system prompt (so it still has your Claude Code context), not a replacement.
const TERMINAL_SYSTEM_PROMPT = [
  "You are replying through a Minecraft ComputerCraft computer terminal:",
  "a narrow (~50 columns), monospaced, ASCII-only text screen.",
  "Rules for EVERY reply:",
  "- Plain ASCII only. No emoji, no accented letters, no smart quotes, no box-drawing.",
  "- No Markdown: no #, *, backticks, code fences, or tables. For lists use '-'.",
  "- Keep it short: aim for under ~6 lines. Be direct, no preamble.",
  "- The user may write Spanish; you may answer in Spanish but WITHOUT accents",
  "  or special characters (write 'comunicate', 'anos', 'que', not the accented forms).",
].join("\n");

let sessionId = null; // keep one conversation alive across messages

function runClaude(prompt) {
  return new Promise((resolve, reject) => {
    const args = [
      "-p", prompt,
      "--output-format", "json",
      "--append-system-prompt", TERMINAL_SYSTEM_PROMPT,
    ];
    if (sessionId) args.push("--resume", sessionId);
    // stdin must be closed: with -p the prompt comes via args, but an open
    // stdin pipe makes claude wait 3s for input and warn on stderr.
    const child = spawn("claude", args, { cwd: WORKDIR, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    let err = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0 && !out) return reject(new Error(err.trim() || `claude exited ${code}`));
      try {
        const parsed = JSON.parse(out);
        if (parsed.session_id) sessionId = parsed.session_id;
        const text = parsed.result ?? parsed.text ?? out;
        if (parsed.is_error) return reject(new Error(toTerminalAscii(String(text))));
        resolve(toTerminalAscii(String(text)));
      } catch {
        resolve(toTerminalAscii(out.trim()));
      }
    });
  });
}

// DNS rebinding: a hostile page can point its own domain at 127.0.0.1, so its
// requests reach this server looking same-origin. Pinning Host shuts that down
// for every route at once.
//
// The absent case is permitted, but node answers 400 to an HTTP/1.1 request
// carrying no Host before this function ever runs, so that branch only covers
// HTTP/1.0 clients. Whether CC: Tweaked needs it is unverified — it works
// either way, since an HTTP/1.1 client sends Host: 127.0.0.1:<port>, which is
// allowed. An empty Host value is not absent and is rejected.
function hostAllowed(h) {
  if (h === undefined) return true;
  let name;
  if (h.startsWith("[")) {
    const end = h.indexOf("]");
    if (end === -1) return false;
    name = h.slice(1, end);
  } else {
    name = h.split(":")[0];
  }
  name = name.toLowerCase();
  return name === "127.0.0.1" || name === "localhost" || name === "::1";
}

const server = http.createServer((req, res) => {
  if (!hostAllowed(req.headers.host)) {
    res.writeHead(403).end("bad host");
    return;
  }

  // --- OS install/update static routes ---
  if (req.method === "GET" && req.url === "/manifest") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(buildManifest(DIST_DIR, OS_VERSION)));
    return;
  }
  if (req.method === "GET" && req.url === "/install") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(installScript(`http://127.0.0.1:${PORT}`, TOKEN));
    return;
  }
  if (req.method === "GET" && req.url === "/gpshost") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(gpsHostScript());
    return;
  }
  if (req.method === "GET" && req.url === "/turtle") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(turtleBootstrapScript(`http://127.0.0.1:${PORT}`));
    return;
  }
  if (req.method === "GET" && req.url === "/turtle-manifest") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(buildManifest(TURTLE_DIR, OS_VERSION)));
    return;
  }
  if (req.method === "GET" && req.url.startsWith("/turtle-fs/")) {
    const abs = safeFsPath(TURTLE_DIR, req.url.slice("/turtle-fs/".length));
    if (!abs) { res.writeHead(404).end("nope"); return; }
    fs.readFile(abs, (e, data) => {
      if (e) { res.writeHead(404).end("not found"); return; }
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(data);
    });
    return;
  }
  if (req.method === "GET" && req.url.startsWith("/fs/")) {
    const abs = safeFsPath(DIST_DIR, req.url.slice("/fs/".length));
    if (!abs) { res.writeHead(404).end("nope"); return; }
    fs.readFile(abs, (e, data) => {
      if (e) { res.writeHead(404).end("not found"); return; }
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(data);
    });
    return;
  }

  // --- serve the Lua client for in-game wget ---
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

  // --- chat endpoint ---
  if (req.method !== "POST") {
    res.writeHead(405).end("POST for chat, GET /claude.lua for the client");
    return;
  }
  // CSRF hardening: this endpoint drives a tool-capable Claude session, so a
  // malicious web page you visit must not be able to POST to it. Require a JSON
  // content type (a cross-origin JSON POST triggers a CORS preflight we never
  // answer, so the browser blocks it) and reject any cross-origin Origin/Referer.
  // The CC: Tweaked http client sends neither header, so the in-game client is
  // unaffected.
  const ctype = req.headers["content-type"] || "";
  if (!ctype.includes("application/json")) {
    res.writeHead(415).end("application/json required");
    return;
  }
  const cross = req.headers.origin || req.headers.referer;
  if (cross && !/^https?:\/\/(127\.0\.0\.1|localhost)(:|\/|$)/.test(cross)) {
    res.writeHead(403).end("cross-origin blocked");
    return;
  }
  if (!tokenOk(req.headers["x-bridge-token"])) {
    res.writeHead(401).end("bad or missing token");
    return;
  }
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
    let reset = false;
    try {
      const j = JSON.parse(body);
      prompt = typeof j.prompt === "string" ? j.prompt : "";
      reset = !!j.reset;
    } catch {
      prompt = body; // raw body = prompt
    }
    if (reset) {
      sessionId = null;
      console.log("session reset");
      // A reset with no prompt is just "forget the conversation".
      if (!prompt.trim()) {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ text: "(memoria borrada)" }));
        return;
      }
    }
    if (!prompt.trim()) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "empty prompt" }));
      return;
    }
    console.log(`> ${prompt}`);
    try {
      const text = await runClaude(prompt);
      console.log(`< ${text.slice(0, 200)}${text.length > 200 ? "..." : ""}`);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ text }));
    } catch (e) {
      console.error(e);
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e.message || e) }));
    }
  });
});

function start() {
  return new Promise((resolve) => {
    server.listen(PORT, "127.0.0.1", () => {
      console.log(`claude-bridge listening on http://127.0.0.1:${PORT}`);
      console.log(`workdir: ${WORKDIR}  |  dist: ${DIST_DIR}  |  os: ${OS_VERSION}`);
      console.log("install in-game: wget run http://127.0.0.1:" + PORT + "/install");
      console.log(`token: ${TOKEN}`);
      resolve(server);
    });
  });
}

if (require.main === module) start();
module.exports = { server, start, TOKEN };
