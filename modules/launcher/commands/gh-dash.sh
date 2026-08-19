#!/bin/bash
# pounce: name = GitHub Dashboard
# pounce: description = gh-dash in a near-fullscreen floating window
# pounce: icon = chevron.left.forwardslash.chevron.right

# ⌘G's target, and a palette row in its own right. Installed only when
# haus.terminal.ghDash.enable is on — a row that opened a window running a
# binary this machine doesn't have would be worse than no row.
exec "$HOME/.config/haus/term/gh-dash.sh"
