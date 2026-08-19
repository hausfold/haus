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
# --pct 100 rather than a fullscreen flag: float-term centres on the VISIBLE
# frame (menu bar and dock excluded), which is what "full window" meant under
# zellij too — the bar stays readable behind it.
set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

exec "$HOME/.config/haus/term/float-term.sh" spawn \
    --title "github" \
    --pct 100 \
    --pin \
    --command "gh-dash"
