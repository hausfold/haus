#!/bin/bash
# pounce: name = Agent Here
# pounce: description = Agent in THIS checkout, on the branch you're looking at
# pounce: icon = sparkle
# pounce: cheat = agent here

# ⌃⌥⇧A's target — the RESIDENT agent, as opposed to ⌘↵'s lane. It works in the
# checkout you already have, on whatever branch is checked out, which makes it
# the only agent allowed to touch the real tree; at most one per window, by
# convention.
#
# It was `bind "Ctrl Alt Shift a" { Run <client>; }` in zellij's config.kdl and
# had to be re-hosted with the rest of the chord layer. Ghostty-scoped rather
# than global, unlike ⌘↵'s predecessor ⌃⌘A: "this checkout" only means anything
# in a terminal window, and a global ⌃⌥⇧A would sit exactly where
# `haus.keys.windowNav = "ctrl-alt"` used to put its workspace throws — the
# collision that option's own doc records.
#
# @AGENT_HERE@ is haus.ai.default's client, baked at build time.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# STAY, always — that is the entire difference between this chord and ⌘↵. A
# resident agent is for the tree in front of you, agent worktree or not, so it
# must not take the hop out to the repo's main checkout that a fresh human
# shell gets. HAUS_STAY=1 suppresses it for the same reason ⌘⇧N sets it.
cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

exec "$HOME/.config/haus/term/new-window.sh" --cwd "$cwd" --env HAUS_STAY=1 -- @AGENT_HERE@
