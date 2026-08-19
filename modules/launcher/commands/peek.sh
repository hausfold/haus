#!/bin/bash
# pounce: name = Peek Files
# pounce: description = Floating yazi browser rooted at the focused window's repo
# pounce: icon = folder
# pounce: cheat = peek files

# ⌘Y's target. Pounce's Ghostty-scoped tap fires `cmd:peek`, which is this file,
# which is a one-line exec into the panel the terminal room installs. Was
# zellij's `Super y`; see find.sh's header for why the chord layer is pounce's.
exec "$HOME/.config/haus/term/peek.sh"
