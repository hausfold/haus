#!/bin/bash
# pounce: name = Restore Terminal Windows
# pounce: description = Reopen a window for every parked shell and lane
# pounce: icon = macwindow.on.rectangle
#
# The on-demand half of scripts/restore-windows.sh (terminal room), which is
# what actually does it. This exists because the automatic half only ever fires
# for the FIRST window of a Ghostty — that is the one moment "put it all back"
# is unambiguously what was meant — and there are two ordinary ways to want it
# later: you closed a few windows and changed your mind, or the machine has
# `haus.terminal.restoreWindows = false` and never does it by itself.
#
# Safe to run at any time, including twice: a session with a window is attached,
# and attached sessions are not in the list.
#
# Absolute path: the daemon's environment has no user PATH.
set -u

restore="$HOME/.config/haus/term/restore-windows.sh"
[ -x "$restore" ] || exit 0

exec "$restore"
