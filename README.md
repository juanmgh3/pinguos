# PinguOS

A desktop OS for CC: Tweaked computers.

CC: Tweaked gives you a programmable computer: an 8-bit terminal you write Lua for.
PinguOS turns one into something closer to a desktop — a wallpaper, clickable icons,
apps in windows, keyboard focus — and hangs real tools off it: a control panel for a
fleet of mining turtles, a GPS map, and a chat app wired to Claude.

I built it to learn Lua, and because a constrained sandbox is a good excuse to write
things I don't otherwise get to write: a small window manager, an immediate-mode UI, a
fleet coordinator, a hardened little HTTP server. It's a learning project, not a product.

## How it gets onto the computer

The whole OS lives in `dist/`. A small Node server (`claude-bridge.js`) serves that
folder over HTTP, so installing it on the target computer is one line:

```
wget run http://127.0.0.1:8080/install
```

That downloads PinguOS and reboots into the desktop. Edit a file on the PC, re-run the
install (or the built-in **Update** app), and it pulls the change and reboots again.
That loop — edit on the PC, hit Update on the computer — is the whole dev cycle.

## The apps

The desktop auto-discovers whatever is in `dist/os/apps/`. Right now that's eight:

- **Fleet** — mission control for the turtles. A live dashboard that listens to every
  turtle over rednet, a menu to hand any one of them a job, and a button to call it back.
- **Claude** — a chat app. It talks to a Claude process running on the PC through the
  bridge, which can use tools, so it's more than a text box.
- **GPS** — a map with waypoints. Reads the computer's position off a GPS constellation
  and lets you save spots.
- **GPS Host** — turns the computer it runs on into a GPS beacon, so you can stand up
  your own constellation instead of needing one already there.
- **Settings** — theme accent, wallpaper, and the bridge connection.
- **Terminal** — drops you into the normal CraftOS shell when you want it.
- **Update** — pulls the latest OS from the bridge and reboots.
- **About** — what it says, and doubles as the copy-me template for a new app.

## The turtle fleet

Turtles are programmable robots provided by CC: Tweaked. The fleet lives in `turtle/`:
each turtle runs an agent that carries a catalog of jobs and broadcasts what it's doing,
and the Fleet app is the other end of that conversation.

The jobs it can run today:

- `branch-mine` and `vein-mine` — strip-mining and follow-the-ore mining
- `dig-down` — straight shaft to a depth
- `lumber`, `fell-tree`, `tree-farm` — felling and replanting
- `crop-loop` — harvest-and-replant a field
- `goto` — navigate to a coordinate

Underneath the jobs is a small library: `nav` for movement and pathing, `blocks` for
identifying what's in front of the turtle, `roles` for what a given turtle is set up to
do, and `api` tying it together. One lesson is written into a comment there: rednet
broadcasts are throttled to about twice a second, because several turtles each announcing
their position every block flooded the fleet computer's event queue and froze it.

## How it's put together

A few decisions shaped everything else, most of them learned by breaking something first.

**Every app is one file that returns a table.** An app is
`{ id, name, icon, color, run = function(ctx) ... end }` and nothing more. The kernel
finds it, draws its icon, and calls `run` when you click. Copy `about.lua` and you have
a new app.

**Apps only get `ctx`.** Everything an app is allowed to touch — the UI toolkit, config,
GPS helpers, system settings, the terminal, logging — arrives in that one `ctx` table.
Apps never reach for globals. That came from getting burned: `require`, `shell` and
`gps` aren't globals inside an app the way you'd expect, so leaning on them crashed
things until everything an app needs went through `ctx` instead.

**A crashing app must not crash the OS.** The kernel launches every app under `pcall`
and shows the error instead of dying — the difference between iterating and rebooting
every few minutes.

**The UI is immediate-mode.** There's no retained tree of widgets. A widget draws
itself and hands back the rectangle it drew into; the app's loop hit-tests clicks
against those rectangles. A small idea that kept the toolkit simple.

**The bridge has zero dependencies.** `claude-bridge.js` is plain Node — `node:` builtins
and `node:test`, no `package.json`, nothing to `npm install`. It serves the install
script, file routes for the OS and the turtles, and the chat endpoint.

Because that chat endpoint spawns a real, tool-capable Claude with its working directory
set to the repo, anything that can reach it can run code as me. So it's built to only be
reachable from my own machine, and it defends itself: loopback-only, a Host check that
stops DNS rebinding, cross-origin rejection plus a required JSON content-type, a 64 KB
cap on request bodies, symlink-aware path containment on the file routes, and a token on
the chat route compared in constant time. [SECURITY.md](SECURITY.md) spells all of that
out, including what it deliberately doesn't defend against.

## Running it

1. **Allow the computer to reach the bridge.** In
   `serverconfig/computercraft-server.toml`, allow loopback above the `$private` deny:

   ```toml
   [[http.rules]]
       host = "127.0.0.1"
       action = "allow"
   ```

2. **Start the bridge on the PC**, from this folder:

   ```
   DIST_DIR=./dist OS_VERSION=0.1.0 node claude-bridge.js
   ```

   It prints a token on startup; the install bakes it into the OS, so the Claude app is
   authenticated from the first boot.

3. **Install on an Advanced Computer** (it needs color and a mouse):

   ```
   wget run http://127.0.0.1:8080/install
   ```

4. **Update later** by re-running that line, or the **Update** app.

## Working on it

The dev loop is the edit-then-Update rhythm above. For everything that can be checked
outside the CC: Tweaked runtime, there are tests:

- Bridge: `node --test` — 36 tests, no install needed
- OS modules: `lua dist/tests/run.lua` — 90 tests
- Turtle library: `lua turtle/tests/run.lua` — 48 tests

The catch is that much of the OS can't be unit-tested at all: any file that depends on
runtime-only APIs only runs under CC: Tweaked itself. For those the only automated signal
is a parse check, `luac -p <file>`, and CI runs it under both Lua 5.1 (what CC: Tweaked
runs) and 5.4 (what my machine runs), because the two disagree on enough syntax to crash
in one and pass in the other. That split is most of the sharp edges in the project —
that, and the terminal being 8-bit, so everything drawn to it has to be plain ASCII.

Conventions, build commands, and the gotchas that each cost a crash live in
[CLAUDE.md](CLAUDE.md).

## License

MIT — see [LICENSE](LICENSE).
