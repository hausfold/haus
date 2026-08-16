#!/bin/bash
# agents-peek.sh — runs INSIDE a throwaway Ghostty window (spawned by a popup
# row click in agents.sh). Live-tails one agent's pane via `zellij subscribe` —
# the payoff for the whole design: glance at what the agent that pinged you is
# actually doing, without stealing focus from your current pane. A separate
# script (not an inline --command) so Ghostty's space-splitting of --command
# never mangles the arguments.
#
#   usage: agents-peek.sh <session> <pane-id>
set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

sess="${1:?session}"; pane="${2:?pane-id}"
printf '\033]0;peek %s / %s\007' "$sess" "$pane"   # window title
echo "── live peek: $sess / $pane  (ctrl-c to close) ──"
# --ansi keeps the agent's colors; -s 300 seeds recent scrollback for context.
zellij --session "$sess" subscribe --pane-id "$pane" --ansi -s 300
echo "── pane ended — press any key ──"; read -r -n1
