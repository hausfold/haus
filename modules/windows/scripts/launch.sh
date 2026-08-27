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

# Focus a window we can SEE rather than activating the app, whenever the target
# workspace already holds one of this app's windows.
#
# `open -a` on a running app is macOS's ⌘⇥, and it raises the app's own last KEY
# window — a per-app fact macOS keeps, which knows nothing about pages. AeroSpace
# follows that focus, so activating Ghostty a beat after switching to `T/<repo>`
# can land you back on whichever Ghostty window macOS remembers, and bare T is
# the usual holder of it (plain windows are sent home to T). That is the whole
# "`caps t` ignores the page I was on, but only when T has windows in it" bug:
# the resolve above is right, the activation drags you off it. With no window of
# the app on the target workspace there is nothing to raise and the switch
# sticks, which is why an EMPTY T never showed it.
#
# Matching is on AeroSpace's `%{app-name}` against the roster name we were
# handed. A roster name that is not the bundle's display name simply finds
# nothing and falls through to `open -a`, which is the old behaviour.
#
# The switch above already focused the workspace's OWN last-focused window, which
# is a better answer than any window this script could pick — so the common case
# is to notice that we have arrived and stop, touching nothing.
if [ -n "$ws" ]; then
    focused="$(aerospace list-windows --focused --format '%{app-name}|%{workspace}' 2>/dev/null)"
    if [ "${focused%%|*}" = "$app" ] && [ "${focused#*|}" = "$ws" ]; then
        exit 0
    fi

    wid="$(aerospace list-windows --workspace "$ws" --format '%{window-id}|%{app-name}' 2>/dev/null |
             awk -F'|' -v want="$app" '$2 == want { print $1; exit }')"
    if [ -n "$wid" ]; then
        aerospace focus --window-id "$wid" 2>/dev/null
        exit 0
    fi
fi

open -a "$app"
