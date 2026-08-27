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

# Focus a window we can SEE, rather than activating the app, whenever the target
# workspace already holds one of this app's windows.
#
# `open -a` on a running app is macOS's own ⌘⇥, and it raises that app's last KEY
# window — a per-app fact macOS keeps, which knows nothing about pages and which
# bare T usually holds, since every plain terminal window is sent home to T
# (../../terminal/scripts/launch.sh's self-tile). Fired a beat after the switch
# above, it drags focus to that window and AeroSpace follows it off the page we
# had just arrived on. That is the whole "`caps t` ignores the page I was on,
# but only when T has windows in it" bug: the resolve is right, the activation
# undoes it. And the landing is a real workspace change, so the MRU push stamps
# bare T at the top of the file the NEXT `caps t` reads — one jump poisons the
# recency, which is what made it stick rather than flicker.
#
# Two cases stay on the old path, both narrower than the one above and neither a
# regression: a workspace holding none of this app's windows (nothing to focus,
# so `open -a` runs and can still raise one elsewhere), and the one-argument form
# `launch.sh "App"` — no workspace was named, so there is nothing to keep it on.
if [ -n "$ws" ]; then
    # Matching is AeroSpace's `%{app-name}` against the roster name we were
    # handed, which options.nix defines as the name `open -a` takes: that is
    # case-insensitive and accepts a `.app` suffix, and `%{app-name}` is neither,
    # so both are normalised away. `tolower` on both sides is the same compare
    # bar/sketchybar/plugins/vitals_lib.sh makes. A roster name that is not the
    # bundle's display name at all still matches nothing and falls through.
    want="${app%.app}"

    # Have we already arrived? The switch focused the workspace's OWN
    # last-focused window, which is a better answer than any this script could
    # pick, so the common case is to notice that and stop, touching nothing.
    arrived="$(aerospace list-windows --focused --format '%{app-name}|%{workspace}' 2>/dev/null |
                 awk -F'|' -v want="$want" -v ws="$ws" '
                   { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2) }
                   tolower($1) == tolower(want) && $2 == ws { print "y" }')"
    [ "$arrived" = y ] && exit 0

    # Otherwise pick one of the app's windows on that workspace by id — TILED
    # ones first. `list-windows` answers in tree order and floating windows are
    # in that answer, so without the preference a float-term popup or a peek
    # window would beat the terminal actually being read — the very "raises a
    # window that is not the one you wanted" this whole block exists to stop.
    # `%{window-layout}` says `floating` for a float and the CONTAINER's layout
    # (`h_tiles`, `v_tiles`) for anything tiled, so the test is against floating
    # rather than for a tiling spelling — same read, and the same `^floating|`
    # compare, as bar/sketchybar/plugins/aerospace_lib.sh's tiled count.
    wid="$(aerospace list-windows --workspace "$ws" \
             --format '%{window-id}|%{app-name}|%{window-layout}' 2>/dev/null |
             awk -F'|' -v want="$want" '
               { gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3) }
               tolower($2) != tolower(want) { next }
               $3 != "floating" && tiled == "" { tiled = $1 }
               any == "" { any = $1 }
               END { print (tiled == "" ? any : tiled) }')"

    # The focus is TESTED, not fired and forgotten: a window can close between
    # the list and the focus — lane windows do, constantly — and an `exit 0` on
    # a focus that failed would make the keypress do nothing at all, with no app
    # raised and nothing said. Falling through costs an `open -a` we might not
    # have needed; swallowing it costs the chord.
    if [ -n "$wid" ] && aerospace focus --window-id "$wid" 2>/dev/null; then
        exit 0
    fi
fi

open -a "$app"
