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
| Worktree hooks | `~/.claude/settings.json` (yours, not the repo's) → `holt hook create` / `holt hook remove` | Claude owns that file and rewrites it, so the rice never touches it — that's why `holt new` exists for the clients with no such flag. |

**Not to be confused with the rice's product surface.** This table is about
*hacking on haus*. What haus **ships to a user's machine** —
`haus.ai.instructions`, `haus.ai.skill`, the generated `haus/` skill in
each client's skills directory and its `consumer-AGENTS.md`/`consumer-CLAUDE.md`
starter pair, the per-client agent-state hooks in `modules/terminal` — is a
feature of the distro, documented in `AGENTS.md` and `modules/ai/agents/`.

The full cross-harness map is [`.agents/README.md`](./.agents/README.md).
