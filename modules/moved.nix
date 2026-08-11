# Options that moved ROOM inside `haus.*` — not the namespace rename.
#
# `./renamed.nix` is the `nebelhaus.*` -> `haus.*` alias set: generated, one
# entry per leaf, and deleted whole once the last consumer has moved. This file
# is the other kind of alias — an option that kept its namespace and changed its
# address — and it is hand-written on purpose, because each entry has a reason
# worth writing down and no enumeration can produce it.
#
# Unlike renamed.nix there is no deletion condition for the file itself: a room
# move can happen again. Entries do age out — drop one when no consumer can
# plausibly still be pinned to a revision that predates the move.
#
# What an alias buys, both times: the old name keeps evaluating (with an
# obsolete-option warning naming the new one), so `~/.config/nix` moves on its
# own schedule instead of in a lockstep PR pair with the rice.
{ lib, ... }:
{
  imports = [
    # 2026-08-11 — the `claude` room became part of `agents`.
    #
    # Both options describe a file the rice ships into a coding agent's home:
    # the always-on instructions, and the `haus` skill. Neither is about Claude
    # Code — the rice installs three clients (`haus.agents.clients`) and every
    # one of them reads both kinds of file, at its own path. Named for the
    # client, they wrote only Claude's copy, which made `agents.default =
    # "codex"` a half-truth: the pane spawned with none of the operating context
    # or option knowledge the same machine hands Claude.
    #
    # `globalMd` -> `instructions` is a rename as well as a move: "global
    # memory" is Claude Code's word for the slot, and the file the other two
    # clients read is called AGENTS.md.
    (lib.mkRenamedOptionModule [ "haus" "claude" "globalMd" ] [ "haus" "agents" "instructions" ])
    (lib.mkRenamedOptionModule [ "haus" "claude" "skill" ] [ "haus" "agents" "skill" ])
  ];
}
