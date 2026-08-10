#!/bin/bash

# $SB — the bar this pill lives on. It can be either one: the readouts are
# movable via haus.sill.bottom.items, and a bare `sketchybar` here would keep
# updating a top-bar item that no longer exists. See bar.sh.
source "$HOME/.config/sketchybar/bar.sh"

# Get CPU usage percentage
CPU_USAGE=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f", s}')

# Nerd Font CPU icon (nf-oct-cpu, U+F4BC). Literal glyph, not printf '\uXXXX' —
# macOS ships bash 3.2, whose printf has no \u/\U escapes and emits the escape
# text verbatim into the bar.
ICON=""

# Update the bar item
"$SB" --set $NAME \
    icon="$ICON" \
    label="${CPU_USAGE}%"
