#!/bin/bash
# pounce: name = Find
# pounce: description = Full-text search over the focused window's scrollback
# pounce: icon = magnifyingglass
# pounce: cheat = find in window

# ⌘F's target. Pounce's Ghostty-scoped tap fires `cmd:find`, which is this
# file, which is a one-line exec into the overlay the terminal room installs.
#
# It was a zellij bind (`Super f`) until zellij was removed. The reason it moved
# to pounce rather than to Ghostty is the one that governs the whole chord
# layer: `ghostty +list-actions` on 1.3.1 lists 85 actions and none of them runs
# a command. A chord that DOES something has to be hosted somewhere that can
# shell out, and pounce's tap is the only app-scoped one of those — see
# notes/zellij-exit.md, decision 4.
exec "$HOME/.config/haus/term/find.sh" launch pane
