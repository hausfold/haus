#!/bin/bash
# aerospace-notify.sh [fullscreen]
#
# AeroSpace's hooks into the bar. No argument is the workspace-change hook
# (exec-on-workspace-change in aerospace.toml); `fullscreen` is the <mod>f
# binding's second command.
#
# Both live here rather than as `exec-and-forget sketchybar --trigger …` lines
# in aerospace.toml so that the path to the MENU bar's sketchybar — Homebrew's,
# and specifically the top bar's mach service — is written in the bar's own
# tree and nowhere in the windows room.

if [ "$1" = fullscreen ]; then
    # Repaint on the keypress rather than up to 2s later on the watcher's next
    # poll. The watcher is what reads the new state and paints both pills; this
    # only wakes it. See plugins/aerospace_lib.sh.
    /opt/homebrew/bin/sketchybar --trigger aerospace_fullscreen_change
    exit 0
fi

/opt/homebrew/bin/sketchybar --trigger aerospace_workspace_change
# Haus-tour hook — one stat when no tour is mid-flight (plugins/tour.sh).
{ [ -f "$HOME/.local/state/haus/tour" ] && "$HOME/.config/sketchybar/plugins/tour.sh" event workspace; } >/dev/null 2>&1 &
