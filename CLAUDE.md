# CLAUDE.md

@AGENTS.md

<!--
Everything above this line is imported from AGENTS.md — the one set of project
instructions, shared by every harness. Put project rules THERE, not here, or
Codex/OpenCode/Copilot silently run without them.

Only Claude-specific wiring belongs below.
-->

## Claude-specific wiring (nothing project-level here)

| Thing | Where | Notes |
|---|---|---|
| Project instructions | `AGENTS.md`, imported above | Claude Code reads only `CLAUDE.md`, so this file exists purely to import it. |
| Session bootstrap | `.claude/settings.json` → `SessionStart` → `.agents/setup.sh` | Same script Codex and OpenCode call. Installs Nix in cloud containers, no-ops locally. |
| Worktree hooks | `~/.claude/settings.json` (yours, not the repo's) → `wt create` / `wt remove` | Claude owns that file and rewrites it, so the rice never touches it — that's why `wt new` exists for the clients with no such flag. |

**Not to be confused with the rice's product surface.** This table is about
*hacking on nebelhaus*. What nebelhaus **ships to a user's machine** —
`nebelhaus.claude.globalMd`, `nebelhaus.claude.skill`, the generated
`~/.claude/skills/nebelhaus/` and its `consumer-AGENTS.md`/`consumer-CLAUDE.md`
starter pair, the per-client agent-state hooks in `modules/hearth` — is a
feature of the distro, documented in `AGENTS.md` and `modules/hearth/claude/`.

The full cross-harness map is [`.agents/README.md`](./.agents/README.md).
