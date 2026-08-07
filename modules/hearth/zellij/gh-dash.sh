#!/bin/bash
# gh-dash.sh — Cmd-G: open gh-dash as the same clean, full-window floating
# overlay as Hearth's custom search. The 1% launcher pane that invokes this
# script exists only long enough to ask the session for the real borderless
# pane; when gh-dash exits, the tiled layout underneath is untouched.

set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

zellij action new-pane \
    --floating \
    --close-on-exit \
    --borderless true \
    --name github \
    --x 0 --y 0 --width 100% --height 100% \
    -- gh-dash >/dev/null
