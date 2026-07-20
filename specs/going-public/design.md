# Going public — phase 1: infrastructure

Status: approved 2026-07-20. Phase 1 of 3.

PinguOS is going public on GitHub. Three things have to be true before the repo
flips: nothing exploitable ships, every change is proved by CI, and the writing
reads like a person wrote it.

This spec covers phase 1 only. Phases 2 and 3 are sketched at the end; each gets
its own spec.

## Current state

Verified 2026-07-20 on `main`:

- 161 tests pass: 23 bridge (`node --test`), 90 OS, 48 turtle
- Zero npm dependencies — there is no `package.json`
- No secrets in the working tree or in history
- Repo is private, named `CC-tweaked-pinguOs`, remote URL still `.../ComputerCraft.git`
- No LICENSE, no description, no `.github/`
- `screenshots/` is gitignored and empty

Work happens on `chore/public-infra`, branched from `main`. The in-flight
`feat/jarvis-me-stock` branch is untouched and rebases onto this afterwards.

## 1. Bridge hardening

### Threat model

`claude-bridge.js` serves HTTP on loopback and spawns `claude` with `cwd` set to
the repo. Anything that can POST to it runs arbitrary code as the user. Two
attackers matter differently:

- **A web page in the user's browser.** Realistic, and the reason the
  Origin/Referer checks already exist. This is what we defend against.
- **Another local process.** Already runs with the user's privileges, so it can
  do everything the bridge offers without going through the bridge. Out of scope.

### Not vulnerabilities

Confirmed by reading the code, recorded so they don't get "fixed" later:

- `spawn("claude", args)` passes an args array with no shell, so there is no
  command injection. The prompt is bound as the value of `-p`, so it cannot be
  reinterpreted as a flag.
- `safeFsPath` containment is correct for traversal, and both `/fs/` and
  `/turtle-fs/` have tests for it.
- The listener binds `127.0.0.1` explicitly, not `0.0.0.0`.

### F1 — No authentication

`POST /` drives a tool-capable Claude and requires nothing to reach it.

The bridge generates a token at startup (`crypto.randomBytes(16).toString("hex")`)
unless `BRIDGE_TOKEN` is set, prints it, and requires it on `POST /`. Comparison
uses `crypto.timingSafeEqual`, not `===`, so a wrong token leaks nothing through
timing. GET routes stay open.

The one-line install survives because `installScript()` generates the Lua client
server-side: the bridge embeds the live token as it generates it. `wget run
http://127.0.0.1:8080/install` works exactly as before and the installed client
is already authenticated.

Handing the token out over an open GET is deliberate. A malicious page cannot
read the response body of a cross-origin GET without CORS, so it never sees the
token — which is precisely the attacker we are defending against. A local process
could read it, but a local process already has everything.

### F2 — No Host validation

Origin/Referer checks are good but DNS rebinding is the standard attack on
loopback services. Accept only `127.0.0.1[:port]`, `localhost[:port]`, or an
absent Host; reject anything else with 403. The CC: Tweaked HTTP client is
unaffected.

### F3 — Unbounded request body

`req.on("data", c => body += c)` has no cap, so any local client can grow the
process until it dies. Cap at 64 KB, respond 413, destroy the request.

### F4 — `safeFsPath` does not resolve symlinks

`path.resolve` normalizes `..` but does not follow links, so a symlink planted
inside `dist/` escapes containment. Resolve the real path and re-check. A
non-existent path returns null and 404s, which is the existing behaviour.

The symlink test skips on `win32` — creating symlinks there needs admin rights.
CI runs on Linux, so the case is covered where it matters.

Each fix lands test-first. The anti-CSRF tests in `test/server.test.js` are the
natural home for F1–F3.

`SECURITY.md` states all of this in the open: what the bridge is, the four
defences, what it deliberately does not defend against, and where to report.
A public repo that teaches people to run a local server owes them that.

## 2. CI

One workflow, `.github/workflows/ci.yml`, three jobs in parallel:

| job | runs |
| --- | --- |
| `bridge` | `node --test` on Node 24, nothing to install |
| `lua` | `lua5.4` via apt, then `dist/tests/run.lua` and `turtle/tests/run.lua` |
| `syntax` | `luac -p` over every `.lua` in the repo |

`syntax` earns its place: the CC-bound files can never be unit-tested because
every call hits a Minecraft API, so a parse check is the only automated signal
they get. It is also the class of bug this project actually ships — see the Lua
5.1/5.4 notes in CLAUDE.md.

Actions are pinned by commit SHA and Dependabot updates them. With zero npm
dependencies, the workflow files are the entire supply-chain surface. Workflows
declare `permissions: contents: read` at the top level.

## 3. GitHub workflow

- `.github/pull_request_template.md` — three short prompts: what changed, why,
  how it was verified. Short template, short PRs.
- `.github/ISSUE_TEMPLATE/` — bug and feature.
- `CODEOWNERS` — `* @juanmgh3`.
- Labels by area (`area:os`, `area:bridge`, `area:turtle`, `area:jarvis`) and
  type (`type:bug`, `type:feat`, `type:docs`).
- Repo settings: squash-merge only, delete branch on merge.

Branch protection and CodeQL are deferred to phase 2: both are free only on
public repos, and paying for Advanced Security to guard a private repo we are
about to open would be backwards.

When protection does land it requires green checks and **zero required
approvals**. GitHub blocks approving your own pull request, so requiring an
approval would deadlock a solo maintainer. Review still happens — it just isn't
a merge gate.

## 4. AGENTS.md

`AGENTS.md` becomes the single source of truth for build commands, conventions
and gotchas. `CLAUDE.md` keeps only Claude-specific setup and points at it. Any
agentic CLI reads `AGENTS.md`, and CI is the verifier they all share.

It carries a **Writing style** section covering commits, PR titles and bodies,
review comments, docs and code comments.

The style already exists in this repo. Comments here work because they name the
failure that motivated them:

```lua
-- ...the rednet broadcast is THROTTLED to ~2/s. Jobs call this every block;
-- several working turtles broadcasting every step floods the fleet computer's
-- event queue (a real limit inside CC) and freezes a pocket.
```

Rules follow from that:

**Don't**

- Emoji, anywhere
- "This PR introduces..." — say what it does
- Restating the diff as bullets; the diff already says that
- "Note that", "It's worth noting", "Importantly"
- Opening with praise: "Great catch!", "Nice work!"
- "comprehensive", "robust", "seamless", "leverage"
- Bold scattered through prose, or a closing summary repeating the opening

**Do**

- PR body: what changed, why, how it was verified. Three lines is a valid PR body.
- Name the failure that motivated the change, if there was one.
- Review comments: point at the line, state the problem, say what breaks if it
  stays. No praise sandwich.
- Link the spec or the gotcha when one applies.

No CI lint on PR text. It is brittle, it false-positives, and in a one-developer
repo the review catches style drift at lower cost.

## 5. Verification contract

Goes in `AGENTS.md`. The point is that the maintainer tests as little as
possible, which is a result of automating verification rather than skipping it.

| Layer | Verified by | Needs a human in-game |
| --- | --- | --- |
| Pure modules (`geo`, `text`, `focus`, `gpu`, `nav`, ...) | unit tests + CI | no |
| Bridge | `node --test` + CI | no |
| CC-bound Lua (`kernel`, apps, `turtle/lib/api.lua`) | `luac -p` only | **yes** |

The third row is a property of the platform: every call hits a Minecraft API
that does not exist outside the game, so no amount of local tooling covers it.

Every task therefore states which of two things is true:

- **No in-game check needed** — the change is covered by tests, say so and move on.
- **In-game check needed** — name the exact steps. "Open the Fleet app, confirm
  the scrollbar pages" beats "test it".

Anything that could not be verified is stated as unverified. Never assume.

## 6. Rename

Rename the repo to `pinguos`, add a description and topics, update the local
remote. GitHub redirects the old URL, so nothing breaks.

## 7. Review-stat experiment

Whether a self-review counts as a contribution is undocumented: the profile
contributions reference lists "Submitting a pull request review" as sometimes
counting and gives no condition about who authored the PR.

So measure it. On one phase-1 PR, leave a review of type Comment, then check the
contribution graph the next day and record the answer here. One PR, one fact,
no guessing.

Pull Shark needs no effort: x1 is 2 merged PRs, x2 is 16, and you can merge your
own. Phase 1 alone produces more than 2. It falls out of working in PRs, which
we are doing anyway.

## Out of scope

**Phase 2 — public.** Migrate in-game UI strings and the JARVIS system prompt to
English, add a LICENSE, rewrite the README to sell the project, capture real
screenshots and untrack `screenshots/` from `.gitignore`, flip to public, then
enable CodeQL and branch protection.

**Phase 3 — agent teams and looping.** Built on green CI and written
conventions. Scale and cost estimated and approved before anything spawns.

## Done when

- The four bridge findings have a failing-then-passing test each
- CI is green on a pull request, all three jobs
- `AGENTS.md` exists, carries the writing style and the verification contract,
  and `CLAUDE.md` points at it
- The repo is named `pinguos` with a description
- The review-stat experiment has an answer recorded in this file
- The one-line in-game install still works against a token-protected bridge
  (in-game check, the only one phase 1 needs)
