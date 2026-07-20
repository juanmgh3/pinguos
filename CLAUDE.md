# PinguOS

Conventions, commands, architecture and gotchas live in [AGENTS.md](AGENTS.md).
Read that first; it applies here in full.

## Claude Code specifics

- The durable record of each feature is its `specs/<slug>/` folder.
- `/spec` → `/plan` → `/tasks` → `/build` for anything touching more than two files.
