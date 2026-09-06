# CLAUDE.md

@AGENTS.md

Claude-only wiring: `.claude/settings.json` runs `SessionStart` → `.agents/setup.sh`; the `WorktreeCreate`/`WorktreeRemove` hooks (`scruff hook create` / `scruff hook remove`) live in `~/.claude/settings.json` and `modules/terminal` re-asserts them every rebuild. Map: [`.agents/README.md`](./.agents/README.md).
