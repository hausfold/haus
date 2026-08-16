#!/bin/bash
# Launch (or focus) an app, optionally on a specific workspace.
#
#   launch.sh "AppName"          # open/focus in the CURRENT workspace
#   launch.sh "AppName" S        # switch to workspace S first, then open/focus
#
# Switching to the assigned workspace BEFORE opening avoids the jank where the
# app appears on the current workspace and then on-window-detected yanks it to
# its assigned one. When the target is already focused, on-window-detected is a
# no-op and there's nothing visible to move.

app="$1"
ws="$2"

# Undim the bar immediately. Safe no-op when invoked outside launch mode —
# disarm bails when nothing is armed.
# Guarded: windows works without bar, so skip the launch-mode toggle if absent.
[ -x "$HOME/.config/sketchybar/plugins/launch_mode.sh" ] \
    && "$HOME/.config/sketchybar/plugins/launch_mode.sh" off 2>/dev/null

# A workspace with lane PAGES under it (T → T/<repo>, since lane-open.sh gives
# every repo's lanes their own page) resolves to the most recently used
# non-empty page, so `caps t` returns to the page you were last working, not to
# a bare T that may hold nothing. workspace-mru.sh falls back to the base name
# when no page is live, which is also the answer on a machine with no pages at
# all — plain workspaces pass through unchanged.
if [ -n "$ws" ] && [ -x "$HOME/.config/aerospace/workspace-mru.sh" ]; then
    ws="$("$HOME/.config/aerospace/workspace-mru.sh" resolve "$ws")"
fi
[ -n "$ws" ] && aerospace workspace "$ws"
open -a "$app"
