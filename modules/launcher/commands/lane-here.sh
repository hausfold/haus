#!/bin/bash
# pounce: name = New Agent Lane
# pounce: description = Agent lane in this page's repo, no questions asked
# pounce: icon = sparkles
# pounce: cheat = agent lane

# The lane chord's front door. Pounce's Ghostty-scoped ⌘↵ fires
# `cmd:lane-here`, which is this file, which is a one-line exec into the script
# the terminal room installs — the same `lane-spawn.sh` the chord has always
# run. What changed on 2026-08-18 is only WHO holds the key.
#
# It was ⌃⌘A in AeroSpace: global, so it fired over a browser too. ⌘↵ can't be
# global — it is "send" in Slack, Claude, Linear and half the Mac — so it rides
# pounce's Ghostty-scoped tap instead, beside ⌘N's shell-here. That covers every
# window you would actually press it from — a lane's own window and any other
# terminal window are both Ghostty. The cost, paid knowingly, is that a lane can
# no longer be started from a browser — and the palette does not paper over it:
# this row is LISTED only on the terminal pages (modules/launcher writes
# `items."cmd:lane-here".workspaces`, from the page the workspaces room puts
# ghostty on), because pressed from anywhere else it inherits no repo, falls
# back to $HOME and refuses. Spawn Agent, which asks which repo instead of
# inheriting one, is the answer there.
#
# What it inherits from a PAGE is stronger than what it inherits from a window:
# standing on `T/<repo>` decides the repo outright, and only the exact directory
# inside it comes from the focused window. lane-cwd.sh's `--page` header has the
# why.
#
# Being a palette command rather than an AeroSpace `exec-and-forget` is what
# makes the chord addressable at all: an app-scoped hotkey fires an ItemTarget
# (`cmd:<id>`), the same grammar a palette row is, so the key and the row are
# one address. It also means the daemon's environment, not AeroSpace's, is what
# the script inherits — lane-spawn.sh sets its own PATH for exactly that reason.
#
# Not to be confused with Spawn Agent (spawn-agent.sh): that one asks which repo
# and what to do, and names the worktree after the answer. This one asks
# nothing — it is the chord, and the whole point of the chord is that pressing
# it is the entire interaction.
set -u

# The script is the terminal room's, installed beside its lane hooks, and the
# `laneCommands` filter takes this file away on a machine that has no lanes — so
# a missing file should be impossible. Say so anyway rather than exiting 127
# into a daemon with no stdout: an invisible failure is the one thing a chord
# can't afford, which is the whole subject of lane-spawn.sh's own header.
spawn="$HOME/.config/haus/lanes/lane-spawn.sh"
[ -x "$spawn" ] || {
  osascript -e 'display notification "lane-spawn.sh is missing — the terminal room installs it; rebuild." with title "haus · agent lane"' >/dev/null 2>&1
  exit 0
}

exec "$spawn"
