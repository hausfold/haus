#!/bin/bash
# pounce: name = New Agent Lane
# pounce: description = Agent lane in the focused window's repo, no questions asked
# pounce: icon = sparkles

# The lane chord's front door. Pounce's Ghostty-scoped ⌘↵ fires
# `cmd:lane-here`, which is this file, which is a one-line exec into the script
# the terminal room installs — the same `lane-spawn.sh` the chord has always
# run. What changed on 2026-08-18 is only WHO holds the key.
#
# It was ⌃⌘A in AeroSpace: global, so it fired over a browser too. ⌘↵ can't be
# global — it is "send" in Slack, Claude, Linear and half the Mac — so it rides
# pounce's Ghostty-scoped tap instead, beside ⌘N's shell-here. That covers every
# window you would actually press it from: a zellij pane and a lane's own window
# are both Ghostty. The cost, paid knowingly, is that a lane can no longer be
# started from a browser; the palette row this header makes (and Spawn Agent
# beside it) is the answer there.
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

exec "$HOME/.config/haus/lanes/lane-spawn.sh"
