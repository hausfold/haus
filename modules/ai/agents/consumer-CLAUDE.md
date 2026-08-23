# CLAUDE.md

@AGENTS.md

<!--
Everything above this line is imported from AGENTS.md — the one set of
instructions for this config repo, shared by every agent. Put rules THERE, not
here, or Codex/OpenCode/Copilot silently run without them.

Claude Code reads only CLAUDE.md, which is the whole reason this file exists.
Only Claude-specific wiring belongs below.
-->

## Claude-specific wiring (nothing project-level here)

| Thing | Where | Notes |
|---|---|---|
| Instructions | `AGENTS.md`, imported above | Claude Code reads only `CLAUDE.md`, so this file exists purely to import it. |
| The haus skill | `~/.claude/skills/haus/` | Installed by `haus.ai.skill`, generated from the haus revision this machine has pinned — so it describes the options that exist *here*. Codex and OpenCode get the same skill at their own paths. |
| Every other tool's skill | `~/.claude/skills/<name>/` | Same option, same fan-out: each hausfold tool names and ships its own (holt's `holt` and `handoff` today). Store symlinks — edit them in the tool's repo, not here. |
| Global memory | `~/.claude/CLAUDE.md` | Written by `haus.ai.instructions` if the host sets it; left alone if not. The other clients get the same text as their `AGENTS.md`, so write it for all of them, not for Claude. |
