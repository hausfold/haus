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
| Worktree hooks | `~/.claude/settings.json` (yours, not the repo's) → `holt hook create` / `holt hook remove` | Claude owns and rewrites that file, so `modules/terminal` merges these two keys in at activation rather than owning it. Self-healing: every rebuild re-asserts them. |

**Not to be confused with the product surface.** This table is about *hacking
on haus*. What haus **ships to a user's machine** — `haus.ai.instructions`,
`haus.ai.skill`, the generated `haus/` skill in each client's skills directory,
its `consumer-AGENTS.md`/`consumer-CLAUDE.md` starter pair, and the per-client
agent-state hooks — is a feature of the layer, documented in `AGENTS.md` and
`modules/ai/agents/`.

The full cross-harness map is [`.agents/README.md`](./.agents/README.md).
