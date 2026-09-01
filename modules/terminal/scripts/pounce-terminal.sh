#!/bin/bash
# pounce's $POUNCE_TERMINAL_LAUNCHER: run "$@" (e.g. `ssh <host>` from the
# pounce SSH plugin) in a new tiled Ghostty window — the same flow
# editor-open-pane.sh uses, through the same helper.
#
# It used to open a tab in haus's `main` zellij session, and wait up to five
# seconds for that session to exist before falling back to a bare window. There
# is no session to wait for now, so the fallback IS the path and the wait is
# gone with it.
#
# The pounce daemon runs under launchd's bare PATH; new-window.sh sets its own.
set -u

[ $# -gt 0 ] || exit 0

exec "$HOME/.config/haus/term/new-window.sh" -- "$@"
