# Options that moved ROOM inside `haus.*`.
#
# Hand-written on purpose: each entry has a reason worth writing down and no
# enumeration can produce it. There is no deletion condition for the file
# itself — a room move can happen again. Entries do age out: drop one when no
# consumer can plausibly still be pinned to a revision that predates the move.
#
# What an alias buys: the old name keeps evaluating (with an obsolete-option
# warning naming the new one), so `~/.config/nix` moves on its own schedule
# instead of in a lockstep PR pair with the layer.
{ lib, ... }:
{
  imports = [
    # 2026-08-11 — the `claude` room became part of `agents`.
    #
    # Both options describe a file the rice ships into a coding agent's home:
    # the always-on instructions, and the `haus` skill. Neither is about Claude
    # Code — the rice installs three clients (`haus.ai.clients`) and every
    # one of them reads both kinds of file, at its own path. Named for the
    # client, they wrote only Claude's copy, which made `ai.default =
    # "codex"` a half-truth: the pane spawned with none of the operating context
    # or option knowledge the same machine hands Claude.
    #
    # `globalMd` -> `instructions` is a rename as well as a move: "global
    # memory" is Claude Code's word for the slot, and the file the other two
    # clients read is called AGENTS.md.
    (lib.mkRenamedOptionModule [ "haus" "claude" "globalMd" ] [ "haus" "ai" "instructions" ])
    (lib.mkRenamedOptionModule [ "haus" "claude" "skill" ] [ "haus" "ai" "skill" ])

    # 2026-08-16 — the room code names are GONE rather than deprecated:
    # `hearth` -> `terminal`, `prowl` -> `windows`, `sill` -> `bar`,
    # `pounce` -> `launcher`, `perch` -> `shelf`, `hush` -> `focus`, and
    # `collar` -> `security.touchId.*` (folding into the namespace the firewall
    # already had, so the one Security room has one address). `den` was never a
    # namespace; its module and export are `core`.
    #
    # No aliases, for the reason the agents -> ai move gives below: the layer
    # has one consumer, its host moved in the same sweep, and an alias set here
    # would be permanent furniture protecting nobody. It would also defeat the
    # point — the whole change is that those words stop appearing.

    # 2026-08-19 — zellij is gone, and the two options that described its
    # in-pane behaviour go with it: `terminal.zellijStartLocked` (boot into
    # Locked input mode) and `terminal.rightClickFullscreen` (a bare
    # right-click zooms a pane). Neither has a successor to rename to —
    # Ghostty has no input modes, and a window is the pane now, so
    # "fullscreen" is windows/AeroSpace's own chord.
    #
    # These get `mkRemovedOptionModule` rather than the silent deletion the
    # room renames below took, and the difference is who is on the other end.
    # A room rename touched `haus.*` spellings inside the layer's own single
    # consumer. These two are PUBLIC, desktop-safe, published in
    # docs/site-data/options.json, and were set by both shipped desktops — so
    # somebody else's host file can name them, and "unknown option" would send
    # them looking for a typo instead of telling them what happened.
    (lib.mkRemovedOptionModule [ "haus" "terminal" "zellijStartLocked" ] ''
      zellij is gone (2026-08-19) — haus ships Ghostty windows tiled by
      haus.windows, with zmx for session persistence. Ghostty has no input
      modes, so there is nothing to start locked. Drop the line.
    '')
    (lib.mkRemovedOptionModule [ "haus" "terminal" "rightClickFullscreen" ] ''
      zellij is gone (2026-08-19), and with it the zellij-unwrapped patch this
      option compiled in. A window is the pane now: zoom it with
      haus.windows' own fullscreen chord (see the Keys page). Drop the line.
    '')

    # 2026-08-13 — the whole coding-agent capability became `haus.ai.*`, and
    # deliberately got NO alias here. `haus.agents.*` and
    # `haus.developer.agents.enable` are gone rather than deprecated: the rice
    # has one consumer, its host moved in the same change, and an alias set for
    # a five-day-old spelling would be permanent furniture bought to protect
    # nobody.
  ];
}
