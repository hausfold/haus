#!/bin/bash
# gh-dash.sh — ⌘G: gh-dash as a clean, near-fullscreen floating window.
#
# It used to be a two-step: a 1%-corner zellij pane whose only job was to ask
# the session for a real borderless one, because KDL's `Run` action can't
# request borderless. There is no session to ask any more, so this IS the
# spawn — one floating Ghostty instance through the shared helper, covering the
# screen, with the tiled desktop underneath untouched. Quit gh-dash and the
# window closes with it.
#
# --tiled rather than a fullscreen flag, and rather than the --pct 100 this
# carried until 2026-08-20: "full window" means the rectangle the TILED windows
# occupy, which is the visible frame inset by AeroSpace's outer gaps. --pct 100
# took the whole visible frame instead, so the popup overhung every window
# underneath it by exactly one gap on each edge and read as oversized rather
# than as the desktop being replaced. Either way the bar stays readable behind
# it — the visible frame excludes the menu bar, and the gap does the rest.
set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

exec "$HOME/.config/haus/term/float-term.sh" spawn \
    --title "github" \
    --tiled \
    --pin \
    --command "gh-dash"
