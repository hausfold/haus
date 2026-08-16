#!/bin/bash
# pounce: name = Toggle Focus
# pounce: description = Focus/DND + Slack status, one switch
# pounce: icon = moon.fill
# pounce: cheat = focus
# Runs under the pounce daemon, so the synthetic DND keypress inherits
# pounce's Accessibility grant — this path needs no extra TCC setup.
# Absolute path: the daemon's environment has no user PATH.
exec "$HOME/.local/bin/focus" toggle
