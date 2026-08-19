#!/bin/bash
# pounce: name = Build This Lane
# pounce: description = bench try lane switch — this worktree plus its holt children
# pounce: icon = hammer

# ⌘B's target. Build+activate the focused window's whole holt LANE — this
# worktree PLUS every `holt child` worktree spawned from it, however many repos
# it touches, in ONE rebuild ("b" for bench, since ⌘L is Links).
#
# Unlike try-batch (which needs an open PR per repo) this tests the LOCAL
# checkouts, uncommitted edits included, so it's the fast loop for a cross-repo
# change mid-flight. Press it from the lane's PARENT worktree; bench refuses if
# it isn't one, or if it has no holt children (see bench's own
# cmd_try/detect_lane).
#
# The window stays open after it exits — the build output and the post-switch
# activation banner are worth reading. Runs UNGATED: bench's BENCH_AGENT_SWITCH
# check only fires for an agent process, and a real keypress is a human at the
# keyboard.
#
# Installed only when haus.developer.enable is on: `bench` lives at a hardcoded
# ~/code/workshop on the family developer's own machines and nowhere else.
#
# The CWD is the whole input. The zellij bind inherited the focused pane's
# directory for free; a chord hosted outside the terminal has none, so ask
# lane-cwd.sh — the same resolver ⌘↵ and ⌘N use. Falling back to $HOME would
# just make bench refuse, which is the honest failure anyway.
cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

exec "$HOME/.config/haus/term/new-window.sh" --cwd "$cwd" -- \
    bash -c '"$HOME/code/workshop/bench" try lane switch; exec zsh'
