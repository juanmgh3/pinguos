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
const { toTerminalAscii } = require("./bridge/ascii");
const { buildManifest } = require("./bridge/manifest");
const { installScript } = require("./bridge/install");

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const WORKDIR = process.env.CLAUDE_WORKDIR || process.cwd();
const LUA_PATH = path.join(__dirname, "claude.lua");
const DIST_DIR = process.env.DIST_DIR || path.join(__dirname, "dist");
const OS_VERSION = process.env.OS_VERSION || "dev";

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

const server = http.createServer((req, res) => {
  // --- OS install/update static routes ---
  if (req.method === "GET" && req.url === "/manifest") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(buildManifest(DIST_DIR, OS_VERSION)));
    return;
  }
  if (req.method === "GET" && req.url === "/install") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(installScript(`http://127.0.0.1:${PORT}`));
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

  // --- serve the Lua client for in-game wget ---
  if (req.method === "GET" && req.url.startsWith("/claude.lua")) {
    fs.readFile(LUA_PATH, "utf8", (e, data) => {
      if (e) {
        console.error("Couldn't read claude.lua:", e.message);
        res.writeHead(404).end("claude.lua not found next to claude-bridge.js");
        return;
      }
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(data);
      console.log("served claude.lua");
    });
    return;
  }

  // --- chat endpoint ---
  if (req.method !== "POST") {
    res.writeHead(405).end("POST for chat, GET /claude.lua for the client");
    return;
  }
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", async () => {
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
      resolve(server);
    });
  });
}

if (require.main === module) start();
module.exports = { server, start };
