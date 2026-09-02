# One client id → where that client keeps the two files haus ships into a
# home: the always-on instructions (`haus.ai.instructions`) and the `haus`
# skill (`haus.ai.skill`). Every client has both slots under a different
# name, which is the whole reason those options are named for the room and not
# for Claude.
#
# PURE DATA, taking nothing — the same direction as skill.nix beside it, and
# for the same reason: modules/ai owns the table, but modules/core renders it
# into the `haus` wrapper (HAUS_AGENT_SKILL_DIRS, one `client=skills-dir` pair
# per entry) so `haus skill install` PARSES this table instead of restating it
# in bash — and core may import data, never read `config.haus.ai.*`. Until
# 2026-09-02 the table was said twice, and test/agent-surface.bats was the
# only thing holding the two spellings equal; that suite now asserts this
# wiring instead.
#
# Verified against the clients themselves rather than their docs, because the
# cost of a wrong path here is silent — a file written where nothing reads it
# looks exactly like a working install:
#
#   codex debug prompt-input   → ~/.codex/AGENTS.md and ~/.codex/skills/*
#                                appear in the model-visible prompt
#   opencode debug skill       → lists ~/.config/opencode/skills/*
#   pi --verbose               → names the context files and skills it loaded
#
# OpenCode also scans `~/.claude/skills` for Claude Code compatibility, so a
# machine running both clients has two copies of this skill in its reach. That
# is safe on purpose: the same probe shows opencode deduplicating by frontmatter
# `name` and preferring its OWN directory, so the skill is offered once. (Its
# docs only say "ensure skill names are unique", which is why this was probed.)
#
# pi has the same overlap and one more of its own: besides `~/.pi/agent/skills`
# it reads `~/.agents/skills` unconditionally, and it implements the Agent
# Skills standard, so it would find a haus skill written anywhere in that set.
# Its own directory is still the one named here, because that is the one this
# room can promise is haus's — `~/.agents/skills` is a shared address several
# clients read and the user's own hand-wired skills live in.
{
  claude = {
    instructions = ".claude/CLAUDE.md";
    skills = ".claude/skills";
  };
  codex = {
    instructions = ".codex/AGENTS.md";
    skills = ".codex/skills";
  };
  opencode = {
    instructions = ".config/opencode/AGENTS.md";
    skills = ".config/opencode/skills";
  };
  # pi keeps everything under one agent directory, `~/.pi/agent`, and reads
  # `AGENTS.md` there as its global context file. `CLAUDE.md` works too — pi
  # accepts either name — but AGENTS.md is the one the family standardises on
  # and the one pi's own docs name first.
  pi = {
    instructions = ".pi/agent/AGENTS.md";
    skills = ".pi/agent/skills";
  };
}
