# JARVIS Core — Implementation Plan (Increment 0)

> **v3 (wrap) — what actually shipped:** in-game testing + the mod source proved that in
> channel mode the Lua CLIENT must execute the brain's tool calls (`claude_tool_exec` →
> `sendToolResult`), so a "thin relay" (v2 Tasks B/D) is insufficient. **Owner's decision:
> wrap ClaudeCraft's complete rom `claude` client** instead of reimplementing it. Net changes
> from v2: Task B's `claudecc.lua` was **removed**; Task D's app became a **launcher**
> (`_G.shell.run("claude")`). Tasks A (remove v1) and C (`fleet_status`) stand. See the spec
> `specs/pinguos/jarvis-core.md` (v3) for the shipped design. The tasks below are the v2
> record; the git history (commits `f8d7c66`..`ce5d124`) reflects the wrap.

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Read the spec
> `specs/pinguos/jarvis-core.md` (v3) first.

**Goal:** Ship the thin JARVIS core: a `jarvis` app where you type NL, `claudecc` relays it to
the ClaudeCraft brain, and the brain answers using its native tools + a `fleet_status` program
we ship. First miracle: *"¿cómo va la flota?"* → real turtle states.

**Architecture:** `claudecc.lua` (the ONLY file touching `_G.claude`: `sendMessage` + adaptive
reply event) ← the `jarvis` app (thin chat UI, prepends `world.md`). The brain runs
`fleet_status.lua` via `run_command`. See the spec for the full diagram + confirmed mechanism.

## Global Constraints

- **`require` is unavailable in apps** (loaded via `loadfile`, see `_G` only). The app loads
  `claudecc` with `loadfile`. No `require` in any `dist/os/jarvis/*.lua`.
- **`_G.claude` is the one mod dependency** — isolated in `claudecc.lua`. `sendMessage` takes a
  **table** `{userMessage=text}` (verified). The reply arrives as a CC event whose name
  contains `"claude"` — matched **adaptively**; the app prints the raw event once to pin it.
- **Lua runs on CC 5.1 AND local 5.4**; **rendered text is ASCII** (WORLD.md too).
- **Test model:** `"$LUA" dist/tests/run.lua` for the (now JARVIS-free) pure suite;
  CC-bound code `luac -p` + in-game. `$LUA`/`$LUAC` = the local Lua 5.4 bin.

---

### Task A: Remove v1 dead code

**Files:** delete `dist/os/jarvis/{protocol,agent,tools}.lua`,
`dist/tests/test_jarvis_protocol.lua`; edit `dist/tests/run.lua`.

- [ ] Remove the four files (`git rm` — specific files, not recursive).
- [ ] Delete the `dofile("dist/tests/test_jarvis_protocol.lua")` line from `run.lua`.
- [ ] Run `"$LUA" dist/tests/run.lua` → expect **90 passed, 0 failed** (back to baseline).
- [ ] Commit: `refactor(jarvis): drop v1 Lua tool-loop (brain has native tools)`.

### Task B: `claudecc.lua` — thin wrapper (rewrite)

**File:** rewrite `dist/os/jarvis/claudecc.lua`.

- [ ] `available()`; `open()` (startChannel(false) + poll `isChannelReady` up to ~10s);
  `send(session, text)` → `sendMessage({userMessage=text})`, wait for the first `claude*`
  event, return its first non-empty string field (the reply); 120s timeout; `close()`
  (stopChannel). Keep an optional debug hook so the app can print the raw event.
- [ ] `luac -p`; commit: `feat(jarvis): thin ClaudeCraft wrapper (sendMessage + reply event)`.

### Task C: `fleet_status.lua` — the program the brain runs (new)

**File:** create `dist/os/jarvis/fleet_status.lua` (headless CLI, reuses `fleet.lua`).

- [ ] Open the modem, `rednet.broadcast(fleet.discover(), fleet.PROTOCOL)`, collect replies
  for ~2s, print one ASCII line per turtle (`#id name role status fuel`) + a total; print a
  clear "no turtles" if empty. Loads `fleet` via `loadfile("/os/fleet.lua")` (no `require`).
- [ ] `luac -p`; commit: `feat(jarvis): fleet_status CLI (read-only, reuses fleet.lua)`.

### Task D: `jarvis` app + `WORLD.md` (rewrite/expand)

**Files:** rewrite `dist/os/apps/jarvis.lua`; expand `dist/data/jarvis/world.md`.

- [ ] `world.md` (ASCII): who JARVIS is; the base facts; the `pingufleet` rednet protocol;
  **"to check the fleet, run: `/os/jarvis/fleet_status.lua`"**; be concise, plain text.
- [ ] App: thin chat UI (reuse `claude.lua` pattern). Load `claudecc` via `loadfile`. On the
  first message of the session, prepend `world.md`. Show the reply; on the first reply, print
  the raw event name once (pins it). Degrade cleanly if `not claudecc.available()`.
- [ ] `luac -p` the app; run the suite (still **90**); commit:
  `feat(jarvis): thin chat app + base WORLD.md (talks to the brain)`.

### Task E: In-game validation (owner) — the first miracle

**No code. Phase boundary — hand off to the owner.**

- [ ] Bridge serves `dist/`; owner runs **Update** in-game.
- [ ] Open **JARVIS**, type *"¿cómo va la flota?"* → the app prints the raw reply event once
  (tell me the name), and the brain answers with the real fleet (having run `fleet_status`).
- [ ] Report the reply event name → I finalize `claudecc` (drop the adaptive match if wanted).
- [ ] On green → **superpowers:finishing-a-development-branch**.

---

## Self-Review

**Spec coverage (v2):** §5 claudecc → Task B; §5 app+WORLD.md → Task D; §5 fleet_status →
Task C; §5 "removed files" → Task A; §7 first miracle → Task E. **Salvage:** claudecc (thin),
app, world.md repurposed; fleet logic → `fleet_status`. **Dropped:** protocol/agent/tools +
their test (Task A). **Open item:** the exact reply event name — pinned by Task E's first run,
which is why claudecc matches `claude*` adaptively until then.
