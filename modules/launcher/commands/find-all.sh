#!/bin/bash
# pounce: name = Find (All Windows)
# pounce: description = Full-text search across every terminal window at once
# pounce: icon = magnifyingglass.circle

# ⌘⇧F's target. A hotkey target is a bare `cmd:<id>` with no arguments, so the
# scope needs a file of its own; everything real lives in find.sh.
exec "$HOME/.config/haus/term/find.sh" launch session
