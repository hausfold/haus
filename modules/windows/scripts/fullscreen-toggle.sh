#!/usr/bin/env bash
# fullscreen-toggle.sh — the whole body of <mod>f, behind the solo-window guard.
#
# AeroSpace's `fullscreen` is a MODE with no other tell of its own: the window
# fills the workspace, its siblings vanish, and nothing says they still exist.
#
# The guard: toggling ON with a solo window is a visual no-op — the window
# already fills the workspace — but it still arms `window-is-fullscreen`,
# which is a trap deferred. The NEXT window to open on this workspace is
# hidden behind this one, and the bar spends the whole time in between
# painting the fullscreen glyph over a mode that meant nothing. The OFF take
# is always allowed: a window left flagged after its siblings closed must
# still have a way back.
#
# The bar notify rides along only when the state actually changed — the same
# shape the two-command binding had before the guard. aerospace-notify.sh
# wakes the bar's aerospace watcher (aerospace_lib.sh); the watcher polls
# too, so dropping it costs latency, not the indicator.

set -euo pipefail

AP="/opt/homebrew/bin/aerospace"
NOTIFY="$HOME/.config/sketchybar/aerospace-notify.sh"

notify() {
    [ -x "$NOTIFY" ] && "$NOTIFY" fullscreen >/dev/null 2>&1 &
}

# Already fullscreen → this press is the OFF take. Always allowed, siblings
# or no: the OFF take is how a window left flagged by a closed sibling
# escapes the mode.
if [ "$("$AP" list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null)" = "true" ]; then
    "$AP" fullscreen
    notify
    exit 0
fi

# Toggle-ON: only with company. Count the windows on the focused workspace;
# a solo window gets nothing, because the toggle's only effect would be
# arming the mode against windows that don't exist yet.
ws="$("$AP" list-workspaces --focused 2>/dev/null || echo "")"
count="$("$AP" list-windows --workspace "$ws" --count 2>/dev/null || echo 0)"

if [ "$count" -gt 1 ]; then
    "$AP" fullscreen
    notify
fi

exit 0
