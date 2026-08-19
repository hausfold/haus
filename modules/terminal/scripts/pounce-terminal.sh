#!/bin/bash
# pounce's $POUNCE_TERMINAL_LAUNCHER: run "$@" (e.g. `ssh <host>` from the pounce
# SSH plugin) in a new tab of the rice's `main` zellij session — the same
# open-in-a-tab flow as editor-open-pane.sh. Ensures Ghostty and the `main`
# session are up first and focuses Ghostty; if the session never appears, falls
# back to a fresh Ghostty window running the command.
#
# The pounce daemon runs under launchd's bare PATH, so be explicit about where
# zellij / open / osascript live rather than trust the inherited environment.
set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

[ $# -gt 0 ] || exit 0

# 1. Ensure Ghostty is running (it autostarts the `main` zellij session).
if ! pgrep -x "Ghostty" >/dev/null; then
    open -a "Ghostty"
    sleep 2.0
fi

# 2. Wait briefly for the `main` session to appear.
if ! zellij list-sessions 2>/dev/null | grep -q "main"; then
    for _ in $(seq 1 10); do
        sleep 0.5
        zellij list-sessions 2>/dev/null | grep -q "main" && break
    done
fi

# 3. Open "$@" in a new tab named after the command, or fall back to a window.
if zellij list-sessions 2>/dev/null | grep -q "main"; then
    osascript -e 'tell application "Ghostty" to activate'
    zellij -s main action new-tab --name "$*" -- "$@"
else
    open -na "Ghostty" --args -e "$*"
fi
